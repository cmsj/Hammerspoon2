//
//  HSConsoleHistoryIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for `hs.consoleHistory()`. `HammerspoonLog.shared` is shared with every other suite, so
/// each test logs messages tagged with its own unique prefix, and searches for that prefix. The
/// tests are synchronous on the main actor, so nothing else can log or clear in the middle of one.
@Suite("hs.consoleHistory tests")
@MainActor
struct HSConsoleHistoryTests {
    /// A harness with `hs` loaded, and a unique tag for the test's messages, also set as `tag` in JS.
    /// Each test makes its own harness, so it's released on the main actor (not stored on the
    /// suite, which Swift Testing may release elsewhere).
    private func makeHarness() -> (JSTestHarness, String) {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        let tag = "[\(UUID().uuidString.prefix(8))]"
        harness.eval("var tag = '\(tag)'")
        return (harness, tag)
    }

    @Test("Returns messages oldest first, with their sequence, date, level and text")
    func testReturnsEntries() {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Info, "\(tag) first")
        HammerspoonLog.shared.log(.Error, "\(tag) second")
        HammerspoonLog.shared.log(.Console, "\(tag) third")

        harness.eval("var history = hs.consoleHistory({ search: tag })")
        #expect(!harness.hasException)
        harness.expectEqual("history.length", 3)
        harness.expectEqual("history.map(e => e.message).join(',')", "\(tag) first,\(tag) second,\(tag) third")
        harness.expectEqual("history.map(e => e.level).join(',')", "info,error,javascript")
        harness.expectTrue("history[0].sequence < history[1].sequence && history[1].sequence < history[2].sequence")
        harness.expectTrue("history[0].date instanceof Date")
        harness.expectTrue("Math.abs(Date.now() - history[0].date.getTime()) < 60000")
    }

    @Test("minimumLevel excludes lower levels")
    func testMinimumLevel() {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Debug, "\(tag) debug")
        HammerspoonLog.shared.log(.Warning, "\(tag) warning")
        HammerspoonLog.shared.log(.Error, "\(tag) error")

        harness.expectEqual("hs.consoleHistory({ search: tag, minimumLevel: 'warning' }).map(e => e.level).join(',')", "warning,error")
        harness.expectEqual("hs.consoleHistory({ search: tag, minimumLevel: 'ERROR' }).map(e => e.level).join(',')", "error")
    }

    @Test("since only returns messages logged after the given sequence")
    func testSince() {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Info, "\(tag) old")
        harness.eval("var last = hs.consoleHistory({ search: tag }).at(-1).sequence")
        HammerspoonLog.shared.log(.Info, "\(tag) new")

        harness.expectEqual("hs.consoleHistory({ search: tag, since: last }).map(e => e.message).join(',')", "\(tag) new")
    }

    @Test("Options set to null or undefined are ignored, as are missing options")
    func testNullOptions() {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Debug, "\(tag) message")

        harness.expectTrue("hs.consoleHistory().some(e => e.message === tag + ' message')")
        harness.expectTrue("hs.consoleHistory(null).some(e => e.message === tag + ' message')")
        harness.expectEqual("hs.consoleHistory({ search: tag, minimumLevel: null, since: undefined }).length", 1)
        #expect(!harness.hasException)
    }

    @Test("Autocomplete entries are never returned")
    func testExcludesAutocomplete() {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Autocomplete, "\(tag) completion")

        harness.expectEqual("hs.consoleHistory({ search: tag }).length", 0)
    }

    @Test("hs.clearConsole() empties the history")
    func testClearConsole() async {
        let (harness, tag) = makeHarness()
        HammerspoonLog.shared.log(.Info, "\(tag) message")
        harness.eval("hs.clearConsole()")
        // clearConsole() clears from a main-actor Task, so give it a chance to run
        for _ in 0..<20 where !HammerspoonLog.shared.entries(minimumLevel: .Info, searchString: tag).isEmpty {
            await Task.yield()
        }

        harness.expectEqual("hs.consoleHistory({ search: tag }).length", 0)
    }

    @Test("Invalid options throw", arguments: [
        "{ minimumLevel: 'loud' }",
        "{ minimumLevel: 'autocomplete' }",
        "{ minimumLevel: 3 }",
        "{ search: 42 }",
        "{ since: 'yesterday' }",
        "{ since: true }",
    ])
    func testInvalidOptionsThrow(options: String) {
        let (harness, _) = makeHarness()
        harness.eval("var threw = false; try { hs.consoleHistory(\(options)) } catch (e) { threw = e instanceof Error }")
        harness.expectTrue("threw")
    }
}
