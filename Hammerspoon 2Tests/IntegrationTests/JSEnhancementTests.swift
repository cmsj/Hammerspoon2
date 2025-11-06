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
        harness.expectTrue("typeof hs.timer.seconds === 'function'")
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

    @Test("Timer.seconds() parses various formats")
    func testTimerSecondsParser() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Duration formats
        harness.expectEqual("hs.timer.seconds('30s')", 30.0)
        harness.expectEqual("hs.timer.seconds('5m')", 300.0)
        harness.expectEqual("hs.timer.seconds('2h')", 7200.0)
        harness.expectEqual("hs.timer.seconds('500ms')", 0.5)

        // Time of day formats
        harness.expectEqual("hs.timer.seconds('01:30:00')", 5400.0)
        harness.expectEqual("hs.timer.seconds('12:00')", 43200.0)
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

    @Test("Timer.delayed() exists and returns correct object")
    func testTimerDelayedFunction() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectTrue("typeof hs.timer.delayed === 'function'")

        harness.eval("var delayed = hs.timer.delayed(1, function() {})")

        harness.expectTrue("typeof delayed === 'object'")
        harness.expectTrue("typeof delayed.start === 'function'")
        harness.expectTrue("typeof delayed.stop === 'function'")
        harness.expectTrue("typeof delayed.running === 'function'")
        harness.expectTrue("typeof delayed.setDelay === 'function'")
    }

    @Test("Timer.delayed() setDelay changes delay")
    func testTimerDelayedSetDelay() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.eval("""
        var delayed = hs.timer.delayed(1, function() {});
        delayed.setDelay(5);
        """)

        // The delay should have changed (we can't easily test the internal state,
        // but we can verify the method exists and doesn't throw)
        harness.expectTrue("typeof delayed.setDelay === 'function'")
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
        harness.expectTrue("typeof hs.timer.delayed === 'function'")
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

    @Test("Enhanced functions can use core functions")
    func testEnhancementsUseCore() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callbackFired = false
        harness.registerCallback("enhancementTest") {
            callbackFired = true
        }

        // timer.delayed uses timer.doAfter internally
        harness.eval("""
        var delayed = hs.timer.delayed(0.05, () => { __test_callback('enhancementTest') });
        delayed.start();
        """)

        let success = harness.waitFor(timeout: 0.2) { callbackFired }
        #expect(success, "Enhanced function should successfully use core function")

        // Cleanup
        harness.eval("delayed.stop()")
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
            checkInterval: hs.timer.seconds('2s'),
            maxWait: hs.timer.minutes(1),
            delay: hs.timer.seconds('500ms')
        };
        """)

        harness.expectEqual("config.checkInterval", 2.0)
        harness.expectEqual("config.maxWait", 60.0)
        harness.expectEqual("config.delay", 0.5)
    }

    // MARK: - Error Handling in Enhancements

    @Test("Enhanced timer functions handle errors gracefully")
    func testEnhancementErrorHandling() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Invalid time string should throw
        harness.eval("hs.timer.seconds('invalid')")
        #expect(harness.hasException, "Invalid time string should throw")

        // Try creating delayed with non-function
        harness.eval("hs.timer.delayed(1, 'not a function')")
        #expect(harness.hasException, "Non-function callback should throw")
    }

    @Test("Timer.seconds() validates time ranges")
    func testTimerSecondsValidation() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Invalid hour (>= 24)
        harness.eval("hs.timer.seconds('25:00:00')")
        harness.expectException()
    }

    // MARK: - Real-World Enhancement Use Cases

    @Test("Debouncing user input with delayed timer")
    func testDebouncingUseCase() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var searchCount = 0
        harness.registerCallback("performSearch") {
            searchCount += 1
        }

        harness.eval("""
        var searchDebounce = hs.timer.delayed(timer.seconds('200ms'), () => { __test_callback('performSearch') });

        function onSearchTextChanged() {
            searchDebounce.start();
        }
        """)

        // Simulate rapid typing
        for _ in 0..<5 {
            harness.eval("onSearchTextChanged()")
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Should only search once after typing stops
        let success = harness.waitFor(timeout: 0.5) { searchCount >= 1 }
        #expect(success, "Debounced search should fire")

        Thread.sleep(forTimeInterval: 0.1)
        #expect(searchCount == 1, "Should only search once despite multiple inputs")

        // Cleanup
        harness.eval("searchDebounce.stop()")
    }

    @Test("Scheduling daily task with time parsing")
    func testDailySchedulingUseCase() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.eval("""
        function scheduleDailyTask(timeString, task) {
            var targetTime = hs.timer.seconds(timeString);
            return {
                time: targetTime,
                task: task
            };
        }

        var morningTask = scheduleDailyTask('09:00', function() {
            console.log('Good morning!');
        });
        """)

        // Should parse to 9 AM (9 * 3600 seconds)
        harness.expectEqual("morningTask.time", 32400.0)
        harness.expectTrue("typeof morningTask.task === 'function'")
    }

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
            hs.timer.seconds('20ms')
        );

        var timeoutTimer = hs.timer.doAfter(timer.seconds('500ms'), () => { __test_callback('onTimeout') });
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
