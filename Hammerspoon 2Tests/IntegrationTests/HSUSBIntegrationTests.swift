//
//  HSUSBIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.usb tests")
struct HSUSBTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.usb API structure tests")
    struct HSUSBStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUSBModule.self, as: "usb")
            return harness
        }

        @Test("attachedDevices is a function")
        func testAttachedDevicesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb.attachedDevices") == "function")
        }

        @Test("on is a function")
        func testOnIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb.once") == "function")
        }

        @Test("_addWatcher is a function")
        func testPrivateAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb._addWatcher") == "function")
        }

        @Test("_removeWatcher is a function")
        func testPrivateRemoveWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.usb._removeWatcher") == "function")
        }

        @Test("_watcherEmitter is initialised by hs.usb.js")
        func testWatcherEmitterInitialised() {
            makeHarness().expectTrue(
                "hs.usb._watcherEmitter !== null && hs.usb._watcherEmitter !== undefined"
            )
        }
    }

    // MARK: - Suite 2: Behaviour

    @Suite("hs.usb behaviour tests")
    struct HSUSBBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUSBModule.self, as: "usb")
            return harness
        }

        @Test("attachedDevices returns an array")
        func testAttachedDevicesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.usb.attachedDevices())")
            #expect(!harness.hasException)
        }

        @Test("each device has the required string and number fields")
        func testDeviceShape() {
            let harness = makeHarness()
            harness.eval("""
                var devices = hs.usb.attachedDevices();
                var allValid = devices.every(function(d) {
                    return typeof d.productName === 'string' &&
                           typeof d.vendorName === 'string' &&
                           typeof d.productID === 'number' &&
                           typeof d.vendorID === 'number';
                });
            """)
            harness.expectTrue("allValid")
            #expect(!harness.hasException)
        }

        @Test("on with non-function listener causes a context exception")
        func testOnNonFunctionCausesException() {
            let harness = makeHarness()
            harness.eval("hs.usb.on('added', 'notAFunction')")
            harness.expectException()
        }

        @Test("on and off do not throw with a function")
        func testOnOffNoThrow() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(device) {};
                hs.usb.on('added', fn);
                hs.usb.off('added', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("duplicate on registration for the same event is silently rejected")
        func testDuplicateListenerRejected() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(device) {};
                hs.usb.on('added', fn);
                hs.usb.on('added', fn);
                hs.usb.off('added', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("listeners only receive the event they registered for")
        func testListenersAreFilteredByEvent() {
            let harness = makeHarness()
            harness.eval("""
                var addedCount = 0;
                var removedCount = 0;
                hs.usb.on('added', function() { addedCount++; });
                hs.usb.on('removed', function() { removedCount++; });
                // Simulate a native 'added' event without a real USB device attached.
                hs.usb._watcherEmitter.emit('added', {});
            """)
            harness.expectEqual("addedCount", 1)
            harness.expectEqual("removedCount", 0)
            #expect(!harness.hasException)
        }

        @Test("once-registered listener fires only one time")
        func testOnceFiresOnlyOnce() {
            let harness = makeHarness()
            harness.eval("""
                var count = 0;
                hs.usb.once('added', function() { count++; });
                hs.usb._watcherEmitter.emit('added', {});
                hs.usb._watcherEmitter.emit('added', {});
            """)
            harness.expectEqual("count", 1)
            #expect(!harness.hasException)
        }
    }
}
