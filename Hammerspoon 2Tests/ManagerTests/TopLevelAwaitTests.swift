//
//  TopLevelAwaitTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import JavaScriptCore
import Testing
@testable import Hammerspoon_2

/// Top-level `await` in Console input and in the user's config, which JavaScriptCore only allows
/// inside async functions.
@Suite("Top-level await")
struct TopLevelAwaitTests {
    /// Waits up to two seconds for `condition`, which may depend on Promise callbacks or log entries
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func errorsLogged() -> Set<String> {
        Set(HammerspoonLog.shared.entries(minimumLevel: .Error).map(\.msg))
    }

    // MARK: - Console

    /// Evaluates `input` as if typed into the Console, returning each value it would show
    private func evalConsoleInput(_ input: String, in engine: JSEngine) async throws -> [JSValue] {
        var shown: [JSValue] = []
        engine.evalConsoleInput(input) { shown.append($0) }
        _ = try await eventually { !shown.isEmpty }
        return shown
    }

    private func makeEngine() throws -> JSEngine {
        let engine = JSEngine()
        try engine.resetContext()
        return engine
    }

    @Test("An awaited expression shows its value", arguments: [
        "await Promise.resolve(42)",
        "await Promise.resolve(42);",
        "await Promise.resolve(42) // the answer",
        "(await Promise.resolve(40)) + 2",
        "await Promise.resolve(42); // with a comment",
        "await Promise.resolve(42) /* with a comment; */",
        "await Promise.resolve(42); ",
    ])
    func awaitedExpression(input: String) async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        let shown = try await evalConsoleInput(input, in: engine)

        #expect(shown.count == 1)
        #expect(shown.first?.toInt32() == 42)
    }

    @Test("Input without top-level await is evaluated as it always was")
    func plainInputUnchanged() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }
        let context = try #require(engine.context)

        // `await` is an ordinary identifier outside async functions
        for input in ["1 + 1", "var await = 3; await", "async function f() { await 1 }"] {
            #expect(TopLevelAwait.rewriteConsoleInput(input, in: context) == nil, "\(input)")
        }
        var shown: [JSValue] = []
        engine.evalConsoleInput("var await = 3; await") { shown.append($0) }
        #expect(shown.map { $0.toInt32() } == [3], "A synchronous result is shown straight away")
    }

    @Test("A declaration with await stays available to later input", arguments: ["const", "let", "var"])
    func declarationIsGlobal(keyword: String) async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        let shown = try await evalConsoleInput("\(keyword) answer = await Promise.resolve(42)", in: engine)

        #expect(shown.first?.isUndefined == true)
        #expect(engine.evalValue("answer")?.toInt32() == 42)
    }

    @Test("Every name in a declaration with await stays available, with its own value", arguments: [
        "const a = await Promise.resolve(1), b = 2",
        "let a = await Promise.resolve([1, 'x,y'].length - 1), b = 2; // note",
        "var a = (await Promise.resolve(1)), b = (() => { return 2 })();",
        "const a = `${`x,${'y,z'}`},`.length - 5 + await Promise.resolve(0), b = `${1}`.length + 1",
    ])
    func multipleDeclarations(input: String) async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        _ = try await evalConsoleInput(input, in: engine)

        #expect(engine.evalValue("a")?.toInt32() == 1)
        #expect(engine.evalValue("b")?.toInt32() == 2)
    }

    @Test("A declaration with a trailing comment stays available")
    func declarationWithComment() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        _ = try await evalConsoleInput("const answer = await Promise.resolve(42); // note", in: engine)

        #expect(engine.evalValue("answer")?.toInt32() == 42)
    }

    @Test("Several statements with await all run")
    func statements() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        let shown = try await evalConsoleInput("let a = await Promise.resolve(1); let b = 2; globalThis.sum = a + b", in: engine)

        #expect(shown.first?.isUndefined == true)
        #expect(engine.evalValue("sum")?.toInt32() == 3)
    }

    @Test("A rejection is logged as an exception, not an unhandled rejection")
    func rejectionLogged() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }
        let token = UUID().uuidString

        var shown: [JSValue] = []
        engine.evalConsoleInput("await Promise.reject(new Error('\(token)'))") { shown.append($0) }

        #expect(try await eventually { errorsLogged().contains("JavaScript Exception: Error: \(token)") })
        #expect(!errorsLogged().contains("Unhandled Promise rejection: Error: \(token)"))
        #expect(shown.isEmpty)
    }

    // MARK: - Config files

    private let scriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("TopLevelAwaitTests-\(UUID().uuidString).js")

    private func evalFile(_ script: String,
                          in engine: JSEngine,
                          onAsyncException: ((HammerspoonError) -> Void)? = nil) throws -> Any? {
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        return try engine.evalFromURL(scriptURL, wrapInIIFE: false, onAsyncException: onAsyncException)
    }

    @Test("A config file can use top-level await")
    func configFileAwaits() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        try evalFile("globalThis.before = 1;\nawait new Promise(r => globalThis.release = r);\nglobalThis.after = 2;", in: engine)

        #expect(engine.evalValue("before")?.toInt32() == 1)
        #expect(engine.evalValue("globalThis.after")?.isUndefined == true, "The rest of the file waits for the await")
        engine.eval("release()")
        #expect(try await eventually { engine.evalValue("globalThis.after")?.toInt32() == 2 })
    }

    @Test("An exception after a config file's first await is reported once, with its line")
    func configFileAsyncException() async throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        var reported: [HammerspoonError] = []
        try evalFile("await null;\nthrow new TypeError('late');", in: engine) { reported.append($0) }

        #expect(try await eventually { !reported.isEmpty })
        #expect(reported.first?.kind == .jsException)
        #expect(reported.first?.msg == "TypeError: late (\(scriptURL.lastPathComponent):2)")
        #expect(try await eventually { errorsLogged().contains("JavaScript Exception: TypeError: late") })
        #expect(!errorsLogged().contains("Unhandled Promise rejection: TypeError: late"))
    }

    @Test("A config file with a syntax error still fails straight away")
    func configFileSyntaxError() throws {
        let engine = try makeEngine()
        defer { engine.shutdown() }

        let error = #expect(throws: HammerspoonError.self) {
            try evalFile("await (\n", in: engine)
        }
        #expect(error?.kind == .jsException)
    }
}
