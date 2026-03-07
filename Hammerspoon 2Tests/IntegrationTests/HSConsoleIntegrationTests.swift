//
//  HSConsoleIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/03/2026.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.console module
@Suite(.serialized)
struct HSConsoleIntegrationTests {

    // MARK: - getConsole Tests

    @Test("getConsole returns empty string when log is empty")
    @MainActor
    func testGetConsoleEmpty() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.clearLog()
        let result = harness.eval("hs.console.getConsole()")
        #expect(result as? String == "")
    }

    @Test("getConsole returns log entries after print")
    @MainActor
    func testGetConsoleAfterPrint() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.clearLog()
        HammerspoonLog.shared.log(.Console, "hello world")
        let result = harness.eval("hs.console.getConsole()") as? String
        #expect(result?.contains("JavaScript: hello world") == true)
    }

    @Test("getConsole returns multiple entries separated by newlines")
    @MainActor
    func testGetConsoleMultipleEntries() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.clearLog()
        HammerspoonLog.shared.log(.Info, "first")
        HammerspoonLog.shared.log(.Warning, "second")
        HammerspoonLog.shared.log(.Error, "third")

        let result = harness.eval("hs.console.getConsole()") as? String ?? ""
        let lines = result.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(result.contains("Info: first"))
        #expect(result.contains("Warning: second"))
        #expect(result.contains("Error: third"))
    }

    @Test("getConsole is accessible as a function from JavaScript")
    func testGetConsoleIsFunction() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        harness.expectTrue("typeof hs.console.getConsole === 'function'")
    }

    // MARK: - getHistory Tests

    @Test("getHistory returns empty array initially")
    @MainActor
    func testGetHistoryEmpty() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.evalHistory = []
        let result = harness.eval("hs.console.getHistory()") as? [String]
        #expect(result == [])
    }

    @Test("getHistory returns eval history entries")
    @MainActor
    func testGetHistoryWithEntries() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.evalHistory = ["print('hi')", "2 + 2", "hs.reload()"]
        let result = harness.eval("hs.console.getHistory()") as? [String]
        #expect(result == ["print('hi')", "2 + 2", "hs.reload()"])
    }

    @Test("getHistory is accessible as a function from JavaScript")
    func testGetHistoryIsFunction() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        harness.expectTrue("typeof hs.console.getHistory === 'function'")
    }

    @Test("getHistory returns an array type in JavaScript")
    @MainActor
    func testGetHistoryReturnsArray() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        HammerspoonLog.shared.evalHistory = ["test"]
        harness.expectTrue("Array.isArray(hs.console.getHistory())")
    }

    // MARK: - Module access

    @Test("console module exposes all expected functions")
    func testModuleAccess() {
        let harness = JSTestHarness()
        harness.loadModule(HSConsoleModule.self, as: "console")

        harness.expectTrue("typeof hs.console === 'object'")
        harness.expectTrue("typeof hs.console.print === 'function'")
        harness.expectTrue("typeof hs.console.open === 'function'")
        harness.expectTrue("typeof hs.console.close === 'function'")
        harness.expectTrue("typeof hs.console.clear === 'function'")
        harness.expectTrue("typeof hs.console.getConsole === 'function'")
        harness.expectTrue("typeof hs.console.getHistory === 'function'")
    }
}
