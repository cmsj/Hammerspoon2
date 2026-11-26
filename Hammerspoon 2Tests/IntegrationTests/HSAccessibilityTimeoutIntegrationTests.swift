//
//  HSAccessibilityTimeoutIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for `hs.accessibilityTimeout` and `withAXTimeoutLimit`. The Accessibility API can't
/// report its timeout, so these check the value `AXMessagingTimeout` last gave it.
///
/// Each test runs synchronously on the main actor, so no other test can change the
/// process-wide timeout while it runs. The harness's teardown resets it.
@Suite("hs.accessibilityTimeout tests")
@MainActor
struct HSAccessibilityTimeoutTests {
    @Test("accessibilityTimeout defaults to 0, the macOS default")
    func testDefault() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.expectEqual("hs.accessibilityTimeout", 0)
        #expect(AXMessagingTimeout.applied == 0)
    }

    @Test("Setting accessibilityTimeout applies it")
    func testSetting() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 1.5")
        #expect(!harness.hasException)
        harness.expectEqual("hs.accessibilityTimeout", 1.5)
        #expect(AXMessagingTimeout.applied == 1.5)

        harness.eval("hs.accessibilityTimeout = 0")
        harness.expectEqual("hs.accessibilityTimeout", 0)
        #expect(AXMessagingTimeout.applied == 0)
    }

    @Test("Invalid timeouts throw and leave the timeout unchanged",
          arguments: ["-1", "NaN", "Infinity", "'soon'", "'1'", "undefined", "null", "true", "1e-50", "1e39"])
    func testInvalid(value: String) {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 2")
        harness.eval("hs.accessibilityTimeout = \(value)")
        harness.expectException()
        harness.expectEqual("hs.accessibilityTimeout", 2)
        #expect(AXMessagingTimeout.applied == 2)
    }

    @Test("The smallest and largest timeouts a Float can hold are accepted",
          arguments: [Double(Float.leastNonzeroMagnitude), Double(Float.greatestFiniteMagnitude)])
    func testFloatBoundaries(seconds: Double) {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = \(seconds)")
        #expect(!harness.hasException)
        harness.expectEqual("hs.accessibilityTimeout", seconds)
        #expect(AXMessagingTimeout.applied == seconds)
    }

    @Test("Shutting down, as reloading does, goes back to the macOS default")
    func testShutdownResets() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 3")
        root.shutdown()
        #expect(AXMessagingTimeout.configured == 0)
        #expect(AXMessagingTimeout.applied == 0)
    }

    @Test("A limit applies while its body runs, then the configured timeout comes back")
    func testLimitRestoresConfigured() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 2")

        let inside = withAXTimeoutLimit(0.25) { AXMessagingTimeout.applied }
        #expect(inside == 0.25)
        #expect(AXMessagingTimeout.applied == 2)
    }

    @Test("A limit with the macOS default configured restores the default")
    func testLimitRestoresDefault() {
        let inside = withAXTimeoutLimit(0.25) { AXMessagingTimeout.applied }
        #expect(inside == 0.25)
        #expect(AXMessagingTimeout.applied == 0)
    }

    @Test("A configured timeout shorter than the limit is kept")
    func testShorterConfiguredWins() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 0.1")

        let inside = withAXTimeoutLimit(0.25) { AXMessagingTimeout.applied }
        #expect(inside == 0.1)
        #expect(AXMessagingTimeout.applied == 0.1)
    }

    @Test("Nested limits keep the shortest, and each restores the one outside it")
    func testNestedLimits() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 2")

        var observed: [Double] = []
        withAXTimeoutLimit(0.25) {
            observed.append(AXMessagingTimeout.applied)
            withAXTimeoutLimit(0.5) { observed.append(AXMessagingTimeout.applied) }
            withAXTimeoutLimit(0.1) { observed.append(AXMessagingTimeout.applied) }
            observed.append(AXMessagingTimeout.applied)
        }
        #expect(observed == [0.25, 0.25, 0.1, 0.25])
        #expect(AXMessagingTimeout.applied == 2)
    }

    @Test("Setting the timeout during a limit takes effect when the limit ends")
    func testConfigureDuringLimit() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()

        let inside = withAXTimeoutLimit(0.25) {
            harness.eval("hs.accessibilityTimeout = 4")
            return AXMessagingTimeout.applied
        }
        #expect(inside == 0.25)
        harness.expectEqual("hs.accessibilityTimeout", 4)
        #expect(AXMessagingTimeout.applied == 4)
    }

    @Test("hs.window.allWindows() puts the configured timeout back")
    func testAllWindowsRestores() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()
        harness.eval("hs.accessibilityTimeout = 2")
        harness.eval("hs.window.allWindows()")
        #expect(!harness.hasException)
        #expect(AXMessagingTimeout.applied == 2)
    }
}
