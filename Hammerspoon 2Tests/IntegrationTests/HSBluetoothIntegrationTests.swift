//
//  HSBluetoothIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreBluetooth
@testable import Hammerspoon_2

/// True only when the user has already granted Bluetooth access. Reading the authorization
/// state never shows the prompt, unlike the first IOBluetooth call does.
private nonisolated func isBluetoothAuthorized() -> Bool {
    CBManager.authorization == .allowedAlways
}

@Suite("hs.bluetooth tests")
struct HSBluetoothTests {

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBluetoothModule.self, as: "bluetooth")
        return harness
    }

    // MARK: - Suite 1: API structure and emitter wiring (no Bluetooth access)

    @Suite("hs.bluetooth API structure tests")
    struct HSBluetoothStructureTests {

        @Test("API structure", arguments: ["pairedDevices", "connectedDevices", "availableDevices", "device", "on", "off", "once", "_addWatcher", "_removeWatcher"])
        func testIsFunction(_ name: String) {
            #expect(makeHarness().evalTypeOf("hs.bluetooth." + name) == "function")
        }

        @Test("_watcherEmitter is initialised by hs.bluetooth.js")
        func testWatcherEmitterInitialised() {
            makeHarness().expectTrue("hs.bluetooth._watcherEmitter !== null && hs.bluetooth._watcherEmitter !== undefined")
        }

        @Test("device() returns null for a malformed address without touching the Bluetooth stack")
        func testMalformedAddress() {
            makeHarness().expectTrue("hs.bluetooth.device('not-an-address') == null")
        }

        @Test("listeners only receive the event they registered for, once fires once")
        func testEmitterRouting() {
            let harness = makeHarness()
            // The first on() would start the native watcher, which registers with IOBluetooth and
            // lists paired devices. Stub the emitter's start/stop hooks so this stays a pure
            // routing test that never needs Bluetooth access.
            harness.eval("""
                var nativeStarted = false;
                hs.bluetooth._watcherEmitter._start = function() { nativeStarted = true; return true; };
                hs.bluetooth._watcherEmitter._stop = function() {};
                var connectedCount = 0, disconnectedCount = 0, onceCount = 0;
                hs.bluetooth.on('connected', function() { connectedCount++; });
                hs.bluetooth.on('disconnected', function() { disconnectedCount++; });
                hs.bluetooth.once('connected', function() { onceCount++; });
                hs.bluetooth._watcherEmitter.emit('connected', {});
                hs.bluetooth._watcherEmitter.emit('connected', {});
            """)
            harness.expectEqual("connectedCount", 2)
            harness.expectEqual("disconnectedCount", 0)
            harness.expectEqual("onceCount", 1)
            harness.expectTrue("nativeStarted")
            #expect(!harness.hasException)
        }

        @Test("on with non-function listener causes a context exception")
        func testOnNonFunctionCausesException() {
            let harness = makeHarness()
            harness.eval("hs.bluetooth.on('connected', 'notAFunction')")
            harness.expectException()
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSBluetoothModule.self, as: "bluetooth")
            harness.collectGarbage()
            #expect(harness.evalTypeOf("hs.bluetooth.on") == "function")
            #expect(harness.evalTypeOf("hs.bluetooth.off") == "function")
            #expect(harness.evalTypeOf("hs.bluetooth.once") == "function")
        }
    }

    // MARK: - Suite 2: Real Bluetooth stack (skipped unless access was already granted)

    @Suite("hs.bluetooth real-hardware tests",
           .serialized,
           .disabled(if: !isBluetoothAuthorized(), "Bluetooth access not granted"))
    struct HSBluetoothHardwareTests {

        @Test("powered is a boolean")
        func testPoweredIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.bluetooth.powered") == "boolean")
        }

        @Test("paired and connected devices are arrays of well-formed objects, and connected ⊆ paired")
        func testDeviceShape() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var connected = hs.bluetooth.connectedDevices();
                var allValid = paired.concat(connected).every(function(d) {
                    return typeof d.name === 'string' && typeof d.address === 'string' &&
                           typeof d.connected === 'boolean' && typeof d.paired === 'boolean' &&
                           typeof d.classOfDevice === 'number' && typeof d.majorClass === 'number' &&
                           (d.rssi === undefined || typeof d.rssi === 'number');
                });
                var pairedAddresses = paired.map(d => d.address);
                var subset = connected.every(d => d.connected && pairedAddresses.includes(d.address));
            """)
            harness.expectTrue("Array.isArray(paired) && Array.isArray(connected)")
            harness.expectTrue("allValid")
            harness.expectTrue("subset")
            #expect(!harness.hasException)
        }

        @Test("device() returns details for a paired device")
        func testDeviceLookup() {
            let harness = makeHarness()
            harness.eval("""
                var paired = hs.bluetooth.pairedDevices();
                var ok = paired.length === 0 || (function() {
                    var info = hs.bluetooth.device(paired[0].address);
                    return info !== null && info.address === paired[0].address &&
                           Array.isArray(info.services) && typeof info.favorite === 'boolean';
                })();
            """)
            harness.expectTrue("ok")
            #expect(!harness.hasException)
        }

        @Test("availableDevices returns a Promise")
        func testAvailableDevicesReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var p = hs.bluetooth.availableDevices(1); var isPromise = p instanceof Promise;")
            harness.expectTrue("isPromise")
            #expect(!harness.hasException)
        }
    }
}
