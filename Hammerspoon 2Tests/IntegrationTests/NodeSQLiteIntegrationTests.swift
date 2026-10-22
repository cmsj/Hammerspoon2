//
//  NodeSQLiteIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import JavaScriptCoreExtras
import SQLite3
@testable import Hammerspoon_2

/// A harness with `require('node:sqlite')`'s exports available as the globals `sqlite`,
/// `DatabaseSync` and `StatementSync`, plus `errorOf(fn)`, which returns what `fn` throws (or
/// null).
private func makeHarness() throws -> JSTestHarness {
    let harness = JSTestHarness()
    try NodeBuiltinModulesInstaller().install(in: harness.context)
    harness.eval("""
        var sqlite = _hs_node_builtins['node:sqlite'];
        var DatabaseSync = sqlite.DatabaseSync;
        var StatementSync = sqlite.StatementSync;
        function errorOf(fn) { try { fn(); return null; } catch (e) { return e; } }
        """)
    return harness
}

/// A fresh database file path in a directory of its own, removed by the returned cleanup.
private func makeDatabasePath() throws -> (path: String, cleanup: () -> Void) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hs_node_sqlite_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory.appendingPathComponent("test.db").path, { try? FileManager.default.removeItem(at: directory) })
}

@Suite("node:sqlite tests")
struct NodeSQLiteTests {

    // MARK: - API structure

    @Suite("node:sqlite API structure")
    struct StructureTests {
        @Test("require('node:sqlite') returns the module, which needs the node: prefix as in Node")
        func testRequire() throws {
            let harness = JSTestHarness()
            try harness.context.install([NodeBuiltinModulesInstaller(), RequireInstaller()])
            #expect(harness.evalTypeOf("require('node:sqlite').DatabaseSync") == "function")
            #expect(harness.evalBool("require('node:sqlite') === require('node:sqlite')") == true)
            harness.eval("require('sqlite')")
            harness.expectException()
        }

        @Test("Exports the DatabaseSync and StatementSync classes")
        func testExports() throws {
            let harness = try makeHarness()
            #expect(harness.evalTypeOf("DatabaseSync") == "function")
            // Not constructible, so JavaScriptCore makes it an object rather than a function, but
            // `instanceof StatementSync` works (see "prepare() returns a StatementSync")
            #expect(harness.evalBool("StatementSync !== undefined && StatementSync !== null") == true)
            #expect(harness.evalString("DatabaseSync.name") == "DatabaseSync")
        }

        @Test("new DatabaseSync() makes an open database")
        func testConstruct() throws {
            let harness = try makeHarness()
            harness.eval("var db = new DatabaseSync(':memory:')")
            #expect(harness.evalBool("db instanceof DatabaseSync") == true)
            #expect(harness.evalBool("db.isOpen") == true)
            #expect(harness.evalBool("db.isTransaction") == false)
            #expect(!harness.hasException)
        }

        @Test("DatabaseSync can't be called without new")
        func testConstructWithoutNew() throws {
            let harness = try makeHarness()
            #expect(harness.evalBool("errorOf(() => DatabaseSync(':memory:')) instanceof TypeError") == true)
        }

        @Test("StatementSync can't be constructed directly")
        func testStatementNotConstructible() throws {
            let harness = try makeHarness()
            #expect(harness.evalBool("errorOf(() => new StatementSync()) !== null") == true)
        }

        @Test("prepare() returns a StatementSync")
        func testPrepare() throws {
            let harness = try makeHarness()
            harness.eval("var stmt = new DatabaseSync(':memory:').prepare('SELECT 1')")
            #expect(harness.evalBool("stmt instanceof StatementSync") == true)
            #expect(harness.evalString("stmt.sourceSQL") == "SELECT 1")
        }
    }

    // MARK: - Running statements

    @Suite("node:sqlite statements")
    struct StatementTests {
        @Test("run() reports changes and the last inserted row ID")
        func testRun() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (a INTEGER, b TEXT)');
                var insert = db.prepare('INSERT INTO t VALUES (?, ?)');
                var first = insert.run(1, 'x');
                var second = insert.run(2, 'y');
                var updated = db.prepare('UPDATE t SET b = ?').run('z');
                """)
            #expect(harness.evalInt("first.changes") == 1)
            #expect(harness.evalInt("first.lastInsertRowid") == 1)
            #expect(harness.evalInt("second.lastInsertRowid") == 2)
            #expect(harness.evalInt("updated.changes") == 2)
            #expect(!harness.hasException)
        }

        @Test("all() and get() return rows as objects with no prototype")
        func testAllAndGet() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec("CREATE TABLE t (a INTEGER, b TEXT); INSERT INTO t VALUES (1, 'x'), (2, 'y')");
                var rows = db.prepare('SELECT * FROM t ORDER BY a').all();
                var row = db.prepare('SELECT * FROM t WHERE a = ?').get(2);
                """)
            #expect(harness.evalString("JSON.stringify(rows)") == #"[{"a":1,"b":"x"},{"a":2,"b":"y"}]"#)
            #expect(harness.evalString("JSON.stringify(row)") == #"{"a":2,"b":"y"}"#)
            #expect(harness.evalBool("Object.getPrototypeOf(row) === null") == true)
            #expect(!harness.hasException)
        }

        @Test("get() returns undefined, not null, when there are no rows")
        func testGetNoRows() throws {
            let harness = try makeHarness()
            #expect(harness.evalTypeOf("new DatabaseSync(':memory:').prepare('SELECT 1 WHERE 0').get()") == "undefined")
        }

        @Test("all() returns an empty array when there are no rows")
        func testAllNoRows() throws {
            let harness = try makeHarness()
            #expect(harness.evalInt("new DatabaseSync(':memory:').prepare('SELECT 1 WHERE 0').all().length") == 0)
        }

        @Test("A column named __proto__ becomes an ordinary property")
        func testProtoColumnName() throws {
            let harness = try makeHarness()
            harness.eval("var row = new DatabaseSync(':memory:').prepare('SELECT 1 AS __proto__').get()")
            #expect(harness.evalBool("Object.hasOwn(row, '__proto__')") == true)
            #expect(harness.evalInt("row.__proto__") == 1)
        }

        @Test("setReturnArrays() returns rows as arrays")
        func testReturnArrays() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare("SELECT 1 AS a, 'x' AS b");
                stmt.setReturnArrays(true);
                """)
            #expect(harness.evalString("JSON.stringify(stmt.get())") == #"[1,"x"]"#)
            #expect(harness.evalString("JSON.stringify(stmt.all())") == #"[[1,"x"]]"#)
        }

        @Test("The returnArrays option applies to the database's statements")
        func testReturnArraysOption() throws {
            let harness = try makeHarness()
            harness.eval("var db = new DatabaseSync(':memory:', { returnArrays: true })")
            #expect(harness.evalString("JSON.stringify(db.prepare('SELECT 1, 2').get())") == "[1,2]")
        }

        @Test("columns() describes the result columns")
        func testColumns() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (a INTEGER, c TEXT)');
                var columns = db.prepare('SELECT a AS x, c, 1 FROM t').columns();
                """)
            #expect(harness.evalInt("columns.length") == 3)
            #expect(harness.evalString("JSON.stringify(columns[0])") ==
                    #"{"column":"a","database":"main","name":"x","table":"t","type":"INTEGER"}"#)
            #expect(harness.evalString("JSON.stringify(columns[2])") ==
                    #"{"column":null,"database":null,"name":"1","table":null,"type":null}"#)
        }

        @Test("expandedSQL shows the bound values")
        func testExpandedSQL() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare('SELECT ?, ?');
                stmt.get('a', null);
                """)
            #expect(harness.evalString("stmt.expandedSQL") == "SELECT 'a', NULL")
        }

        @Test("prepare() only compiles the first statement")
        func testPrepareFirstStatementOnly() throws {
            let harness = try makeHarness()
            #expect(harness.evalString("JSON.stringify(new DatabaseSync(':memory:').prepare('SELECT 1 AS a; SELECT 2 AS a').all())")
                    == #"[{"a":1}]"#)
        }

        @Test("exec() runs several statements")
        func testExec() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (a); INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)');
                """)
            #expect(harness.evalInt("db.prepare('SELECT count(*) AS n FROM t').get().n") == 2)
        }

        @Test("isTransaction reflects an open transaction")
        func testIsTransaction() throws {
            let harness = try makeHarness()
            harness.eval("var db = new DatabaseSync(':memory:'); db.exec('BEGIN')")
            #expect(harness.evalBool("db.isTransaction") == true)
            harness.eval("db.exec('COMMIT')")
            #expect(harness.evalBool("db.isTransaction") == false)
        }
    }

    // MARK: - Values

    @Suite("node:sqlite value conversion")
    struct ValueTests {
        @Test("Values round-trip through a table")
        func testRoundTrip() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (v)');
                var insert = db.prepare('INSERT INTO t VALUES (?)');
                var select = db.prepare('SELECT v, typeof(v) AS type FROM t WHERE rowid = ?');
                function roundTrip(value) {
                    var id = insert.run(value).lastInsertRowid;
                    return select.get(id);
                }
                """)
            #expect(harness.evalString("roundTrip(null).type") == "null")
            #expect(harness.evalString("roundTrip(undefined).type") == "null")
            #expect(harness.evalDouble("roundTrip(1.5).v") == 1.5)
            #expect(harness.evalString("roundTrip('héllo 👋').v") == "héllo 👋")
            #expect(harness.evalInt("roundTrip('a\\u0000b').v.length") == 3)
            #expect(harness.evalString("roundTrip(true).type") == "integer")
            #expect(harness.evalInt("roundTrip(true).v") == 1)
            #expect(harness.evalInt("roundTrip(false).v") == 0)
            #expect(harness.evalString("roundTrip(42n).type") == "integer")
            #expect(harness.evalInt("roundTrip(42n).v") == 42)
            #expect(!harness.hasException)
        }

        @Test("Numbers bind as REAL, and INTEGER affinity stores whole numbers as integers")
        func testNumberAffinity() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (i INTEGER, v)');
                db.prepare('INSERT INTO t VALUES (?, ?)').run(3, 3);
                var types = db.prepare('SELECT typeof(i) AS i, typeof(v) AS v FROM t').get();
                """)
            #expect(harness.evalString("types.i") == "integer")
            #expect(harness.evalString("types.v") == "real")
        }

        @Test("Typed arrays bind as blobs, and blobs read as Uint8Arrays")
        func testBlobs() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                var select = db.prepare('SELECT ? AS b, typeof(?) AS type');
                var bytes = select.get(new Uint8Array([1, 2, 255]), new Uint8Array([1])).b;
                var view = select.get(new Uint8Array([9, 8, 7, 6]).subarray(1, 3), null).b;
                var empty = select.get(new Uint8Array(0), new Uint8Array(0));
                var literal = db.prepare("SELECT x'cafe' AS b").get().b;
                """)
            #expect(harness.evalBool("bytes instanceof Uint8Array") == true)
            #expect(harness.evalString("Array.from(bytes).join(',')") == "1,2,255")
            #expect(harness.evalString("Array.from(view).join(',')") == "8,7")
            #expect(harness.evalString("empty.type") == "blob")
            #expect(harness.evalInt("empty.b.length") == 0)
            #expect(harness.evalString("Array.from(literal).join(',')") == "202,254")
        }

        @Test("Integers beyond Number.MAX_SAFE_INTEGER throw unless readBigInts is set")
        func testLargeIntegers() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                var stmt = db.prepare('SELECT 9007199254740993 AS big');
                var error = errorOf(() => stmt.get());
                """)
            #expect(harness.evalString("error.code") == "ERR_OUT_OF_RANGE")
            #expect(harness.evalBool("error instanceof RangeError") == true)
            #expect(harness.evalInt("db.prepare('SELECT 9007199254740991 AS n').get().n") == 9007199254740991)

            harness.eval("stmt.setReadBigInts(true)")
            #expect(harness.evalBool("stmt.get().big === 9007199254740993n") == true)
            #expect(!harness.hasException)
        }

        @Test("readBigInts makes run() report BigInts")
        func testRunBigInts() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:', { readBigInts: true });
                db.exec('CREATE TABLE t (a)');
                var result = db.prepare('INSERT INTO t VALUES (1)').run();
                var row = db.prepare('SELECT a, 1.5 AS f FROM t').get();
                """)
            #expect(harness.evalTypeOf("result.changes") == "bigint")
            #expect(harness.evalTypeOf("result.lastInsertRowid") == "bigint")
            #expect(harness.evalTypeOf("row.a") == "bigint")
            #expect(harness.evalTypeOf("row.f") == "number")
        }

        @Test("BigInts beyond 64 bits can't be bound")
        func testBigIntTooLarge() throws {
            let harness = try makeHarness()
            harness.eval("var error = errorOf(() => new DatabaseSync(':memory:').prepare('SELECT ?').get(2n ** 64n))")
            #expect(harness.evalString("error.code") == "ERR_INVALID_ARG_VALUE")
            #expect(harness.evalBool("error instanceof TypeError") == true)
        }

        @Test("Unbindable values throw ERR_INVALID_ARG_TYPE")
        func testUnbindable() throws {
            let harness = try makeHarness()
            harness.eval("var error = errorOf(() => new DatabaseSync(':memory:').prepare('SELECT ?, ?').get(1, Symbol('x')))")
            #expect(harness.evalString("error.code") == "ERR_INVALID_ARG_TYPE")
            #expect(harness.evalString("error.message") == "Provided value cannot be bound to SQLite parameter 2.")
        }
    }

    // MARK: - Parameters

    @Suite("node:sqlite parameters")
    struct ParameterTests {
        @Test("Named parameters bind with or without their prefix")
        func testNamedParameters() throws {
            let harness = try makeHarness()
            harness.eval("var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a, $b AS b, @c AS c')")
            #expect(harness.evalString("JSON.stringify(stmt.get({ a: 1, b: 2, c: 3 }))") == #"{"a":1,"b":2,"c":3}"#)
            #expect(harness.evalString("JSON.stringify(stmt.get({ ':a': 1, '$b': 2, '@c': 3 }))") == #"{"a":1,"b":2,"c":3}"#)
        }

        @Test("Unbound parameters are NULL, rather than keeping a previous run's values")
        func testBindingsCleared() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a, :b AS b');
                stmt.get({ a: 1, b: 2 });
                var row = stmt.get({ a: 5 });
                """)
            #expect(harness.evalString("JSON.stringify(row)") == #"{"a":5,"b":null}"#)
        }

        @Test("Unknown named parameters throw, unless allowed")
        func testUnknownNamedParameters() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a');
                var error = errorOf(() => stmt.get({ a: 1, zz: 2 }));
                """)
            #expect(harness.evalString("error.code") == "ERR_INVALID_STATE")
            #expect(harness.evalString("error.message") == "Unknown named parameter 'zz'")

            harness.eval("stmt.setAllowUnknownNamedParameters(true)")
            #expect(harness.evalInt("stmt.get({ a: 1, zz: 2 }).a") == 1)
        }

        @Test("Bare names can be disallowed")
        func testDisallowBareNames() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a');
                stmt.setAllowBareNamedParameters(false);
                """)
            #expect(harness.evalString("errorOf(() => stmt.get({ a: 1 })).code") == "ERR_INVALID_STATE")
            #expect(harness.evalInt("stmt.get({ ':a': 1 }).a") == 1)
        }

        @Test("A bare name matching two prefixed parameters is ambiguous")
        func testConflictingBareNames() throws {
            let harness = try makeHarness()
            harness.eval("var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a, $a AS b')")
            #expect(harness.evalString("errorOf(() => stmt.get({ a: 1 })).message") ==
                    "Cannot create bare named parameter 'a' because of conflicting names ':a' and '$a'.")
            #expect(harness.evalString("JSON.stringify(stmt.get({ ':a': 1, '$a': 2 }))") == #"{"a":1,"b":2}"#)
        }

        @Test("Anonymous parameters skip named ones, and follow a named-parameter object")
        func testMixedParameters() throws {
            let harness = try makeHarness()
            harness.eval("var stmt = new DatabaseSync(':memory:').prepare('SELECT ? AS x, :n AS n, ? AS y')")
            #expect(harness.evalString("JSON.stringify(stmt.get({ n: 'N' }, 1, 2))") == #"{"x":1,"n":"N","y":2}"#)
            #expect(harness.evalString("JSON.stringify(stmt.get(1, 2))") == #"{"x":1,"n":null,"y":2}"#)
        }

        @Test("Numbered parameters take anonymous values")
        func testNumberedParameters() throws {
            let harness = try makeHarness()
            #expect(harness.evalString("JSON.stringify(new DatabaseSync(':memory:').prepare('SELECT ?1 AS a, ?1 AS b').get(7))")
                    == #"{"a":7,"b":7}"#)
        }

        @Test("A named-parameter getter that closes the database throws instead of crashing")
        func testGetterClosesDatabase() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                var stmt = db.prepare('SELECT :a AS a');
                var error = errorOf(() => stmt.get({ get a() { db.close(); return 1; } }));
                """)
            #expect(harness.evalString("error.message") == "statement has been finalized")
        }

        @Test("A named-parameter getter that runs the same statement doesn't disturb its binding")
        func testGetterRunsStatement() throws {
            let harness = try makeHarness()
            harness.eval("""
                var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a, :b AS b');
                var row = stmt.get({ get a() { stmt.all({ a: 9, b: 9 }); return 1; }, b: 2 });
                """)
            #expect(harness.evalString("JSON.stringify(row)") == #"{"a":1,"b":2}"#)
        }

        @Test("An exception from a named-parameter getter reaches the caller")
        func testGetterThrows() throws {
            let harness = try makeHarness()
            harness.eval("var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a')")
            #expect(harness.evalString("errorOf(() => stmt.get({ get a() { throw new Error('boom'); } })).message") == "boom")
        }

        @Test("Getters of properties that match no parameter aren't run, as in Node")
        func testUnknownGettersNotRead() throws {
            let harness = try makeHarness()
            harness.eval("""
                var reads = 0;
                var stmt = new DatabaseSync(':memory:').prepare('SELECT :a AS a');
                var params = { a: 1, get unused() { reads++; throw new Error('boom'); } };
                var strictError = errorOf(() => stmt.get(params));
                stmt.setAllowUnknownNamedParameters(true);
                var row = stmt.get(params);
                """)
            #expect(harness.evalString("strictError.message") == "Unknown named parameter 'unused'")
            #expect(harness.evalInt("row.a") == 1)
            #expect(harness.evalInt("reads") == 0)
        }

        @Test("Too many parameters throws a SQLite error")
        func testTooManyParameters() throws {
            let harness = try makeHarness()
            harness.eval("var error = errorOf(() => new DatabaseSync(':memory:').prepare('SELECT ?').get(1, 2))")
            #expect(harness.evalString("error.code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalInt("error.errcode") == Int(SQLITE_RANGE))
        }
    }

    // MARK: - Iteration

    @Suite("node:sqlite iteration")
    struct IterationTests {
        private func makeHarnessWithTable() throws -> JSTestHarness {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (x); INSERT INTO t VALUES (1), (2), (3)');
                var stmt = db.prepare('SELECT x FROM t ORDER BY x');
                """)
            return harness
        }

        @Test("iterate() works with for...of and spread")
        func testForOf() throws {
            let harness = try makeHarnessWithTable()
            harness.eval("var seen = []; for (const row of stmt.iterate()) seen.push(row.x);")
            #expect(harness.evalString("seen.join(',')") == "1,2,3")
            #expect(harness.evalString("[...stmt.iterate()].map(r => r.x).join(',')") == "1,2,3")
            #expect(!harness.hasException)
        }

        @Test("next() reports done, with a null value, after the last row")
        func testNext() throws {
            let harness = try makeHarnessWithTable()
            harness.eval("var it = stmt.iterate(); it.next(); it.next(); it.next(); var end = it.next(); var after = it.next();")
            #expect(harness.evalBool("end.done") == true)
            #expect(harness.evalBool("end.value === null") == true)
            #expect(harness.evalBool("after.done") == true)
        }

        @Test("Breaking out of a loop ends the iterator")
        func testBreak() throws {
            let harness = try makeHarnessWithTable()
            harness.eval("var it = stmt.iterate(); for (const row of it) { break; }")
            #expect(harness.evalBool("it.next().done") == true)
        }

        @Test("Running the statement again invalidates an iterator")
        func testInvalidated() throws {
            let harness = try makeHarnessWithTable()
            harness.eval("var it = stmt.iterate(); it.next(); stmt.all();")
            #expect(harness.evalString("errorOf(() => it.next()).message") == "iterator was invalidated")
        }

        @Test("Iterators inherit JavaScript's iterator helpers")
        func testIteratorHelpers() throws {
            let harness = try makeHarnessWithTable()
            #expect(harness.evalString("stmt.iterate().map(r => r.x * 10).toArray().join(',')") == "10,20,30")
        }
    }

    // MARK: - Opening and closing

    @Suite("node:sqlite database lifecycle")
    struct LifecycleTests {
        @Test("A closed database throws, and its statements are finalized")
        func testClose() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                var stmt = db.prepare('SELECT 1');
                db.close();
                """)
            #expect(harness.evalBool("db.isOpen") == false)
            #expect(harness.evalString("errorOf(() => db.exec('SELECT 1')).message") == "database is not open")
            #expect(harness.evalString("errorOf(() => db.close()).code") == "ERR_INVALID_STATE")
            #expect(harness.evalString("errorOf(() => stmt.get()).message") == "statement has been finalized")
        }

        @Test("open: false defers opening to open()")
        func testDeferredOpen() throws {
            let harness = try makeHarness()
            harness.eval("var db = new DatabaseSync(':memory:', { open: false })")
            #expect(harness.evalBool("db.isOpen") == false)
            harness.eval("db.open()")
            #expect(harness.evalBool("db.isOpen") == true)
            #expect(harness.evalString("errorOf(() => db.open()).message") == "database is already open")
        }

        @Test("A file database persists, reopens and reports its location")
        func testFileDatabase() throws {
            let (path, cleanup) = try makeDatabasePath()
            defer { cleanup() }
            let harness = try makeHarness()
            harness.eval("""
                var path = '\(path)';
                var db = new DatabaseSync(path);
                db.exec("CREATE TABLE t (a); INSERT INTO t VALUES ('kept')");
                var location = db.location();
                db.close();
                db.open();
                var reopened = db.prepare('SELECT a FROM t').get().a;
                var other = new DatabaseSync(path).prepare('SELECT a FROM t').get().a;
                """)
            #expect(harness.evalBool("location.endsWith('/test.db')") == true)
            #expect(harness.evalString("reopened") == "kept")
            #expect(harness.evalString("other") == "kept")
            #expect(harness.evalBool("new DatabaseSync(':memory:').location() === null") == true)
            #expect(harness.evalBool("db.location('nope') === null") == true)
        }

        @Test("readOnly databases reject writes")
        func testReadOnly() throws {
            let (path, cleanup) = try makeDatabasePath()
            defer { cleanup() }
            let harness = try makeHarness()
            harness.eval("""
                new DatabaseSync('\(path)').exec('CREATE TABLE t (a)');
                var error = errorOf(() => new DatabaseSync('\(path)', { readOnly: true }).exec('INSERT INTO t VALUES (1)'));
                """)
            #expect(harness.evalString("error.code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalInt("error.errcode") == Int(SQLITE_READONLY))
        }

        @Test("Failing to open throws a SQLite error")
        func testOpenFailure() throws {
            let harness = try makeHarness()
            harness.eval("var error = errorOf(() => new DatabaseSync('/nonexistent-directory/x.db'))")
            #expect(harness.evalString("error.code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalInt("error.errcode") == Int(SQLITE_CANTOPEN))
            #expect(harness.evalString("error.errstr") == "unable to open database file")
        }

        @Test("timeout waits for a locked database, then fails with SQLITE_BUSY")
        func testTimeout() throws {
            let (path, cleanup) = try makeDatabasePath()
            defer { cleanup() }
            let harness = try makeHarness()
            harness.eval("""
                var writer = new DatabaseSync('\(path)');
                writer.exec('CREATE TABLE t (a); BEGIN IMMEDIATE');
                var started = Date.now();
                var error = errorOf(() => new DatabaseSync('\(path)', { timeout: 100 }).exec('INSERT INTO t VALUES (1)'));
                var waited = Date.now() - started;
                writer.exec('ROLLBACK');
                """)
            #expect(harness.evalInt("error.errcode") == Int(SQLITE_BUSY))
            #expect((harness.evalInt("waited") ?? 0) >= 90)
        }
    }

    // MARK: - Database defaults

    @Suite("node:sqlite database options")
    struct OptionTests {
        @Test("Foreign key constraints are enforced by default")
        func testForeignKeys() throws {
            let harness = try makeHarness()
            let schema = "CREATE TABLE p (id INTEGER PRIMARY KEY); CREATE TABLE c (p REFERENCES p(id)); INSERT INTO c VALUES (1)"
            #expect(harness.evalString("errorOf(() => new DatabaseSync(':memory:').exec('\(schema)')).code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalBool("errorOf(() => new DatabaseSync(':memory:', { enableForeignKeyConstraints: false }).exec('\(schema)')) === null") == true)
        }

        @Test("Double-quoted string literals are rejected unless enabled")
        func testDoubleQuotedStrings() throws {
            let harness = try makeHarness()
            #expect(harness.evalString("errorOf(() => new DatabaseSync(':memory:').prepare('SELECT \"nope\"')).code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalString("new DatabaseSync(':memory:', { enableDoubleQuotedStringLiterals: true }).prepare('SELECT \"yes\" AS s').get().s") == "yes")
        }
    }

    // MARK: - Errors

    @Suite("node:sqlite errors")
    struct ErrorTests {
        @Test("SQLite errors carry Node's code, errcode and errstr")
        func testSQLiteError() throws {
            let harness = try makeHarness()
            harness.eval("var error = errorOf(() => new DatabaseSync(':memory:').exec('BOGUS'))")
            #expect(harness.evalBool("error instanceof Error") == true)
            #expect(harness.evalString("error.code") == "ERR_SQLITE_ERROR")
            #expect(harness.evalInt("error.errcode") == Int(SQLITE_ERROR))
            #expect(harness.evalString("error.errstr") == "SQL logic error")
            #expect(harness.evalString("error.message") == #"near "BOGUS": syntax error"#)
        }

        @Test("exec() stops at the first failing statement")
        func testExecStopsAtFailure() throws {
            let harness = try makeHarness()
            harness.eval("""
                var db = new DatabaseSync(':memory:');
                db.exec('CREATE TABLE t (a)');
                var error = errorOf(() => db.exec('INSERT INTO t VALUES (1); SELECT * FROM missing; INSERT INTO t VALUES (2)'));
                """)
            #expect(harness.evalString("error.message") == "no such table: missing")
            #expect(harness.evalInt("db.prepare('SELECT count(*) AS n FROM t').get().n") == 1)
        }

        @Test("Arguments of the wrong type throw ERR_INVALID_ARG_TYPE")
        func testArgumentTypes() throws {
            let harness = try makeHarness()
            harness.eval("var db = new DatabaseSync(':memory:')")
            for expression in [
                "new DatabaseSync(1)",
                "new DatabaseSync()",
                "new DatabaseSync(':memory:', 5)",
                "new DatabaseSync(':memory:', { readOnly: 'yes' })",
                "new DatabaseSync(':memory:', { timeout: 1.5 })",
                "db.exec(5)",
                "db.prepare(5)",
                "db.location(5)",
                "db.prepare('SELECT 1').setReadBigInts('yes')",
            ] {
                #expect(harness.evalString("errorOf(() => \(expression)).code") == "ERR_INVALID_ARG_TYPE", "\(expression)")
                #expect(harness.evalBool("errorOf(() => \(expression)) instanceof TypeError") == true, "\(expression)")
            }
        }

        @Test("prepare() rejects SQL with no statements")
        func testEmptySQL() throws {
            let harness = try makeHarness()
            #expect(harness.evalString("errorOf(() => new DatabaseSync(':memory:').prepare('  -- nothing')).code") == "ERR_INVALID_ARG_VALUE")
        }
    }

    // MARK: - Memory

    @Suite("node:sqlite memory management")
    struct MemoryTests {
        @Test("A database and statement the caller dropped are garbage collected")
        func testDroppedObjectsCollected() throws {
            let harness = try makeHarness()
            weak var database: DatabaseSync?
            weak var statement: StatementSync?
            autoreleasepool {
                harness.eval("var db = new DatabaseSync(':memory:'); var stmt = db.prepare('SELECT 1'); stmt.get();")
                database = harness.evalValue("db")?.toObjectOf(DatabaseSync.self) as? DatabaseSync
                statement = harness.evalValue("stmt")?.toObjectOf(StatementSync.self) as? StatementSync
                harness.eval("db = null; stmt = null")
            }
            #expect(database != nil)
            harness.collectGarbage()
            #expect(database == nil)
            #expect(statement == nil)
        }

        @Test("A statement keeps its database open after the caller drops the database")
        func testStatementKeepsDatabase() throws {
            let harness = try makeHarness()
            autoreleasepool {
                harness.eval("""
                    var db = new DatabaseSync(':memory:');
                    db.exec("CREATE TABLE t (a); INSERT INTO t VALUES ('still here')");
                    var stmt = db.prepare('SELECT a FROM t');
                    db = null;
                    """)
            }
            harness.collectGarbage()
            #expect(harness.evalString("stmt.get().a") == "still here")
        }

        @Test("A partly read iterator the caller dropped releases the database's read lock")
        func testDroppedIteratorReleasesLock() throws {
            let (path, cleanup) = try makeDatabasePath()
            defer { cleanup() }
            let harness = try makeHarness()
            harness.eval("""
                var writer = new DatabaseSync('\(path)');
                writer.exec('CREATE TABLE t (a); INSERT INTO t VALUES (1), (2)');
                var reader = new DatabaseSync('\(path)');
                var stmt = reader.prepare('SELECT a FROM t');
                """)
            autoreleasepool {
                harness.eval("void stmt.iterate().next()")
            }
            #expect(harness.evalString("errorOf(() => writer.exec('INSERT INTO t VALUES (3)')).code") == "ERR_SQLITE_ERROR",
                    "the iterator should hold a read lock while it's alive")
            harness.collectGarbage()
            #expect(harness.evalBool("errorOf(() => writer.exec('INSERT INTO t VALUES (3)')) === null") == true)
        }

        @Test("Databases, statements and iterators are released after shutdown")
        func testNoLeaksAfterReload() throws {
            let tracker = WeakLeakTracker()
            try autoreleasepool {
                let harness = try makeHarness()
                harness.eval("""
                    var db = new DatabaseSync(':memory:');
                    db.exec('CREATE TABLE t (a); INSERT INTO t VALUES (1), (2)');
                    var stmt = db.prepare('SELECT a FROM t');
                    var it = stmt.iterate();
                    it.next();
                    """)
                if let database = harness.evalValue("db")?.toObjectOf(DatabaseSync.self) as? DatabaseSync {
                    tracker.track(database)
                }
                if let statement = harness.evalValue("stmt")?.toObjectOf(StatementSync.self) as? StatementSync {
                    tracker.track(statement)
                }
                if let iterator = harness.evalValue("it")?.toObjectOf(StatementSyncIterator.self) as? StatementSyncIterator {
                    tracker.track(iterator)
                }
                harness.eval("db = null; stmt = null; it = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
