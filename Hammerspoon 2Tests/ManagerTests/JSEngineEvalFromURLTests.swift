//
//  JSEngineEvalFromURLTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 15/11/2026.
//

import Foundation
import JavaScriptCore
import Testing
@testable import Hammerspoon_2

/// `evalFromURL` is how the user's config is loaded, and an uncaught exception in it must reach
/// `ManagerManager` (which tells the user about it) as well as the Console.
@Suite("JSEngine.evalFromURL")
struct JSEngineEvalFromURLTests {
    private let scriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("JSEngineEvalFromURLTests-\(UUID().uuidString).js")

    private func evalFromURL(_ script: String, in engine: JSEngine) throws -> Any? {
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        return try engine.evalFromURL(scriptURL)
    }

    @Test("An uncaught exception is thrown, described with its file and line")
    func uncaughtExceptionThrows() throws {
        let engine = JSEngine()
        defer { engine.shutdown() }
        try engine.resetContext()

        let error = #expect(throws: HammerspoonError.self) {
            try evalFromURL("const a = 1;\nthrow new TypeError('boom');\nglobalThis.reached = true;", in: engine)
        }

        #expect(error?.kind == .jsException)
        #expect(error?.msg == "TypeError: boom (\(scriptURL.lastPathComponent):2)")
        #expect(engine.eval("globalThis.reached") as? Bool != true, "Evaluation should stop at the exception")
    }

    @Test("An exception the script catches itself isn't thrown")
    func caughtExceptionDoesNotThrow() throws {
        let engine = JSEngine()
        defer { engine.shutdown() }
        try engine.resetContext()

        let result = try evalFromURL("try { throw new Error('handled') } catch (e) { 'recovered' }", in: engine)

        #expect((result as? JSValue)?.toString() == "recovered")
    }

    @Test("The exception is still logged, and later exceptions are logged as before")
    func exceptionsStillLogged() async throws {
        let engine = JSEngine()
        defer { engine.shutdown() }
        try engine.resetContext()
        let configToken = UUID().uuidString
        let laterToken = UUID().uuidString

        _ = try? evalFromURL("throw new Error('\(configToken)')", in: engine)
        engine.eval("throw new Error('\(laterToken)')")

        // Log entries are added asynchronously
        let expected = ["JavaScript Exception: Error: \(configToken)", "JavaScript Exception: Error: \(laterToken)"]
        func allLogged() -> Bool {
            let messages = Set(HammerspoonLog.shared.entries(minimumLevel: .Error).map(\.msg))
            return expected.allSatisfy(messages.contains)
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !allLogged() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(allLogged())
    }
}
