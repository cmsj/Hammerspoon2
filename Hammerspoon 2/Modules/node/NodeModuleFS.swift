//
//  NodeModuleFS.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Darwin

// MARK: - Errors

/// The outcome of a failed `NodeFS` operation, carrying enough detail to build a
/// Node-style `Error` (with `.code`, `.errno`, `.syscall`, `.path`) on the JS side.
/// `@unchecked Sendable` because `.invalidArgType` carries a `JSValue`: safe here since every
/// `NodeFSFailure` is created and consumed synchronously within a single JS-calling-thread
/// call stack (thrown, then immediately caught and turned into a JS exception/rejection in the
/// same function), never persisted or handed across threads.
private enum NodeFSFailure: Error, @unchecked Sendable {
    /// A failure that came from a specific POSIX syscall; `errnoValue` is the raw `errno`
    /// captured immediately after the call failed.
    case posix(errnoValue: Int32, syscall: String, path: String, path2: String?)
    /// A failure with no corresponding POSIX errno (eg. an unsupported encoding).
    case generic(code: String, message: String)
    /// A JS-facing argument that wasn't a string, matching Node's `ERR_INVALID_ARG_TYPE`.
    case invalidArgType(argName: String, actual: JSValue)

    /// Builds the JS `Error` object this failure should surface as, matching the shape of
    /// Node's own filesystem errors closely enough for `error.code` checks to work the same way.
    func jsValue(in context: JSContext) -> JSValue {
        switch self {
        case .posix(let errnoValue, let syscall, let path, let path2):
            let code = NodeFS.errorCode(for: errnoValue)
            let reason = unsafe String(cString: strerror(errnoValue))
            let text = path2.map { "\(code): \(reason), \(syscall) '\(path)' -> '\($0)'" }
                ?? "\(code): \(reason), \(syscall) '\(path)'"
            let error = JSValue(newErrorFromMessage: text, in: context) ?? JSValue(undefinedIn: context)
            error?.setObject(code, forKeyedSubscript: "code" as NSString)
            error?.setObject(syscall, forKeyedSubscript: "syscall" as NSString)
            error?.setObject(path, forKeyedSubscript: "path" as NSString)
            if let path2 { error?.setObject(path2, forKeyedSubscript: "dest" as NSString) }
            error?.setObject(-Int(errnoValue), forKeyedSubscript: "errno" as NSString)
            return error ?? JSValue(undefinedIn: context)
        case .generic(let code, let message):
            let error = JSValue(newErrorFromMessage: message, in: context) ?? JSValue(undefinedIn: context)
            error?.setObject(code, forKeyedSubscript: "code" as NSString)
            return error ?? JSValue(undefinedIn: context)
        case .invalidArgType(let argName, let actual):
            let message = "The \"\(argName)\" argument must be of type string. Received \(NodeFS.describeType(actual))"
            let error = JSValue(newErrorFromMessage: message, in: context) ?? JSValue(undefinedIn: context)
            error?.setObject("ERR_INVALID_ARG_TYPE", forKeyedSubscript: "code" as NSString)
            return error ?? JSValue(undefinedIn: context)
        }
    }
}

/// A partial re-implementation of Node.js's `fs` module, covering the synchronous API and
/// `fs.promises`. See ``NodeUtil`` for the sibling `util` re-implementation and the rationale
/// for grouping Node built-ins this way.
///
/// Every throwing function here does the real POSIX syscall itself (rather than going through
/// `FileManager`) so that failures carry a real `errno`, letting ``NodeFSFailure`` build a JS
/// error with the same `.code` (`"ENOENT"`, `"EEXIST"`, etc.) Node code expects to check.
///
/// There is no `Buffer` type in this engine yet, so unlike Node, file content is always read
/// and written as UTF-8 text - passing any other `encoding` throws `ERR_INVALID_ARG_VALUE`.
enum NodeFS {
    /// Expand `~` in a path the same way every other filesystem-facing module in this app does.
    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Validates that a JS value is a string, throwing Node's `ERR_INVALID_ARG_TYPE` otherwise.
    ///
    /// Every JS-facing string parameter in this module is declared `JSString` (see
    /// `Engine/JSFunction.swift`) rather than `String` specifically so this can run before
    /// JSExport's automatic coercion would otherwise silently turn a number/array/object into
    /// some string and hide the caller's mistake.
    fileprivate static func requireString(_ value: JSString, _ argName: String) throws -> String {
        guard value.isString else {
            throw NodeFSFailure.invalidArgType(argName: argName, actual: value)
        }
        return value.toString() ?? ""
    }

    /// Same as `requireString`, but a missing/`undefined`/`null` value is treated as "not
    /// provided" (returns `nil`) rather than an error. This is also where JSExport's
    /// undefined-argument quirk is handled now - at the `JSValue` level, before it can be
    /// stringified to the literal text `"undefined"`.
    fileprivate static func requireOptionalString(_ value: JSString?, _ argName: String) throws -> String? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard value.isString else {
            throw NodeFSFailure.invalidArgType(argName: argName, actual: value)
        }
        return value.toString() ?? ""
    }

    /// Extracts a boolean flag from a Node-style options argument (eg. `{ recursive: true }`).
    ///
    /// Real Node functions like `mkdirSync`/`rmSync`/`readdirSync` take a single options
    /// *object* here, not a positional boolean - passing a bare boolean (as this module's first
    /// implementation did, and as some of this module's own tests still do for convenience) is
    /// something Node itself never supported. To stay compatible with real Node code while not
    /// breaking that shorthand, a bare boolean is accepted too and treated as this flag's value
    /// directly. Anything else (omitted/`undefined`/`null`, or an object missing this field)
    /// yields `defaultValue`.
    fileprivate static func optionsFlag(_ options: JSValue?, _ field: String, default defaultValue: Bool = false) -> Bool {
        guard let options, !options.isUndefined, !options.isNull else { return defaultValue }
        if options.isBoolean { return options.toBool() }
        guard options.isObject, let value = options.objectForKeyedSubscript(field), !value.isUndefined, !value.isNull else {
            return defaultValue
        }
        return value.toBool()
    }

    /// Extracts an integer field from a Node-style options object (eg. `{ mode: 0o755 }`).
    /// Unlike `optionsFlag`, there's no bare-value shorthand: a non-object `options` (or an
    /// object missing this field) yields `defaultValue`.
    fileprivate static func optionsInt(_ options: JSValue?, _ field: String, default defaultValue: Int) -> Int {
        guard let options, options.isObject,
              let value = options.objectForKeyedSubscript(field), !value.isUndefined, !value.isNull
        else { return defaultValue }
        return Int(value.toInt32())
    }

    /// Defines each key/value pair in `fields` as a real *own*, enumerable data property on
    /// `target`, via `Object.defineProperty` rather than plain assignment. This matters because
    /// every `@objc` property JSExport bridges (eg. `NodeFSStats.size`) is installed as a
    /// non-enumerable *inherited* accessor on a shared per-class prototype (mirroring how a
    /// JS `class { get size() {} }` behaves) - so a plain `target[key] = value` wouldn't create
    /// a new own property at all; it would invoke that inherited accessor's setter (or silently
    /// no-op for a getter-only one). `defineProperty` bypasses the prototype chain entirely and
    /// writes straight to `target`'s own property table, so the new property shadows the
    /// inherited one for `Object.keys()`/`JSON.stringify()`/`util.inspect()`/spread - while
    /// direct access (`stats.size`) already worked fine either way, since normal property
    /// *reads* do walk the prototype chain regardless of enumerability.
    ///
    /// See `NodeFSStats.primeEnumerableProperties(in:)` / `NodeFSDirent.primeEnumerableProperties(in:)`,
    /// which use this to match Node's real `fs.Stats`/`fs.Dirent` (whose constructors assign
    /// their data fields with `this.x = value`, an own-and-enumerable JS mechanism from the
    /// start - fundamentally different from a class-body accessor, not just a different flag).
    fileprivate static func defineEnumerableProperties(on target: JSValue, in context: JSContext, _ fields: [String: Any]) {
        guard let objectConstructor = context.objectForKeyedSubscript("Object") else { return }
        for (key, value) in fields {
            _ = objectConstructor.invokeMethod("defineProperty", withArguments: [
                target, key,
                ["value": value, "enumerable": true, "writable": false, "configurable": true] as [String: Any],
            ])
        }
    }

    /// Parses `readdirSync`/`fs.promises.readdir`'s options argument. A bare boolean is
    /// shorthand for `withFileTypes` only (matching this module's pre-options-object API) -
    /// `recursive` is never implied by it, only ever read from an actual options object.
    fileprivate static func parseReaddirOptions(_ options: JSValue?) -> (withFileTypes: Bool, recursive: Bool) {
        if let options, options.isBoolean {
            return (options.toBool(), false)
        }
        return (optionsFlag(options, "withFileTypes"), optionsFlag(options, "recursive"))
    }

    /// Parses `rmSync`/`fs.promises.rm`'s options argument. A bare boolean is shorthand for
    /// `recursive` only (the flag anyone reaching for a shorthand almost always means) -
    /// `force` is never implied by it, only ever read from an actual options object.
    fileprivate static func parseRmOptions(_ options: JSValue?) -> (recursive: Bool, force: Bool) {
        if let options, options.isBoolean {
            return (options.toBool(), false)
        }
        return (optionsFlag(options, "recursive"), optionsFlag(options, "force"))
    }

    /// Mirrors Node's internal `determineSpecificType()`, used to build the "Received ..."
    /// suffix of `ERR_INVALID_ARG_TYPE` messages.
    fileprivate nonisolated static func describeType(_ value: JSValue) -> String {
        if value.isNull { return "null" }
        if value.isUndefined { return "undefined" }
        if value.isBoolean { return value.toBool() ? "type boolean (true)" : "type boolean (false)" }
        if value.isNumber {
            let d = value.toDouble()
            if d == 0 { return d.sign == .minus ? "type number (-0)" : "type number (0)" }
            if d.isNaN { return "type number (NaN)" }
            if d == .infinity { return "type number (Infinity)" }
            if d == -.infinity { return "type number (-Infinity)" }
            return "type number (\(value.toString() ?? "\(d)"))"
        }
        if value.isString {
            var s = value.toString() ?? ""
            if s.count > 28 { s = String(s.prefix(25)) + "..." }
            return s.contains("'") ? "type string (\"\(s)\")" : "type string ('\(s)')"
        }
        if value.isFunction {
            let name = value.objectForKeyedSubscript("name")?.toString() ?? ""
            return "function \(name)"
        }
        if value.isObject {
            if let ctorName = value.objectForKeyedSubscript("constructor")?.objectForKeyedSubscript("name")?.toString(),
               !ctorName.isEmpty {
                return "an instance of \(ctorName)"
            }
            return "an object"
        }
        return "type \(value.toString() ?? "unknown")"
    }

    /// Maps a raw `errno` to the string Node's `error.code` would report for it. Covers the
    /// codes filesystem code commonly branches on; anything else becomes `"UNKNOWN"`, matching
    /// libuv's own fallback.
    fileprivate nonisolated static func errorCode(for errnoValue: Int32) -> String {
        switch errnoValue {
        case ENOENT:     return "ENOENT"
        case EPERM:      return "EPERM"
        case EACCES:     return "EACCES"
        case EEXIST:     return "EEXIST"
        case ENOTDIR:    return "ENOTDIR"
        case EISDIR:     return "EISDIR"
        case EINVAL:     return "EINVAL"
        case EMFILE:     return "EMFILE"
        case ENFILE:     return "ENFILE"
        case ENOSPC:     return "ENOSPC"
        case EROFS:      return "EROFS"
        case ENAMETOOLONG: return "ENAMETOOLONG"
        case ELOOP:      return "ELOOP"
        case ENOTEMPTY:  return "ENOTEMPTY"
        case EXDEV:      return "EXDEV"
        case EBADF:      return "EBADF"
        case ENOTSUP:    return "ENOTSUP"
        default:         return "UNKNOWN"
        }
    }

    /// Builds a fresh copy of the dictionary backing `fs.constants`/`fs.promises.constants`
    /// (see the doc comment on `NodeFSModuleAPI.constants` for the grouping). Only constants
    /// that are meaningful on macOS are included; the Windows/libuv-internal-only ones Node
    /// also exposes (`UV_FS_SYMLINK_*`, `UV_FS_O_*`, `UV_DIRENT_*`) are omitted.
    ///
    /// Typed `NSDictionary` (a real reference type) rather than `[String: Int]`: JSExport
    /// re-bridges a Swift `Dictionary`-typed property fresh on every read, so two accessors
    /// vending the "same" Swift dictionary value do not produce `===`-equal JS objects - a
    /// stored `NSDictionary` reference bridges once and keeps its JS wrapper identity across
    /// reads instead, which `fs.promises.constants === fs.constants` (matching Node) needs.
    ///
    /// This is a *function*, not a shared `static let`: each `NodeFSModule` (one per `JSContext`,
    /// via `NodeBuiltinModulesInstaller`) must call this once and share the single result with
    /// its own `NodeFSPromisesModule` - never store the result somewhere wider than one JS
    /// context. A single process-wide `static let` instance bridged into a *different*
    /// `JSVirtualMachine` per `require('fs')` call is unambiguously wrong regardless of the
    /// point below. Separately, and even with per-context instances: JavaScriptCore's bridged-
    /// object identity is empirically unreliable specifically when a test process creates and
    /// tears down many short-lived `JSVirtualMachine`s in a row (confirmed: the two `NSDictionary`
    /// instances have identical content but `===` intermittently still reports `false`) - this
    /// doesn't affect the real app, which only ever has one `JSContext` alive at a time, so
    /// tests assert structural equality instead of `===` for this specific property.
    static func makeConstants() -> NSDictionary { [
        "F_OK": Int(F_OK),
        "R_OK": Int(R_OK),
        "W_OK": Int(W_OK),
        "X_OK": Int(X_OK),
        "COPYFILE_EXCL": 1,
        "COPYFILE_FICLONE": 2,
        "COPYFILE_FICLONE_FORCE": 4,
        "S_IFMT": Int(S_IFMT),
        "S_IFREG": Int(S_IFREG),
        "S_IFDIR": Int(S_IFDIR),
        "S_IFCHR": Int(S_IFCHR),
        "S_IFBLK": Int(S_IFBLK),
        "S_IFIFO": Int(S_IFIFO),
        "S_IFLNK": Int(S_IFLNK),
        "S_IFSOCK": Int(S_IFSOCK),
        "S_IRWXU": Int(S_IRWXU),
        "S_IRUSR": Int(S_IRUSR),
        "S_IWUSR": Int(S_IWUSR),
        "S_IXUSR": Int(S_IXUSR),
        "S_IRWXG": Int(S_IRWXG),
        "S_IRGRP": Int(S_IRGRP),
        "S_IWGRP": Int(S_IWGRP),
        "S_IXGRP": Int(S_IXGRP),
        "S_IRWXO": Int(S_IRWXO),
        "S_IROTH": Int(S_IROTH),
        "S_IWOTH": Int(S_IWOTH),
        "S_IXOTH": Int(S_IXOTH),
        "O_RDONLY": Int(O_RDONLY),
        "O_WRONLY": Int(O_WRONLY),
        "O_RDWR": Int(O_RDWR),
        "O_CREAT": Int(O_CREAT),
        "O_EXCL": Int(O_EXCL),
        "O_NOCTTY": Int(O_NOCTTY),
        "O_TRUNC": Int(O_TRUNC),
        "O_APPEND": Int(O_APPEND),
        "O_DIRECTORY": Int(O_DIRECTORY),
        "O_NOFOLLOW": Int(O_NOFOLLOW),
        "O_SYNC": Int(O_SYNC),
        "O_DSYNC": Int(O_DSYNC),
        "O_SYMLINK": Int(O_SYMLINK),
        "O_NONBLOCK": Int(O_NONBLOCK),
    ]
    }

    /// Translates an `NSError` thrown by `FileManager` into a ``NodeFSFailure``, unwrapping the
    /// underlying POSIX error when `FileManager` provides one so `.code` stays accurate.
    private static func wrap(_ error: Error, syscall: String, path: String) -> NodeFSFailure {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            return .posix(errnoValue: Int32(ns.code), syscall: syscall, path: path, path2: nil)
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return .posix(errnoValue: Int32(underlying.code), syscall: syscall, path: path, path2: nil)
        }
        return .generic(code: "UNKNOWN", message: ns.localizedDescription)
    }

    // MARK: - File I/O

    static func existsSync(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: expand(path))
    }

    static func readFile(_ path: String, encoding: String?) throws -> String {
        if let encoding, !["utf8", "utf-8"].contains(encoding.lowercased()) {
            throw NodeFSFailure.generic(
                code: "ERR_INVALID_ARG_VALUE",
                message: "The \"encoding\" argument must be 'utf8'; Buffer output is not supported. Received '\(encoding)'"
            )
        }
        let full = expand(path)
        let fd = unsafe open(full, O_RDONLY)
        guard fd >= 0 else { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "open", path: path, path2: nil) }
        defer { close(fd) }

        var st = Darwin.stat()
        guard unsafe fstat(fd, &st) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "fstat", path: path, path2: nil)
        }
        if (st.st_mode & S_IFMT) == S_IFDIR {
            throw NodeFSFailure.posix(errnoValue: EISDIR, syscall: "read", path: path, path2: nil)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = buffer.withUnsafeMutableBytes { unsafe read(fd, $0.baseAddress, $0.count) }
            if n < 0 { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "read", path: path, path2: nil) }
            if n == 0 { break }
            unsafe data.append(buffer, count: n)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw NodeFSFailure.generic(code: "ERR_INVALID_ARG_VALUE", message: "\(path) does not contain valid UTF-8 data")
        }
        return string
    }

    /// Maps a Node write `flag` string to the `open()` flags it corresponds to. Only the four
    /// flags most JS code actually uses are supported: `"w"` (default), `"wx"`, `"a"`, `"ax"`.
    private static func openFlags(forWriteFlag flag: String?) -> Int32 {
        switch flag {
        case "a":  return O_WRONLY | O_CREAT | O_APPEND
        case "ax": return O_WRONLY | O_CREAT | O_APPEND | O_EXCL
        case "wx": return O_WRONLY | O_CREAT | O_TRUNC | O_EXCL
        default:   return O_WRONLY | O_CREAT | O_TRUNC
        }
    }

    static func writeFile(_ path: String, _ content: String, flag: String?) throws {
        let full = expand(path)
        let fd = unsafe open(full, openFlags(forWriteFlag: flag), 0o666)
        guard fd >= 0 else { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "open", path: path, path2: nil) }
        defer { close(fd) }

        guard let data = content.data(using: .utf8) else {
            throw NodeFSFailure.generic(code: "ERR_INVALID_ARG_VALUE", message: "content could not be encoded as UTF-8")
        }
        try unsafe data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            var written = 0
            while written < ptr.count {
                let n = unsafe write(fd, ptr.baseAddress!.advanced(by: written), ptr.count - written)
                if n < 0 { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "write", path: path, path2: nil) }
                written += n
            }
        }
    }

    static func appendFile(_ path: String, _ content: String) throws {
        try writeFile(path, content, flag: "a")
    }

    // MARK: - Directories

    static func mkdir(_ path: String, recursive: Bool) throws {
        let full = expand(path)
        guard recursive else {
            guard unsafe Darwin.mkdir(full, 0o777) == 0 else {
                throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "mkdir", path: path, path2: nil)
            }
            return
        }

        // Preserve whether `full` is absolute or relative: unconditionally prefixing every
        // accumulated component with "/" would root a relative path (eg. "build/dist") at
        // "/build/dist" instead of resolving it against the current working directory.
        let isAbsolute = full.hasPrefix("/")
        var accumulated = ""
        for component in full.split(separator: "/") {
            accumulated = accumulated.isEmpty
                ? (isAbsolute ? "/\(component)" : String(component))
                : "\(accumulated)/\(component)"
            if unsafe Darwin.mkdir(accumulated, 0o777) != 0, Darwin.errno != EEXIST {
                throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "mkdir", path: path, path2: nil)
            }
        }
    }

    static func rmdir(_ path: String, recursive: Bool) throws {
        let full = expand(path)
        guard recursive else {
            guard unsafe Darwin.rmdir(full) == 0 else {
                throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "rmdir", path: path, path2: nil)
            }
            return
        }
        do {
            try FileManager.default.removeItem(atPath: full)
        } catch {
            throw wrap(error, syscall: "rmdir", path: path)
        }
    }

    static func rm(_ path: String, recursive: Bool, force: Bool) throws {
        let full = expand(path)
        var st = Darwin.stat()
        guard unsafe Darwin.lstat(full, &st) == 0 else {
            if Darwin.errno == ENOENT, force { return }
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "lstat", path: path, path2: nil)
        }

        let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        guard isDirectory else {
            guard unsafe Darwin.unlink(full) == 0 else {
                // `force` (matching Node) only ignores the path already being gone - a TOCTOU
                // race is possible even though the lstat() above just confirmed it existed -
                // not any other failure (permissions, etc.), which must still be reported.
                if Darwin.errno == ENOENT, force { return }
                throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "unlink", path: path, path2: nil)
            }
            return
        }

        // Unlike `rmdirSync`, `rmSync` never removes a directory - empty or not - unless
        // `recursive` is set. `force` doesn't substitute for this either: it's a wholly
        // separate option, only ever about the path already being missing.
        guard recursive else {
            throw NodeFSFailure.generic(
                code: "ERR_FS_EISDIR",
                message: "Path is a directory: rm returned EISDIR (is a directory) \(path)"
            )
        }

        do {
            try FileManager.default.removeItem(atPath: full)
        } catch {
            let failure = wrap(error, syscall: "rm", path: path)
            if case .posix(let errnoValue, _, _, _) = failure, errnoValue == ENOENT, force { return }
            throw failure
        }
    }

    static func readdir(_ path: String, withFileTypes: Bool, recursive: Bool) throws -> [Any] {
        let full = expand(path)
        return try readdir(atFullPath: full, relativeTo: full, withFileTypes: withFileTypes, recursive: recursive, originalPath: path)
    }

    /// - Parameters:
    ///   - fullPath: Absolute path of the directory to list right now.
    ///   - root: Absolute path of the top-level directory the caller asked for, used to compute
    ///     relative paths when `recursive` is `true`.
    ///   - originalPath: The path exactly as the caller passed it (unexpanded), for error messages.
    private static func readdir(
        atFullPath fullPath: String,
        relativeTo root: String,
        withFileTypes: Bool,
        recursive: Bool,
        originalPath: String
    ) throws -> [Any] {
        guard let dir = unsafe opendir(fullPath) else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "scandir", path: originalPath, path2: nil)
        }
        defer { unsafe closedir(dir) }

        var results: [Any] = []
        var subdirectories: [String] = []
        while let entry = unsafe Darwin.readdir(dir) {
            let name = unsafe withUnsafePointer(to: entry.pointee.d_name) { namePtr in
                unsafe namePtr.withMemoryRebound(to: CChar.self, capacity: 1024) { unsafe String(cString: $0) }
            }
            if name == "." || name == ".." { continue }

            let entryFullPath = "\(fullPath)/\(name)"
            let dType = unsafe entry.pointee.d_type
            let type = direntType(dType: dType, fullPath: entryFullPath)

            if withFileTypes {
                // Matches Node: `Dirent.name` is always the bare filename, even when `recursive`
                // is set. Node also exposes `.parentPath` in that case, which this engine does
                // not implement yet.
                results.append(NodeFSDirent(name: name, type: type))
            } else if recursive {
                let relativePath = entryFullPath.hasPrefix(root + "/")
                    ? String(entryFullPath.dropFirst(root.count + 1))
                    : name
                results.append(relativePath)
            } else {
                results.append(name)
            }

            if recursive, type == "directory" {
                subdirectories.append(entryFullPath)
            }
        }

        if recursive {
            for subdirectory in subdirectories.sorted() {
                let nested = try readdir(
                    atFullPath: subdirectory,
                    relativeTo: root,
                    withFileTypes: withFileTypes,
                    recursive: recursive,
                    originalPath: originalPath
                )
                results.append(contentsOf: nested)
            }
        }
        return results
    }

    private static func direntType(dType: UInt8, fullPath: String) -> String {
        switch dType {
        case UInt8(DT_REG):  return "file"
        case UInt8(DT_DIR):  return "directory"
        case UInt8(DT_LNK):  return "symlink"
        case UInt8(DT_SOCK): return "socket"
        case UInt8(DT_FIFO): return "fifo"
        case UInt8(DT_CHR):  return "characterDevice"
        case UInt8(DT_BLK):  return "blockDevice"
        default:
            var st = Darwin.stat()
            guard unsafe Darwin.lstat(fullPath, &st) == 0 else { return "unknown" }
            switch st.st_mode & S_IFMT {
            case S_IFREG:  return "file"
            case S_IFDIR:  return "directory"
            case S_IFLNK:  return "symlink"
            case S_IFSOCK: return "socket"
            case S_IFIFO:  return "fifo"
            case S_IFCHR:  return "characterDevice"
            case S_IFBLK:  return "blockDevice"
            default:       return "unknown"
            }
        }
    }

    // MARK: - Metadata

    static func stat(_ path: String) throws -> NodeFSStats {
        let full = expand(path)
        // Calling the POSIX stat() function by name is ambiguous in Swift (it collides with the
        // imported `struct stat` type's synthesized initializer), so "follow symlinks" is
        // implemented as realpath() (which resolves every symlink in the path) + lstat() on the
        // result - equivalent to stat(), and consistent with how hs.fs avoids the same collision.
        guard let resolvedPtr = unsafe Darwin.realpath(full, nil) else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "stat", path: path, path2: nil)
        }
        defer { unsafe free(resolvedPtr) }
        guard let resolved = unsafe String(validatingCString: resolvedPtr) else {
            throw NodeFSFailure.generic(code: "UNKNOWN", message: "stat: could not decode resolved path for \(path)")
        }
        var st = Darwin.stat()
        guard unsafe Darwin.lstat(resolved, &st) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "stat", path: path, path2: nil)
        }
        return NodeFSStats(st)
    }

    static func lstat(_ path: String) throws -> NodeFSStats {
        let full = expand(path)
        var st = Darwin.stat()
        guard unsafe Darwin.lstat(full, &st) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "lstat", path: path, path2: nil)
        }
        return NodeFSStats(st)
    }

    // MARK: - Files and links

    static func rename(_ oldPath: String, _ newPath: String) throws {
        guard unsafe Darwin.rename(expand(oldPath), expand(newPath)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "rename", path: oldPath, path2: newPath)
        }
    }

    static func copyFile(_ src: String, _ dest: String, mode: Int) throws {
        let s = expand(src)
        let d = expand(dest)
        let excl = (mode & 1) != 0 // fs.constants.COPYFILE_EXCL

        let srcFD = unsafe open(s, O_RDONLY)
        guard srcFD >= 0 else { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "open", path: src, path2: nil) }
        defer { close(srcFD) }

        var srcStat = Darwin.stat()
        guard unsafe fstat(srcFD, &srcStat) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "fstat", path: src, path2: nil)
        }

        // Guard against src and dest resolving to the same file (the same path, a hard link to
        // the same inode, or dest being a symlink that points back at src): opening dest with
        // O_TRUNC below would otherwise truncate the shared file before any bytes are read,
        // silently destroying its content while still reporting success. realpath() resolves
        // any symlinks in dest's path (including a symlink dest itself), so lstat-ing the
        // result is equivalent to stat-ing the original dest path.
        if let destResolvedPtr = unsafe Darwin.realpath(d, nil) {
            defer { unsafe free(destResolvedPtr) }
            if let destResolved = unsafe String(validatingCString: destResolvedPtr) {
                var destStat = Darwin.stat()
                if unsafe Darwin.lstat(destResolved, &destStat) == 0,
                   destStat.st_dev == srcStat.st_dev, destStat.st_ino == srcStat.st_ino {
                    throw NodeFSFailure.posix(errnoValue: EINVAL, syscall: "copyfile", path: dest, path2: nil)
                }
            }
        }

        var destFlags: Int32 = O_WRONLY | O_CREAT | O_TRUNC
        if excl { destFlags |= O_EXCL }
        let destFD = unsafe open(d, destFlags, 0o666)
        guard destFD >= 0 else { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "open", path: dest, path2: nil) }
        defer { close(destFD) }

        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = buffer.withUnsafeMutableBytes { unsafe read(srcFD, $0.baseAddress, $0.count) }
            if n < 0 { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "read", path: src, path2: nil) }
            if n == 0 { break }
            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                    unsafe write(destFD, ptr.baseAddress!.advanced(by: written), n - written)
                }
                if w < 0 { throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "write", path: dest, path2: nil) }
                written += w
            }
        }
    }

    static func symlink(_ target: String, _ path: String) throws {
        // `target` is intentionally not expanded/resolved: like Node/POSIX symlink(), it need
        // not exist and is stored in the link literally.
        guard unsafe Darwin.symlink(target, expand(path)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "symlink", path: path, path2: nil)
        }
    }

    static func readlink(_ path: String) throws -> String {
        let full = expand(path)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let n = buffer.withUnsafeMutableBufferPointer { ptr in
            unsafe Darwin.readlink(full, ptr.baseAddress, ptr.count - 1)
        }
        guard n >= 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "readlink", path: path, path2: nil)
        }
        let bytes = buffer[0..<n].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func realpath(_ path: String) throws -> String {
        let full = expand(path)
        guard let resolved = unsafe Darwin.realpath(full, nil) else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "realpath", path: path, path2: nil)
        }
        defer { unsafe free(resolved) }
        guard let result = unsafe String(validatingCString: resolved) else {
            throw NodeFSFailure.generic(code: "UNKNOWN", message: "realpath: could not decode result for \(path)")
        }
        return result
    }

    static func link(_ existingPath: String, _ newPath: String) throws {
        guard unsafe Darwin.link(expand(existingPath), expand(newPath)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "link", path: existingPath, path2: newPath)
        }
    }

    static func unlink(_ path: String) throws {
        guard unsafe Darwin.unlink(expand(path)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "unlink", path: path, path2: nil)
        }
    }

    static func access(_ path: String, mode: Int) throws {
        guard unsafe Darwin.access(expand(path), Int32(mode)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "access", path: path, path2: nil)
        }
    }

    static func truncate(_ path: String, len: Int) throws {
        guard unsafe Darwin.truncate(expand(path), off_t(len)) == 0 else {
            throw NodeFSFailure.posix(errnoValue: Darwin.errno, syscall: "truncate", path: path, path2: nil)
        }
    }
}

// MARK: - fs.Stats

/// The JS-facing surface of a Node-style `fs.Stats` object, as returned by `statSync`/`lstatSync`
/// (and their `fs.promises` equivalents). Users should never construct these directly.
@objc protocol NodeFSStatsAPI: HSTypeAPI, JSExport {
    /// ID of the device containing the file.
    @objc var dev: Int { get }
    /// Inode number.
    @objc var ino: Int { get }
    /// File mode: type and permission bits, eg. `33188` (`0o100644`).
    @objc var mode: Int { get }
    /// Number of hard links.
    @objc var nlink: Int { get }
    /// User ID of the owner.
    @objc var uid: Int { get }
    /// Group ID of the owner.
    @objc var gid: Int { get }
    /// Device ID, if this is a device file.
    @objc var rdev: Int { get }
    /// Size in bytes.
    @objc var size: Int { get }
    /// Preferred block size for I/O.
    @objc var blksize: Int { get }
    /// Number of 512-byte blocks allocated.
    @objc var blocks: Int { get }
    /// Last access time, in milliseconds since the Unix epoch.
    @objc var atimeMs: Double { get }
    /// Last modification time, in milliseconds since the Unix epoch.
    @objc var mtimeMs: Double { get }
    /// Last inode change time, in milliseconds since the Unix epoch.
    @objc var ctimeMs: Double { get }
    /// Creation time, in milliseconds since the Unix epoch.
    @objc var birthtimeMs: Double { get }
    /// Last access time.
    @objc var atime: Date { get }
    /// Last modification time.
    @objc var mtime: Date { get }
    /// Last inode change time.
    @objc var ctime: Date { get }
    /// Creation time.
    @objc var birthtime: Date { get }

    /// Check whether this describes a regular file.
    /// - Returns: `true` if this describes a regular file.
    /// - Example: `fs.statSync("/etc/hosts").isFile() // true`
    @objc func isFile() -> Bool
    /// Check whether this describes a directory.
    /// - Returns: `true` if this describes a directory.
    /// - Example: `fs.statSync("/tmp").isDirectory() // true`
    @objc func isDirectory() -> Bool
    /// Check whether this describes a symbolic link.
    /// - Returns: `true` if this describes a symbolic link. Only ever `true` when the `Stats`
    ///   came from `lstatSync`/`fs.promises.lstat`, since `statSync` follows symlinks.
    @objc func isSymbolicLink() -> Bool
    /// Check whether this describes a block device.
    /// - Returns: `true` if this describes a block device.
    @objc func isBlockDevice() -> Bool
    /// Check whether this describes a character device.
    /// - Returns: `true` if this describes a character device.
    @objc func isCharacterDevice() -> Bool
    /// Check whether this describes a FIFO/named pipe.
    /// - Returns: `true` if this describes a FIFO/named pipe.
    @objc func isFIFO() -> Bool
    /// Check whether this describes a Unix domain socket.
    /// - Returns: `true` if this describes a Unix domain socket.
    @objc func isSocket() -> Bool
}

@_documentation(visibility: private)
@objc class NodeFSStats: NSObject, NodeFSStatsAPI {
    @objc var typeName = "NodeFSStats"

    @objc let dev: Int
    @objc let ino: Int
    @objc let mode: Int
    @objc let nlink: Int
    @objc let uid: Int
    @objc let gid: Int
    @objc let rdev: Int
    @objc let size: Int
    @objc let blksize: Int
    @objc let blocks: Int
    @objc let atimeMs: Double
    @objc let mtimeMs: Double
    @objc let ctimeMs: Double
    @objc let birthtimeMs: Double

    init(_ st: Darwin.stat) {
        dev = Int(st.st_dev)
        ino = Int(st.st_ino)
        mode = Int(st.st_mode)
        nlink = Int(st.st_nlink)
        uid = Int(st.st_uid)
        gid = Int(st.st_gid)
        rdev = Int(st.st_rdev)
        size = Int(st.st_size)
        blksize = Int(st.st_blksize)
        blocks = Int(st.st_blocks)
        atimeMs = Double(st.st_atimespec.tv_sec) * 1000 + Double(st.st_atimespec.tv_nsec) / 1_000_000
        mtimeMs = Double(st.st_mtimespec.tv_sec) * 1000 + Double(st.st_mtimespec.tv_nsec) / 1_000_000
        ctimeMs = Double(st.st_ctimespec.tv_sec) * 1000 + Double(st.st_ctimespec.tv_nsec) / 1_000_000
        birthtimeMs = Double(st.st_birthtimespec.tv_sec) * 1000 + Double(st.st_birthtimespec.tv_nsec) / 1_000_000
        modeBits = mode_t(st.st_mode)
        super.init()
    }

    private let modeBits: mode_t

    @objc var atime: Date { Date(timeIntervalSince1970: atimeMs / 1000) }
    @objc var mtime: Date { Date(timeIntervalSince1970: mtimeMs / 1000) }
    @objc var ctime: Date { Date(timeIntervalSince1970: ctimeMs / 1000) }
    @objc var birthtime: Date { Date(timeIntervalSince1970: birthtimeMs / 1000) }

    @objc func isFile() -> Bool { (modeBits & S_IFMT) == S_IFREG }
    @objc func isDirectory() -> Bool { (modeBits & S_IFMT) == S_IFDIR }
    @objc func isSymbolicLink() -> Bool { (modeBits & S_IFMT) == S_IFLNK }
    @objc func isBlockDevice() -> Bool { (modeBits & S_IFMT) == S_IFBLK }
    @objc func isCharacterDevice() -> Bool { (modeBits & S_IFMT) == S_IFCHR }
    @objc func isFIFO() -> Bool { (modeBits & S_IFMT) == S_IFIFO }
    @objc func isSocket() -> Bool { (modeBits & S_IFMT) == S_IFSOCK }

    @objc func toString() -> String { "<NodeFSStats: size=\(size), mode=\(String(mode, radix: 8))>" }
    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    /// Must be called (with the current `JSContext`) before this object is first returned to
    /// JS, so its data fields show up under `Object.keys()`/`JSON.stringify()`/`util.inspect()`/
    /// spread, matching Node's own `fs.Stats` - see `NodeFS.defineEnumerableProperties` for why
    /// this is otherwise not the case. `isFile()` etc. intentionally stay as ordinary
    /// (non-enumerable) prototype methods, matching Node's own `Stats.prototype.isFile` etc.
    @discardableResult
    func primeEnumerableProperties(in context: JSContext) -> JSValue {
        let wrapper = JSValue(object: self, in: context)!
        NodeFS.defineEnumerableProperties(on: wrapper, in: context, [
            "dev": dev, "ino": ino, "mode": mode, "nlink": nlink, "uid": uid, "gid": gid,
            "rdev": rdev, "size": size, "blksize": blksize, "blocks": blocks,
            "atimeMs": atimeMs, "mtimeMs": mtimeMs, "ctimeMs": ctimeMs, "birthtimeMs": birthtimeMs,
            "atime": atime, "mtime": mtime, "ctime": ctime, "birthtime": birthtime,
        ])
        return wrapper
    }
}

// MARK: - fs.Dirent

/// The JS-facing surface of a Node-style `fs.Dirent` object, as returned by
/// `readdirSync(path, { withFileTypes: true })`. Users should never construct these directly.
@objc protocol NodeFSDirentAPI: HSTypeAPI, JSExport {
    /// The bare filename (not a full path).
    @objc var name: String { get }

    /// Check whether this entry is a regular file.
    /// - Returns: `true` if this entry is a regular file.
    @objc func isFile() -> Bool
    /// Check whether this entry is a directory.
    /// - Returns: `true` if this entry is a directory.
    @objc func isDirectory() -> Bool
    /// Check whether this entry is a symbolic link.
    /// - Returns: `true` if this entry is a symbolic link.
    @objc func isSymbolicLink() -> Bool
    /// Check whether this entry is a block device.
    /// - Returns: `true` if this entry is a block device.
    @objc func isBlockDevice() -> Bool
    /// Check whether this entry is a character device.
    /// - Returns: `true` if this entry is a character device.
    @objc func isCharacterDevice() -> Bool
    /// Check whether this entry is a FIFO/named pipe.
    /// - Returns: `true` if this entry is a FIFO/named pipe.
    @objc func isFIFO() -> Bool
    /// Check whether this entry is a Unix domain socket.
    /// - Returns: `true` if this entry is a Unix domain socket.
    @objc func isSocket() -> Bool
}

@_documentation(visibility: private)
@objc class NodeFSDirent: NSObject, NodeFSDirentAPI {
    @objc var typeName = "NodeFSDirent"
    @objc let name: String
    private let type: String

    init(name: String, type: String) {
        self.name = name
        self.type = type
        super.init()
    }

    @objc func isFile() -> Bool { type == "file" }
    @objc func isDirectory() -> Bool { type == "directory" }
    @objc func isSymbolicLink() -> Bool { type == "symlink" }
    @objc func isBlockDevice() -> Bool { type == "blockDevice" }
    @objc func isCharacterDevice() -> Bool { type == "characterDevice" }
    @objc func isFIFO() -> Bool { type == "fifo" }
    @objc func isSocket() -> Bool { type == "socket" }

    @objc func toString() -> String { "<NodeFSDirent: \(name) (\(type))>" }
    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    /// Must be called (with the current `JSContext`) before this object is first returned to
    /// JS, so `name` shows up under `Object.keys()`/`JSON.stringify()`/`util.inspect()`/spread,
    /// matching Node's own `fs.Dirent` - see `NodeFS.defineEnumerableProperties` for why this is
    /// otherwise not the case. `isFile()` etc. intentionally stay as ordinary (non-enumerable)
    /// prototype methods, matching Node's own `Dirent.prototype.isFile` etc.
    @discardableResult
    func primeEnumerableProperties(in context: JSContext) -> JSValue {
        let wrapper = JSValue(object: self, in: context)!
        NodeFS.defineEnumerableProperties(on: wrapper, in: context, ["name": name])
        return wrapper
    }
}

// MARK: - fs (sync)

/// The JS-facing surface of Node's `fs` module, reachable as `require('fs')`.
///
/// WARNING: This module is an experiment to see if high levels of Node.js compatibility can be achieved with AI agents.
///
/// Covers the synchronous API (`readFileSync`, `writeFileSync`, `statSync`, etc.) plus
/// `fs.promises`. There is no `Buffer` type in this engine yet, so file content is always
/// UTF-8 text - passing any `encoding` other than `"utf8"` throws.
///
/// Every `*Sync` function throws a JS `Error` on failure, with `.code` set to the same string
/// Node would use (`"ENOENT"`, `"EEXIST"`, `"ENOTEMPTY"`, etc.), plus `.errno`, `.syscall`, and
/// `.path`. Passing a non-string where a string is expected throws a `TypeError` with
/// `.code === "ERR_INVALID_ARG_TYPE"`, matching Node.
///
/// - Example:
/// ```js
/// const fs = require('fs')
///
/// fs.writeFileSync("/tmp/hello.txt", "Hello, world!\n")
/// console.log(fs.readFileSync("/tmp/hello.txt"))
///
/// try {
///     fs.readFileSync("/does/not/exist")
/// } catch (e) {
///     console.log(e.code) // "ENOENT"
/// }
/// ```
@objc protocol NodeFSModuleAPI: JSExport {
    /// Filesystem constants used by `accessSync`/`fs.promises.access` (`F_OK`, `R_OK`, `W_OK`,
    /// `X_OK`), `copyFileSync`/`fs.promises.copyFile` (`COPYFILE_*`), file mode bits (`S_I*`,
    /// checked against `Stats.mode`), and `open()` flags (`O_*`).
    @objc var constants: NSDictionary { get }

    /// SKIP_DOCS
    /// Fully documented as its own `fs.promises` namespace instead (see
    /// ``NodeFSPromisesModuleAPI``), to avoid colliding with that namespace in the generated
    /// TypeScript, which can't merge a `const` property with a nested namespace of the same name.
    @objc var promises: NodeFSPromisesModule { get }

    /// Synchronously check whether a path exists. Unlike every other function in this module,
    /// this never throws (matching Node) - a non-string argument is simply treated as
    /// "does not exist", the same as any other error checking the path.
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if anything exists at the path.
    /// - Example: `if (fs.existsSync("/tmp/file.txt")) console.log("exists")`
    @objc func existsSync(_ path: JSString) -> Bool

    /// Synchronously read a file as a UTF-8 string.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - encoding?: Must be `"utf8"` (or omitted); any other value throws, since this engine has no `Buffer` type.
    /// - Returns: The file's contents.
    /// - Example: `const text = fs.readFileSync("/etc/hosts", "utf8")`
    @objc func readFileSync(_ path: JSString, _ encoding: JSString?) -> String?

    /// Synchronously write a UTF-8 string to a file, creating or truncating it.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - data: String to write.
    ///   - flag?: One of `"w"` (default: create/truncate), `"wx"` (like `"w"` but fails if the file already exists), `"a"` (append), or `"ax"` (like `"a"` but fails if the file already exists).
    /// - Example: `fs.writeFileSync("/tmp/hello.txt", "Hello, world!\n")`
    @objc func writeFileSync(_ path: JSString, _ data: JSString, _ flag: JSString?)

    /// Synchronously append a UTF-8 string to a file, creating it if needed.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - data: String to append.
    /// - Example: `fs.appendFileSync("/tmp/log.txt", "another line\n")`
    @objc func appendFileSync(_ path: JSString, _ data: JSString)

    /// Synchronously create a directory.
    /// - Parameters:
    ///   - path: Path of the directory to create. `~` is expanded.
    ///   - options?: A `{ recursive: boolean }` object (matching Node), or a bare boolean as shorthand for `recursive`. When `recursive` is `true`, creates all missing intermediate directories and does not throw if the directory already exists. Defaults to `false`, matching Node.
    /// - Example: `fs.mkdirSync("~/Projects/new-thing", { recursive: true })`
    /// - Example: `fs.mkdirSync("~/Projects/new-thing", true)`
    @objc func mkdirSync(_ path: JSString, _ options: JSValue?)

    /// Synchronously remove an empty directory.
    /// - Parameters:
    ///   - path: Path of the directory to remove. `~` is expanded.
    ///   - options?: A `{ recursive: boolean }` object (matching Node), or a bare boolean as shorthand for `recursive`. When `true`, removes the directory and its entire contents. Defaults to `false`.
    /// - Example: `fs.rmdirSync("/tmp/empty-dir")`
    @objc func rmdirSync(_ path: JSString, _ options: JSValue?)

    /// Synchronously remove a file or directory. The modern replacement for `unlinkSync`/`rmdirSync`.
    ///
    /// Unlike `rmdirSync`, this never removes a directory - empty or not - unless `recursive`
    /// is `true`; without it, `path` being a directory throws (`ERR_FS_EISDIR`), matching Node.
    /// - Parameters:
    ///   - path: Path to remove. `~` is expanded.
    ///   - options?: A `{ recursive?: boolean, force?: boolean }` object, matching Node. `recursive`: when `true` and `path` is a directory, removes it and its entire contents; defaults to `false`. `force`: when `true`, a missing path is not treated as an error; defaults to `false`. `force` never substitutes for `recursive` - a directory without `recursive` still throws even with `force: true`.
    /// - Example: `fs.rmSync("/tmp/old-dir", { recursive: true, force: true })`
    @objc func rmSync(_ path: JSString, _ options: JSValue?)

    /// Synchronously delete a single file.
    /// - Parameter path: Path to the file. `~` is expanded.
    /// - Example: `fs.unlinkSync("/tmp/old.txt")`
    @objc func unlinkSync(_ path: JSString)

    /// Synchronously list the contents of a directory.
    /// - Parameters:
    ///   - path: Path to the directory. `~` is expanded.
    ///   - options?: A `{ withFileTypes?: boolean, recursive?: boolean }` object (matching Node), or a bare boolean as shorthand for `withFileTypes`. `withFileTypes`: returns `Dirent` objects instead of bare filenames; defaults to `false`. `recursive`: walks subdirectories too - filenames (when `withFileTypes` is `false`) become paths relative to `path`; `Dirent.name` stays the bare filename either way (this engine doesn't implement `Dirent.parentPath`); defaults to `false`.
    /// - Returns: An array of filenames, or of `Dirent` objects if `withFileTypes` is `true`.
    /// - Example: `const files = fs.readdirSync("~/Documents")`
    /// - Example: `fs.readdirSync("~/Documents", { withFileTypes: true }).forEach(d => console.log(d.name, d.isDirectory()))`
    /// - Example: `const allFiles = fs.readdirSync("~/Documents", { recursive: true })`
    @objc func readdirSync(_ path: JSString, _ options: JSValue?) -> [Any]?

    /// Synchronously get file metadata, following symbolic links.
    /// - Parameters:
    ///   - path: Path to inspect. `~` is expanded.
    ///   - options?: A `{ throwIfNoEntry?: boolean }` object (matching Node), or a bare boolean as shorthand for `throwIfNoEntry`. Defaults to `true`. When `false`, returns `undefined` instead of throwing if the path does not exist.
    /// - Returns: A `Stats` object.
    /// - Example: `console.log(fs.statSync("/etc/hosts").size)`
    @objc func statSync(_ path: JSString, _ options: JSValue?) -> NodeFSStats?

    /// Synchronously get file metadata, without following symbolic links.
    /// - Parameters:
    ///   - path: Path to inspect. `~` is expanded.
    ///   - options?: A `{ throwIfNoEntry?: boolean }` object (matching Node), or a bare boolean as shorthand for `throwIfNoEntry`. Defaults to `true`. When `false`, returns `undefined` instead of throwing if the path does not exist.
    /// - Returns: A `Stats` object.
    /// - Example: `console.log(fs.lstatSync("/var").isSymbolicLink())`
    @objc func lstatSync(_ path: JSString, _ options: JSValue?) -> NodeFSStats?

    /// Synchronously rename (move) a file or directory.
    /// - Parameters:
    ///   - oldPath: Existing path. `~` is expanded.
    ///   - newPath: New path. `~` is expanded.
    /// - Example: `fs.renameSync("/tmp/old.txt", "/tmp/new.txt")`
    @objc func renameSync(_ oldPath: JSString, _ newPath: JSString)

    /// Synchronously copy a file.
    /// - Parameters:
    ///   - src: Path to the existing file. `~` is expanded.
    ///   - dest: Destination path. `~` is expanded. Overwritten if it already exists, unless `mode` includes `fs.constants.COPYFILE_EXCL`.
    ///   - mode?: Bitwise-OR of `fs.constants.COPYFILE_*` flags. Only `COPYFILE_EXCL` has any effect. Defaults to `0`.
    /// - Example: `fs.copyFileSync("/tmp/a.txt", "/tmp/b.txt")`
    @objc func copyFileSync(_ src: JSString, _ dest: JSString, _ mode: Int)

    /// Synchronously create a symbolic link.
    /// - Parameters:
    ///   - target: The path the symlink will point to. Not expanded or validated - it need not exist.
    ///   - path: The path where the symlink will be created. `~` is expanded.
    /// - Example: `fs.symlinkSync("/usr/local/bin", "/tmp/bin-link")`
    @objc func symlinkSync(_ target: JSString, _ path: JSString)

    /// Synchronously read the target of a symbolic link.
    /// - Parameter path: Path to the symbolic link. `~` is expanded.
    /// - Returns: The raw target path.
    /// - Example: `console.log(fs.readlinkSync("/var"))`
    @objc func readlinkSync(_ path: JSString) -> String?

    /// Synchronously resolve a path to its absolute, canonical form, following all symlinks.
    /// - Parameter path: Path to resolve. `~` is expanded.
    /// - Returns: The resolved absolute path.
    /// - Example: `console.log(fs.realpathSync("~/Library"))`
    @objc func realpathSync(_ path: JSString) -> String?

    /// Synchronously create a hard link.
    /// - Parameters:
    ///   - existingPath: Path of the existing file. `~` is expanded.
    ///   - newPath: Path for the new hard link. `~` is expanded.
    /// - Example: `fs.linkSync("/tmp/a.txt", "/tmp/b.txt")`
    @objc func linkSync(_ existingPath: JSString, _ newPath: JSString)

    /// Synchronously test a path's accessibility.
    /// - Parameters:
    ///   - path: Path to check. `~` is expanded.
    ///   - mode?: A `fs.constants` value (`F_OK`, `R_OK`, `W_OK`, `X_OK`), or a bitwise-OR of them. Defaults to `F_OK` (existence only).
    /// - Example: `fs.accessSync("/tmp", fs.constants.W_OK)`
    @objc func accessSync(_ path: JSString, _ mode: Int)

    /// Synchronously truncate (or extend, zero-filled) a file to the given length.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - len?: Desired length in bytes. Defaults to `0`.
    /// - Example: `fs.truncateSync("/tmp/big.log", 0)`
    @objc func truncateSync(_ path: JSString, _ len: Int)
}

@_documentation(visibility: private)
@objc class NodeFSModule: NSObject, NodeFSModuleAPI {
    let promises = NodeFSPromisesModule()
    let constants: NSDictionary

    override init() {
        // Built once per NodeFSModule (one per JSContext) and shared by reference with
        // `promises`, so `fs.promises.constants === fs.constants` holds - see the doc comment
        // on `NodeFS.makeConstants()` for why this must not be a shared process-wide instance.
        constants = NodeFS.makeConstants()
        super.init()
        promises.constants = constants
    }

    /// Runs a throwing `NodeFS` operation, translating any failure into a JS exception on the
    /// current context and returning `nil`/`false`/etc. as JSExport requires.
    private func sync<T>(_ body: () throws -> T) -> T? {
        guard let context = JSContext.current() else { return nil }
        do {
            return try body()
        } catch let failure as NodeFSFailure {
            context.exception = failure.jsValue(in: context)
            return nil
        } catch {
            context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
            return nil
        }
    }

    @objc func existsSync(_ path: JSString) -> Bool {
        guard path.isString, let p = path.toString() else { return false }
        return NodeFS.existsSync(p)
    }

    @objc func readFileSync(_ path: JSString, _ encoding: JSString?) -> String? {
        sync {
            let p = try NodeFS.requireString(path, "path")
            let enc = try NodeFS.requireOptionalString(encoding, "encoding")
            return try NodeFS.readFile(p, encoding: enc)
        }
    }

    @objc func writeFileSync(_ path: JSString, _ data: JSString, _ flag: JSString?) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            let d = try NodeFS.requireString(data, "data")
            let f = try NodeFS.requireOptionalString(flag, "flag")
            try NodeFS.writeFile(p, d, flag: f)
        }
    }

    @objc func appendFileSync(_ path: JSString, _ data: JSString) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            let d = try NodeFS.requireString(data, "data")
            try NodeFS.appendFile(p, d)
        }
    }

    @objc func mkdirSync(_ path: JSString, _ options: JSValue?) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.mkdir(p, recursive: NodeFS.optionsFlag(options, "recursive"))
        }
    }

    @objc func rmdirSync(_ path: JSString, _ options: JSValue?) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.rmdir(p, recursive: NodeFS.optionsFlag(options, "recursive"))
        }
    }

    @objc func rmSync(_ path: JSString, _ options: JSValue?) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            let (recursive, force) = NodeFS.parseRmOptions(options)
            try NodeFS.rm(p, recursive: recursive, force: force)
        }
    }

    @objc func unlinkSync(_ path: JSString) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.unlink(p)
        }
    }

    @objc func readdirSync(_ path: JSString, _ options: JSValue?) -> [Any]? {
        sync {
            let p = try NodeFS.requireString(path, "path")
            let (withFileTypes, recursive) = NodeFS.parseReaddirOptions(options)
            let results = try NodeFS.readdir(p, withFileTypes: withFileTypes, recursive: recursive)
            if withFileTypes, let context = JSContext.current() {
                for case let dirent as NodeFSDirent in results { dirent.primeEnumerableProperties(in: context) }
            }
            return results
        }
    }

    @objc func statSync(_ path: JSString, _ options: JSValue? = nil) -> NodeFSStats? {
        let throwIfNoEntry = NodeFS.optionsFlag(options, "throwIfNoEntry", default: true)
        guard let context = JSContext.current() else { return nil }
        do {
            let p = try NodeFS.requireString(path, "path")
            let stats = try NodeFS.stat(p)
            stats.primeEnumerableProperties(in: context)
            return stats
        } catch let failure as NodeFSFailure {
            if case .posix(let errnoValue, _, _, _) = failure, errnoValue == ENOENT, !throwIfNoEntry { return nil }
            context.exception = failure.jsValue(in: context)
            return nil
        } catch {
            context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
            return nil
        }
    }

    @objc func lstatSync(_ path: JSString, _ options: JSValue? = nil) -> NodeFSStats? {
        let throwIfNoEntry = NodeFS.optionsFlag(options, "throwIfNoEntry", default: true)
        guard let context = JSContext.current() else { return nil }
        do {
            let p = try NodeFS.requireString(path, "path")
            let stats = try NodeFS.lstat(p)
            stats.primeEnumerableProperties(in: context)
            return stats
        } catch let failure as NodeFSFailure {
            if case .posix(let errnoValue, _, _, _) = failure, errnoValue == ENOENT, !throwIfNoEntry { return nil }
            context.exception = failure.jsValue(in: context)
            return nil
        } catch {
            context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
            return nil
        }
    }

    @objc func renameSync(_ oldPath: JSString, _ newPath: JSString) {
        _ = sync {
            let o = try NodeFS.requireString(oldPath, "oldPath")
            let n = try NodeFS.requireString(newPath, "newPath")
            try NodeFS.rename(o, n)
        }
    }

    @objc func copyFileSync(_ src: JSString, _ dest: JSString, _ mode: Int) {
        _ = sync {
            let s = try NodeFS.requireString(src, "src")
            let d = try NodeFS.requireString(dest, "dest")
            try NodeFS.copyFile(s, d, mode: mode)
        }
    }

    @objc func symlinkSync(_ target: JSString, _ path: JSString) {
        _ = sync {
            let t = try NodeFS.requireString(target, "target")
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.symlink(t, p)
        }
    }

    @objc func readlinkSync(_ path: JSString) -> String? {
        sync {
            let p = try NodeFS.requireString(path, "path")
            return try NodeFS.readlink(p)
        }
    }

    @objc func realpathSync(_ path: JSString) -> String? {
        sync {
            let p = try NodeFS.requireString(path, "path")
            return try NodeFS.realpath(p)
        }
    }

    @objc func linkSync(_ existingPath: JSString, _ newPath: JSString) {
        _ = sync {
            let e = try NodeFS.requireString(existingPath, "existingPath")
            let n = try NodeFS.requireString(newPath, "newPath")
            try NodeFS.link(e, n)
        }
    }

    @objc func accessSync(_ path: JSString, _ mode: Int) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.access(p, mode: mode)
        }
    }

    @objc func truncateSync(_ path: JSString, _ len: Int) {
        _ = sync {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.truncate(p, len: len)
        }
    }
}

// MARK: - fs.promises

/// The promise-based equivalents of `fs`'s `*Sync` functions, reachable as `require('fs').promises`
/// and `require('fs/promises')`.
///
/// WARNING: This module is an experiment to see if high levels of Node.js compatibility can be achieved with AI agents.
///
/// Every function here runs its work synchronously (there is no background I/O thread pool in
/// this engine) and wraps the result in an already-settled `Promise`, so `await`/`.then()` still
/// work exactly as in Node, just without any real concurrency.
/// - Example:
/// ```js
/// const fs = require('fs')
///
/// async function main() {
///     await fs.promises.writeFile("/tmp/hello.txt", "Hello, world!\n")
///     console.log(await fs.promises.readFile("/tmp/hello.txt"))
/// }
/// main()
/// ```
@objc protocol NodeFSPromisesModuleAPI: JSExport {
    /// The same object as `fs.constants`, matching Node.
    @objc var constants: NSDictionary { get }

    /// Read a file as a UTF-8 string. See `fs.readFileSync` for details.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - encoding?: Must be `"utf8"` (or omitted); any other value rejects, since this engine has no `Buffer` type.
    /// - Returns: A `Promise` resolving to the file's contents.
    /// - Example: `const text = await fs.promises.readFile("/etc/hosts")`
    @objc func readFile(_ path: JSString, _ encoding: JSString?) -> JSPromise?

    /// Write a UTF-8 string to a file, creating or truncating it. See `fs.writeFileSync` for details.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - data: String to write.
    ///   - flag?: One of `"w"` (default), `"wx"`, `"a"`, or `"ax"`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.writeFile("/tmp/hello.txt", "Hello, world!\n")`
    @objc func writeFile(_ path: JSString, _ data: JSString, _ flag: JSString?) -> JSPromise?

    /// Append a UTF-8 string to a file, creating it if needed. See `fs.appendFileSync` for details.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - data: String to append.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.appendFile("/tmp/log.txt", "another line\n")`
    @objc func appendFile(_ path: JSString, _ data: JSString) -> JSPromise?

    /// Create a directory. See `fs.mkdirSync` for details.
    /// - Parameters:
    ///   - path: Path of the directory to create. `~` is expanded.
    ///   - options?: A `{ recursive: boolean }` object (matching Node), or a bare boolean as shorthand for `recursive`. When `true`, creates all missing intermediate directories. Defaults to `false`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.mkdir("~/Projects/new-thing", { recursive: true })`
    @objc func mkdir(_ path: JSString, _ options: JSValue?) -> JSPromise?

    /// Remove an empty directory. See `fs.rmdirSync` for details.
    /// - Parameters:
    ///   - path: Path of the directory to remove. `~` is expanded.
    ///   - options?: A `{ recursive: boolean }` object (matching Node), or a bare boolean as shorthand for `recursive`. When `true`, removes the directory and its entire contents. Defaults to `false`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.rmdir("/tmp/empty-dir")`
    @objc func rmdir(_ path: JSString, _ options: JSValue?) -> JSPromise?

    /// Remove a file or directory. See `fs.rmSync` for details.
    /// - Parameters:
    ///   - path: Path to remove. `~` is expanded.
    ///   - options?: A `{ recursive?: boolean, force?: boolean }` object, matching Node. `recursive`: when `true` and `path` is a directory, removes it and its entire contents; defaults to `false`. `force`: when `true`, a missing path is not treated as an error; defaults to `false`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.rm("/tmp/old-dir", { recursive: true, force: true })`
    @objc func rm(_ path: JSString, _ options: JSValue?) -> JSPromise?

    /// Delete a single file. See `fs.unlinkSync` for details.
    /// - Parameter path: Path to the file. `~` is expanded.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.unlink("/tmp/old.txt")`
    @objc func unlink(_ path: JSString) -> JSPromise?

    /// List the contents of a directory. See `fs.readdirSync` for details.
    /// - Parameters:
    ///   - path: Path to the directory. `~` is expanded.
    ///   - options?: A `{ withFileTypes?: boolean, recursive?: boolean }` object (matching Node), or a bare boolean as shorthand for `withFileTypes`. Both default to `false`.
    /// - Returns: A `Promise` resolving to an array of filenames, or of `Dirent` objects if `withFileTypes` is `true`.
    /// - Example: `const files = await fs.promises.readdir("~/Documents")`
    @objc func readdir(_ path: JSString, _ options: JSValue?) -> JSPromise?

    /// Get file metadata, following symbolic links. See `fs.statSync` for details.
    /// - Parameter path: Path to inspect. `~` is expanded.
    /// - Returns: A `Promise` resolving to a `Stats` object.
    /// - Example: `console.log((await fs.promises.stat("/etc/hosts")).size)`
    @objc func stat(_ path: JSString) -> JSPromise?

    /// Get file metadata, without following symbolic links. See `fs.lstatSync` for details.
    /// - Parameter path: Path to inspect. `~` is expanded.
    /// - Returns: A `Promise` resolving to a `Stats` object.
    /// - Example: `console.log((await fs.promises.lstat("/var")).isSymbolicLink())`
    @objc func lstat(_ path: JSString) -> JSPromise?

    /// Rename (move) a file or directory. See `fs.renameSync` for details.
    /// - Parameters:
    ///   - oldPath: Existing path. `~` is expanded.
    ///   - newPath: New path. `~` is expanded.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.rename("/tmp/old.txt", "/tmp/new.txt")`
    @objc func rename(_ oldPath: JSString, _ newPath: JSString) -> JSPromise?

    /// Copy a file. See `fs.copyFileSync` for details.
    /// - Parameters:
    ///   - src: Path to the existing file. `~` is expanded.
    ///   - dest: Destination path. `~` is expanded. Overwritten if it already exists, unless `mode` includes `fs.constants.COPYFILE_EXCL`.
    ///   - mode?: Bitwise-OR of `fs.constants.COPYFILE_*` flags. Only `COPYFILE_EXCL` has any effect. Defaults to `0`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.copyFile("/tmp/a.txt", "/tmp/b.txt")`
    @objc func copyFile(_ src: JSString, _ dest: JSString, _ mode: Int) -> JSPromise?

    /// Create a symbolic link. See `fs.symlinkSync` for details.
    /// - Parameters:
    ///   - target: The path the symlink will point to. Not expanded or validated - it need not exist.
    ///   - path: The path where the symlink will be created. `~` is expanded.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.symlink("/usr/local/bin", "/tmp/bin-link")`
    @objc func symlink(_ target: JSString, _ path: JSString) -> JSPromise?

    /// Read the target of a symbolic link. See `fs.readlinkSync` for details.
    /// - Parameter path: Path to the symbolic link. `~` is expanded.
    /// - Returns: A `Promise` resolving to the raw target path.
    /// - Example: `console.log(await fs.promises.readlink("/var"))`
    @objc func readlink(_ path: JSString) -> JSPromise?

    /// Resolve a path to its absolute, canonical form, following all symlinks. See `fs.realpathSync` for details.
    /// - Parameter path: Path to resolve. `~` is expanded.
    /// - Returns: A `Promise` resolving to the resolved absolute path.
    /// - Example: `console.log(await fs.promises.realpath("~/Library"))`
    @objc func realpath(_ path: JSString) -> JSPromise?

    /// Create a hard link. See `fs.linkSync` for details.
    /// - Parameters:
    ///   - existingPath: Path of the existing file. `~` is expanded.
    ///   - newPath: Path for the new hard link. `~` is expanded.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.link("/tmp/a.txt", "/tmp/b.txt")`
    @objc func link(_ existingPath: JSString, _ newPath: JSString) -> JSPromise?

    /// Test a path's accessibility. See `fs.accessSync` for details.
    /// - Parameters:
    ///   - path: Path to check. `~` is expanded.
    ///   - mode?: A `fs.constants` value (`F_OK`, `R_OK`, `W_OK`, `X_OK`), or a bitwise-OR of them. Defaults to `F_OK` (existence only).
    /// - Returns: A `Promise` resolving to `undefined` if accessible, or rejecting otherwise.
    /// - Example: `await fs.promises.access("/tmp", fs.constants.W_OK)`
    @objc func access(_ path: JSString, _ mode: Int) -> JSPromise?

    /// Truncate (or extend, zero-filled) a file to the given length. See `fs.truncateSync` for details.
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - len?: Desired length in bytes. Defaults to `0`.
    /// - Returns: A `Promise` resolving to `undefined`.
    /// - Example: `await fs.promises.truncate("/tmp/big.log", 0)`
    @objc func truncate(_ path: JSString, _ len: Int) -> JSPromise?
}

@_documentation(visibility: private)
@objc class NodeFSPromisesModule: NSObject, NodeFSPromisesModuleAPI {
    /// Overwritten by the owning `NodeFSModule`'s `init()` right after construction, so this
    /// default only matters if a `NodeFSPromisesModule` is ever used unpaired.
    var constants: NSDictionary = NodeFS.makeConstants()

    /// Runs a throwing `NodeFS` operation that produces no value and wraps its outcome in a
    /// settled `Promise`, resolving with `undefined`.
    private func wrap(_ body: @escaping () throws -> Void) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { holder in
            do {
                try body()
                holder.resolveWith(nil)
            } catch let failure as NodeFSFailure {
                holder.rejectWithValue(failure.jsValue(in: context))
            } catch {
                let value = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
                holder.rejectWithValue(value ?? JSValue(undefinedIn: context))
            }
        }
    }

    /// Runs a throwing `NodeFS` operation that produces a value and wraps its outcome in a
    /// settled `Promise`, resolving with that value.
    private func wrap<T>(_ body: @escaping () throws -> T) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { holder in
            do {
                holder.resolveWith(try body())
            } catch let failure as NodeFSFailure {
                holder.rejectWithValue(failure.jsValue(in: context))
            } catch {
                let value = JSValue(newErrorFromMessage: error.localizedDescription, in: context)
                holder.rejectWithValue(value ?? JSValue(undefinedIn: context))
            }
        }
    }

    @objc func readFile(_ path: JSString, _ encoding: JSString?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let enc = try NodeFS.requireOptionalString(encoding, "encoding")
            return try NodeFS.readFile(p, encoding: enc)
        }
    }

    @objc func writeFile(_ path: JSString, _ data: JSString, _ flag: JSString?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let d = try NodeFS.requireString(data, "data")
            let f = try NodeFS.requireOptionalString(flag, "flag")
            try NodeFS.writeFile(p, d, flag: f)
        }
    }

    @objc func appendFile(_ path: JSString, _ data: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let d = try NodeFS.requireString(data, "data")
            try NodeFS.appendFile(p, d)
        }
    }

    @objc func mkdir(_ path: JSString, _ options: JSValue?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.mkdir(p, recursive: NodeFS.optionsFlag(options, "recursive"))
        }
    }

    @objc func rmdir(_ path: JSString, _ options: JSValue?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.rmdir(p, recursive: NodeFS.optionsFlag(options, "recursive"))
        }
    }

    @objc func rm(_ path: JSString, _ options: JSValue?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let (recursive, force) = NodeFS.parseRmOptions(options)
            try NodeFS.rm(p, recursive: recursive, force: force)
        }
    }

    @objc func unlink(_ path: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.unlink(p)
        }
    }

    @objc func readdir(_ path: JSString, _ options: JSValue?) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let (withFileTypes, recursive) = NodeFS.parseReaddirOptions(options)
            let results = try NodeFS.readdir(p, withFileTypes: withFileTypes, recursive: recursive)
            if withFileTypes, let context = JSContext.current() {
                for case let dirent as NodeFSDirent in results { dirent.primeEnumerableProperties(in: context) }
            }
            return results
        }
    }

    @objc func stat(_ path: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let stats = try NodeFS.stat(p)
            if let context = JSContext.current() { stats.primeEnumerableProperties(in: context) }
            return stats
        }
    }

    @objc func lstat(_ path: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            let stats = try NodeFS.lstat(p)
            if let context = JSContext.current() { stats.primeEnumerableProperties(in: context) }
            return stats
        }
    }

    @objc func rename(_ oldPath: JSString, _ newPath: JSString) -> JSPromise? {
        wrap {
            let o = try NodeFS.requireString(oldPath, "oldPath")
            let n = try NodeFS.requireString(newPath, "newPath")
            try NodeFS.rename(o, n)
        }
    }

    @objc func copyFile(_ src: JSString, _ dest: JSString, _ mode: Int) -> JSPromise? {
        wrap {
            let s = try NodeFS.requireString(src, "src")
            let d = try NodeFS.requireString(dest, "dest")
            try NodeFS.copyFile(s, d, mode: mode)
        }
    }

    @objc func symlink(_ target: JSString, _ path: JSString) -> JSPromise? {
        wrap {
            let t = try NodeFS.requireString(target, "target")
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.symlink(t, p)
        }
    }

    @objc func readlink(_ path: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            return try NodeFS.readlink(p)
        }
    }

    @objc func realpath(_ path: JSString) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            return try NodeFS.realpath(p)
        }
    }

    @objc func link(_ existingPath: JSString, _ newPath: JSString) -> JSPromise? {
        wrap {
            let e = try NodeFS.requireString(existingPath, "existingPath")
            let n = try NodeFS.requireString(newPath, "newPath")
            try NodeFS.link(e, n)
        }
    }

    @objc func access(_ path: JSString, _ mode: Int) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.access(p, mode: mode)
        }
    }

    @objc func truncate(_ path: JSString, _ len: Int) -> JSPromise? {
        wrap {
            let p = try NodeFS.requireString(path, "path")
            try NodeFS.truncate(p, len: len)
        }
    }
}
