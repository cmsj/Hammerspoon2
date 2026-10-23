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

/// Runs an audio device by attaching a do-nothing IOProc to it, so it reports itself as in use.
/// Used instead of AVAudioEngine, which creates a private aggregate output device that outlives
/// the engine and then confuses the default-device tests. The HAL zeroes output buffers before
/// calling the IOProc, so this plays silence. Callers must stop() it.
private final class DeviceRunner {
    private let deviceID: AudioObjectID
    private var procID: AudioDeviceIOProcID?

    init?(deviceID: AudioObjectID) {
        self.deviceID = deviceID
        guard unsafe AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil, Self.makeIOBlock()) == noErr,
              let procID = unsafe procID else { return nil }
        guard unsafe AudioDeviceStart(deviceID, procID) == noErr else {
            unsafe AudioDeviceDestroyIOProcID(deviceID, procID)
            return nil
        }
    }

    // nonisolated: the block runs on CoreAudio's realtime thread, and a closure literal formed in
    // a MainActor context would trap there on its hidden isolation check
    private nonisolated static func makeIOBlock() -> AudioDeviceIOBlock {
        return { _, _, _, _, _ in }
    }

    func stop() {
        guard let procID = unsafe procID else { return }
        unsafe AudioDeviceStop(deviceID, procID)
        unsafe AudioDeviceDestroyIOProcID(deviceID, procID)
        unsafe self.procID = nil
    }
}

@Suite("hs.audiodevice tests")
struct HSAudioDeviceTests {
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
            #expect(harness.evalTypeOf("hs.audiodevice.all()[0].transportType") == "string")
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

        @Test("volume, inputVolume and balance refuse values outside 0.0-1.0 and stay unchanged")
        func testScalarsRefuseOutOfRangeValues() {
            let harness = makeHarness()
            // Refused values never reach CoreAudio, so this changes nothing on any device
            harness.eval("""
            var _rangeResults = [];
            hs.audiodevice.all().forEach(function(d) {
                ['volume', 'inputVolume', 'balance'].forEach(function(prop) {
                    var before = d[prop];
                    if (before === null) return;
                    [50, 100, 1.01, -0.1, NaN].forEach(function(bad) {
                        d[prop] = bad;
                        _rangeResults.push({ prop: prop, bad: bad, unchanged: d[prop] === before });
                    });
                });
            });
            var _rangeFailures = _rangeResults.filter(function(r) { return !r.unchanged; })
                .map(function(r) { return r.prop + "=" + r.bad; });
        """)
            #expect(!harness.hasException)
            #expect(harness.evalValue("_rangeFailures")?.toArray() as? [String] == [])
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

        // MARK: - Activity

        @Test("isInUse is a boolean on every device")
        func testIsInUseIsBoolean() {
            let harness = makeHarness()
            harness.expectTrue("hs.audiodevice.all().every(function(d) { return typeof d.isInUse === 'boolean'; })")
        }

        @Test("isInUse matches CoreAudio's running-somewhere state")
        @MainActor
        func testIsInUseMatchesCoreAudio() {
            let module = HSAudioDeviceModule(engineID: UUID())
            for dev in module.all() {
                var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                guard unsafe AudioObjectGetPropertyData(dev.objectID, &a, 0, nil, &size, &value) == noErr else { continue }
                #expect(dev.isInUse == (value != 0), "\(dev.name)")
            }
        }

        @Test("jackConnected is a boolean on every device")
        func testJackConnectedType() {
            let harness = makeHarness()
            harness.expectTrue("hs.audiodevice.all().every(function(d) { return typeof d.jackConnected === 'boolean'; })")
        }

        // MARK: - Per-device watcher event names

        @Test("per-device on() with an unknown event throws and starts nothing")
        func testDeviceOnRejectsUnknownEvent() {
            let harness = makeHarness()
            harness.eval("""
                var d = hs.audiodevice.all()[0];
                var names = d._eventNames;
                var message = null;
                try {
                    d.on('vmOut', function() {});
                } catch (err) {
                    message = err.message;
                }
                var listenerCount = d._watcherEmitter ? d._watcherEmitter._listenerCount : 0;
                // Drop the never-started emitter so no JSValue from this context lingers on the device
                d._removeWatcher();
            """)
            #expect(harness.evalValue("names")?.toArray() as? [String] == ["vmout", "vmin", "mout", "min", "rate", "dsout", "dsin", "balance", "inUse", "jack", "config"])
            // device on() is a native method that invokeMethods into the JS emitter; a caught
            // error must not also reach the context's exceptionHandler.
            #expect(!harness.hasException)
            #expect(harness.evalString("message") == "hs.audiodevice device.on(): unknown event 'vmOut'. Known events: vmout, vmin, mout, min, rate, dsout, dsin, balance, inUse, jack, config")
            #expect(harness.evalInt("listenerCount") == 0)
        }

        // MARK: - Module-level watcher

        @Test("module on() and off() cycle is safe")
        func testModuleWatcherOnOffCycle() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function() {};
                hs.audiodevice.on('dOut', fn);
                hs.audiodevice.off('dOut', fn);
                return true;
            })()
        """)
        }

        @Test("module off() with unregistered listener is safe")
        func testModuleOffUnregisteredWatcher() {
            let harness = makeHarness()
            harness.eval("hs.audiodevice.off('dOut', function() {});")
            harness.expectTrue("true")
        }

        @Test("module on() with the same listener twice is safe")
        func testModuleOnIdempotent() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function() {};
                hs.audiodevice.on('dOut', fn);
                hs.audiodevice.on('dOut', fn); // duplicate — should not crash
                hs.audiodevice.off('dOut', fn);
                return true;
            })()
        """)
        }

        @Test("module on() throws if the native watcher fails to start")
        func testModuleOnThrowsWhenNativeStartFails() {
            // Regression test for a code review comment (same class of bug fixed for
            // hs.power's battery watcher): if _addWatcher fails to register any CoreAudio
            // property listener, the LazyWatcherEmitter's start() function must throw rather
            // than silently succeed - otherwise the listener gets recorded as if the watcher
            // were running and never receives events. Simulates total native failure by
            // swapping in a stub that returns false, since real CoreAudio registration can't
            // be forced to fail from a test. hs.audiodevice.on() is pure JS (unlike the
            // per-device case below), so checking !hasException is valid here.
            let harness = makeHarness()
            harness.eval("""
                hs.audiodevice._addWatcher = function(fn) { return false; };
                var threw = false;
                try {
                    hs.audiodevice.on('dOut', function() {});
                } catch (err) {
                    threw = true;
                }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
        }

        @Test("module on/off/once survive garbage collection of the module's JS wrapper")
        func testModuleOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSAudioDeviceModule.self, as: "audiodevice")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.audiodevice.on") == "function")
            #expect(harness.evalTypeOf("hs.audiodevice.off") == "function")
            #expect(harness.evalTypeOf("hs.audiodevice.once") == "function")

            harness.eval("""
                var fn = function() {};
                hs.audiodevice.on('dOut', fn);
                hs.audiodevice.off('dOut', fn);
            """)
            #expect(!harness.hasException)
        }

        // MARK: - Per-device watcher

        @Test("device on() and off() cycle is safe")
        func testDeviceWatcherOnOffCycle() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var dev = hs.audiodevice.all()[0];
                var fn = function() {};
                dev.on('vmout', fn);
                dev.off('vmout', fn);
                return true;
            })()
        """)
        }

        @Test("device off() with unregistered listener is safe")
        func testDeviceOffUnregisteredWatcher() {
            let harness = makeHarness()
            harness.eval("""
            var _safeRemoveDev = hs.audiodevice.all()[0];
            _safeRemoveDev.off('vmout', function() {});
        """)
            harness.expectTrue("true")
        }

        @Test("device on() throws if the native watcher fails to start")
        func testDeviceOnThrowsWhenNativeStartFails() {
            // Same regression as the module-level test above, for the per-device watcher.
            // device on()/once() are native Swift methods that invokeMethod into the JS
            // emitter; an exception the caller catches must not also reach the context's
            // exceptionHandler (which logs it as an error), hence the !hasException check.
            let harness = makeHarness()
            harness.eval("""
                var _failDev = hs.audiodevice.all()[0];
                _failDev._addWatcher = function(fn) { return false; };
                var threw = false;
                try {
                    _failDev.on('vmout', function() {});
                } catch (err) {
                    threw = true;
                }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
        }

        @Test("device on() throws, instead of silently returning, if the emitter factory is unavailable")
        func testDeviceOnThrowsWithoutEmitterFactory() {
            let harness = makeHarness()
            harness.eval("""
                var _noFactoryDev = hs.audiodevice.all()[0];
                hs.audiodevice._makeDeviceEmitter = null;
                var message = null;
                try {
                    _noFactoryDev.on('vmout', function() {});
                } catch (err) {
                    message = err.message;
                }
            """)
            #expect(!harness.hasException)
            #expect(harness.evalString("message") == "hs.audiodevice device: device watcher emitter factory is unavailable")
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
            var _devWatchFired = false;
            var _devWatchVolume = null;
            var _watchFn = function(volume) { _devWatchFired = true; _devWatchVolume = volume; };
            var _volDev = hs.audiodevice.defaultOutputDevice();
            _volDev.on('vmout', _watchFn);
        """)
            defer { harness.eval("_volDev.off('vmout', _watchFn);") }

            dev.volume = nudged
            try await Task.sleep(for: .milliseconds(500))

            harness.expectTrue("_devWatchFired")
            // The listener receives the new volume (CoreAudio may quantise it slightly)
            let reported = try #require(harness.evalDouble("_devWatchVolume"))
            #expect(abs(reported - nudged.doubleValue) < 0.02)
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
            var _multiFn1 = function() { _multiCallCount1++; };
            var _multiFn2 = function() { _multiCallCount2++; };
            var _multiDev = hs.audiodevice.defaultOutputDevice();
            _multiDev.on('vmout', _multiFn1);
            _multiDev.on('vmout', _multiFn2);
        """)
            defer { harness.eval("""
            _multiDev.off('vmout', _multiFn1);
            _multiDev.off('vmout', _multiFn2);
        """) }

            dev.volume = nudged
            defer { dev.volume = originalVolume }
            try await Task.sleep(for: .milliseconds(700))

            let multiCallCount1 = harness.eval("_multiCallCount1") as! Int
            let multiCallCount2 = harness.eval("_multiCallCount2") as! Int
            #expect(multiCallCount1 > 0)
            #expect(multiCallCount2 > 0)
        }

        @Test("device on() and off() cycle is safe for the inUse, jack, balance and config events")
        func testDeviceWatcherNewEventsOnOffCycle() {
            let harness = makeHarness()
            harness.eval("""
                var _newEventsDev = hs.audiodevice.all()[0];
                var _newEventsFn = function() {};
                ['inUse', 'jack', 'balance', 'config'].forEach(function(e) {
                    _newEventsDev.on(e, _newEventsFn);
                    _newEventsDev.off(e, _newEventsFn);
                });
            """)
            #expect(!harness.hasException)
        }

        @Test("device watcher fires inUse with the new state when the device starts and stops running")
        @MainActor
        func testDeviceWatcherFiresInUse() async throws {
            let harness = makeHarness()

            let module = HSAudioDeviceModule(engineID: UUID())
            // Needs an output device nothing else is using, so starting our own engine is what
            // flips its state
            guard let dev = module.defaultOutputDevice(), dev.isOutput, !dev.isInUse else { return }

            harness.eval("""
            var _inUseStates = [];
            var _inUseFn = function(inUse) { _inUseStates.push(inUse); };
            var _inUseDev = hs.audiodevice.defaultOutputDevice();
            _inUseDev.on('inUse', _inUseFn);
        """)
            defer { harness.eval("_inUseDev.off('inUse', _inUseFn);") }
            #expect(!harness.hasException)

            guard let runner = DeviceRunner(deviceID: dev.objectID) else { return }
            defer { runner.stop() }

            let started = await harness.waitForAsync(timeout: 2.0) {
                harness.evalBool("_inUseStates.indexOf(true) !== -1") == true
            }
            #expect(started)
            #expect(dev.isInUse)

            runner.stop()
            let stopped = await harness.waitForAsync(timeout: 3.0) {
                harness.evalBool("_inUseStates[_inUseStates.length - 1] === false") == true
            }
            #expect(stopped)
            harness.expectTrue("_inUseStates.every(function(s) { return typeof s === 'boolean'; })")
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
            var _sysOutFired = false;
            var _sysOutUID = null;
            var _sysOutFn = function(device) { _sysOutFired = true; _sysOutUID = device ? device.uid : null; };
            hs.audiodevice.on('dOut', _sysOutFn);
        """)
            defer { harness.eval("hs.audiodevice.off('dOut', _sysOutFn);") }

            _ = altDevice.setDefaultOutputDevice()
            try await Task.sleep(for: .milliseconds(500))

            harness.expectTrue("_sysOutFired")
            #expect(harness.evalString("_sysOutUID") == altDevice.uid)
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
            var _sysInFired = false;
            var _sysInUID = null;
            var _sysInFn = function(device) { _sysInFired = true; _sysInUID = device ? device.uid : null; };
            hs.audiodevice.on('dIn', _sysInFn);
        """)
            defer { harness.eval("hs.audiodevice.off('dIn', _sysInFn);") }

            _ = altDevice.setDefaultInputDevice()
            try await Task.sleep(for: .milliseconds(500))

            harness.expectTrue("_sysInFired")
            #expect(harness.evalString("_sysInUID") == altDevice.uid)
        }

        @Test("system watcher passes the added device to dev+ and its identity to dev-")
        @MainActor
        func testSystemWatcherDevicePayloads() async throws {
            let harness = makeHarness()
            harness.eval("""
            var _added = [], _removed = [];
            var _addFn = function(device) { _added.push({ uid: device.uid, name: device.name, isDevice: device.toString().indexOf('HSAudioDevice') !== -1 }); };
            var _removeFn = function(info) { _removed.push(info); };
            hs.audiodevice.on('dev+', _addFn);
            hs.audiodevice.on('dev-', _removeFn);
        """)
            defer { harness.eval("hs.audiodevice.off('dev+', _addFn); hs.audiodevice.off('dev-', _removeFn);") }
            #expect(!harness.hasException)

            let uid = "net.tenshu.Hammerspoon-2.tests.aggregate.\(UUID().uuidString)"
            let name = "Hammerspoon 2 test aggregate"
            // A private aggregate with no sub-devices: it's only visible to this process and
            // routes no audio, and it's destroyed below
            let description: [String: Any] = [
                kAudioAggregateDeviceUIDKey: uid,
                kAudioAggregateDeviceNameKey: name,
                kAudioAggregateDeviceIsPrivateKey: 1,
            ]
            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            guard unsafe AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr else {
                Issue.record("Couldn't create an aggregate device")
                return
            }
            var destroyed = false
            defer { if !destroyed { AudioHardwareDestroyAggregateDevice(aggregateID) } }

            let added = await harness.waitForAsync(timeout: 3.0) {
                harness.evalBool("_added.some(function(d) { return d.uid === '\(uid)'; })") == true
            }
            #expect(added)
            harness.expectTrue("_added.filter(function(d) { return d.uid === '\(uid)'; })[0].isDevice")

            AudioHardwareDestroyAggregateDevice(aggregateID)
            destroyed = true
            let removed = await harness.waitForAsync(timeout: 3.0) {
                harness.evalBool("_removed.some(function(d) { return d.uid === '\(uid)'; })") == true
            }
            #expect(removed)
            harness.eval("var _removedInfo = _removed.filter(function(d) { return d.uid === '\(uid)'; })[0];")
            #expect(harness.evalString("_removedInfo.name") == name)
            #expect(harness.evalInt("_removedInfo.id") == Int(aggregateID))
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

        // MARK: - Per-device emitter factory GC survival

        @Test("hs.audiodevice.js per-device emitter factory survives garbage collection of the module wrapper")
        func testDeviceEmitterFactorySurvivesGC() {
            // `makeHarness()` (via `loadModule`) stores the module wrapper permanently as a
            // property of `hs`, which would keep that specific wrapper JS-reachable for the
            // rest of the test and make garbage collection a no-op — defeating the point of
            // this test. `makeUnpinned` instead mirrors what `ModuleRoot.audiodevice` actually
            // does in production: `hs.audiodevice` is a *computed* accessor handing back the
            // same Swift singleton on every access, without any particular JS wrapper for it
            // ever being pinned — letting JavaScriptCore's wrapper cache actually collect an
            // unreferenced wrapper, and running the real `hs.audiodevice.js` (not a
            // reimplementation) against it.
            let (harness, _) = JSTestHarness.makeUnpinned(HSAudioDeviceModule.self, as: "audiodevice")
            #expect(harness.evalTypeOf("hs.audiodevice._makeDeviceEmitter") == "function")

            // Nothing above stored the wrapper `hs.audiodevice` resolved to while running that
            // script, so it's now eligible for collection. If the factory were still a bare JS
            // expando (the pre-fix bug) rather than the native `_makeDeviceEmitter` property, it
            // would live on that now-collectible wrapper and be lost; a subsequent
            // `hs.audiodevice` access would return a fresh wrapper without it.
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.audiodevice._makeDeviceEmitter") == "function")
            // Confirm the survivor is a genuine, working LazyWatcherEmitter, not just any
            // object shaped like one.
            harness.expectTrue("""
            (function() {
                var e = hs.audiodevice._makeDeviceEmitter({ _addWatcher: function() {}, _removeWatcher: function() {} });
                return typeof e.on === 'function' && typeof e.off === 'function' && typeof e.once === 'function';
            })()
        """)
        }

        @Test("per-device on() finds its emitter factory after the hs.audiodevice module wrapper is collected")
        func testDeviceOnSurvivesModuleWrapperGC() {
            // hs.audiodevice exposed as a computed accessor (see makeUnpinned), not a stored
            // value, so no particular JS wrapper for the module is kept reachable.
            let (harness, _) = JSTestHarness.makeUnpinned(HSAudioDeviceModule.self, as: "audiodevice")

            harness.eval("var __gcTestDevice = hs.audiodevice.all()[0];")
            #expect(!harness.hasException)

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            // HSAudioDevice.on() re-fetches `hs.audiodevice` from JS on every call and reads
            // `_makeDeviceEmitter` off whatever wrapper it finds there — which, after a GC pass
            // with no wrapper pinned, could be a fresh one. That's only safe because the factory
            // is the native `_makeDeviceEmitter` property (Swift-object-backed, so any wrapper
            // for the same object exposes it) rather than a JS expando (wrapper-local, and lost
            // when that specific wrapper is collected) — so a real end-to-end on()/off() cycle
            // must still succeed here.
            harness.eval("""
            var fn = function() {};
            __gcTestDevice.on('vmout', fn);
            __gcTestDevice.off('vmout', fn);
        """)
            #expect(!harness.hasException)
        }
    }
}

// MARK: - Garbage collection (issue #267)

extension HSAudioDeviceTests.HSAudioDeviceIntegrationTests {
    // A watching device is also kept alive by its own emitter (its _watcherEmitter's start
    // closure captures the device, a cycle _removeWatcher() breaks), so the first half holds
    // even without the tracker; the second half is what catches a device that never un-pins.
    @Test("A watching device the caller didn't keep survives garbage collection, and is collected once the watcher is removed")
    func testWatchingDeviceLifetime() throws {
        let harness = makeHarness()
        weak var device: HSAudioDevice?
        autoreleasepool {
            harness.eval("var d = hs.audiodevice.defaultOutputDevice() || hs.audiodevice.all()[0]; d.on('vmout', function() {}); void 0")
            device = harness.evalValue("d")?.toObjectOf(HSAudioDevice.self) as? HSAudioDevice
            harness.eval("d = null; void 0")
        }
        #expect(!harness.hasException)
        harness.collectGarbage()
        #expect(device != nil, "A watching device must not be collected")

        autoreleasepool { device?._removeWatcher() }
        harness.collectGarbage()
        #expect(device == nil, "A device with no watcher must not be kept alive")
    }
}

// MARK: - JSON Serialization

extension HSAudioDeviceTests {
    @Suite("hs.audiodevice JSON serialization", .disabled(if: hasNoAudioDevices(), "No audio hardware present"))
    struct HSAudioDeviceJSONTests {
        @Test("JSON.stringify() of a device includes its identity and state")
        func testDeviceToJSON() {
            let harness = JSTestHarness()
            harness.loadModule(HSAudioDeviceModule.self, as: "audiodevice")

            harness.eval("""
                var d = hs.audiodevice.all()[0];
                var parsed = JSON.parse(JSON.stringify(d));
                """)
            harness.expectTrue("parsed.id === d.id && parsed.name === d.name && parsed.uid === d.uid")
            harness.expectTrue("parsed.isInput === d.isInput && parsed.isOutput === d.isOutput")
            harness.expectTrue("parsed.transportType === d.transportType")
            // Unsupported values must survive as null rather than vanishing from the output
            harness.expectTrue("'volume' in parsed && (parsed.volume === null || typeof parsed.volume === 'number')")
            harness.expectTrue("'sampleRate' in parsed && (parsed.sampleRate === null || typeof parsed.sampleRate === 'number')")
            #expect(!harness.hasException)
        }
    }
}
