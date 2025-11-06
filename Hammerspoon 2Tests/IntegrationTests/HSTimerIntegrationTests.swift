//
//  HSTimerIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.timer module
///
/// These tests verify async timer behavior, callback execution, and JavaScript enhancements.
/// Timer tests are inherently time-dependent, so we use short delays to keep tests fast.
struct HSTimerIntegrationTests {

    // MARK: - Basic Timer Creation Tests

    @Test("doAfter creates and fires a one-shot timer")
    func testDoAfterFromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callbackFired = false
        harness.registerCallback("testCallback") {
            callbackFired = true
        }

        harness.eval("hs.timer.doAfter(0.05, () => { __test_callback('testCallback') })")

        // Wait for timer to fire
        let success = harness.waitFor(timeout: 0.2) { callbackFired }
        #expect(success, "hs.timer should have fired within timeout")
        #expect(callbackFired, "Callback should have been called")
    }

    @Test("doEvery creates and fires a repeating timer")
    func testDoEveryFromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callCount = 0
        harness.registerCallback("repeatCallback") {
            callCount += 1
        }

        harness.eval("""
        var repeatTimer = hs.timer.doEvery(0.05, () => { __test_callback('repeatCallback') });
        """)

        // Wait for multiple fires
        let success = harness.waitFor(timeout: 0.3) { callCount >= 3 }
        #expect(success, "hs.timer should have fired at least 3 times")
        #expect(callCount >= 3, "Callback should have been called multiple times")

        // Stop the timer
        harness.eval("repeatTimer.stop()")
    }

    @Test("hs.timer can be stopped")
    func testTimerStop() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callCount = 0
        harness.registerCallback("stoppableCallback") {
            callCount += 1
        }

        harness.eval("""
        var stoppableTimer = timer.doEvery(0.05, () => { __test_callback('stoppableCallback') });
        """)

        // Let it fire once or twice
        Thread.sleep(forTimeInterval: 0.1)

        // Stop the timer
        harness.eval("stoppableTimer.stop()")
        let countAfterStop = callCount

        // Wait a bit more - count should not increase
        Thread.sleep(forTimeInterval: 0.15)

        #expect(callCount == countAfterStop, "hs.timer should not fire after being stopped")
    }

    @Test("new() creates timer that requires manual start")
    func testNewTimer() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callbackFired = false
        harness.registerCallback("manualCallback") {
            callbackFired = true
        }

        harness.eval("""
        var manualTimer = timer.new(0.05, () => { __test_callback('manualCallback') }, false);
        """)

        // Should not fire yet
        Thread.sleep(forTimeInterval: 0.1)
        #expect(!callbackFired, "hs.timer should not fire before start() is called")

        // Now start it
        harness.eval("manualTimer.start()")

        let success = harness.waitFor(timeout: 0.2) { callbackFired }
        #expect(success, "hs.timer should fire after start() is called")
    }

    // MARK: - Timer Object Tests

    @Test("hs.timer object has expected methods")
    func testTimerObjectAPI() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.eval("var t = hs.timer.doAfter(10, function() {})")

        harness.expectTrue("typeof t.start === 'function'")
        harness.expectTrue("typeof t.stop === 'function'")
        harness.expectTrue("typeof t.running === 'function'")
    }

    @Test("running() returns correct state")
    func testTimerRunningState() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.eval("""
        var stateTimer = hs.timer.doAfter(10, function() {});
        """)

        harness.expectTrue("stateTimer.running() === true")

        harness.eval("stateTimer.stop()")
        harness.expectTrue("stateTimer.running() === false")

        harness.eval("stateTimer.start()")
        harness.expectTrue("stateTimer.running() === true")

        // Cleanup
        harness.eval("stateTimer.stop()")
    }

    // MARK: - Utility Function Tests

    @Test("secondsSinceEpoch returns reasonable value")
    func testSecondsSinceEpoch() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        let result = harness.eval("hs.timer.secondsSinceEpoch()")
        #expect(result is Double, "secondsSinceEpoch should return a number")

        let seconds = result as? Double ?? -1
        // Should be somewhere around 2025 (roughly 1.7+ billion seconds since epoch)
        #expect(seconds > 1700000000, "secondsSinceEpoch should return Unix timestamp")
    }

    @Test("absoluteTime returns monotonic time")
    func testAbsoluteTime() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        let time1 = harness.eval("hs.timer.absoluteTime()") as? Double ?? -1
        Thread.sleep(forTimeInterval: 0.01)
        let time2 = harness.eval("hs.timer.absoluteTime()") as? Double ?? -1

        #expect(time2 > time1, "absoluteTime should increase monotonically")
    }

    @Test("localTime returns seconds since midnight")
    func testLocalTime() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        let result = harness.eval("hs.timer.localTime()")
        #expect(result is Double, "localTime should return a number")

        let seconds = result as? Double ?? -1
        #expect(seconds >= 0, "localTime should be non-negative")
        #expect(seconds < 86400, "localTime should be less than 86400 (24 hours)")
    }

    // MARK: - JavaScript Enhancement Tests

    @Test("hs.timer.minutes() converts correctly")
    func testMinutesConversion() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectEqual("hs.timer.minutes(1)", 60.0)
        harness.expectEqual("hs.timer.minutes(5)", 300.0)
    }

    @Test("hs.timer.hours() converts correctly")
    func testHoursConversion() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectEqual("hs.timer.hours(1)", 3600.0)
        harness.expectEqual("hs.timer.hours(2)", 7200.0)
    }

    @Test("hs.timer.days() converts correctly")
    func testDaysConversion() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectEqual("hs.timer.days(1)", 86400.0)
        harness.expectEqual("hs.timer.days(7)", 604800.0)
    }

    @Test("hs.timer.weeks() converts correctly")
    func testWeeksConversion() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.expectEqual("hs.timer.weeks(1)", 604800.0)
        harness.expectEqual("hs.timer.weeks(2)", 1209600.0)
    }

    @Test("hs.timer.seconds() parses time strings")
    func testSecondsParser() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // HH:MM:SS format
        harness.expectEqual("hs.timer.seconds('01:30:45')", 5445.0)
        harness.expectEqual("hs.timer.seconds('12:00:00')", 43200.0)

        // HH:MM format
        harness.expectEqual("hs.timer.seconds('01:30')", 5400.0)

        // Duration format
        harness.expectEqual("hs.timer.seconds('30s')", 30.0)
        harness.expectEqual("hs.timer.seconds('5m')", 300.0)
        harness.expectEqual("hs.timer.seconds('2h')", 7200.0)
        harness.expectEqual("hs.timer.seconds('1d')", 86400.0)
        harness.expectEqual("hs.timer.seconds('500ms')", 0.5)
    }

    @Test("hs.timer.seconds() throws on invalid input")
    func testSecondsParserErrors() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        // Invalid time format
        harness.eval("hs.timer.seconds('not-a-time')")
        harness.expectException()
    }

    @Test("hs.timer.waitUntil() fires when predicate becomes true")
    func testWaitUntil() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var actionFired = false
        harness.registerCallback("waitUntilAction") {
            actionFired = true
        }

        harness.eval("""
        var counter = 0;
        var waitTimer = timer.waitUntil(
            function() { return counter >= 3; },
            () => { __test_callback('waitUntilAction') },
            0.02
        );
        """)

        // Increment counter after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = harness.eval("counter = 3")
        }

        let success = harness.waitFor(timeout: 0.3) { actionFired }
        #expect(success, "waitUntil should fire when predicate becomes true")

        // Cleanup
        harness.eval("if (waitTimer && waitTimer.running()) waitTimer.stop()")
    }

    @Test("hs.timer.doUntil() runs action and stops when predicate is true")
    func testDoUntil() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var actionCount = 0
        harness.registerCallback("doUntilAction") {
            actionCount += 1
        }

        harness.eval("""
        var doUntilCounter = 0;
        var doUntilTimer = timer.doUntil(
            function() { return doUntilCounter >= 3; },
            function() {
                __test_callback('doUntilAction');
                doUntilCounter++;
            },
            0.02
        );
        """)

        let success = harness.waitFor(timeout: 0.3) { actionCount >= 3 }
        #expect(success, "doUntil should execute action multiple times")
        #expect(actionCount >= 3, "Action should have been called at least 3 times")

        // Cleanup
        harness.eval("if (doUntilTimer && doUntilTimer.running()) doUntilTimer.stop()")
    }

    @Test("hs.timer.delayed() creates debounced timer")
    func testDelayedTimer() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var callbackCount = 0
        harness.registerCallback("delayedCallback") {
            callbackCount += 1
        }

        harness.eval("""
        var delayed = timer.delayed(0.1, () => { __test_callback('delayedCallback') });
        """)

        // Start and restart multiple times (should only fire once)
        harness.eval("delayed.start()")
        Thread.sleep(forTimeInterval: 0.03)
        harness.eval("delayed.start()") // Reset the timer
        Thread.sleep(forTimeInterval: 0.03)
        harness.eval("delayed.start()") // Reset again

        // Now wait for it to fire
        let success = harness.waitFor(timeout: 0.3) { callbackCount >= 1 }
        #expect(success, "Delayed timer should eventually fire")

        // Should only have fired once despite multiple start() calls
        Thread.sleep(forTimeInterval: 0.05)
        #expect(callbackCount == 1, "Delayed timer should only fire once after final start()")
    }

    @Test("hs.timer.delayed() object has expected API")
    func testDelayedTimerAPI() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        harness.eval("var delayed = hs.timer.delayed(1, function() {})")

        harness.expectEqual("typeof delayed.start", "function")
        harness.expectTrue("typeof delayed.start === 'function'")
        harness.expectTrue("typeof delayed.stop === 'function'")
        harness.expectTrue("typeof delayed.running === 'function'")
        harness.expectTrue("typeof delayed.setDelay === 'function'")
    }

    // MARK: - Real-World Use Cases

    @Test("Debounce pattern works correctly")
    func testDebouncePattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var saveCount = 0
        harness.registerCallback("saveDocument") {
            saveCount += 1
        }

        harness.eval("""
        var saveDebounce = timer.delayed(0.1, __test_callback('saveDocument'));

        function onTextChanged() {
            saveDebounce.start();
        }
        """)

        // Simulate rapid typing
        for _ in 0..<10 {
            harness.eval("onTextChanged()")
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Should only save once after typing stops
        let success = harness.waitFor(timeout: 0.3) { saveCount >= 1 }
        #expect(success, "Debounced save should fire")

        Thread.sleep(forTimeInterval: 0.05)
        #expect(saveCount == 1, "Should only save once despite multiple changes")
    }

    @Test("Polling pattern with waitUntil works")
    func testPollingPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var completionFired = false
        harness.registerCallback("onComplete") {
            completionFired = true
        }

        harness.eval("""
        var attempts = 0;
        var maxAttempts = 5;

        var pollTimer = timer.waitUntil(
            function() {
                attempts++;
                return attempts >= maxAttempts;
            },
            () => { __test_callback('onComplete') },
            0.02
        );
        """)

        let success = harness.waitFor(timeout: 0.3) { completionFired }
        #expect(success, "Polling should complete")

        let attempts = harness.eval("attempts") as? Int ?? -1
        #expect(attempts >= 5, "Should have polled multiple times")

        // Cleanup
        harness.eval("if (pollTimer && pollTimer.running()) pollTimer.stop()")
    }

    @Test("Timeout pattern works")
    func testTimeoutPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")

        var timeoutFired = false
        harness.registerCallback("onTimeout") {
            timeoutFired = true
        }

        harness.eval("""
        function performActionWithTimeout(action, timeoutSeconds) {
            var completed = false;
            var timeoutTimer = timer.doAfter(timeoutSeconds, function() {
                if (!completed) {
                    __test_callback('onTimeout');
                }
            });

            // Simulate async action
            return {
                complete: function() {
                    completed = true;
                    timeoutTimer.stop();
                }
            };
        }

        var operation = performActionWithTimeout(function() {}, 0.05);
        // Don't call operation.complete() - let it timeout
        """)

        let success = harness.waitFor(timeout: 0.2) { timeoutFired }
        #expect(success, "Timeout should fire when operation doesn't complete")
    }
}
