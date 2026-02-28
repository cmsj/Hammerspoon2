//
//  JSEnhancementTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for JavaScript enhancement files
///
/// Many modules have companion .js files that add convenience functions,
/// syntactic sugar, and higher-level abstractions on top of the Swift core.
/// These tests ensure those enhancements work correctly.
struct JSEnhancementTests {

    // MARK: - Timer Enhancement Tests

    @Test("Timer time conversion functions exist")
    func testTimerConversionFunctions() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectTrue("typeof hs.timer.minutes === 'function'")
        harness.expectTrue("typeof hs.timer.hours === 'function'")
        harness.expectTrue("typeof hs.timer.days === 'function'")
        harness.expectTrue("typeof hs.timer.weeks === 'function'")
    }

    @Test("Timer conversion functions work correctly")
    func testTimerConversions() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Test each conversion
        harness.expectEqual("hs.timer.minutes(2)", 120.0)
        harness.expectEqual("hs.timer.hours(1)", 3600.0)
        harness.expectEqual("hs.timer.days(1)", 86400.0)
        harness.expectEqual("hs.timer.weeks(1)", 604800.0)
    }

    @Test("Timer predicate functions exist")
    func testTimerPredicateFunctions() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectTrue("typeof hs.timer.doUntil === 'function'")
        harness.expectTrue("typeof hs.timer.doWhile === 'function'")
        harness.expectTrue("typeof hs.timer.waitUntil === 'function'")
        harness.expectTrue("typeof hs.timer.waitWhile === 'function'")
    }

    @Test("Timer predicate functions validate input types")
    func testTimerPredicateValidation() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Should throw when predicate is not a function
        harness.eval("hs.timer.doUntil('not a function', function() {})")
        harness.expectException()
    }

    @Test("Timer.waitUntil requires function arguments")
    func testTimerWaitUntilValidation() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Should throw when action is not a function
        harness.eval("hs.timer.waitUntil(function() { return true; }, 'not a function')")
        harness.expectException()
    }

    // MARK: - Enhancement Loading Tests

    @Test("JavaScript enhancements load automatically with modules")
    func testEnhancementsAutoLoad() {
        let harness = JSTestHarness()

        // Load timer module - should automatically load hs.timer.js
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Enhanced functions should be available
        harness.expectTrue("typeof hs.timer.minutes === 'function'")
    }

    @Test("Enhancements don't break core functionality")
    func testEnhancementsDontBreakCore() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Core Swift functions should still work
        harness.expectTrue("typeof hs.timer.doAfter === 'function'")
        harness.expectTrue("typeof hs.timer.doEvery === 'function'")
        harness.expectTrue("typeof hs.timer.new === 'function'")

        // And they should still be callable
        harness.eval("var t = hs.timer.doAfter(10, function() {})")
        #expect(!harness.hasException, "Core functions should work after enhancements load")

        // Cleanup
        harness.eval("t.stop()")
    }

    // MARK: - Complex Enhancement Patterns

    @Test("Predicate-based timer with real condition works")
    func testPredicateTimerIntegration() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var completionFired = false
        harness.registerCallback("predicateComplete") {
            completionFired = true
        }

        harness.eval("""
        var count = 0;
        var predicateTimer = hs.timer.waitUntil(
            function() {
                count++;
                return count >= 3;
            },
            () => { __test_callback('predicateComplete') },
            0.02
        );
        """)

        let success = harness.waitFor(timeout: 0.3) { completionFired }
        #expect(success, "Predicate timer should fire when condition met")

        let finalCount = harness.eval("count") as! Int
        #expect(finalCount >= 3, "Predicate should have been checked multiple times")

        // Cleanup
        harness.eval("if (predicateTimer && predicateTimer.running()) predicateTimer.stop()")
    }

    @Test("doWhile stops when predicate becomes false")
    func testDoWhileStopsCorrectly() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var actionCount = 0
        harness.registerCallback("whileAction") {
            actionCount += 1
        }

        harness.eval("""
        var whileCount = 0;
        var whileTimer = hs.timer.doWhile(
            function() {
                whileCount++;
                return whileCount < 5;
            },
            () => { __test_callback('whileAction') },
            0.02
        );
        """)

        // Wait for timer to complete
        let success = harness.waitFor(timeout: 0.3) { actionCount >= 4 }
        #expect(success, "doWhile should execute action while predicate is true")

        // Give it a bit more time to ensure it stopped
        Thread.sleep(forTimeInterval: 0.1)

        // Should have stopped around count 4-5
        #expect(actionCount < 10, "doWhile should have stopped when predicate became false")

        // Cleanup
        harness.eval("if (whileTimer && whileTimer.running()) whileTimer.stop()")
    }

    @Test("Chained enhancement functions work together")
    func testChainedEnhancements() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Use multiple enhancement features together
        harness.eval("""
        var config = {
            checkInterval: 2,
            maxWait: hs.timer.minutes(1),
            delay: 0.5
        };
        """)

        harness.expectEqual("config.checkInterval", 2.0)
        harness.expectEqual("config.maxWait", 60.0)
        harness.expectEqual("config.delay", 0.5)
    }

    // MARK: - Real-World Enhancement Use Cases

    @Test("Polling with timeout pattern")
    func testPollingWithTimeoutPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var completionCalled = false
        var timeoutCalled = false

        harness.registerCallback("onComplete") { completionCalled = true }
        harness.registerCallback("onTimeout") { timeoutCalled = true }

        harness.eval("""
        var attempts = 0;
        var maxAttempts = 3;

        var pollTimer = hs.timer.waitUntil(
            function() {
                attempts++;
                return attempts >= maxAttempts;
            },
            () => { __test_callback('onComplete') },
            0.02
        );

        var timeoutTimer = hs.timer.doAfter(0.5, () => { __test_callback('onTimeout') });
        """)

        // Should complete before timeout
        let success = harness.waitFor(timeout: 0.3) { completionCalled }
        #expect(success, "Polling should complete before timeout")
        #expect(!timeoutCalled, "Timeout should not fire if polling completes")

        // Cleanup
        harness.eval("if (pollTimer && pollTimer.running()) pollTimer.stop()")
        harness.eval("if (timeoutTimer && timeoutTimer.running()) timeoutTimer.stop()")
    }
}
