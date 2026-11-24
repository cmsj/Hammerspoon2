//
//  HSCheckForUpdatesIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Stands in for Sparkle's updater, so the tests don't start a real update check
private final class FakeUpdateChecker: UpdateChecking {
    var canCheckForUpdates: Bool
    private(set) var checkCount = 0

    init(canCheckForUpdates: Bool) {
        self.canCheckForUpdates = canCheckForUpdates
    }

    func checkForUpdates() {
        checkCount += 1
    }
}

@Suite("hs.checkForUpdates tests")
@MainActor
struct HSCheckForUpdatesTests {
    @Test("Starts an update check and returns true when one can start")
    func testStartsCheck() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        let fake = FakeUpdateChecker(canCheckForUpdates: true)
        root.updateChecker = { fake }

        harness.expectEqual("hs.checkForUpdates()", true)
        #expect(fake.checkCount == 1)
    }

    @Test("Returns false without checking when a check can't start")
    func testCannotCheck() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        let fake = FakeUpdateChecker(canCheckForUpdates: false)
        root.updateChecker = { fake }

        harness.expectEqual("hs.checkForUpdates()", false)
        #expect(fake.checkCount == 0)
    }
}
