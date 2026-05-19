//
//  HSAudioDeviceIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreAudio
@testable import Hammerspoon_2

private nonisolated func hasNoAudioDevices() -> Bool {
    let sysObjID = AudioObjectID(kAudioObjectSystemObject)
    var a = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard unsafe AudioObjectGetPropertyDataSize(sysObjID, &a, 0, nil, &size) == noErr, size > 0 else {
        return true
    }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    return count == 0
}

/// Integration tests for the hs.audiodevice module.
///
/// These tests are designed to run on both development machines (which have audio
/// hardware) and CI runners (which may have no audio devices at all).  Every test
/// that requires a real device first checks whether one is available and skips
/// gracefully if not.
@Suite("hs.audiodevice tests", .serialized, .disabled(if: hasNoAudioDevices(), "No audio hardware present"))
struct HSAudioDeviceIntegrationTests {

    // MARK: - Helpers

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSAudioDeviceModule.self, as: "audiodevice")
        return harness
    }

    // MARK: - Module-level API

    @Test("all() returns an array")
    func testAllReturnsArray() {
        let harness = makeHarness()
        harness.expectTrue("Array.isArray(hs.audiodevice.all())")
    }

    @Test("allOutputDevices() returns an array")
    func testAllOutputDevicesReturnsArray() {
        let harness = makeHarness()
        harness.expectTrue("Array.isArray(hs.audiodevice.allOutputDevices())")
    }

    @Test("allInputDevices() returns an array")
    func testAllInputDevicesReturnsArray() {
        let harness = makeHarness()
        harness.expectTrue("Array.isArray(hs.audiodevice.allInputDevices())")
    }

    @Test("allOutputDevices() is a subset of all()")
    func testOutputDevicesIsSubset() {
        let harness = makeHarness()
        harness.expectTrue("""
            hs.audiodevice.allOutputDevices().every(function(d) {
                return hs.audiodevice.all().some(function(a) { return a.uid === d.uid; });
            })
        """)
    }

    @Test("allInputDevices() is a subset of all()")
    func testInputDevicesIsSubset() {
        let harness = makeHarness()
        harness.expectTrue("""
            hs.audiodevice.allInputDevices().every(function(d) {
                return hs.audiodevice.all().some(function(a) { return a.uid === d.uid; });
            })
        """)
    }

    @Test("defaultOutputDevice() returns null or an HSAudioDevice")
    func testDefaultOutputDeviceType() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.audiodevice.defaultOutputDevice()")
        // Either null (no devices) or an object
        let isNullOrObject = result?.isNull == true || result?.isUndefined == true || result?.isObject == true
        #expect(isNullOrObject)
    }

    @Test("defaultInputDevice() returns null or an HSAudioDevice")
    func testDefaultInputDeviceType() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.audiodevice.defaultInputDevice()")
        let isNullOrObject = result?.isNull == true || result?.isUndefined == true || result?.isObject == true
        #expect(isNullOrObject)
    }

    @Test("defaultEffectDevice() returns null or an HSAudioDevice")
    func testDefaultEffectDeviceType() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.audiodevice.defaultEffectDevice()")
        let isNullOrObject = result?.isNull == true || result?.isUndefined == true || result?.isObject == true
        #expect(isNullOrObject)
    }

    @Test("findDeviceByName() returns null for unknown device")
    func testFindDeviceByNameUnknown() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.audiodevice.findDeviceByName('__nonexistent_device__')")
        #expect(result?.isNull == true || result?.isUndefined == true)
    }

    @Test("findDeviceByUID() returns null for unknown UID")
    func testFindDeviceByUIDUnknown() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.audiodevice.findDeviceByUID('__nonexistent_uid__')")
        #expect(result?.isNull == true || result?.isUndefined == true)
    }

    @Test("findDeviceByName() can round-trip through all()")
    func testFindDeviceByNameRoundTrip() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var devices = hs.audiodevice.all();
                if (devices.length === 0) return true;
                var first = devices[0];
                var found = hs.audiodevice.findDeviceByName(first.name);
                return found !== null && found.uid === first.uid;
            })()
        """)
    }

    @Test("findDeviceByUID() can round-trip through all()")
    func testFindDeviceByUIDRoundTrip() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var devices = hs.audiodevice.all();
                if (devices.length === 0) return true;
                var first = devices[0];
                var found = hs.audiodevice.findDeviceByUID(first.uid);
                return found !== null && found.name === first.name;
            })()
        """)
    }

    // MARK: - Device identity properties

    @Test("HSAudioDevice has a non-empty name")
    func testDeviceName() {
        let harness = makeHarness()
        harness.expectTrue("hs.audiodevice.all()[0].name.length > 0")
    }

    @Test("HSAudioDevice has a non-empty uid")
    func testDeviceUID() {
        let harness = makeHarness()
        harness.expectTrue("hs.audiodevice.all()[0].uid.length > 0")
    }

    @Test("HSAudioDevice id is a positive integer")
    func testDeviceID() {
        let harness = makeHarness()
        harness.expectTrue("hs.audiodevice.all()[0].id > 0")
    }

    @Test("HSAudioDevice isInput and isOutput are booleans")
    func testDeviceCapabilities() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.all()[0];
                return typeof d.isInput === 'boolean' && typeof d.isOutput === 'boolean';
            })()
        """)
    }

    @Test("HSAudioDevice transportType is a string")
    func testTransportType() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.audiodevice.all()[0].transportType === 'string'")
    }

    @Test("allOutputDevices() all have isOutput true")
    func testAllOutputHaveIsOutput() {
        let harness = makeHarness()
        harness.expectTrue("""
            hs.audiodevice.allOutputDevices().every(function(d) { return d.isOutput === true; })
        """)
    }

    @Test("allInputDevices() all have isInput true")
    func testAllInputHaveIsInput() {
        let harness = makeHarness()
        harness.expectTrue("""
            hs.audiodevice.allInputDevices().every(function(d) { return d.isInput === true; })
        """)
    }

    // MARK: - Channels

    @Test("outputChannels is a non-negative integer")
    func testOutputChannels() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.all()[0];
                return typeof d.outputChannels === 'number' && d.outputChannels >= 0;
            })()
        """)
    }

    @Test("inputChannels is a non-negative integer")
    func testInputChannels() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.all()[0];
                return typeof d.inputChannels === 'number' && d.inputChannels >= 0;
            })()
        """)
    }

    // MARK: - Volume & Mute

    @Test("output device volume is a number or null")
    func testOutputVolume() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.defaultOutputDevice();
                if (!d) return true;
                var v = d.volume;
                return v === null || (typeof v === 'number' && v >= 0 && v <= 1);
            })()
        """)
    }

    @Test("output device muted is a boolean")
    func testOutputMuted() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.defaultOutputDevice();
                return d ? typeof d.muted === 'boolean' : true;
            })()
        """)
    }

    @Test("availableSampleRates is an array")
    func testAvailableSampleRates() {
        let harness = makeHarness()
        harness.expectTrue("""
            Array.isArray(hs.audiodevice.all()[0].availableSampleRates)
        """)
    }

    @Test("sampleRate is a number or null")
    func testSampleRate() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.all()[0];
                var r = d.sampleRate;
                return r === null || (typeof r === 'number' && r > 0);
            })()
        """)
    }

    // MARK: - Data sources

    @Test("outputDataSources() returns an array")
    func testOutputDataSources() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.defaultOutputDevice();
                return d ? Array.isArray(d.outputDataSources()) : true;
            })()
        """)
    }

    @Test("inputDataSources() returns an array")
    func testInputDataSources() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.defaultInputDevice();
                return d ? Array.isArray(d.inputDataSources()) : true;
            })()
        """)
    }

    // MARK: - Module-level watcher

    @Test("module addWatcher() and removeWatcher() cycle is safe")
    func testModuleWatcherAddRemoveCycle() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var fn = function(e) {};
                hs.audiodevice.addWatcher(fn);
                hs.audiodevice.removeWatcher(fn);
                return true;
            })()
        """)
    }

    @Test("module removeWatcher() with unregistered listener is safe")
    func testModuleRemoveUnregisteredWatcher() {
        let harness = makeHarness()
        harness.eval("hs.audiodevice.removeWatcher(function() {});")
        harness.expectTrue("true")
    }

    @Test("module addWatcher() with the same listener twice is safe")
    func testModuleAddWatcherIdempotent() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var fn = function(e) {};
                hs.audiodevice.addWatcher(fn);
                hs.audiodevice.addWatcher(fn); // duplicate — should not crash
                hs.audiodevice.removeWatcher(fn);
                return true;
            })()
        """)
    }

    // MARK: - Per-device watcher

    @Test("device addWatcher() and removeWatcher() cycle is safe")
    func testDeviceWatcherAddRemoveCycle() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var dev = hs.audiodevice.all()[0];
                var fn = function(e) {};
                dev.addWatcher(fn);
                dev.removeWatcher(fn);
                return true;
            })()
        """)
    }

    @Test("device removeWatcher() with unregistered listener is safe")
    func testDeviceRemoveUnregisteredWatcher() {
        let harness = makeHarness()
        harness.eval("""
            var _safeRemoveDev = hs.audiodevice.all()[0];
            _safeRemoveDev.removeWatcher(function() {});
        """)
        harness.expectTrue("true")
    }

    @Test("device watcher fires vmout event when output volume changes")
    @MainActor
    func testDeviceWatcherFiresOnVolumeChange() async throws {
        let harness = makeHarness()

        let module = HSAudioDeviceModule(engineID: UUID())
        guard let dev = module.defaultOutputDevice(), dev.isOutput,
              let originalVolume = dev.volume else { return }

        defer { dev.volume = originalVolume }

        let nudged = NSNumber(value: originalVolume.doubleValue > 0.5
            ? originalVolume.doubleValue - 0.05
            : originalVolume.doubleValue + 0.05)

        harness.eval("""
            var _devWatchEvents = [];
            var _watchFn = function(e) { _devWatchEvents.push(e); };
            var _volDev = hs.audiodevice.defaultOutputDevice();
            _volDev.addWatcher(_watchFn);
        """)
        defer { harness.eval("_volDev.removeWatcher(_watchFn);") }

        dev.volume = nudged
        try await Task.sleep(for: .milliseconds(500))

        harness.expectTrue("_devWatchEvents.indexOf('vmout') !== -1")
    }

    @Test("multiple device watcher listeners all fire on the same event")
    @MainActor
    func testMultipleDeviceWatchersAllFire() async throws {
        let harness = makeHarness()

        let module = HSAudioDeviceModule(engineID: UUID())
        guard let dev = module.defaultOutputDevice(), dev.isOutput,
              let originalVolume = dev.volume else { return }

        defer { dev.volume = originalVolume }

        let nudged = NSNumber(value: originalVolume.doubleValue > 0.5
            ? originalVolume.doubleValue - 0.05
            : originalVolume.doubleValue + 0.05)

        harness.eval("""
            var _multiCallCount1 = 0, _multiCallCount2 = 0;
            var _multiFn1 = function(e) { if (e === 'vmout') _multiCallCount1++; };
            var _multiFn2 = function(e) { if (e === 'vmout') _multiCallCount2++; };
            var _multiDev = hs.audiodevice.defaultOutputDevice();
            _multiDev.addWatcher(_multiFn1);
            _multiDev.addWatcher(_multiFn2);
        """)
        defer { harness.eval("""
            _multiDev.removeWatcher(_multiFn1);
            _multiDev.removeWatcher(_multiFn2);
        """) }

        dev.volume = nudged
        defer { dev.volume = originalVolume }
        try await Task.sleep(for: .milliseconds(700))

        let multiCallCount1 = harness.eval("_multiCallCount1") as! Int
        let multiCallCount2 = harness.eval("_multiCallCount2") as! Int
        #expect(multiCallCount1 > 0)
        #expect(multiCallCount2 > 0)
//        harness.expectTrue("_multiCallCount1 > 0")
//        harness.expectTrue("_multiCallCount2 > 0")
    }

    // MARK: - System watcher callbacks

    @Test("system watcher fires dOut event when default output device changes")
    @MainActor
    func testSystemWatcherFiresOnDefaultOutputChange() async throws {
        let harness = makeHarness()

        let module = HSAudioDeviceModule(engineID: UUID())
        let outputs = module.allOutputDevices()
        guard outputs.count >= 2, let originalDefault = module.defaultOutputDevice() else { return }
        guard let altDevice = outputs.first(where: { $0.uid != originalDefault.uid }) else { return }

        defer { _ = originalDefault.setDefaultOutputDevice() }

        harness.eval("""
            var _sysOutEvents = [];
            var _sysOutFn = function(e) { _sysOutEvents.push(e); };
            hs.audiodevice.addWatcher(_sysOutFn);
        """)
        defer { harness.eval("hs.audiodevice.removeWatcher(_sysOutFn);") }

        _ = altDevice.setDefaultOutputDevice()
        try await Task.sleep(for: .milliseconds(500))

        harness.expectTrue("_sysOutEvents.indexOf('dOut') !== -1")
    }

    @Test("system watcher fires dIn event when default input device changes")
    @MainActor
    func testSystemWatcherFiresOnDefaultInputChange() async throws {
        let harness = makeHarness()

        let module = HSAudioDeviceModule(engineID: UUID())
        let inputs = module.allInputDevices()
        guard inputs.count >= 2, let originalDefault = module.defaultInputDevice() else { return }
        guard let altDevice = inputs.first(where: { $0.uid != originalDefault.uid }) else { return }

        defer { _ = originalDefault.setDefaultInputDevice() }

        harness.eval("""
            var _sysInEvents = [];
            var _sysInFn = function(e) { _sysInEvents.push(e); };
            hs.audiodevice.addWatcher(_sysInFn);
        """)
        defer { harness.eval("hs.audiodevice.removeWatcher(_sysInFn);") }

        _ = altDevice.setDefaultInputDevice()
        try await Task.sleep(for: .milliseconds(500))

        harness.expectTrue("_sysInEvents.indexOf('dIn') !== -1")
    }

    // MARK: - Default device setters (smoke tests only — no mutation)

    @Test("setDefaultOutputDevice/InputDevice/EffectDevice methods exist")
    func testDefaultDeviceSetterMethodsExist() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var d = hs.audiodevice.all()[0];
                return typeof d.setDefaultOutputDevice === 'function' &&
                       typeof d.setDefaultInputDevice === 'function' &&
                       typeof d.setDefaultEffectDevice === 'function';
            })()
        """)
    }

    // MARK: - Manager reuse

    @Test("HSAudioDeviceManager returns the same instance for the same device")
    func testManagerReuse() {
        let harness = makeHarness()
        // The manager should return the same Swift object for the same AudioObjectID.
        // We can't directly verify object identity from JS, but we can verify that
        // the returned objects have identical properties.
        harness.expectTrue("""
            (function() {
                var a = hs.audiodevice.all()[0];
                var b = hs.audiodevice.findDeviceByUID(a.uid);
                return b !== null && a.id === b.id && a.name === b.name;
            })()
        """)
    }
}
