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
            makeHarness().expectTrue("typeof hs.usb.attachedDevices === 'function'")
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.usb.addWatcher === 'function'")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.usb.removeWatcher === 'function'")
        }

        @Test("_addWatcher is a function")
        func testPrivateAddWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.usb._addWatcher === 'function'")
        }

        @Test("_removeWatcher is a function")
        func testPrivateRemoveWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.usb._removeWatcher === 'function'")
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

        @Test("addWatcher with non-function causes a context exception")
        func testAddWatcherNonFunctionCausesException() {
            let harness = makeHarness()
            harness.eval("hs.usb.addWatcher('notAFunction')")
            harness.expectException()
        }

        @Test("addWatcher and removeWatcher do not throw with a function")
        func testAddRemoveWatcherNoThrow() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(event, device) {};
                hs.usb.addWatcher(fn);
                hs.usb.removeWatcher(fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("duplicate addWatcher registration is silently rejected")
        func testDuplicateWatcherRejected() {
            let harness = makeHarness()
            harness.eval("""
                var fn = function(event, device) {};
                hs.usb.addWatcher(fn);
                hs.usb.addWatcher(fn);
                hs.usb.removeWatcher(fn);
            """)
            #expect(!harness.hasException)
        }
    }
}
