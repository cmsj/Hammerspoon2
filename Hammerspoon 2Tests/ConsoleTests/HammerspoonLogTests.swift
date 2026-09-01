//
//  HammerspoonLogTests.swift
//  Hammerspoon 2Tests
//

import Testing
@testable import Hammerspoon_2

/// `HammerspoonLog`/`SettingsManager` are real process-wide `@MainActor` singletons
/// with no per-test injection, so this suite is serialized and each test clears/restores
/// the shared state it touches rather than relying on isolation between tests.
///
/// Serializing this suite only prevents its own tests from racing each other — other
/// test suites elsewhere in the target run in parallel and can log through the same
/// `HammerspoonLog.shared` singleton (e.g. via AKDebug/AKWarning calls in unrelated
/// production code under test). Every test below tags its own messages with a unique
/// prefix and filters to that prefix before asserting on counts/order, so ambient
/// logging noise from concurrent suites can't make these flaky.
@Suite("HammerspoonLog tests", .serialized)
@MainActor
struct HammerspoonLogTests {

    init() {
        HammerspoonLog.shared.clearLog()
    }

    /// A short, unique-per-call prefix so a test's own messages can be picked out of
    /// the shared log even if other suites are concurrently logging into it too.
    private func uniqueTag() -> String {
        "[\(UUID().uuidString.prefix(8))]"
    }

    @Test("Per-level buffers evict independently")
    func testPerLevelEvictionIsolation() {
        let tag = uniqueTag()
        let originalCap = SettingsManager.shared.consoleHistoryLength
        defer { SettingsManager.shared.consoleHistoryLength = originalCap }
        SettingsManager.shared.consoleHistoryLength = 3

        for i in 0..<10 {
            HammerspoonLog.shared.log(.Debug, "\(tag) debug \(i)")
        }
        HammerspoonLog.shared.log(.Warning, "\(tag) warning A")
        HammerspoonLog.shared.log(.Warning, "\(tag) warning B")

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
            .filter { $0.msg.hasPrefix(tag) }
        let debugCount = entries.filter { $0.logType == .Debug }.count
        let warningCount = entries.filter { $0.logType == .Warning }.count

        #expect(debugCount == 3, "Debug buffer should be capped to consoleHistoryLength")
        #expect(warningCount == 2, "Warning entries should survive Debug spam untouched")
    }

    @Test(".Garbage buffer capacity is independent of consoleHistoryLength")
    func testGarbageCapacityIndependence() {
        let tag = uniqueTag()
        let originalCap = SettingsManager.shared.consoleHistoryLength
        defer { SettingsManager.shared.consoleHistoryLength = originalCap }
        SettingsManager.shared.consoleHistoryLength = 5000

        for i in 0..<250 {
            HammerspoonLog.shared.log(.Garbage, "\(tag) garbage \(i)")
        }

        let garbageCount = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
            .filter { $0.logType == .Garbage && $0.msg.hasPrefix(tag) }.count
        #expect(garbageCount == 200, "Garbage buffer should be capped at its own hardcoded capacity regardless of consoleHistoryLength")
    }

    @Test("Merged entries are ordered chronologically across levels")
    func testChronologicalMerge() {
        let tag = uniqueTag()
        HammerspoonLog.shared.log(.Warning, "\(tag) 1")
        HammerspoonLog.shared.log(.Debug, "\(tag) 2")
        HammerspoonLog.shared.log(.Error, "\(tag) 3")
        HammerspoonLog.shared.log(.Debug, "\(tag) 4")

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
            .filter { $0.msg.hasPrefix(tag) }
        #expect(entries.map { $0.msg } == ["\(tag) 1", "\(tag) 2", "\(tag) 3", "\(tag) 4"])
    }

    @Test("minimumLevel excludes lower severities")
    func testMinimumLevelFiltering() {
        let tag = uniqueTag()
        HammerspoonLog.shared.log(.Debug, "\(tag) debug")
        HammerspoonLog.shared.log(.Info, "\(tag) info")
        HammerspoonLog.shared.log(.Warning, "\(tag) warning")
        HammerspoonLog.shared.log(.Error, "\(tag) error")

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Warning)
            .filter { $0.msg.hasPrefix(tag) }
        #expect(entries.map { $0.logType } == [.Warning, .Error])
    }

    @Test("searchString filters by substring")
    func testSearchStringFiltering() {
        let tag = uniqueTag()
        HammerspoonLog.shared.log(.Info, "\(tag) hello world")
        HammerspoonLog.shared.log(.Info, "\(tag) goodbye world")

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage, searchString: "\(tag) hello")
        #expect(entries.count == 1)
        #expect(entries.first?.msg == "\(tag) hello world")
    }

    @Test("AKGarbage gate blocks storage when disabled")
    func testAKGarbageGateDisabled() {
        let tag = uniqueTag()
        akSetGarbageLoggingEnabled(false)
        defer { akSetGarbageLoggingEnabled(false) }

        // The gate short-circuits before AKLog ever spawns a Task, so this is
        // deterministic without needing to wait for anything.
        AKGarbage("\(tag) should not be stored")

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
            .filter { $0.msg.hasPrefix(tag) }
        #expect(entries.filter { $0.logType == .Garbage }.isEmpty)
    }

    /// `AKLog` dispatches into the shared log via a fire-and-forget
    /// `Task { @MainActor in ... }`, so there's nothing to `await` directly.
    /// We're already on MainActor's serial executor, so repeatedly yielding
    /// gives that already-enqueued, fully-synchronous job a chance to run;
    /// polling (rather than a fixed yield count) avoids flakiness under load
    /// without resorting to a real time-based sleep.
    private func waitUntil(_ condition: () -> Bool, attempts: Int = 20) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("AKGarbage gate allows storage when enabled")
    func testAKGarbageGateEnabled() async {
        let tag = uniqueTag()
        akSetGarbageLoggingEnabled(true)
        defer { akSetGarbageLoggingEnabled(false) }

        AKGarbage("\(tag) should be stored")
        await waitUntil {
            HammerspoonLog.shared.entries(minimumLevel: .Garbage)
                .contains { $0.logType == .Garbage && $0.msg == "\(tag) should be stored" }
        }

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
        #expect(entries.contains { $0.logType == .Garbage && $0.msg == "\(tag) should be stored" })
    }

    @Test("garbageLoggingEnabled setting drives the AKGarbage gate")
    func testSettingsWiresGate() async {
        let tag = uniqueTag()
        let original = SettingsManager.shared.garbageLoggingEnabled
        defer {
            SettingsManager.shared.garbageLoggingEnabled = original
            akSetGarbageLoggingEnabled(original)
        }

        SettingsManager.shared.garbageLoggingEnabled = true
        AKGarbage("\(tag) via settings")
        await waitUntil {
            HammerspoonLog.shared.entries(minimumLevel: .Garbage)
                .contains { $0.logType == .Garbage && $0.msg == "\(tag) via settings" }
        }

        let entries = HammerspoonLog.shared.entries(minimumLevel: .Garbage)
        #expect(entries.contains { $0.logType == .Garbage && $0.msg == "\(tag) via settings" })
    }
}
