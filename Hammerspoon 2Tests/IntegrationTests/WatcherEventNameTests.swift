//
//  WatcherEventNameTests.swift
//  Hammerspoon 2Tests
//
//  Every watcher module's on()/once() must reject an event name it can never emit, rather than
//  registering a listener that silently never fires (#253). One parameterized test per module
//  checks both halves: the module's Swift-side `_eventNames` list, and that a misspelt name
//  throws before the native watcher is started.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// One watcher module's expected event names, plus a plausible typo of one of them.
nonisolated struct WatcherEventNameCase: CustomTestStringConvertible, Sendable {
    let moduleType: any HSModuleAPI.Type
    let module: String
    let expectedNames: [String]
    let typo: String
    /// JS expression that's true when no native watcher has been started and no listener recorded
    let nothingStarted: String

    var testDescription: String { "hs." + module }

    init(_ moduleType: any HSModuleAPI.Type, _ module: String, _ expectedNames: [String], typo: String, nothingStarted: String? = nil) {
        self.moduleType = moduleType
        self.module = module
        self.expectedNames = expectedNames
        self.typo = typo
        self.nothingStarted = nothingStarted ?? "hs.\(module)._watcherEmitter._listenerCount === 0"
    }
}

@Suite("Watcher event name validation tests")
struct WatcherEventNameTests {

    nonisolated static let cases: [WatcherEventNameCase] = [
        .init(HSApplicationModule.self, "application",
              ["willLaunch", "didLaunch", "didTerminate", "didHide", "didUnhide", "didActivate", "didDeactivate"],
              typo: "didlaunch"),
        .init(HSAudioDeviceModule.self, "audiodevice", ["dOut", "dIn", "dSErr", "dev+", "dev-"], typo: "dev-added"),
        .init(HSCameraModule.self, "camera", ["connected", "disconnected"], typo: "connect"),
        .init(HSStreamDeckModule.self, "streamdeck", ["connected", "disconnected"], typo: "disconnect"),
        .init(HSSerialModule.self, "serial", ["added", "removed"], typo: "add"),
        .init(HSUSBModule.self, "usb", ["added", "removed"], typo: "remove"),
        .init(HSKeycodesModule.self, "keycodes", ["change"], typo: "changed"),
        .init(HSLocaleModule.self, "locale", ["change"], typo: "changed"),
        .init(HSPasteboardModule.self, "pasteboard", ["change"], typo: "changed"),
        .init(HSScreenModule.self, "screen", ["change"], typo: "changed"),
        .init(HSPowerModule.self, "power",
              ["screensDidSleep", "screensDidWake", "screensDidLock", "screensDidUnlock",
               "screensaverDidStart", "screensaverDidStop", "screensaverWillStop",
               "systemWillSleep", "systemDidWake", "systemWillPowerOff",
               "sessionDidBecomeActive", "sessionDidResignActive", "change"],
              typo: "chnage",
              nothingStarted: "hs.power._eventWatcherEmitter._listenerCount === 0 && hs.power._batteryWatcherEmitter._listenerCount === 0"),
        .init(HSWifiModule.self, "wifi",
              ["powerChange", "ssidChange", "bssidChange", "countryCodeChange", "linkChange",
               "linkQualityChange", "modeChange", "scanCacheUpdated"],
              typo: "ssidChanged",
              nothingStarted: "Object.keys(hs.wifi._watcherEmitter.events).length === 0"),
    ]

    private func makeHarness(_ testCase: WatcherEventNameCase) -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(testCase.moduleType, as: testCase.module)
        return harness
    }

    @Test("_eventNames lists exactly the events the module emits", arguments: cases)
    func testEventNames(_ testCase: WatcherEventNameCase) {
        let harness = makeHarness(testCase)
        let names = harness.evalValue("hs.\(testCase.module)._eventNames")?.toArray() as? [String]
        #expect(names == testCase.expectedNames)
    }

    @Test("on() with an unknown event throws, lists the known events, and starts nothing", arguments: cases)
    func testOnRejectsUnknownEvent(_ testCase: WatcherEventNameCase) {
        let harness = makeHarness(testCase)
        harness.eval("""
            var fn = function() {};
            var message = null;
            try {
                hs.\(testCase.module).on('\(testCase.typo)', fn);
            } catch (err) {
                message = err.message;
            }
        """)
        #expect(!harness.hasException)
        let message = harness.evalString("message")
        #expect(message?.contains("unknown event '\(testCase.typo)'") == true, "got: \(message ?? "nil")")
        #expect(message?.contains(testCase.expectedNames.joined(separator: ", ")) == true, "got: \(message ?? "nil")")
        #expect(harness.evalBool(testCase.nothingStarted) == true)
    }

    @Test("once() with an unknown event throws and starts nothing", arguments: cases)
    func testOnceRejectsUnknownEvent(_ testCase: WatcherEventNameCase) {
        let harness = makeHarness(testCase)
        harness.eval("""
            var threw = false;
            try {
                hs.\(testCase.module).once('\(testCase.typo)', function() {});
            } catch (err) {
                threw = true;
            }
        """)
        #expect(!harness.hasException)
        #expect(harness.evalBool("threw") == true)
        #expect(harness.evalBool(testCase.nothingStarted) == true)
    }
}
