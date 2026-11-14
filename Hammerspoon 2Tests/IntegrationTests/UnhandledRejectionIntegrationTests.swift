//
//  UnhandledRejectionIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import JavaScriptCoreExtras
@testable import Hammerspoon_2
import HammerspoonSDK

/// A JSContext with an UnhandledRejectionInstaller that records what it reports, instead of
/// logging it
@MainActor
private final class RejectionContext {
    let context: JSContext
    private(set) var reported: [JSValue] = []
    private(set) var exceptions: [String] = []

    init() throws {
        context = JSContext(virtualMachine: JSVirtualMachine())!
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown")
        }
        try context.install([UnhandledRejectionInstaller { [weak self] reason in self?.reported.append(reason) }])
    }

    func eval(_ script: String, sourceURL: String = "file:///config/init.js") {
        context.evaluateScript(script, withSourceURL: URL(string: sourceURL))
    }

    var reportedMessages: [String] { reported.map { $0.toString() ?? "" } }
}

@Suite("Unhandled Promise rejections")
@MainActor
struct UnhandledRejectionTests {

    @Test("a rejection nothing handles is reported, once, with its reason")
    func testUnhandledIsReported() async throws {
        let ctx = try RejectionContext()
        ctx.eval("Promise.reject(new Error('boom'))")

        #expect(await waitUntil { !ctx.reported.isEmpty })
        #expect(ctx.reportedMessages == ["Error: boom"])
        #expect(ctx.exceptions.isEmpty)
    }

    @Test("a rejection handled in the same turn isn't reported")
    func testHandledIsNotReported() async throws {
        let ctx = try RejectionContext()
        ctx.eval("""
            globalThis.caught = false;
            const p = Promise.reject(new Error('boom'));
            p.catch(() => { caught = true; });
            Promise.reject(new Error('also handled')).then(() => {}, () => {});
            """)

        #expect(await waitUntil { ctx.context.evaluateScript("caught")?.toBool() == true })
        // Give a wrongly reported rejection the same chance to arrive as a real one would have
        ctx.eval("Promise.reject(new Error('sentinel'))")
        #expect(await waitUntil { !ctx.reported.isEmpty })
        #expect(ctx.reportedMessages == ["Error: sentinel"])
    }

    @Test("an error thrown in an async function or a then() callback is reported, with where it was thrown")
    func testThrownInAsyncCodeIsReported() async throws {
        let ctx = try RejectionContext()
        ctx.eval("""
            async function load() {
                undefinedFunction();
            }
            load();
            Promise.resolve().then(() => { throw new TypeError('in then'); });
            """, sourceURL: "file:///config/Spoons/Broken/init.js")

        #expect(await waitUntil { ctx.reported.count == 2 })
        #expect(Set(ctx.reportedMessages) == ["ReferenceError: Can't find variable: undefinedFunction", "TypeError: in then"])
        let stacks = ctx.reported.compactMap { $0.objectForKeyedSubscript("stack")?.toString() }
        #expect(stacks.allSatisfy { $0.contains("Spoons/Broken/init.js") }, "\(stacks)")
    }

    @Test("logging copes with reasons that aren't Errors, without throwing")
    func testLogNonErrorReasons() throws {
        let ctx = try RejectionContext()
        for script in ["undefined", "null", "42", "'text'", "({ message: 'object' })", "new Error('err')"] {
            let reason = try #require(ctx.context.evaluateScript(script))
            UnhandledRejectionInstaller.log(reason)
        }
        #expect(ctx.exceptions.isEmpty)
    }

    @Test("JSEngine logs an unhandled rejection in the user's config to the console, with its stack")
    func testJSEngineLogsRejections() async throws {
        let engine = JSEngine()
        defer { engine.shutdown() }
        try engine.resetContext()
        let token = UUID().uuidString
        engine.eval("(async function broken() { throw new Error('\(token)'); })()")

        func logged() -> [String] {
            HammerspoonLog.shared.entries(minimumLevel: .Error).map(\.msg).filter { $0.contains(token) || $0.contains("broken@") }
        }
        #expect(await waitUntil { logged().count >= 2 })
        let messages = logged()
        #expect(messages.first == "Unhandled Promise rejection: Error: \(token)")
        #expect(messages.contains { $0.hasPrefix("Stack trace: ") && $0.contains("broken@") }, "\(messages)")
    }

    /// Spins the main run loop until `condition` is true, or a second has passed
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(1)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}
