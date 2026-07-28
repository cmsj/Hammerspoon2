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

        @Test("watcherEventTypes is an object")
        func testWatcherEventTypesIsObject() {
            #expect(makeHarness().evalTypeOf("hs.wifi.watcherEventTypes") == "object")
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.wifi.addWatcher") == "function")
        }

        @Test("addWatcher returns an object with the expected shape")
        func testAddWatcherShape() {
            let harness = makeHarness()
            harness.eval("var w = hs.wifi.addWatcher()")
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("w.identifier") == "string")
            #expect(harness.evalTypeOf("w.events") == "object")
            #expect(harness.evalTypeOf("w.start") == "function")
            #expect(harness.evalTypeOf("w.stop") == "function")
            #expect(harness.evalTypeOf("w.setCallback") == "function")
            #expect(harness.evalTypeOf("w.destroy") == "function")
            harness.eval("w.destroy()")
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

        @Test("watcherEventTypes contains exactly the expected event names")
        func testWatcherEventTypesContents() {
            let harness = makeHarness()
            let result = harness.evalValue("hs.wifi.watcherEventTypes.slice().sort()")
            let events = result?.toArray() as? [String]
            #expect(events == [
                "bssidChange", "countryCodeChange", "linkChange", "linkQualityChange",
                "modeChange", "powerChange", "scanCacheUpdated", "ssidChange"
            ])
        }

        @Test("a new watcher defaults to watching ssidChange only")
        func testWatcherDefaultEvents() {
            let harness = makeHarness()
            harness.eval("var w = hs.wifi.addWatcher()")
            let events = harness.evalValue("w.events")?.toArray() as? [String]
            #expect(events == ["ssidChange"])
            harness.eval("w.destroy()")
        }

        @Test("setting events to a valid list is reflected back")
        func testSetValidEvents() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.wifi.addWatcher()
                w.events = ["powerChange", "linkChange"]
            """)
            let events = harness.evalValue("w.events")?.toArray() as? [String]
            #expect(Set(events ?? []) == Set(["powerChange", "linkChange"]))
            #expect(!harness.hasException)
            harness.eval("w.destroy()")
        }

        @Test("setting events with an unrecognized name drops it without throwing")
        func testSetInvalidEventDropped() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.wifi.addWatcher()
                w.events = ["powerChange", "bogusEvent"]
            """)
            let events = harness.evalValue("w.events")?.toArray() as? [String]
            #expect(events == ["powerChange"])
            #expect(!harness.hasException)
            harness.eval("w.destroy()")
        }

        @Test("setting events to an empty or all-invalid list is refused, keeping the previous value")
        func testSetEmptyEventsRefused() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.wifi.addWatcher()
                w.events = ["bogusEvent"]
            """)
            let events = harness.evalValue("w.events")?.toArray() as? [String]
            #expect(events == ["ssidChange"])
            #expect(!harness.hasException)
            harness.eval("w.destroy()")
        }

        @Test("start/stop/setCallback are chainable")
        func testChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.wifi.addWatcher()
                var chained = w.setCallback(function(event, info) {}).start().stop() === w
            """)
            #expect(harness.evalBool("chained") == true)
            #expect(!harness.hasException)
            harness.eval("w.destroy()")
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

    // MARK: - Memory Leak Tests

    @Test("Active HSWifiWatcher is released after shutdown")
    func testWifiWatcherDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSWifiModule.self, as: "wifi")
            harness.eval("""
                var w = hs.wifi.addWatcher()
                w.events = ["ssidChange", "powerChange"]
                w.setCallback(function(event, info) {})
                w.start()
            """)
            if let obj = harness.evalValue("w")?.toObjectOf(HSWifiWatcher.self) as? HSWifiWatcher {
                tracker.track(obj)
            }
            harness.eval("w = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
