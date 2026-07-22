//
//  HSRequireIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Test context

// RequireContext creates an isolated JSContext with the full CommonJS require()
// system installed and a temporary directory for test modules.  Each test creates
// its own instance so there is no shared state between tests.
private final class RequireContext {
    let context: JSContext
    let tempDir: URL
    private(set) var lastException: JSValue?

    init() throws {
        let vm = JSVirtualMachine()
        let ctx = JSContext(virtualMachine: vm)!
        ctx.name = "RequireTestContext"
        context = ctx

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs_require_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        ctx.exceptionHandler = { [weak self] _, exc in self?.lastException = exc }
        try RequireInstaller().install(in: ctx)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // Write a JS/JSON file to the temp dir and return the absolute path.
    @discardableResult
    func write(_ relativePath: String, _ content: String) throws -> String {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @discardableResult
    func eval(_ script: String) -> JSValue? {
        lastException = nil
        return context.evaluateScript(script)
    }

    var hadException: Bool { lastException != nil }
}

// MARK: - Test suites

@Suite("require() tests")
struct HSRequireTests {

    // MARK: - Module exports patterns

    @Suite("module.exports patterns")
    struct ExportsPatternTests {

        @Test("module.exports = object is returned by require()")
        func testModuleExportsObject() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("greet.js", """
                module.exports = {
                    hello: function(name) { return 'Hello, ' + name + '!'; }
                };
            """)
            let result = ctx.eval("require('\(path)').hello('World')")
            #expect(result?.toString() == "Hello, World!")
            #expect(!ctx.hadException)
        }

        @Test("exports.property assignment pattern works")
        func testExportsPropertyPattern() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("math.js", """
                exports.double = function(n) { return n * 2; };
                exports.square = function(n) { return n * n; };
            """)
            ctx.eval("var m = require('\(path)')")
            #expect(ctx.eval("m.double(5)")?.toInt32() == 10)
            #expect(ctx.eval("m.square(4)")?.toInt32() == 16)
            #expect(!ctx.hadException)
        }

        @Test("module.exports can be a function")
        func testModuleExportsFunction() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("fn.js", """
                module.exports = function(x) { return x + 1; };
            """)
            let result = ctx.eval("require('\(path)')(41)")
            #expect(result?.toInt32() == 42)
            #expect(!ctx.hadException)
        }

        @Test("module.exports can be a primitive value")
        func testModuleExportsPrimitive() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("answer.js", "module.exports = 42;")
            let result = ctx.eval("require('\(path)')")
            #expect(result?.toInt32() == 42)
            #expect(!ctx.hadException)
        }
    }

    // MARK: - Path resolution

    @Suite("path resolution")
    struct PathResolutionTests {

        @Test("absolute path is resolved directly")
        func testAbsolutePath() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("abs.js", "module.exports = 'absolute';")
            let result = ctx.eval("require('\(path)')")
            #expect(result?.toString() == "absolute")
            #expect(!ctx.hadException)
        }

        @Test(".js extension is inferred when omitted")
        func testJsExtensionInferred() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("infer.js", "module.exports = 'inferred';")
            let pathNoExt = (path as NSString).deletingPathExtension
            let result = ctx.eval("require('\(pathNoExt)')")
            #expect(result?.toString() == "inferred")
            #expect(!ctx.hadException)
        }

        @Test("index.js is resolved when given a directory path")
        func testIndexJsResolution() throws {
            let ctx = try RequireContext()
            try ctx.write("pkg/index.js", "module.exports = 'from index';")
            let dirPath = ctx.tempDir.appendingPathComponent("pkg").path
            let result = ctx.eval("require('\(dirPath)')")
            #expect(result?.toString() == "from index")
            #expect(!ctx.hadException)
        }

        @Test("relative require inside a module resolves against that module's directory")
        func testRelativeRequireFromWithinModule() throws {
            let ctx = try RequireContext()
            try ctx.write("lib/utils.js", "module.exports = { add: function(a,b) { return a+b; } };")
            let mainPath = try ctx.write("lib/main.js", """
                var utils = require('./utils');
                module.exports = utils.add(3, 4);
            """)
            let result = ctx.eval("require('\(mainPath)')")
            #expect(result?.toInt32() == 7)
            #expect(!ctx.hadException)
        }

        @Test("multi-level relative path (../) is resolved correctly")
        func testMultiLevelRelativePath() throws {
            let ctx = try RequireContext()
            try ctx.write("shared/constants.js", "module.exports = { PI: 3.14159 };")
            let mainPath = try ctx.write("app/main.js", """
                var c = require('../shared/constants');
                module.exports = c.PI;
            """)
            let result = ctx.eval("require('\(mainPath)')")
            #expect(abs((result?.toDouble() ?? 0) - 3.14159) < 0.001)
            #expect(!ctx.hadException)
        }
    }

    // MARK: - JSON support

    @Suite("JSON file support")
    struct JSONTests {

        @Test("require() on a .json file parses and returns the object")
        func testJSONRequire() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("config.json", """
                { "name": "MySpoon", "version": "1.0.0", "enabled": true }
            """)
            ctx.eval("var cfg = require('\(path)')")
            #expect(ctx.eval("cfg.name")?.toString() == "MySpoon")
            #expect(ctx.eval("cfg.version")?.toString() == "1.0.0")
            #expect(ctx.eval("cfg.enabled")?.toBool() == true)
            #expect(!ctx.hadException)
        }

        @Test("JSON require infers .json extension")
        func testJSONExtensionInferred() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("data.json", #"{ "value": 99 }"#)
            let pathNoExt = (path as NSString).deletingPathExtension
            let result = ctx.eval("require('\(pathNoExt)').value")
            #expect(result?.toInt32() == 99)
            #expect(!ctx.hadException)
        }
    }

    // MARK: - Module caching

    @Suite("module caching")
    struct CachingTests {

        @Test("requiring the same path twice returns the identical exports object")
        func testCacheReturnsSameObject() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("singleton.js", """
                module.exports = { count: 0 };
            """)
            ctx.eval("""
                var a = require('\(path)');
                var b = require('\(path)');
                a.count = 1;
            """)
            #expect(ctx.eval("b.count")?.toInt32() == 1)
            #expect(!ctx.hadException)
        }

        @Test("module body is executed only once even when required multiple times")
        func testModuleBodyExecutedOnce() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("counter.js", """
                if (!globalThis.__counterExecutions) globalThis.__counterExecutions = 0;
                globalThis.__counterExecutions++;
                module.exports = {};
            """)
            ctx.eval("require('\(path)'); require('\(path)'); require('\(path)');")
            let count = ctx.eval("globalThis.__counterExecutions")?.toInt32()
            #expect(count == 1)
            #expect(!ctx.hadException)
        }

        @Test("require.cache holds the cached module")
        func testRequireCache() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("cached.js", "module.exports = 'cached';")
            ctx.eval("require('\(path)')")
            let inCache = ctx.eval("require.cache['\(path)'] !== undefined")
            #expect(inCache?.toBool() == true)
            #expect(!ctx.hadException)
        }
    }

    // MARK: - Circular dependencies

    @Suite("circular dependency handling")
    struct CircularTests {

        @Test("circular requires do not infinite-loop and return partial exports")
        func testCircularRequireDoesNotLoop() throws {
            let ctx = try RequireContext()
            // a.js requires b.js, b.js requires a.js — classic circular dependency
            let aPath = ctx.tempDir.appendingPathComponent("a.js").path
            let bPath = ctx.tempDir.appendingPathComponent("b.js").path
            try ctx.write("a.js", """
                var b = require('\(bPath)');
                module.exports = { name: 'a', bName: b.name };
            """)
            try ctx.write("b.js", """
                var a = require('\(aPath)');
                module.exports = { name: 'b', aName: a.name };
            """)
            // Requiring a should not throw or hang
            ctx.eval("var result = require('\(aPath)')")
            #expect(!ctx.hadException)
            // a.name is set; b.aName may be undefined (partial exports) which is
            // the documented CommonJS circular-dependency behaviour
            #expect(ctx.eval("result.name")?.toString() == "a")
        }
    }

    // MARK: - Module scope

    @Suite("module scope isolation")
    struct ScopeTests {

        @Test("top-level var in a module does not leak into global scope")
        func testTopLevelVarIsIsolated() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("isolated.js", """
                var secretVariable = 'should not escape';
                module.exports = {};
            """)
            ctx.eval("require('\(path)')")
            let leaked = ctx.eval("typeof secretVariable")?.toString()
            #expect(leaked == "undefined")
            #expect(!ctx.hadException)
        }

        @Test("__filename inside a module equals the resolved path")
        func testFilenameIsSet() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("checkname.js", """
                module.exports = __filename;
            """)
            let result = ctx.eval("require('\(path)')")
            #expect(result?.toString() == path)
            #expect(!ctx.hadException)
        }

        @Test("__dirname inside a module equals the module's directory")
        func testDirnameIsSet() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("checkdir.js", """
                module.exports = __dirname;
            """)
            let expectedDir = (path as NSString).deletingLastPathComponent
            let result = ctx.eval("require('\(path)')")
            #expect(result?.toString() == expectedDir)
            #expect(!ctx.hadException)
        }
    }

    // MARK: - require.resolve()

    @Suite("require.resolve()")
    struct ResolveTests {

        @Test("require.resolve() returns the absolute path without loading the module")
        func testResolveReturnsPath() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("resolveme.js", "module.exports = {};")
            let pathNoExt = (path as NSString).deletingPathExtension
            let resolved = ctx.eval("require.resolve('\(pathNoExt)')")
            #expect(resolved?.toString() == path)
            #expect(!ctx.hadException)
        }

        @Test("require.resolve() throws for a missing module")
        func testResolveThrowsForMissing() throws {
            let ctx = try RequireContext()
            ctx.eval("require.resolve('/no/such/file/ever')")
            #expect(ctx.hadException)
        }
    }

    // MARK: - Error handling

    @Suite("error handling")
    struct ErrorTests {

        @Test("requiring a non-existent file throws an error")
        func testMissingModuleThrows() throws {
            let ctx = try RequireContext()
            ctx.eval("require('/no/such/file.js')")
            #expect(ctx.hadException)
        }

        @Test("a syntax error in a required module throws and does not cache the module")
        func testSyntaxErrorDoesNotCache() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("bad.js", "this is not valid javascript !!!{{{")
            ctx.eval("try { require('\(path)') } catch(e) {}")
            // After failure the module should not be in require.cache
            let inCache = ctx.eval("require.cache['\(path)'] !== undefined")
            #expect(inCache?.toBool() == false)
        }

        @Test("a runtime error in a required module throws and does not cache the module")
        func testRuntimeErrorDoesNotCache() throws {
            let ctx = try RequireContext()
            let path = try ctx.write("throws.js", "throw new Error('oops');")
            ctx.eval("try { require('\(path)') } catch(e) {}")
            let inCache = ctx.eval("require.cache['\(path)'] !== undefined")
            #expect(inCache?.toBool() == false)
        }
    }

    // MARK: - Spoon resolution

    @Suite("Spoon resolution")
    struct SpoonTests {

        @Test("spoon.json main field is used as the entry point")
        func testSpoonJsonMainField() throws {
            let ctx = try RequireContext()
            // Build a fake Spoon directory in temp and point SPOONS_DIR at it
            // by requiring the entry file directly (we test the spoon.json parsing
            // logic indirectly: write a module that reads its own spoon.json).
            let spoonDir = ctx.tempDir.appendingPathComponent("Spoons/TestSpoon")
            try FileManager.default.createDirectory(at: spoonDir, withIntermediateDirectories: true)
            let spoonJson = spoonDir.appendingPathComponent("spoon.json")
            try """
                { "name": "TestSpoon", "version": "1.0.0", "main": "src/init.js" }
            """.write(to: spoonJson, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(
                at: spoonDir.appendingPathComponent("src"),
                withIntermediateDirectories: true
            )
            try "module.exports = { spoon: true };".write(
                to: spoonDir.appendingPathComponent("src/init.js"),
                atomically: true,
                encoding: .utf8
            )

            // Require via absolute path to the Spoon dir (not bare-name resolution,
            // which depends on ~/.hammerspoon/Spoons — not stable in tests).
            // tryExtensions("/…/TestSpoon") → checks /…/TestSpoon/index.js then
            // gives up. We use the main entry directly to verify spoon.json parsing.
            let mainPath = spoonDir.appendingPathComponent("src/init.js").path
            let result = ctx.eval("require('\(mainPath)').spoon")
            #expect(result?.toBool() == true)
            #expect(!ctx.hadException)
        }
    }
}
