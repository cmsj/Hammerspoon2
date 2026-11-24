//
//  JSCallbackTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("JSCallback tests")
@MainActor
struct JSCallbackTests {
    /// Runs `body` and returns the messages it logged at Error level.
    ///
    /// AKLog appends to HammerspoonLog from a main-actor Task, and other suites may be logging
    /// concurrently. So `body` is bracketed by two sentinels logged in the same synchronous
    /// stretch: their Tasks are enqueued back to back with `body`'s, so whatever lands between
    /// them came from `body`.
    private func errorsLogged(by body: () -> Void) async -> [String] {
        let start = "JSCallbackTests start \(UUID().uuidString)"
        let end = "JSCallbackTests end \(UUID().uuidString)"
        AKError(start)
        body()
        AKError(end)

        for _ in 0..<200 {
            let messages = HammerspoonLog.shared.entries(minimumLevel: .Error).map(\.msg)
            if let startIndex = messages.firstIndex(of: start), let endIndex = messages.firstIndex(of: end) {
                return Array(messages[(startIndex + 1)..<endIndex])
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for the log sentinels")
        return []
    }

    @Test("Optional callbacks accept undefined and null without logging an error", arguments: ["undefined", "null"])
    func testOptionalCallbackAcceptsMissingValue(_ expression: String) async {
        let harness = JSTestHarness()
        let owner = NSObject()
        var callback: JSCallback?

        let errors = await errorsLogged {
            callback = JSCallback(value: harness.context.evaluateScript(expression), owner: owner, silentOnUndefined: true)
        }

        #expect(callback == nil)
        #expect(errors.isEmpty, "\(expression) should be accepted silently for an optional callback")
    }

    @Test("Optional callbacks still log an error for a non-function value")
    func testOptionalCallbackRejectsNonFunction() async {
        let harness = JSTestHarness()
        let owner = NSObject()
        var callback: JSCallback?

        let errors = await errorsLogged {
            callback = JSCallback(value: harness.context.evaluateScript("42"), owner: owner, silentOnUndefined: true)
        }

        #expect(callback == nil)
        #expect(errors == ["Unable to create JSCallback: value is not a function"])
    }

    @Test("Required callbacks log an error for null")
    func testRequiredCallbackRejectsNull() async {
        let harness = JSTestHarness()
        let owner = NSObject()
        var callback: JSCallback?

        let errors = await errorsLogged {
            callback = JSCallback(value: harness.context.evaluateScript("null"), owner: owner)
        }

        #expect(callback == nil)
        #expect(errors == ["Unable to create JSCallback: value is not a function"])
    }
}
