//
//  LazyWatcherEmitterTests.swift
//  Hammerspoon 2Tests
//
//  Direct tests of the shared LazyWatcherEmitter/KeyedLazyWatcherEmitter classes in
//  Engine/engine.js, independent of any specific hs.foo module or real hardware.
//

import Testing
@testable import Hammerspoon_2

@Suite("LazyWatcherEmitter tests")
struct LazyWatcherEmitterTests {

    private func makeHarness() -> JSTestHarness {
        JSTestHarness()
    }

    @Test("a failed start() does not block a later retry")
    func testFailedStartDoesNotBlockRetry() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0;
            var shouldFail = true;
            var e = new LazyWatcherEmitter("test", function() {
                startCalls++;
                if (shouldFail) { throw new Error("boom"); }
            }, function() {});

            var fn1 = function() {};
            var threw = false;
            try {
                e.on('x', fn1);
            } catch (err) {
                threw = true;
            }
        """)
        harness.expectTrue("threw")
        harness.expectEqual("startCalls", 1)
        // The failed attempt must not have recorded the listener - a bare re-registration of
        // the SAME listener (not a duplicate-rejection) proves nothing was left behind.
        harness.expectFalse("e.events['x'] && e.events['x'].includes(fn1)")

        harness.eval("""
            shouldFail = false;
            var fn2 = function() {};
            e.on('x', fn2);
        """)
        // The retry must have actually called start() again, not silently skipped it.
        harness.expectEqual("startCalls", 2)
        harness.expectTrue("e.events['x'].includes(fn2)")
        #expect(!harness.hasException)
    }

    @Test("a successful start() is only called once across multiple listeners")
    func testSuccessfulStartCalledOnce() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0, stopCalls = 0;
            var e = new LazyWatcherEmitter("test", function() { startCalls++; }, function() { stopCalls++; });

            var fn1 = function() {};
            var fn2 = function() {};
            e.on('x', fn1);
            e.on('y', fn2);
        """)
        harness.expectEqual("startCalls", 1)
        harness.expectEqual("stopCalls", 0)

        harness.eval("""
            e.off('x', fn1);
        """)
        harness.expectEqual("stopCalls", 0)

        harness.eval("""
            e.off('y', fn2);
        """)
        harness.expectEqual("stopCalls", 1)
        #expect(!harness.hasException)
    }
}
