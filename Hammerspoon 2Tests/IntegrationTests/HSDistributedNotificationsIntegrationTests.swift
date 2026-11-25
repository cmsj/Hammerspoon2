//
//  HSDistributedNotificationsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import Foundation
@testable import Hammerspoon_2

@Suite("hs.distributednotifications tests")
struct HSDistributedNotificationsTests {

    // MARK: - Suite 1: API Structure

    @Suite("hs.distributednotifications API structure tests")
    struct HSDistributedNotificationsStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSDistributedNotificationsModule.self, as: "distributednotifications")
            return harness
        }

        @Test("post, on, off and once are functions")
        func testFunctions() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.distributednotifications.post") == "function")
            #expect(harness.evalTypeOf("hs.distributednotifications.on") == "function")
            #expect(harness.evalTypeOf("hs.distributednotifications.off") == "function")
            #expect(harness.evalTypeOf("hs.distributednotifications.once") == "function")
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSDistributedNotificationsModule.self, as: "distributednotifications")

            harness.collectGarbage()

            #expect(harness.evalTypeOf("hs.distributednotifications.on") == "function")
            #expect(harness.evalTypeOf("hs.distributednotifications.off") == "function")
            #expect(harness.evalTypeOf("hs.distributednotifications.once") == "function")

            harness.eval("""
                var fn = function() {};
                hs.distributednotifications.on('org.hammerspoon.test.gc', fn);
                hs.distributednotifications.off('org.hammerspoon.test.gc', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("_watcherEmitter is initialized by hs.distributednotifications.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.distributednotifications._watcherEmitter !== null && hs.distributednotifications._watcherEmitter !== undefined"
            )
        }
    }

    // MARK: - Suite 2: Posting

    @Suite("hs.distributednotifications post tests")
    struct HSDistributedNotificationsPostTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSDistributedNotificationsModule.self, as: "distributednotifications")
            return harness
        }

        @Test("post() with only a name returns true")
        func testPostNameOnly() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.distributednotifications.post('org.hammerspoon.test.postOnly')") == true)
            #expect(!harness.hasException)
        }

        @Test("post() with an empty name returns false")
        func testPostEmptyName() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.distributednotifications.post('')") == false)
            #expect(!harness.hasException)
        }

        @Test("post() with userInfo that can't be sent returns false")
        func testPostInvalidUserInfo() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.distributednotifications.post('org.hammerspoon.test.bad', null, { v: null })") == false)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: Watchers

    // Distributed notifications reach the main thread through the main dispatch queue, which can't
    // run while a synchronous test spins the run loop, so tests that wait for one are async.
    @Suite("hs.distributednotifications watcher tests", .serialized)
    struct HSDistributedNotificationsWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSDistributedNotificationsModule.self, as: "distributednotifications")
            return harness
        }

        /// A notification name no other test (or process) uses
        private func uniqueName() -> String {
            "org.hammerspoon.test.\(UUID().uuidString)"
        }

        @Test("_addWatcher reports success, then refuses a second subscription by returning false")
        func testAddWatcherReportsRefusal() {
            let harness = makeHarness()
            let name = uniqueName()
            harness.eval("""
            var first = hs.distributednotifications._addWatcher('\(name)', function() {});
            var second = hs.distributednotifications._addWatcher('\(name)', function() {});
            hs.distributednotifications._removeWatcher('\(name)');
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("first") == true)
            #expect(harness.evalBool("second") == false)
        }

        @Test("on() with an empty name throws and records nothing")
        func testOnEmptyNameThrows() {
            let harness = makeHarness()
            harness.eval("""
            var threw = false;
            try {
                hs.distributednotifications.on('', function() {});
            } catch (err) {
                threw = true;
            }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            harness.expectFalse("Array.isArray(hs.distributednotifications._watcherEmitter.events[''])")
        }

        @Test("listener receives the object and userInfo of a posted notification")
        func testListenerReceivesNotification() async {
            let harness = makeHarness()
            let name = uniqueName()
            harness.eval("""
            var received = null;
            hs.distributednotifications.on('\(name)', (object, userInfo) => {
                received = { object: object, userInfo: userInfo };
            });
            hs.distributednotifications.post('\(name)', 'hammerspoon-test', { state: 'Playing', count: 3, nested: [1, 2] });
            """)
            #expect(!harness.hasException)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalBool("received !== null") == true })
            #expect(harness.evalString("received.object") == "hammerspoon-test")
            #expect(harness.evalString("received.userInfo.state") == "Playing")
            #expect(harness.evalInt("received.userInfo.count") == 3)
            #expect(harness.evalString("JSON.stringify(received.userInfo.nested)") == "[1,2]")
        }

        @Test("a notification with no object or userInfo gives null and an empty object")
        func testListenerReceivesNullObjectAndEmptyUserInfo() async {
            let harness = makeHarness()
            let name = uniqueName()
            harness.eval("""
            var received = null;
            hs.distributednotifications.on('\(name)', (object, userInfo) => {
                received = { object: object, userInfo: userInfo };
            });
            hs.distributednotifications.post('\(name)');
            """)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalBool("received !== null") == true })
            harness.expectTrue("received.object === null")
            #expect(harness.evalString("JSON.stringify(received.userInfo)") == "{}")
            #expect(!harness.hasException)
        }

        @Test("off() stops further callbacks")
        func testOffStopsCallbacks() async {
            let harness = makeHarness()
            let name = uniqueName()
            let marker = uniqueName()
            harness.eval("""
            var count = 0;
            var markerSeen = false;
            function handler() { count++; }
            hs.distributednotifications.on('\(name)', handler);
            hs.distributednotifications.on('\(marker)', () => { markerSeen = true; });
            hs.distributednotifications.post('\(name)');
            """)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalInt("count") == 1 })
            // Notifications are delivered in order, so once the marker arrives, any further
            // posting of `name` would have been delivered too
            harness.eval("""
            hs.distributednotifications.off('\(name)', handler);
            hs.distributednotifications.post('\(name)');
            hs.distributednotifications.post('\(marker)');
            """)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalBool("markerSeen") == true })
            #expect(harness.evalInt("count") == 1)
            #expect(!harness.hasException)
        }

        @Test("once() fires a single time")
        func testOnceFiresOnce() async {
            let harness = makeHarness()
            let name = uniqueName()
            let marker = uniqueName()
            harness.eval("""
            var count = 0;
            var markerSeen = false;
            hs.distributednotifications.once('\(name)', () => { count++; });
            hs.distributednotifications.on('\(marker)', () => { markerSeen = true; });
            hs.distributednotifications.post('\(name)');
            hs.distributednotifications.post('\(name)');
            hs.distributednotifications.post('\(marker)');
            """)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalBool("markerSeen") == true })
            #expect(harness.evalInt("count") == 1)
            #expect(!harness.hasException)
        }

        @Test("listeners for different names fire independently")
        func testDifferentNamesIndependent() async {
            let harness = makeHarness()
            let nameA = uniqueName()
            let nameB = uniqueName()
            harness.eval("""
            var seenA = 0, seenB = 0;
            hs.distributednotifications.on('\(nameA)', () => { seenA++; });
            hs.distributednotifications.on('\(nameB)', () => { seenB++; });
            hs.distributednotifications.post('\(nameB)');
            """)
            #expect(await harness.waitForAsync(timeout: 2.0) { harness.evalInt("seenB") == 1 })
            #expect(harness.evalInt("seenA") == 0)
            #expect(!harness.hasException)
        }

        @Test("listeners keep firing after garbage collection")
        func testListenerSurvivesGC() async {
            let harness = makeHarness()
            let name = uniqueName()
            var fired = false
            harness.registerCallback("onNotification") { fired = true }
            autoreleasepool {
                _ = harness.eval("void hs.distributednotifications.on('\(name)', function() { __test_callback('onNotification'); })")
            }
            harness.collectGarbage()
            harness.eval("hs.distributednotifications.post('\(name)')")
            #expect(await harness.waitForAsync(timeout: 2.0) { fired })
        }

        @Test("shutdown() stops delivering notifications")
        func testShutdownStopsDelivery() async {
            let (harness, module) = JSTestHarness.makeUnpinned(HSDistributedNotificationsModule.self, as: "distributednotifications")
            let name = uniqueName()
            var fired = false
            var markerSeen = false
            harness.registerCallback("onNotification") { fired = true }
            // Observed natively, so it still arrives after the module has shut down. Delivery is
            // in order, so once it arrives, the posting before it would have been delivered too.
            let marker = DistributedNotificationObserver(name: Notification.Name(name + ".marker")) {
                markerSeen = true
            }
            harness.eval("hs.distributednotifications.on('\(name)', function() { __test_callback('onNotification'); })")
            module.shutdown()
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(name + ".marker"), object: nil, userInfo: nil, deliverImmediately: true)
            #expect(await harness.waitForAsync(timeout: 2.0) { markerSeen })
            #expect(!fired)
            withExtendedLifetime(marker) {}
        }
    }
}
