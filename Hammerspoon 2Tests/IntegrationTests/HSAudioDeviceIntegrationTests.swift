//
//  HSAudioDeviceIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import CoreAudio
@testable import Hammerspoon_2

/// Integration tests for the hs.audiodevice module.
///
/// These tests are designed to run on both development machines (which have audio
/// hardware) and CI runners (which may have no audio devices at all).  Every test
/// that requires a real device first checks whether one is available and skips
/// gracefully if not.
struct HSAudioDeviceIntegrationTests {

    // MARK: - Helpers

    /// Returns `true` when the system has at least one audio device.
    private func hasAudioDevices(_ harness: JSTestHarness) -> Bool {
        let count = harness.eval("hs.audiodevice.all().length") as? Int ?? 0
        return count > 0
    }

    /// Returns `true` when the system has a default output device.
    private func hasDefaultOutput(_ harness: JSTestHarness) -> Bool {
        let result = harness.evalValue("hs.audiodevice.defaultOutputDevice()")
        return result?.isNull == false && result?.isUndefined == false
    }

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
        guard hasAudioDevices(harness) else { return }
        harness.expectTrue("""
            hs.audiodevice.allOutputDevices().every(function(d) {
                return hs.audiodevice.all().some(function(a) { return a.uid === d.uid; });
            })
        """)
    }

    @Test("allInputDevices() is a subset of all()")
    func testInputDevicesIsSubset() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
        harness.expectTrue("hs.audiodevice.all()[0].name.length > 0")
    }

    @Test("HSAudioDevice has a non-empty uid")
    func testDeviceUID() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
        harness.expectTrue("hs.audiodevice.all()[0].uid.length > 0")
    }

    @Test("HSAudioDevice id is a positive integer")
    func testDeviceID() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
        harness.expectTrue("hs.audiodevice.all()[0].id > 0")
    }

    @Test("HSAudioDevice isInput and isOutput are booleans")
    func testDeviceCapabilities() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
        guard hasDefaultOutput(harness) else { return }
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
        guard hasDefaultOutput(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
        harness.expectTrue("""
            Array.isArray(hs.audiodevice.all()[0].availableSampleRates)
        """)
    }

    @Test("sampleRate is a number or null")
    func testSampleRate() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
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
        guard hasDefaultOutput(harness) else { return }
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

    // MARK: - System watcher

    @Test("watcherIsActive() starts false, becomes true after startWatcher()")
    func testSystemWatcherActiveState() {
        let harness = makeHarness()
        harness.expectFalse("hs.audiodevice.watcherIsActive()")
        harness.eval("hs.audiodevice.setWatcherCallback(function() {})")
        harness.eval("hs.audiodevice.startWatcher()")
        harness.expectTrue("hs.audiodevice.watcherIsActive()")
        harness.eval("hs.audiodevice.stopWatcher()")
        harness.expectFalse("hs.audiodevice.watcherIsActive()")
    }

    @Test("startWatcher() is idempotent")
    func testSystemWatcherIdempotent() {
        let harness = makeHarness()
        harness.eval("hs.audiodevice.setWatcherCallback(function() {})")
        harness.eval("hs.audiodevice.startWatcher()")
        harness.eval("hs.audiodevice.startWatcher()") // second call should be safe
        harness.expectTrue("hs.audiodevice.watcherIsActive()")
        harness.eval("hs.audiodevice.stopWatcher()")
    }

    @Test("stopWatcher() when not started is safe")
    func testStopWatcherWhenNotStarted() {
        let harness = makeHarness()
        // Should not crash
        harness.eval("hs.audiodevice.stopWatcher()")
        harness.expectFalse("hs.audiodevice.watcherIsActive()")
    }

    // MARK: - Per-device watcher

    @Test("device watcherIsActive() starts false, becomes true after startWatcher()")
    func testDeviceWatcherActiveState() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
        harness.eval("""
            var testDev = hs.audiodevice.all()[0];
            testDev.setWatcherCallback(function(e) {});
            testDev.startWatcher();
        """)
        harness.expectTrue("testDev.watcherIsActive()")
        harness.eval("testDev.stopWatcher()")
        harness.expectFalse("testDev.watcherIsActive()")
    }

    @Test("device stopWatcher() when not started is safe")
    func testDeviceStopWatcherWhenNotStarted() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
        // Should not crash
        harness.eval("""
            var safeDev = hs.audiodevice.all()[0];
            safeDev.stopWatcher();
        """)
        harness.expectFalse("safeDev.watcherIsActive()")
    }

    // MARK: - Default device setters (smoke tests only — no mutation)

    @Test("setDefaultOutputDevice/InputDevice/EffectDevice methods exist")
    func testDefaultDeviceSetterMethodsExist() {
        let harness = makeHarness()
        guard hasAudioDevices(harness) else { return }
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
        guard hasAudioDevices(harness) else { return }
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
