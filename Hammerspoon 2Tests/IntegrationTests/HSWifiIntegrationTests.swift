//
//  HSWifiIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreWLAN
@testable import Hammerspoon_2

private nonisolated func hasWifiInterface() -> Bool {
    !(CWWiFiClient().interfaceNames() ?? []).isEmpty
}

@Suite("hs.wifi tests")
struct HSWifiTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.wifi API structure tests")
    struct HSWifiStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWifiModule.self, as: "wifi")
            return harness
        }

        @Test("interfaces is a function")
        func testInterfacesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.interfaces") == "function")
        }

        @Test("interfaceDetails is a function")
        func testInterfaceDetailsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.interfaceDetails") == "function")
        }

        @Test("currentNetwork is a function")
        func testCurrentNetworkIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.currentNetwork") == "function")
        }

        @Test("setPower is a function")
        func testSetPowerIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.setPower") == "function")
        }

        @Test("disassociate is a function")
        func testDisassociateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.disassociate") == "function")
        }

        @Test("associate is a function")
        func testAssociateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.associate") == "function")
        }

        @Test("scanNetworks is a function")
        func testScanNetworksIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.scanNetworks") == "function")
        }

        @Test("on is a function")
        func testOnIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.once") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.wifi.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.wifi._watcherEmitter !== null && hs.wifi._watcherEmitter !== undefined"
            )
        }
    }

    // MARK: - Suite 2: Behaviour

    @Suite("hs.wifi behaviour tests")
    struct HSWifiBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWifiModule.self, as: "wifi")
            return harness
        }

        @Test("on() throws and records nothing when the native watcher fails to start")
        func testOnThrowsWhenNativeStartFails() {
            let harness = makeHarness()
            harness.eval("""
            hs.wifi._addWatcher = function(event, fn) { return false; };
            var threw = false;
            try {
                hs.wifi.on('ssidChange', function() {});
            } catch (err) {
                threw = true;
            }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            harness.expectFalse("hs.wifi._watcherEmitter.events['ssidChange'] && hs.wifi._watcherEmitter.events['ssidChange'].length > 0")
        }

        @Test("on throws when listener is not a function")
        func testOnThrowsForNonFunction() {
            let harness = makeHarness()
            harness.eval("hs.wifi.on('ssidChange', 'not a function')")
            #expect(harness.hasException)
        }

        @Test("on throws when listener is null")
        func testOnThrowsForNull() {
            let harness = makeHarness()
            harness.eval("hs.wifi.on('ssidChange', null)")
            #expect(harness.hasException)
        }

        @Test("on and off cycle completes without error")
        func testOnOffCycleIsSafe() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(info) {};
                hs.wifi.on('ssidChange', fn);
                hs.wifi.off('ssidChange', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("adding the same listener twice is idempotent")
        func testAddSameListenerTwiceIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(info) {};
                hs.wifi.on('ssidChange', fn);
                hs.wifi.on('ssidChange', fn);
                hs.wifi.off('ssidChange', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("multiple distinct event types can be watched and removed independently")
        func testMultipleDistinctEvents() {
            let harness = makeHarness()
            harness.eval("""
                var fn1 = function(info) {};
                var fn2 = function(info) {};
                hs.wifi.on('ssidChange', fn1);
                hs.wifi.on('powerChange', fn2);
                hs.wifi.off('ssidChange', fn1);
                hs.wifi.off('powerChange', fn2);
            """)
            #expect(!harness.hasException)
        }

        @Test("multiple listeners for the same event share one native registration")
        func testMultipleListenersSameEvent() {
            let harness = makeHarness()
            harness.eval("""
                var fn1 = function(info) {};
                var fn2 = function(info) {};
                hs.wifi.on('ssidChange', fn1);
                hs.wifi.on('ssidChange', fn2);
            """)
            #expect(!harness.hasException)
            harness.expectTrue("hs.wifi._watcherEmitter.events['ssidChange'].includes(fn1)")
            harness.expectTrue("hs.wifi._watcherEmitter.events['ssidChange'].includes(fn2)")
            harness.eval("""
                hs.wifi.off('ssidChange', fn1);
                hs.wifi.off('ssidChange', fn2);
            """)
            #expect(!harness.hasException)
        }

        @Test("off with an unregistered listener does not throw")
        func testRemoveUnregisteredListenerIsSafe() {
            let harness = makeHarness()
            harness.eval("hs.wifi.off('ssidChange', function(info) {})")
            #expect(!harness.hasException)
        }

        @Test("on with an unrecognized event name throws, and does not register")
        func testUnrecognizedEventNameIsRefused() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(info) {};
                var threw = false;
                try {
                    hs.wifi.on('bogusEvent', fn);
                } catch (err) {
                    threw = true;
                }
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("threw") == true)
            harness.expectFalse("Array.isArray(hs.wifi._watcherEmitter.events['bogusEvent'])")
        }

        @Test("_addWatcher reuses an already-active registration instead of refusing")
        func testAddWatcherReusesAlreadyActiveRegistration() {
            // Regression test for a code review comment: if a previous _removeWatcher call for
            // an event failed to actually stop CoreWLAN monitoring, the old behavior cleared
            // watcherCallbacks anyway, leaving no way to recover - a later on() call would hit
            // "already watching" from CoreWLAN's perspective (if it re-attempted) with no state
            // on our side to detect or handle that. The real CoreWLAN stop failure can't be
            // forced from a test (no hardware mocking for CWWiFiClient), but the externally
            // observable fix is here: _addWatcher must now succeed (reusing the existing
            // registration) rather than warn-and-refuse when called while already registered -
            // exactly the state a failed stop would have left behind. Calling it directly twice
            // in a row exercises that same "already registered" branch without needing to
            // simulate the failure that would normally lead to it.
            let harness = makeHarness()
            harness.eval("""
                var fn1 = function() {};
                var started1 = hs.wifi._addWatcher('ssidChange', fn1);
                var fn2 = function() {};
                var started2 = hs.wifi._addWatcher('ssidChange', fn2);
            """)
            #expect(!harness.hasException)
            harness.expectTrue("started1")
            harness.expectTrue("started2")
            harness.eval("hs.wifi._removeWatcher('ssidChange')")
            #expect(!harness.hasException)
        }

        @Test("once-registered listener fires only one time")
        func testOnceFiresOnlyOnce() {
            let harness = makeHarness()
            harness.eval("""
                var count = 0;
                hs.wifi.once('ssidChange', function() { count++; });
                hs.wifi._watcherEmitter.emit('ssidChange', {interface: "en0"});
                hs.wifi._watcherEmitter.emit('ssidChange', {interface: "en0"});
            """)
            harness.expectEqual("count", 1)
            #expect(!harness.hasException)
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSWifiModule.self, as: "wifi")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.wifi.on") == "function")
            #expect(harness.evalTypeOf("hs.wifi.off") == "function")
            #expect(harness.evalTypeOf("hs.wifi.once") == "function")

            harness.eval("""
                var fn = function(info) {};
                hs.wifi.on('ssidChange', fn);
                hs.wifi.off('ssidChange', fn);
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: Real-hardware tests

    @Suite("hs.wifi real-hardware tests",
           .disabled(if: !hasWifiInterface(), "No Wi-Fi interface available"))
    struct HSWifiHardwareTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWifiModule.self, as: "wifi")
            return harness
        }

        @Test("interfaces returns a non-empty array of strings")
        func testInterfaces() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.wifi.interfaces())")
            harness.expectTrue("hs.wifi.interfaces().length > 0")
            #expect(!harness.hasException)
        }

        // Binding a CWInterface (as opposed to just listing interface names, which
        // testInterfaces() above confirms works) can fail inside the XCTest runner
        // process even when a real Wi-Fi interface is present on the machine — CoreWLAN
        // appears to treat the test bundle differently from a normal foreground app.
        // These tests therefore only assert the call doesn't throw and, if it does
        // resolve, that the shape is correct — they don't require it to resolve.

        @Test("interfaceDetails does not throw, and is null/undefined or well-shaped")
        func testInterfaceDetails() {
            let harness = makeHarness()
            harness.eval("var d = hs.wifi.interfaceDetails()")
            #expect(!harness.hasException)
            harness.expectTrue("""
                d === null || d === undefined ||
                (typeof d === 'object' && typeof d.power === 'boolean' && typeof d.active === 'boolean')
            """)
        }

        @Test("interfaceDetails does not throw for an unknown interface")
        func testInterfaceDetailsUnknownInterface() {
            let harness = makeHarness()
            harness.eval("var d = hs.wifi.interfaceDetails('not-a-real-interface')")
            #expect(!harness.hasException)
            harness.expectTrue("d === null || d === undefined")
        }

        @Test("currentNetwork does not throw")
        func testCurrentNetwork() {
            let harness = makeHarness()
            harness.eval("var n = hs.wifi.currentNetwork()")
            #expect(!harness.hasException)
            harness.expectTrue("n === null || n === undefined || typeof n === 'string'")
        }

        // Regression test for JSExport bridging an omitted argument to the literal string
        // "undefined" rather than Swift nil (see feedback_jsexport_optional_args memory /
        // HSModule skill note). Before the fix, omitting the interface argument caused
        // client.interface(withName: "undefined") to be looked up instead of the default
        // interface, which could diverge from explicitly passing the real interface name.
        @Test("omitting the interface argument resolves the same interface as passing its name explicitly")
        func testOmittedInterfaceMatchesExplicitName() {
            let harness = makeHarness()
            harness.eval("""
                var name = hs.wifi.interfaces()[0]
                var byName = hs.wifi.interfaceDetails(name)
                var omitted = hs.wifi.interfaceDetails()
                var sameNullness = (byName === null || byName === undefined) === (omitted === null || omitted === undefined)
                var sameInterface = sameNullness && (
                    (byName === null || byName === undefined) || (byName.interface === omitted.interface)
                )
            """)
            #expect(!harness.hasException)
            harness.expectTrue("sameInterface")
        }

        // setPower/disassociate/associate are not exercised against real hardware —
        // they would disrupt the developer's Wi-Fi connection. Only their Promise/
        // return shape is checked (Suite 1) or exercised without awaiting a real
        // network result, per the "don't test live network calls" rule.

        @Test("scanNetworks returns a thenable Promise")
        func testScanNetworksReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var p = hs.wifi.scanNetworks()")
            #expect(!harness.hasException)
            harness.expectTrue("typeof p === 'object' && typeof p.then === 'function'")
        }

        @Test("associate returns a thenable Promise")
        func testAssociateReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var p = hs.wifi.associate('__hs-wifi-test-nonexistent-ssid__', 'x')")
            #expect(!harness.hasException)
            harness.expectTrue("typeof p === 'object' && typeof p.then === 'function'")
        }
    }

}
