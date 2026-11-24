//
//  JSCallbackTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("JSCallback tests")
@MainActor
struct JSCallbackTests {
    @Test("Optional callbacks treat undefined and null as no callback", arguments: ["undefined", "null"])
    func testOptionalCallbackAcceptsMissingValue(_ expression: String) {
        let harness = JSTestHarness()
        let owner = NSObject()

        let callback = JSCallback(value: harness.context.evaluateScript(expression), owner: owner, silentOnUndefined: true)

        #expect(callback == nil)
    }

    @Test("Optional callbacks accept a function")
    func testOptionalCallbackAcceptsFunction() {
        let harness = JSTestHarness()
        let owner = NSObject()

        let callback = JSCallback(value: harness.context.evaluateScript("(() => 42)"), owner: owner, silentOnUndefined: true)

        #expect(callback?.call(withArguments: [])?.toInt32() == 42)
    }

    @Test("Callbacks reject non-function values", arguments: ["null", "42", "'hello'", "({})"])
    func testCallbackRejectsNonFunction(_ expression: String) {
        let harness = JSTestHarness()
        let owner = NSObject()

        let callback = JSCallback(value: harness.context.evaluateScript(expression), owner: owner)

        #expect(callback == nil)
    }
}
