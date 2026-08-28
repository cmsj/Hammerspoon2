//
//  HSLoadSpoonIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Test context

// LoadSpoonContext creates an isolated JSContext with require() and a full ModuleRoot (as `hs`)
// installed, plus a temporary config directory whose Spoons/ subdirectory tests can populate.
// A MockSettingsManager points ModuleRoot's hs.loadSpoon() at that temp directory, so tests
// never touch the real config location. Each test creates its own instance.
private final class LoadSpoonContext {
    let context: JSContext
    let configDir: URL
    private(set) var lastException: JSValue?

    init() throws {
        let vm = JSVirtualMachine()
        let ctx = JSContext(virtualMachine: vm)!
        ctx.name = "LoadSpoonTestContext"
        context = ctx

        configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs_loadspoon_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        ctx.exceptionHandler = { [weak self] _, exc in self?.lastException = exc }
        try RequireInstaller().install(in: ctx)

        let settings = MockSettingsManager()
        settings.configLocation = configDir.appendingPathComponent("init.js")
        let moduleRoot = ModuleRoot(engineID: UUID(), settings: settings)
        ctx.setObject(moduleRoot, forKeyedSubscript: "hs" as NSString)
    }

    deinit {
        try? FileManager.default.removeItem(at: configDir)
    }

    // Write a Spoon's spoon.json. Pass nil for any field to omit it entirely.
    @discardableResult
    func writeSpoonJSON(
        spoon: String,
        name: String? = "TestSpoon",
        author: String? = "A. Developer",
        version: String? = "1.0.0",
        description: String? = "A test spoon."
    ) throws -> URL {
        var fields: [String] = []
        if let name { fields.append(#""name": "\#(name)""#) }
        if let author { fields.append(#""author": "\#(author)""#) }
        if let version { fields.append(#""version": "\#(version)""#) }
        if let description { fields.append(#""description": "\#(description)""#) }
        let json = "{ " + fields.joined(separator: ", ") + " }"
        return try write(spoon: spoon, "spoon.json", json)
    }

    @discardableResult
    func writeSpoonInit(spoon: String, _ content: String) throws -> URL {
        try write(spoon: spoon, "init.js", content)
    }

    @discardableResult
    func write(spoon: String, _ relativePath: String, _ content: String) throws -> URL {
        let url = configDir.appendingPathComponent("Spoons/\(spoon)/\(relativePath)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func eval(_ script: String) -> JSValue? {
        lastException = nil
        return context.evaluateScript(script)
    }

    var hadException: Bool { lastException != nil }
}

// MARK: - Test suites

@Suite("hs.loadSpoon() tests")
struct HSLoadSpoonTests {

    @Suite("validation")
    struct ValidationTests {

        @Test("loading a Spoon with no spoon.json throws")
        func testMissingSpoonJSONThrows() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = {};")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }

        @Test("loading a Spoon with malformed spoon.json throws")
        func testMalformedSpoonJSONThrows() throws {
            let ctx = try LoadSpoonContext()
            try ctx.write(spoon: "TestSpoon", "spoon.json", "{ not valid json")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = {};")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }

        @Test("loading a Spoon whose spoon.json is missing a required field throws")
        func testMissingRequiredFieldThrows() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon", description: nil)
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = {};")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }

        @Test("loading a Spoon whose spoon.json has an empty required field throws")
        func testEmptyRequiredFieldThrows() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon", author: "")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = {};")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }

        @Test("loading a Spoon with no init.js throws")
        func testMissingInitJSThrows() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }

        @Test("loading a Spoon that doesn't exist at all throws")
        func testNonexistentSpoonThrows() throws {
            let ctx = try LoadSpoonContext()
            ctx.eval("hs.loadSpoon('NoSuchSpoon')")
            #expect(ctx.hadException)
        }
    }

    @Suite("loading")
    struct LoadingTests {

        @Test("a well-formed Spoon loads and returns its module.exports")
        func testValidSpoonLoads() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.writeSpoonInit(spoon: "TestSpoon", """
                module.exports = { greet: function (n) { return 'Hello, ' + n; } };
            """)
            let result = ctx.eval("hs.loadSpoon('TestSpoon').greet('World')")
            #expect(result?.toString() == "Hello, World")
            #expect(!ctx.hadException)
        }

        @Test("a Spoon's init.js can require() a sibling file relative to its own directory")
        func testSpoonCanRequireRelativeFile() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.write(spoon: "TestSpoon", "lib/helper.js", """
                module.exports = { double: function (n) { return n * 2; } };
            """)
            try ctx.writeSpoonInit(spoon: "TestSpoon", """
                var helper = require('./lib/helper.js');
                module.exports = { doubled: helper.double(21) };
            """)
            let result = ctx.eval("hs.loadSpoon('TestSpoon').doubled")
            #expect(result?.toInt32() == 42)
            #expect(!ctx.hadException)
        }

        @Test("loading the same Spoon twice returns the identical cached exports object")
        func testLoadingSameSpoonTwiceReturnsCachedExports() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = { count: 0 };")
            ctx.eval("""
                var a = hs.loadSpoon('TestSpoon');
                var b = hs.loadSpoon('TestSpoon');
                a.count = 1;
            """)
            let result = ctx.eval("hs.loadSpoon('TestSpoon').count")
            #expect(result?.toInt32() == 1)
            #expect(!ctx.hadException)
        }

        @Test("a runtime error inside a Spoon's init.js propagates as an exception")
        func testSpoonInitThrowingPropagates() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "throw new Error('boom');")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            #expect(ctx.hadException)
        }
    }

    @Suite("hs.spoons namespace")
    struct SpoonsNamespaceTests {

        @Test("a loaded Spoon is reachable at hs.spoons.NAME with the same exports object")
        func testSpoonRegisteredInNamespace() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = { marker: 'unique-value' };")
            ctx.eval("hs.loadSpoon('TestSpoon')")
            let result = ctx.eval("hs.spoons.TestSpoon.marker")
            #expect(result?.toString() == "unique-value")
            #expect(!ctx.hadException)
        }

        @Test("hs.spoons.NAME is the identical object returned by loadSpoon(), not a copy")
        func testSpoonsNamespaceHoldsSameIdentity() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "TestSpoon")
            try ctx.writeSpoonInit(spoon: "TestSpoon", "module.exports = { count: 0 };")
            ctx.eval("""
                var loaded = hs.loadSpoon('TestSpoon');
                hs.spoons.TestSpoon.count = 42;
            """)
            let result = ctx.eval("loaded.count")
            #expect(result?.toInt32() == 42)
            #expect(!ctx.hadException)
        }

        @Test("a Spoon that fails to load is not registered in hs.spoons")
        func testFailedLoadDoesNotRegister() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "BrokenSpoon")
            // No init.js written, so this load fails.
            ctx.eval("try { hs.loadSpoon('BrokenSpoon') } catch (e) {}")
            let result = ctx.eval("typeof hs.spoons.BrokenSpoon")
            #expect(result?.toString() == "undefined")
        }

        @Test("multiple loaded Spoons are all reachable independently under hs.spoons")
        func testMultipleSpoonsCoexistInNamespace() throws {
            let ctx = try LoadSpoonContext()
            try ctx.writeSpoonJSON(spoon: "SpoonA")
            try ctx.writeSpoonInit(spoon: "SpoonA", "module.exports = { which: 'A' };")
            try ctx.writeSpoonJSON(spoon: "SpoonB")
            try ctx.writeSpoonInit(spoon: "SpoonB", "module.exports = { which: 'B' };")
            ctx.eval("""
                hs.loadSpoon('SpoonA');
                hs.loadSpoon('SpoonB');
            """)
            let a = ctx.eval("hs.spoons.SpoonA.which")
            let b = ctx.eval("hs.spoons.SpoonB.which")
            #expect(a?.toString() == "A")
            #expect(b?.toString() == "B")
            #expect(!ctx.hadException)
        }
    }
}
