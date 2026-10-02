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

    @Test("an event name of '__proto__' does not collide with Object.prototype")
    func testProtoEventNameDoesNotCollideWithObjectPrototype() {
        let harness = makeHarness()
        harness.eval("""
            var startedEvents = [], stoppedEvents = [];
            var e = new KeyedLazyWatcherEmitter("test", function(event) {
                startedEvents.push(event);
            }, function(event) {
                stoppedEvents.push(event);
            });

            var fn = function() {};
            var onThrew = false;
            try {
                e.on('__proto__', fn);
            } catch (err) {
                onThrew = true;
            }
        """)
        #expect(!harness.hasException)
        harness.expectFalse("onThrew")
        // The native watcher must actually have been started for this key, not silently skipped.
        harness.expectTrue("startedEvents.includes('__proto__')")
        // And the listener must be findable again afterwards, not swallowed into Object.prototype.
        harness.expectTrue("Array.isArray(e.events['__proto__'])")
        harness.expectTrue("e.events['__proto__'].includes(fn)")

        harness.eval("""
            e.off('__proto__', fn);
        """)
        #expect(!harness.hasException)
        // off() must have found the listener and actually called stop() for this key.
        harness.expectTrue("stoppedEvents.includes('__proto__')")
    }

    @Test("once() rejects a non-function listener instead of registering it")
    func testOnceRejectsNonFunctionListener() {
        let harness = makeHarness()
        harness.eval("""
            var e = new EventEmitter();
            var threw = false;
            try {
                e.once('x', 42);
            } catch (err) {
                threw = true;
            }
        """)
        #expect(!harness.hasException)
        harness.expectTrue("threw")
        // Nothing should have been recorded for the rejected listener.
        harness.expectFalse("e.events['x'] && e.events['x'].length > 0")
    }

    @Test("a rejected once() listener does not block delivery to other listeners")
    func testRejectedOnceListenerDoesNotBlockOtherListeners() {
        // Regression test for a code review comment: once() used to only validate the function it
        // wraps `listener` in (always callable), never `listener` itself, so an invalid listener
        // would register successfully and only throw once emit() invoked it - aborting delivery to
        // every other listener still queued in that same emit() call. Exercised on LazyWatcherEmitter
        // (not just the base EventEmitter) since that's the class every hs.foo module-level watcher
        // actually uses, and it inherits once() unchanged.
        let harness = makeHarness()
        harness.eval("""
            var received = null;
            var e = new LazyWatcherEmitter("test", function() {}, function() {});
            e.on('x', function(value) { received = value; });

            var threw = false;
            try {
                e.once('x', 'not a function');
            } catch (err) {
                threw = true;
            }

            e.emit('x', 'hello');
        """)
        #expect(!harness.hasException)
        harness.expectTrue("threw")
        // The valid listener registered via on() must still have received the event.
        harness.expectEqual("received", "hello")
    }
}
