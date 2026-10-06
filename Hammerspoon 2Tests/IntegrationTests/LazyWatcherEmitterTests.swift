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

    @Test("a start() returning false makes on() log and throw, records nothing, and allows a retry")
    func testStartReturningFalseThrows() {
        let harness = makeHarness()
        harness.eval("""
            // The failure is logged as well as thrown, so it's still seen when on() is called
            // from a promise callback, where the throw would become an unhandled rejection.
            var logged = [];
            console.error = function(msg) { logged.push(msg); };
            var startCalls = 0;
            var shouldFail = true;
            var e = new LazyWatcherEmitter("hs.test", function() {
                startCalls++;
                return !shouldFail;
            }, function() {});

            var fn = function() {};
            var message = null;
            try {
                e.on('x', fn);
            } catch (err) {
                message = err.message;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("message") == "hs.test.on(): failed to start watcher for 'x'")
        #expect(harness.evalString("logged.join('|')") == "hs.test.on(): failed to start watcher for 'x'")
        harness.expectFalse("e.events['x'] && e.events['x'].includes(fn)")

        harness.eval("""
            shouldFail = false;
            e.on('x', fn);
        """)
        #expect(!harness.hasException)
        #expect(harness.evalInt("startCalls") == 2)
        harness.expectTrue("e.events['x'].includes(fn)")
    }

    @Test("a start() returning false makes once() throw too, naming once() in the error")
    func testStartReturningFalseThrowsFromOnce() {
        let harness = makeHarness()
        harness.eval("""
            var e = new LazyWatcherEmitter("hs.test", function() { return false; }, function() {});
            var message = null;
            try {
                e.once('x', function() {});
            } catch (err) {
                message = err.message;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("message") == "hs.test.once(): failed to start watcher for 'x'")
        harness.expectFalse("e.events['x'] && e.events['x'].length > 0")
    }

    @Test("once() errors name once() and the emitter's label", arguments: ["LazyWatcherEmitter", "KeyedLazyWatcherEmitter"])
    func testOnceErrorsNameOnce(emitterClass: String) {
        let harness = makeHarness()
        harness.eval("""
            var e = new \(emitterClass)("hs.test", function() {}, function() {}, ['x']);
            var badListener = null, unknownEvent = null;
            try { e.once('x', 42); } catch (err) { badListener = err.message; }
            try { e.once('y', function() {}); } catch (err) { unknownEvent = err.message; }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("badListener") == "hs.test.once(): listener must be a function")
        #expect(harness.evalString("unknownEvent") == "hs.test.once(): unknown event 'y'. Known events: x")
    }

    @Test("a keyed start() returning false makes on() throw, records nothing, and allows a retry")
    func testKeyedStartReturningFalseThrows() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0;
            var shouldFail = true;
            var e = new KeyedLazyWatcherEmitter("hs.test", function(event) {
                startCalls++;
                return !shouldFail;
            }, function(event) {});

            var fn = function() {};
            var message = null;
            try {
                e.on('x', fn);
            } catch (err) {
                message = err.message;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("message") == "hs.test.on(): failed to start watcher for 'x'")
        harness.expectFalse("e.events['x'] && e.events['x'].includes(fn)")

        harness.eval("""
            shouldFail = false;
            e.on('x', fn);
        """)
        #expect(!harness.hasException)
        #expect(harness.evalInt("startCalls") == 2)
        harness.expectTrue("e.events['x'].includes(fn)")
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

    // MARK: - knownEvents (#253)

    @Test("an unknown event name throws before start() is called or anything is recorded")
    func testUnknownEventRejected() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0;
            var e = new LazyWatcherEmitter("test", function() { startCalls++; }, function() {}, ['alpha', 'beta']);
            var message = null;
            try {
                e.on('alpah', function() {});
            } catch (err) {
                message = err.message;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("message") == "test.on(): unknown event 'alpah'. Known events: alpha, beta")
        #expect(harness.evalInt("startCalls") == 0)
        #expect(harness.evalInt("e._listenerCount") == 0)
        harness.expectFalse("'alpah' in e.events")
    }

    @Test("a known event name is accepted and starts the watcher")
    func testKnownEventAccepted() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0, received = null;
            var e = new LazyWatcherEmitter("test", function() { startCalls++; }, function() {}, ['alpha', 'beta']);
            e.on('beta', function(value) { received = value; });
            e.emit('beta', 'hello');
        """)
        #expect(!harness.hasException)
        #expect(harness.evalInt("startCalls") == 1)
        #expect(harness.evalString("received") == "hello")
    }

    @Test("once() is validated too, since it routes through on()")
    func testOnceUnknownEventRejected() {
        let harness = makeHarness()
        harness.eval("""
            var startCalls = 0, threw = false;
            var e = new LazyWatcherEmitter("test", function() { startCalls++; }, function() {}, ['alpha']);
            try {
                e.once('beta', function() {});
            } catch (err) {
                threw = true;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalBool("threw") == true)
        #expect(harness.evalInt("startCalls") == 0)
    }

    @Test("an inherited Object.prototype name is not mistaken for a known event")
    func testPrototypeNameIsNotKnownEvent() {
        let harness = makeHarness()
        harness.eval("""
            var threw = false;
            var e = new LazyWatcherEmitter("test", function() {}, function() {}, ['alpha']);
            try {
                e.on('toString', function() {});
            } catch (err) {
                threw = true;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalBool("threw") == true)
    }

    @Test("an emitter with no knownEvents list accepts any event name")
    func testNoKnownEventsAcceptsAnything() {
        let harness = makeHarness()
        harness.eval("""
            var e = new LazyWatcherEmitter("test", function() {}, function() {});
            e.on('anything at all', function() {});
            var k = new KeyedLazyWatcherEmitter("test", function() { return true; }, function() {});
            k.on('also anything', function() {});
        """)
        #expect(!harness.hasException)
        #expect(harness.evalInt("e._listenerCount") == 1)
        harness.expectTrue("Array.isArray(k.events['also anything'])")
    }

    @Test("KeyedLazyWatcherEmitter rejects an unknown event name before calling start()")
    func testKeyedUnknownEventRejected() {
        let harness = makeHarness()
        harness.eval("""
            var started = [];
            var e = new KeyedLazyWatcherEmitter("test", function(event) { started.push(event); return true; }, function() {}, ['alpha']);
            var message = null;
            try {
                e.on('beta', function() {});
            } catch (err) {
                message = err.message;
            }
            e.on('alpha', function() {});
        """)
        #expect(!harness.hasException)
        #expect(harness.evalString("message") == "test.on(): unknown event 'beta'. Known events: alpha")
        #expect(harness.evalString("started.join(',')") == "alpha")
    }
}
