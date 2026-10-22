//
//  NodeModuleSQLite.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import SQLite3

// A partial re-implementation of Node.js's `node:sqlite` module, backed by the SQLite library
// that ships with macOS.
//
// The goal is fidelity with Node, so that Node's own documentation (and code written for Node)
// applies: the same classes, method names, value conversions, options and error codes. The
// supported surface is `DatabaseSync` (open/close/exec/prepare/location/isOpen/isTransaction)
// and `StatementSync` (run/get/all/iterate/columns plus their option setters). Node's
// user-defined functions, aggregates, extensions, sessions, backups and tag stores aren't
// implemented.

// MARK: - Errors

/// Builds the errors `node:sqlite` throws, with the same `code` (and for SQLite failures,
/// `errcode`/`errstr`) properties as Node's.
nonisolated enum NodeSQLiteError {
    /// An error for a failed SQLite call, as Node's `ERR_SQLITE_ERROR`.
    /// - Parameters:
    ///   - code: The SQLite result code
    ///   - db: The connection the call was made on, whose error message is used if there is one
    static func sqlite(_ code: Int32, db: OpaquePointer?, in context: JSContext) -> JSValue? {
        let message: String
        if let db = unsafe db, let cMessage = unsafe sqlite3_errmsg(db) {
            message = unsafe String(cString: cMessage)
        } else {
            message = errstr(code)
        }
        let error = make("Error", message: message, code: "ERR_SQLITE_ERROR", in: context)
        error?.setValue(code, forProperty: "errcode")
        error?.setValue(errstr(code), forProperty: "errstr")
        return error
    }

    /// An `ERR_INVALID_STATE` error, e.g. for using a closed database.
    static func invalidState(_ message: String, in context: JSContext) -> JSValue? {
        make("Error", message: message, code: "ERR_INVALID_STATE", in: context)
    }

    /// An `ERR_INVALID_ARG_TYPE` error, for an argument of the wrong type.
    static func invalidArgType(_ message: String, in context: JSContext) -> JSValue? {
        make("TypeError", message: message, code: "ERR_INVALID_ARG_TYPE", in: context)
    }

    /// An `ERR_INVALID_ARG_VALUE` error, for an argument of the right type but an unusable value.
    static func invalidArgValue(_ message: String, in context: JSContext) -> JSValue? {
        make("TypeError", message: message, code: "ERR_INVALID_ARG_VALUE", in: context)
    }

    /// An `ERR_OUT_OF_RANGE` error, for an integer too large to be a JS number.
    static func outOfRange(_ message: String, in context: JSContext) -> JSValue? {
        make("RangeError", message: message, code: "ERR_OUT_OF_RANGE", in: context)
    }

    private static func errstr(_ code: Int32) -> String {
        guard let cString = unsafe sqlite3_errstr(code) else { return "unknown error" }
        return unsafe String(cString: cString)
    }

    /// Makes an error with one of JS's built-in error constructors, falling back to a plain
    /// `Error` if the script has replaced that constructor with something unusable.
    private static func make(_ constructorName: String, message: String, code: String, in context: JSContext) -> JSValue? {
        var error: JSValue?
        if constructorName != "Error",
           let constructor = context.objectForKeyedSubscript(constructorName), constructor.isObject {
            error = constructor.construct(withArguments: [message])
        }
        if error?.isObject != true {
            error = JSValue(newErrorFromMessage: message, in: context)
        }
        error?.setValue(code, forProperty: "code")
        return error
    }
}

/// Throws `error` to the JS code that called into Swift.
private func throwJS(_ makeError: (JSContext) -> JSValue?) {
    guard let context = JSContext.current() else { return }
    context.exception = makeError(context)
}

// MARK: - Value conversion

/// Converts between JS values and SQLite values the way Node's `node:sqlite` does.
private enum NodeSQLiteValues {
    /// The largest integer magnitude a JS number holds exactly (Number.MAX_SAFE_INTEGER).
    static let maxSafeInteger: Int64 = (1 << 53) - 1

    /// Tells SQLite to copy bound text and blobs, since Swift's buffers are temporary.
    nonisolated(unsafe) static let transient = unsafe unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// An object with no prototype, as Node returns rows and column descriptions.
    static func makeNullPrototypeObject(in context: JSContext) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }
        let ctx = unsafe context.jsGlobalContextRef
        unsafe JSObjectSetPrototype(ctx, object.jsValueRef, JSValueMakeNull(ctx))
        return object
    }

    /// Whether `value` is a typed array (e.g. `Uint8Array`), which binds as a blob rather than
    /// being read as an object of named parameters. Checked natively so scripts can't spoof it.
    static func isTypedArray(_ value: JSValue) -> Bool {
        let ctx = unsafe value.context.jsGlobalContextRef
        let type = unsafe JSValueGetTypedArrayType(ctx, value.jsValueRef, nil)
        return type != kJSTypedArrayTypeNone && type != kJSTypedArrayTypeArrayBuffer
    }

    /// Reads column `index` of the current row of `stmt`.
    /// - Returns: The value, or nil if it couldn't be represented (an exception is thrown then)
    static func readColumn(_ stmt: OpaquePointer, _ index: Int32, readBigInts: Bool, in context: JSContext) -> JSValue? {
        switch unsafe sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            let integer = unsafe sqlite3_column_int64(stmt, index)
            if readBigInts {
                return JSValue(newBigIntFrom: integer, in: context)
            }
            guard integer >= -maxSafeInteger && integer <= maxSafeInteger else {
                context.exception = NodeSQLiteError.outOfRange(
                    "Value is too large to be represented as a JavaScript number: \(integer)", in: context)
                return nil
            }
            return JSValue(double: Double(integer), in: context)
        case SQLITE_FLOAT:
            return JSValue(double: unsafe sqlite3_column_double(stmt, index), in: context)
        case SQLITE_TEXT:
            let count = Int(unsafe sqlite3_column_bytes(stmt, index))
            guard let text = unsafe sqlite3_column_text(stmt, index) else {
                return JSValue(object: "", in: context)
            }
            let string = unsafe String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
            return JSValue(object: string, in: context)
        case SQLITE_BLOB:
            let count = Int(unsafe sqlite3_column_bytes(stmt, index))
            guard count > 0, let blob = unsafe sqlite3_column_blob(stmt, index) else {
                return context.makeUint8Array([UInt8]())
            }
            let bytes = unsafe UnsafeRawBufferPointer(start: blob, count: count)
            return unsafe context.makeUint8Array(bytes)
        default:
            return JSValue(nullIn: context)
        }
    }

    /// Binds `value` to parameter `index` of `stmt`.
    /// - Returns: false if it couldn't be bound (an exception is thrown then)
    static func bind(_ value: JSValue, to stmt: OpaquePointer, at index: Int32, db: OpaquePointer, in context: JSContext) -> Bool {
        let result: Int32
        if value.isNull || value.isUndefined {
            result = unsafe sqlite3_bind_null(stmt, index)
        } else if value.isBoolean {
            result = unsafe sqlite3_bind_int64(stmt, index, value.toBool() ? 1 : 0)
        } else if value.isNumber {
            // Node binds every number as a REAL; column affinity turns whole numbers back into
            // INTEGERs where the schema asks for them.
            result = unsafe sqlite3_bind_double(stmt, index, value.toDouble())
        } else if value.isString {
            let string = value.toString() ?? ""
            result = string.withCString { pointer in
                unsafe sqlite3_bind_text64(stmt, index, pointer, sqlite3_uint64(string.utf8.count), transient, UInt8(SQLITE_UTF8))
            }
        } else if value.isBigInt {
            guard value.compare(Int64.max) != .greaterThan, value.compare(Int64.min) != .lessThan else {
                context.exception = NodeSQLiteError.invalidArgValue("BigInt value is too large to bind.", in: context)
                return false
            }
            result = unsafe sqlite3_bind_int64(stmt, index, value.toInt64())
        } else if isTypedArray(value), let bytes = value.typedArrayBytes {
            if bytes.isEmpty {
                result = unsafe sqlite3_bind_zeroblob(stmt, index, 0)
            } else {
                result = bytes.withUnsafeBytes { buffer in
                    unsafe sqlite3_bind_blob64(stmt, index, buffer.baseAddress, sqlite3_uint64(buffer.count), transient)
                }
            }
        } else {
            context.exception = NodeSQLiteError.invalidArgType(
                "Provided value cannot be bound to SQLite parameter \(index).", in: context)
            return false
        }
        guard result == SQLITE_OK else {
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: db, in: context)
            return false
        }
        return true
    }
}

// MARK: - Argument validation

/// Validates an optional boolean argument the way Node does.
/// - Returns: The value, `defaultValue` if it's undefined, or nil (with an exception thrown) if it
///   isn't a boolean
private func booleanArgument(_ value: JSValue?, name: String, default defaultValue: Bool, in context: JSContext) -> Bool? {
    guard let value, !value.isUndefined else { return defaultValue }
    guard value.isBoolean else {
        context.exception = NodeSQLiteError.invalidArgType("The \"\(name)\" argument must be a boolean.", in: context)
        return nil
    }
    return value.toBool()
}

/// Validates a string argument the way Node does.
/// - Returns: The string, or nil (with an exception thrown) if `value` isn't one
private func stringArgument(_ value: JSValue, name: String, in context: JSContext) -> String? {
    guard value.isString, let string = value.toString() else {
        context.exception = NodeSQLiteError.invalidArgType("The \"\(name)\" argument must be a string.", in: context)
        return nil
    }
    return string
}

// MARK: - DatabaseSync

/// A connection to a SQLite database, as Node's `DatabaseSync` from `require('node:sqlite')`.
///
/// Every method runs synchronously. Databases are opened with foreign key constraints enforced and
/// double-quoted string literals disabled, as in Node.
///
/// Not implemented from Node: `function()`, `aggregate()`, `loadExtension()`,
/// `enableLoadExtension()`, `createSession()`, `applyChangeset()`, `backup()`,
/// `createTagStore()` and `Symbol.dispose`.
@objc protocol DatabaseSyncAPI: HSTypeAPI, JSExport {
    /// Opens a SQLite database.
    ///
    /// Supported options, all optional:
    /// - `open` (boolean, default `true`): open the database now. If `false`, call `open()` later.
    /// - `readOnly` (boolean, default `false`): open the database read-only.
    /// - `enableForeignKeyConstraints` (boolean, default `true`): enforce foreign key constraints.
    /// - `enableDoubleQuotedStringLiterals` (boolean, default `false`): accept double-quoted string literals.
    /// - `timeout` (integer, default `0`): milliseconds to wait for a locked database before failing.
    /// - `readBigInts` (boolean, default `false`): read INTEGER values as `BigInt`s.
    /// - `returnArrays` (boolean, default `false`): return rows as arrays instead of objects.
    /// - `allowBareNamedParameters` (boolean, default `true`): allow named parameters without their prefix character.
    /// - `allowUnknownNamedParameters` (boolean, default `false`): ignore named parameters that the statement doesn't use.
    ///
    /// Statements prepared on this database start with its `readBigInts`, `returnArrays`,
    /// `allowBareNamedParameters` and `allowUnknownNamedParameters` settings.
    /// - Parameters:
    ///   - path: {string} The path of the database file, or `":memory:"` for an in-memory database. A leading `~` is expanded to the home directory. Relative paths are relative to Hammerspoon's working directory, so use absolute paths.
    ///   - options?: {Record<string, any>} The options described above
    /// - Example:
    /// ```js
    /// const { DatabaseSync } = require('node:sqlite')
    /// const db = new DatabaseSync('~/notes.db')
    /// db.exec('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, body TEXT)')
    /// ```
    init(path: JSValue, options: JSValue)

    /// Whether the database is currently open.
    @objc var isOpen: Bool { get }

    /// Whether the database is inside a transaction. Throws if the database isn't open.
    @objc var isTransaction: Bool { get }

    /// Opens the database. Only needed if it was constructed with `open: false`, or after
    /// `close()`. Throws if the database is already open.
    /// - Example:
    /// ```js
    /// const db = new DatabaseSync('~/notes.db', { open: false })
    /// db.open()
    /// ```
    @objc func open()

    /// Closes the database, finalizing every statement prepared on it. Throws if the database
    /// isn't open.
    /// - Example:
    /// ```js
    /// db.close()
    /// ```
    @objc func close()

    /// Runs one or more SQL statements, without returning any results. Statements run in order
    /// until one fails, which throws.
    /// - Parameter sql: {string} The SQL to run
    /// - Example:
    /// ```js
    /// db.exec(`
    ///     CREATE TABLE IF NOT EXISTS visits (app TEXT, at INTEGER);
    ///     DELETE FROM visits WHERE at < unixepoch() - 86400;
    /// `)
    /// ```
    @objc func exec(_ sql: JSValue)

    /// Compiles a SQL statement so it can be run, any number of times, with different parameters.
    /// Only the first statement in `sql` is compiled.
    /// - Parameter sql: {string} The SQL to compile
    /// - Returns: {StatementSync} The prepared statement
    /// - Example:
    /// ```js
    /// const insert = db.prepare('INSERT INTO visits (app, at) VALUES (?, unixepoch())')
    /// insert.run('Safari')
    /// ```
    @objc func prepare(_ sql: JSValue) -> StatementSync?

    /// The file path of a database attached to this connection.
    /// - Parameter dbName?: {string} The name of the attached database. Defaults to `"main"`.
    /// - Returns: The path, or `null` for an in-memory database or an unknown name
    /// - Example:
    /// ```js
    /// console.log(db.location())
    /// ```
    @objc func location(_ dbName: JSValue) -> String?
}

@_documentation(visibility: private)
@safe @objc(DatabaseSync) final class DatabaseSync: NSObject, DatabaseSyncAPI {
    @objc var typeName = "DatabaseSync"

    /// Roughly what an open connection holds natively (its schema and page cache), reported to
    /// JavaScriptCore so a dropped connection is collected, and its file closed, promptly.
    private static let estimatedConnectionCost = 256 * 1024

    /// The expanded path passed to the constructor, or nil if the constructor failed.
    private let path: String?
    private let readOnly: Bool
    private let enableForeignKeyConstraints: Bool
    private let enableDoubleQuotedStringLiterals: Bool
    private let timeout: Int32

    // Defaults for statements prepared on this database
    let readBigInts: Bool
    let returnArrays: Bool
    let allowBareNamedParameters: Bool
    let allowUnknownNamedParameters: Bool

    /// The open connection, or nil while closed.
    private(set) var handle: OpaquePointer?

    /// Statements prepared on this database, held weakly, so `close()` can finalize them. Not an
    /// HSObjectTracker: that holds its JSContext until a module shuts it down, and nothing shuts
    /// down a database on reload, so it would keep the old context alive.
    private var statements: [ObjectIdentifier: WeakStatement] = [:]

    private struct WeakStatement {
        weak var statement: StatementSync?
    }

    init(path: JSValue, options: JSValue) {
        var parsed: Options?
        var expandedPath: String?
        if let context = JSContext.current() {
            if let string = Self.validatePath(path, in: context) {
                expandedPath = string
                parsed = Options(options, in: context)
            }
        }
        let options = parsed ?? Options()
        self.path = parsed == nil ? nil : expandedPath
        readOnly = options.readOnly
        enableForeignKeyConstraints = options.enableForeignKeyConstraints
        enableDoubleQuotedStringLiterals = options.enableDoubleQuotedStringLiterals
        timeout = options.timeout
        readBigInts = options.readBigInts
        returnArrays = options.returnArrays
        allowBareNamedParameters = options.allowBareNamedParameters
        allowUnknownNamedParameters = options.allowUnknownNamedParameters
        super.init()
        AKGarbage("Init of DatabaseSync")

        // An exception is already pending if the arguments were invalid; JavaScriptCore throws it
        // from the constructor, and this object is dropped.
        if self.path != nil && options.open, let context = JSContext.current() {
            openConnection(in: context)
        }
    }

    isolated deinit {
        closeConnection()
        AKGarbage("Deinit of DatabaseSync")
    }

    // MARK: Properties

    @objc var isOpen: Bool { unsafe handle != nil }

    @objc var isTransaction: Bool {
        guard let handle = unsafe openHandle() else { return false }
        return unsafe sqlite3_get_autocommit(handle) == 0
    }

    // MARK: Methods

    @objc func open() {
        guard let context = JSContext.current() else { return }
        guard unsafe handle == nil else {
            context.exception = NodeSQLiteError.invalidState("database is already open", in: context)
            return
        }
        openConnection(in: context)
    }

    @objc func close() {
        guard unsafe openHandle() != nil else { return }
        closeConnection()
    }

    @objc func exec(_ sql: JSValue) {
        guard let context = JSContext.current(), let handle = unsafe openHandle(),
              let sql = stringArgument(sql, name: "sql", in: context) else { return }
        let result = unsafe sqlite3_exec(handle, sql, nil, nil, nil)
        if result != SQLITE_OK {
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: handle, in: context)
        }
    }

    @objc func prepare(_ sql: JSValue) -> StatementSync? {
        guard let context = JSContext.current(), let handle = unsafe openHandle(),
              let sql = stringArgument(sql, name: "sql", in: context) else { return nil }
        var stmt: OpaquePointer?
        let result = unsafe sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: handle, in: context)
            return nil
        }
        // SQL with no statements in it (empty, or only comments) compiles to nothing
        guard let stmt = unsafe stmt else {
            context.exception = NodeSQLiteError.invalidArgValue("The SQL query contains no statements.", in: context)
            return nil
        }
        let statement = unsafe StatementSync(stmt, database: self)
        statements = statements.filter { $0.value.statement != nil }
        statements[ObjectIdentifier(statement)] = WeakStatement(statement: statement)
        return statement
    }

    @objc func location(_ dbName: JSValue) -> String? {
        guard let context = JSContext.current(), let handle = unsafe openHandle() else { return nil }
        var name = "main"
        if !dbName.isUndefined {
            guard let string = stringArgument(dbName, name: "dbName", in: context) else { return nil }
            name = string
        }
        // In-memory and temporary databases have an empty filename
        guard let filename = unsafe sqlite3_db_filename(handle, name),
              unsafe filename.pointee != 0 else { return nil }
        return unsafe String(cString: filename)
    }

    @objc func toString() -> String {
        "DatabaseSync(\(path ?? "invalid"), \(isOpen ? "open" : "closed"))"
    }

    // MARK: Internals

    /// The open connection, or nil, with `ERR_INVALID_STATE` thrown, if the database is closed.
    func openHandle() -> OpaquePointer? {
        guard let handle = unsafe handle else {
            throwJS { NodeSQLiteError.invalidState("database is not open", in: $0) }
            return nil
        }
        return unsafe handle
    }

    private func openConnection(in context: JSContext) {
        guard let path else { return }
        var flags = SQLITE_OPEN_URI
        flags |= readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)

        var db: OpaquePointer?
        let result = unsafe sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db = unsafe db else {
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: db, in: context)
            // SQLite allocates a connection even when opening fails, which must still be closed
            unsafe sqlite3_close_v2(db)
            return
        }
        unsafe hs_sqlite3_db_config_int(db, SQLITE_DBCONFIG_ENABLE_FKEY, enableForeignKeyConstraints ? 1 : 0)
        unsafe hs_sqlite3_db_config_int(db, SQLITE_DBCONFIG_DQS_DML, enableDoubleQuotedStringLiterals ? 1 : 0)
        unsafe hs_sqlite3_db_config_int(db, SQLITE_DBCONFIG_DQS_DDL, enableDoubleQuotedStringLiterals ? 1 : 0)
        if timeout > 0 {
            unsafe sqlite3_busy_timeout(db, timeout)
        }
        unsafe handle = db
        JSExtraMemory.report(Self.estimatedConnectionCost, in: context)
    }

    private func closeConnection() {
        guard let db = unsafe handle else { return }
        // Finalizes every statement, so the connection can close (and release its file) now
        for entry in statements.values {
            entry.statement?.finalizeHandle()
        }
        statements.removeAll()
        unsafe sqlite3_close_v2(db)
        unsafe handle = nil
    }

    /// Validates the constructor's `path` argument, and expands a leading `~`.
    /// - Returns: The expanded path, or nil (with an exception thrown) if it's invalid
    private static func validatePath(_ path: JSValue, in context: JSContext) -> String? {
        guard path.isString, let string = path.toString(), !string.contains("\0") else {
            context.exception = NodeSQLiteError.invalidArgType(
                "The \"path\" argument must be a string without null bytes.", in: context)
            return nil
        }
        return NSString(string: string).expandingTildeInPath
    }

    /// The constructor's options, with Node's defaults.
    private struct Options {
        var open = true
        var readOnly = false
        var enableForeignKeyConstraints = true
        var enableDoubleQuotedStringLiterals = false
        var timeout: Int32 = 0
        var readBigInts = false
        var returnArrays = false
        var allowBareNamedParameters = true
        var allowUnknownNamedParameters = false

        init() {}

        /// Parses an options argument.
        /// - Returns: nil (with an exception thrown) if any option is invalid
        init?(_ value: JSValue, in context: JSContext) {
            guard !value.isUndefined else { return }
            guard value.isObject else {
                context.exception = NodeSQLiteError.invalidArgType("The \"options\" argument must be an object.", in: context)
                return nil
            }
            func flag(_ name: String, _ defaultValue: Bool) -> Bool? {
                booleanArgument(value.forProperty(name), name: "options.\(name)", default: defaultValue, in: context)
            }
            guard let open = flag("open", open),
                  let readOnly = flag("readOnly", readOnly),
                  let enableForeignKeyConstraints = flag("enableForeignKeyConstraints", enableForeignKeyConstraints),
                  let enableDoubleQuotedStringLiterals = flag("enableDoubleQuotedStringLiterals", enableDoubleQuotedStringLiterals),
                  let readBigInts = flag("readBigInts", readBigInts),
                  let returnArrays = flag("returnArrays", returnArrays),
                  let allowBareNamedParameters = flag("allowBareNamedParameters", allowBareNamedParameters),
                  let allowUnknownNamedParameters = flag("allowUnknownNamedParameters", allowUnknownNamedParameters) else {
                return nil
            }
            self.open = open
            self.readOnly = readOnly
            self.enableForeignKeyConstraints = enableForeignKeyConstraints
            self.enableDoubleQuotedStringLiterals = enableDoubleQuotedStringLiterals
            self.readBigInts = readBigInts
            self.returnArrays = returnArrays
            self.allowBareNamedParameters = allowBareNamedParameters
            self.allowUnknownNamedParameters = allowUnknownNamedParameters

            if let timeout = value.forProperty("timeout"), !timeout.isUndefined {
                let number = timeout.toDouble()
                guard timeout.isNumber, number.rounded() == number, number >= 0, number <= Double(Int32.max) else {
                    context.exception = NodeSQLiteError.invalidArgType(
                        "The \"options.timeout\" argument must be an integer.", in: context)
                    return nil
                }
                self.timeout = Int32(number)
            }
        }
    }
}

// MARK: - StatementSync

/// A prepared statement, as Node's `StatementSync`. Made by `DatabaseSync.prepare()`; it can't be
/// constructed directly.
///
/// Parameters are bound the same way for `run()`, `get()`, `all()` and `iterate()`: if the first
/// argument is an object (other than a typed array), its properties are bound to named
/// parameters (`:name`, `@name` or `$name`), and any remaining arguments are bound, in order, to
/// anonymous (`?`) parameters. Values convert as in Node:
///
/// | JavaScript | SQLite |
/// |---|---|
/// | `null`, `undefined` | NULL |
/// | number | REAL (stored as INTEGER in columns with INTEGER affinity) |
/// | boolean | INTEGER 1 or 0 |
/// | bigint | INTEGER |
/// | string | TEXT |
/// | typed array (e.g. `Uint8Array`) | BLOB |
///
/// Results come back as `null`, numbers (or `BigInt`s, see `setReadBigInts()`), strings and
/// `Uint8Array`s. An INTEGER too large to be a JS number throws, unless `readBigInts` is set.
@objc protocol StatementSyncAPI: HSTypeAPI, JSExport {
    /// Runs the statement, and returns the number of rows it changed and the ID of the last row
    /// inserted.
    /// VARIADIC(params: any[])
    /// - Parameter params: Named parameters (an object) and/or anonymous parameters
    /// - Returns: {{ changes: number | bigint, lastInsertRowid: number | bigint }} The rows changed and the last inserted row ID. These are `BigInt`s if `readBigInts` is set.
    /// - Example:
    /// ```js
    /// const insert = db.prepare('INSERT INTO notes (body) VALUES (:body)')
    /// const { lastInsertRowid } = insert.run({ body: 'Buy milk' })
    /// ```
    @objc func run(_ params: JSValue) -> JSValue?

    /// Runs the statement and returns its first row.
    /// VARIADIC(params: any[])
    /// - Parameter params: Named parameters (an object) and/or anonymous parameters
    /// - Returns: {any} The first row, as an object keyed by column name (or an array, if `returnArrays` is set), or `undefined` if there are no rows
    /// - Example:
    /// ```js
    /// const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(1)
    /// if (note) console.log(note.body)
    /// ```
    @objc func get(_ params: JSValue) -> JSValue?

    /// Runs the statement and returns all of its rows.
    /// VARIADIC(params: any[])
    /// - Parameter params: Named parameters (an object) and/or anonymous parameters
    /// - Returns: {any[]} The rows, each an object keyed by column name (or an array, if `returnArrays` is set)
    /// - Example:
    /// ```js
    /// for (const note of db.prepare('SELECT * FROM notes').all()) {
    ///     console.log(note.id + ': ' + note.body)
    /// }
    /// ```
    @objc func all(_ params: JSValue) -> JSValue?

    /// Runs the statement and returns an iterator over its rows, which are read as the iterator
    /// is advanced. Running the statement again invalidates the iterator.
    /// VARIADIC(params: any[])
    /// - Parameter params: Named parameters (an object) and/or anonymous parameters
    /// - Returns: {IterableIterator<any>} An iterator over the rows
    /// - Example:
    /// ```js
    /// for (const note of db.prepare('SELECT * FROM notes').iterate()) {
    ///     if (note.body.includes('milk')) break
    /// }
    /// ```
    @objc func iterate(_ params: JSValue) -> StatementSyncIterator?

    /// Describes the columns the statement returns.
    /// - Returns: {Array<{ column: string | null, database: string | null, name: string, table: string | null, type: string | null }>} One object per column: its name in the result (`name`), and, for a column read directly from a table, the original column name, database, table and declared type
    /// - Example:
    /// ```js
    /// const names = db.prepare('SELECT * FROM notes').columns().map(c => c.name)
    /// ```
    @objc func columns() -> JSValue?

    /// The statement's SQL, with each parameter replaced by the value most recently bound to it.
    @objc var expandedSQL: String? { get }

    /// The statement's SQL, as passed to `prepare()`.
    @objc var sourceSQL: String? { get }

    /// Sets whether INTEGER values are read as `BigInt`s, including `run()`'s `changes` and
    /// `lastInsertRowid`.
    /// - Parameter enabled: {boolean} Whether to read `BigInt`s
    /// - Example:
    /// ```js
    /// stmt.setReadBigInts(true)
    /// ```
    @objc func setReadBigInts(_ enabled: JSValue)

    /// Sets whether rows are returned as arrays of values instead of objects.
    /// - Parameter enabled: {boolean} Whether to return arrays
    /// - Example:
    /// ```js
    /// stmt.setReturnArrays(true)
    /// ```
    @objc func setReturnArrays(_ enabled: JSValue)

    /// Sets whether named parameters may be given without their prefix character (`{ id: 1 }`
    /// for `:id`).
    /// - Parameter enabled: {boolean} Whether to allow bare names
    /// - Example:
    /// ```js
    /// stmt.setAllowBareNamedParameters(false)
    /// ```
    @objc func setAllowBareNamedParameters(_ enabled: JSValue)

    /// Sets whether named parameters the statement doesn't use are ignored, rather than throwing.
    /// - Parameter enabled: {boolean} Whether to ignore unknown names
    /// - Example:
    /// ```js
    /// stmt.setAllowUnknownNamedParameters(true)
    /// ```
    @objc func setAllowUnknownNamedParameters(_ enabled: JSValue)
}

@_documentation(visibility: private)
@safe @objc(StatementSync) final class StatementSync: NSObject, StatementSyncAPI {
    @objc var typeName = "StatementSync"

    /// The compiled statement, or nil once finalized.
    private var handle: OpaquePointer?
    /// Keeps the database alive while its statements are, as in Node.
    private let database: DatabaseSync

    private var readBigInts: Bool
    private var returnArrays: Bool
    private var allowBareNamedParameters: Bool
    private var allowUnknownNamedParameters: Bool

    /// Counts the times the statement has been run, so an iterator can tell when the statement
    /// has been run again underneath it.
    private(set) var executionCount = 0

    /// Bare parameter names (without their prefix) mapped to their full names, built when first
    /// needed.
    private var bareNames: [String: String]?

    init(_ handle: OpaquePointer, database: DatabaseSync) {
        unsafe self.handle = handle
        self.database = database
        readBigInts = database.readBigInts
        returnArrays = database.returnArrays
        allowBareNamedParameters = database.allowBareNamedParameters
        allowUnknownNamedParameters = database.allowUnknownNamedParameters
        super.init()
        AKGarbage("Init of StatementSync")
    }

    isolated deinit {
        finalizeHandle()
        AKGarbage("Deinit of StatementSync")
    }

    /// Finalizes the statement. Also called when its database is closed.
    func finalizeHandle() {
        guard let handle = unsafe handle else { return }
        unsafe sqlite3_finalize(handle)
        unsafe self.handle = nil
    }

    // MARK: Running

    @objc func run(_ params: JSValue) -> JSValue? {
        guard let context = JSContext.current(), let stmt = unsafe start(in: context),
              let db = unsafe database.handle else { return nil }
        defer { unsafe sqlite3_reset(stmt) }

        var result = unsafe sqlite3_step(stmt)
        while result == SQLITE_ROW {
            result = unsafe sqlite3_step(stmt)
        }
        guard result == SQLITE_DONE else {
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: db, in: context)
            return nil
        }

        let changes = unsafe sqlite3_changes64(db)
        let lastInsertRowid = unsafe sqlite3_last_insert_rowid(db)
        guard let summary = JSValue(newObjectIn: context) else { return nil }
        if readBigInts {
            summary.setValue(JSValue(newBigIntFrom: changes, in: context), forProperty: "changes")
            summary.setValue(JSValue(newBigIntFrom: lastInsertRowid, in: context), forProperty: "lastInsertRowid")
        } else {
            summary.setValue(Double(changes), forProperty: "changes")
            summary.setValue(Double(lastInsertRowid), forProperty: "lastInsertRowid")
        }
        return summary
    }

    @objc func get(_ params: JSValue) -> JSValue? {
        guard let context = JSContext.current(), let stmt = unsafe start(in: context) else { return nil }
        defer { unsafe sqlite3_reset(stmt) }

        switch unsafe step(stmt, in: context) {
        case .row: return unsafe readRow(stmt, in: context)
        case .done: return JSValue(undefinedIn: context)
        case .failed: return nil
        }
    }

    @objc func all(_ params: JSValue) -> JSValue? {
        guard let context = JSContext.current(), let stmt = unsafe start(in: context),
              let rows = JSValue(newArrayIn: context) else { return nil }
        defer { unsafe sqlite3_reset(stmt) }

        var count = 0
        while true {
            switch unsafe step(stmt, in: context) {
            case .row:
                guard let row = unsafe readRow(stmt, in: context) else { return nil }
                rows.setValue(row, at: count)
                count += 1
            case .done:
                return rows
            case .failed:
                return nil
            }
        }
    }

    @objc func iterate(_ params: JSValue) -> StatementSyncIterator? {
        guard let context = JSContext.current(), unsafe start(in: context) != nil else { return nil }
        return StatementSyncIterator(statement: self, execution: executionCount)
    }

    @objc func columns() -> JSValue? {
        guard let context = JSContext.current(), let stmt = unsafe liveHandle(),
              let columns = JSValue(newArrayIn: context) else { return nil }
        func string(_ cString: UnsafePointer<CChar>?) -> Any {
            guard let cString = unsafe cString else { return NSNull() }
            return unsafe String(cString: cString)
        }
        let count = unsafe sqlite3_column_count(stmt)
        for index in 0..<count {
            guard let column = NodeSQLiteValues.makeNullPrototypeObject(in: context) else { return nil }
            column.setValue(unsafe string(sqlite3_column_origin_name(stmt, index)), forProperty: "column")
            column.setValue(unsafe string(sqlite3_column_database_name(stmt, index)), forProperty: "database")
            column.setValue(unsafe string(sqlite3_column_name(stmt, index)), forProperty: "name")
            column.setValue(unsafe string(sqlite3_column_table_name(stmt, index)), forProperty: "table")
            column.setValue(unsafe string(sqlite3_column_decltype(stmt, index)), forProperty: "type")
            columns.setValue(column, at: Int(index))
        }
        return columns
    }

    // MARK: Properties

    @objc var expandedSQL: String? {
        guard let stmt = unsafe liveHandle(), let expanded = unsafe sqlite3_expanded_sql(stmt) else { return nil }
        defer { unsafe sqlite3_free(expanded) }
        return unsafe String(cString: expanded)
    }

    @objc var sourceSQL: String? {
        guard let stmt = unsafe liveHandle(), let sql = unsafe sqlite3_sql(stmt) else { return nil }
        return unsafe String(cString: sql)
    }

    @objc func setReadBigInts(_ enabled: JSValue) {
        if let value = setting(enabled, name: "readBigInts") { readBigInts = value }
    }

    @objc func setReturnArrays(_ enabled: JSValue) {
        if let value = setting(enabled, name: "returnArrays") { returnArrays = value }
    }

    @objc func setAllowBareNamedParameters(_ enabled: JSValue) {
        if let value = setting(enabled, name: "allowBareNamedParameters") { allowBareNamedParameters = value }
    }

    @objc func setAllowUnknownNamedParameters(_ enabled: JSValue) {
        if let value = setting(enabled, name: "allowUnknownNamedParameters") { allowUnknownNamedParameters = value }
    }

    @objc func toString() -> String {
        "StatementSync(\(sourceSQL ?? "finalized"))"
    }

    // MARK: Internals

    enum StepResult {
        case row, done, failed
    }

    /// Advances `stmt` by one row.
    func step(_ stmt: OpaquePointer, in context: JSContext) -> StepResult {
        switch unsafe sqlite3_step(stmt) {
        case SQLITE_ROW:
            return .row
        case SQLITE_DONE:
            return .done
        case let result:
            context.exception = unsafe NodeSQLiteError.sqlite(result, db: database.handle, in: context)
            return .failed
        }
    }

    /// Reads the current row of `stmt` as an object keyed by column name, or an array.
    /// - Returns: The row, or nil (with an exception thrown) if a value couldn't be read
    func readRow(_ stmt: OpaquePointer, in context: JSContext) -> JSValue? {
        let count = unsafe sqlite3_column_count(stmt)
        if returnArrays {
            guard let row = JSValue(newArrayIn: context) else { return nil }
            for index in 0..<count {
                guard let value = unsafe NodeSQLiteValues.readColumn(stmt, index, readBigInts: readBigInts, in: context) else { return nil }
                row.setValue(value, at: Int(index))
            }
            return row
        }
        guard let row = NodeSQLiteValues.makeNullPrototypeObject(in: context) else { return nil }
        for index in 0..<count {
            guard let value = unsafe NodeSQLiteValues.readColumn(stmt, index, readBigInts: readBigInts, in: context) else { return nil }
            let name = unsafe sqlite3_column_name(stmt, index).map { unsafe String(cString: $0) } ?? ""
            row.setValue(value, forProperty: name)
        }
        return row
    }

    /// The compiled statement, or nil, with `ERR_INVALID_STATE` thrown, if it has been finalized.
    func liveHandle() -> OpaquePointer? {
        guard let handle = unsafe handle else {
            throwJS { NodeSQLiteError.invalidState("statement has been finalized", in: $0) }
            return nil
        }
        return unsafe handle
    }

    /// Resets the statement and binds the arguments of the JS call in progress, ready to step.
    /// - Returns: The statement, or nil (with an exception thrown) if it couldn't be started
    private func start(in context: JSContext) -> OpaquePointer? {
        guard let stmt = unsafe liveHandle(), let db = unsafe database.handle else { return nil }
        executionCount += 1
        unsafe sqlite3_reset(stmt)
        unsafe sqlite3_clear_bindings(stmt)

        // JSExport declares a single parameter, but these methods take any number
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
        var anonymous = arguments[...]
        if let first = arguments.first, first.isObject, !NodeSQLiteValues.isTypedArray(first) {
            guard unsafe bindNamed(first, to: stmt, db: db, in: context) else { return nil }
            anonymous = arguments.dropFirst()
        }

        var index: Int32 = 1
        for value in anonymous {
            // Skip over named parameters. Numbered ones (?NNN) take anonymous values.
            while let name = unsafe sqlite3_bind_parameter_name(stmt, index), unsafe name.pointee != UInt8(ascii: "?") {
                index += 1
            }
            guard unsafe NodeSQLiteValues.bind(value, to: stmt, at: index, db: db, in: context) else { return nil }
            index += 1
        }
        return unsafe stmt
    }

    /// Binds the properties of `object` to the statement's named parameters.
    private func bindNamed(_ object: JSValue, to stmt: OpaquePointer, db: OpaquePointer, in context: JSContext) -> Bool {
        let ctx = unsafe context.jsGlobalContextRef
        guard let objectRef = unsafe JSValueToObject(ctx, object.jsValueRef, nil) else { return true }
        let names = unsafe JSObjectCopyPropertyNames(ctx, objectRef)
        defer { unsafe JSPropertyNameArrayRelease(names) }

        let count = unsafe JSPropertyNameArrayGetCount(names)
        for i in 0..<count {
            let nameRef = unsafe JSPropertyNameArrayGetNameAtIndex(names, i)
            let key = unsafe JSStringCopyCFString(kCFAllocatorDefault, nameRef) as String

            var index = unsafe sqlite3_bind_parameter_index(stmt, key)
            if index == 0 && allowBareNamedParameters {
                guard let bareNames = unsafe bareParameterNames(stmt, in: context) else { return false }
                if let fullName = bareNames[key] {
                    index = unsafe sqlite3_bind_parameter_index(stmt, fullName)
                }
            }
            guard index != 0 else {
                if allowUnknownNamedParameters { continue }
                context.exception = NodeSQLiteError.invalidState("Unknown named parameter '\(key)'", in: context)
                return false
            }
            guard let value = object.forProperty(key),
                  unsafe NodeSQLiteValues.bind(value, to: stmt, at: index, db: db, in: context) else { return false }
        }
        return true
    }

    /// The statement's named parameters, keyed by their names without the prefix character.
    /// - Returns: The names, or nil (with an exception thrown) if two parameters differ only in
    ///   their prefix (e.g. `:id` and `$id`), so a bare name would be ambiguous
    private func bareParameterNames(_ stmt: OpaquePointer, in context: JSContext) -> [String: String]? {
        if let bareNames { return bareNames }
        var names: [String: String] = [:]
        let count = unsafe sqlite3_bind_parameter_count(stmt)
        for index in stride(from: 1, through: count, by: 1) {
            guard let cName = unsafe sqlite3_bind_parameter_name(stmt, index) else { continue }
            let fullName = unsafe String(cString: cName)
            guard !fullName.hasPrefix("?") else { continue }
            let bareName = String(fullName.dropFirst())
            if let existing = names[bareName], existing != fullName {
                context.exception = NodeSQLiteError.invalidState(
                    "Cannot create bare named parameter '\(bareName)' because of conflicting names '\(existing)' and '\(fullName)'.",
                    in: context)
                return nil
            }
            names[bareName] = fullName
        }
        bareNames = names
        return names
    }

    /// Validates the argument of a `set...()` method.
    private func setting(_ value: JSValue, name: String) -> Bool? {
        guard let context = JSContext.current(), unsafe liveHandle() != nil else { return nil }
        guard value.isBoolean else {
            context.exception = NodeSQLiteError.invalidArgType("The \"\(name)\" argument must be a boolean.", in: context)
            return nil
        }
        return value.toBool()
    }
}

// MARK: - StatementSyncIterator

/// Iterates over the rows of a statement, as returned by `StatementSync.iterate()`. It's a
/// standard JS iterator, so it works with `for...of`, spread syntax and iterator helpers.
@objc protocol StatementSyncIteratorAPI: HSTypeAPI, JSExport {
    /// Reads the next row.
    /// - Returns: {{ done: boolean, value: any }} The next row as `value`, or `done: true` (with `value` `null`) once there are no more rows
    /// - Example:
    /// ```js
    /// const rows = db.prepare('SELECT * FROM notes').iterate()
    /// const first = rows.next().value
    /// ```
    @objc func next() -> JSValue?

    /// Stops iterating, releasing the statement. `for...of` calls this when the loop exits early.
    /// - Returns: {{ done: boolean, value: any }} `{ done: true, value: null }`
    /// - Example:
    /// ```js
    /// rows.return()
    /// ```
    @objc func `return`() -> JSValue?
}

@_documentation(visibility: private)
@objc(StatementSyncIterator) final class StatementSyncIterator: NSObject, StatementSyncIteratorAPI {
    @objc var typeName = "StatementSyncIterator"

    private let statement: StatementSync
    /// The statement's execution this iterator reads, so running the statement again can be
    /// detected.
    private let execution: Int
    private var isDone = false

    init(statement: StatementSync, execution: Int) {
        self.statement = statement
        self.execution = execution
        super.init()
        AKGarbage("Init of StatementSyncIterator")
    }

    isolated deinit {
        AKGarbage("Deinit of StatementSyncIterator")
    }

    @objc func next() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        if isDone { return result(done: true, value: nil, in: context) }
        guard let stmt = unsafe statement.liveHandle() else { return nil }
        guard statement.executionCount == execution else {
            context.exception = NodeSQLiteError.invalidState("iterator was invalidated", in: context)
            return nil
        }

        switch unsafe statement.step(stmt, in: context) {
        case .row:
            guard let row = unsafe statement.readRow(stmt, in: context) else {
                unsafe finish(stmt)
                return nil
            }
            return result(done: false, value: row, in: context)
        case .done:
            unsafe finish(stmt)
            return result(done: true, value: nil, in: context)
        case .failed:
            unsafe finish(stmt)
            return nil
        }
    }

    @objc func `return`() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        if !isDone, statement.executionCount == execution, let stmt = unsafe statement.liveHandle() {
            unsafe finish(stmt)
        }
        isDone = true
        return result(done: true, value: nil, in: context)
    }

    @objc func toString() -> String {
        "StatementSyncIterator"
    }

    /// Ends iteration, resetting the statement so it no longer holds the database's read lock.
    private func finish(_ stmt: OpaquePointer) {
        isDone = true
        unsafe sqlite3_reset(stmt)
    }

    private func result(done: Bool, value: JSValue?, in context: JSContext) -> JSValue? {
        guard let result = NodeSQLiteValues.makeNullPrototypeObject(in: context) else { return nil }
        result.setValue(done, forProperty: "done")
        result.setValue(value ?? JSValue(nullIn: context), forProperty: "value")
        return result
    }
}

// MARK: - Module exports

/// Builds the object `require('node:sqlite')` returns.
enum NodeSQLiteModule {
    static func makeExports(in context: JSContext) throws -> JSValue {
        guard let exports = JSValue(newObjectIn: context),
              let databaseSync = JSValue(object: DatabaseSync.self, in: context),
              let statementSync = JSValue(object: StatementSync.self, in: context),
              let iterator = JSValue(object: StatementSyncIterator.self, in: context) else {
            throw HammerspoonError(.vmCreation, msg: "Failed to create the node:sqlite exports")
        }
        exports.setValue(databaseSync, forProperty: "DatabaseSync")
        exports.setValue(statementSync, forProperty: "StatementSync")

        // Make iterators standard JS iterators, and keep their constructor (and so the prototype
        // modified here, which JavaScriptCore only holds weakly) alive with the exports.
        let setUp = context.evaluateScript("""
            (function (exports, Iterator, iteratorClass) {
                'use strict';
                const prototype = iteratorClass.prototype;
                if (typeof Iterator === 'function' && Iterator.prototype) {
                    Object.setPrototypeOf(prototype, Iterator.prototype);
                } else {
                    Object.defineProperty(prototype, Symbol.iterator, {
                        value: function () { return this; }, configurable: true, writable: true,
                    });
                }
                Object.defineProperty(exports, Symbol('StatementSyncIterator'), { value: iteratorClass });
                return exports;
            })
            """)
        guard let setUp, setUp.isObject,
              setUp.call(withArguments: [exports, context.objectForKeyedSubscript("Iterator") as Any, iterator]) != nil,
              context.exception == nil else {
            throw HammerspoonError(.vmCreation, msg: "Failed to set up node:sqlite iterators")
        }
        return exports
    }
}
