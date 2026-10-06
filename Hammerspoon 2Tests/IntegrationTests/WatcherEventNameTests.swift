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
///
/// This deliberately holds no module metatype: under default MainActor isolation the
/// `HSFooModule: HSModuleAPI` conformances are MainActor-isolated, and Swift 6.2 rejects
/// using them in the nonisolated `cases` initializer. `WatcherEventNameTests.moduleTypes`
/// maps `module` back to its type on the MainActor instead.
nonisolated struct WatcherEventNameCase: CustomTestStringConvertible, Sendable {
    let module: String
    let expectedNames: [String]
    let typo: String
    /// JS expression that's true when no native watcher has been started and no listener recorded
    let nothingStarted: String

    var testDescription: String { "hs." + module }

    init(_ module: String, _ expectedNames: [String], typo: String, nothingStarted: String? = nil) {
        self.module = module
        self.expectedNames = expectedNames
        self.typo = typo
        self.nothingStarted = nothingStarted ?? "hs.\(module)._watcherEmitter._listenerCount === 0"
    }
}

@Suite("Watcher event name validation tests")
struct WatcherEventNameTests {

    nonisolated static let cases: [WatcherEventNameCase] = [
        .init("application",
              ["willLaunch", "didLaunch", "didTerminate", "didHide", "didUnhide", "didActivate", "didDeactivate"],
              typo: "didlaunch"),
        .init("audiodevice", ["dOut", "dIn", "dSErr", "dev+", "dev-"], typo: "dev-added"),
        .init("camera", ["connected", "disconnected"], typo: "connect"),
        .init("streamdeck", ["connected", "disconnected"], typo: "disconnect"),
        .init("serial", ["added", "removed"], typo: "add"),
        .init("usb", ["added", "removed"], typo: "remove"),
        .init("keycodes", ["change"], typo: "changed"),
        .init("locale", ["change"], typo: "changed"),
        .init("pasteboard", ["change"], typo: "changed"),
        .init("screen", ["change"], typo: "changed"),
        .init("power",
              ["screensDidSleep", "screensDidWake", "screensDidLock", "screensDidUnlock",
               "screensaverDidStart", "screensaverDidStop", "screensaverWillStop",
               "systemWillSleep", "systemDidWake", "systemWillPowerOff",
               "sessionDidBecomeActive", "sessionDidResignActive", "change"],
              typo: "chnage",
              nothingStarted: "hs.power._eventWatcherEmitter._listenerCount === 0 && hs.power._batteryWatcherEmitter._listenerCount === 0"),
        .init("wifi",
              ["powerChange", "ssidChange", "bssidChange", "countryCodeChange", "linkChange",
               "linkQualityChange", "modeChange", "scanCacheUpdated"],
              typo: "ssidChanged",
              nothingStarted: "Object.keys(hs.wifi._watcherEmitter.events).length === 0"),
    ]

    private static let moduleTypes: [String: any HSModuleAPI.Type] = [
        "application": HSApplicationModule.self,
        "audiodevice": HSAudioDeviceModule.self,
        "camera": HSCameraModule.self,
        "streamdeck": HSStreamDeckModule.self,
        "serial": HSSerialModule.self,
        "usb": HSUSBModule.self,
        "keycodes": HSKeycodesModule.self,
        "locale": HSLocaleModule.self,
        "pasteboard": HSPasteboardModule.self,
        "screen": HSScreenModule.self,
        "power": HSPowerModule.self,
        "wifi": HSWifiModule.self,
    ]

    private func makeHarness(_ testCase: WatcherEventNameCase) throws -> JSTestHarness {
        let harness = JSTestHarness()
        let moduleType = try #require(Self.moduleTypes[testCase.module], "no module type for hs.\(testCase.module)")
        harness.loadModule(moduleType, as: testCase.module)
        return harness
    }

    @Test("_eventNames lists exactly the events the module emits", arguments: cases)
    func testEventNames(_ testCase: WatcherEventNameCase) throws {
        let harness = try makeHarness(testCase)
        let names = harness.evalValue("hs.\(testCase.module)._eventNames")?.toArray() as? [String]
        #expect(names == testCase.expectedNames)
    }

    @Test("on() with an unknown event throws, lists the known events, and starts nothing", arguments: cases)
    func testOnRejectsUnknownEvent(_ testCase: WatcherEventNameCase) throws {
        let harness = try makeHarness(testCase)
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
    func testOnceRejectsUnknownEvent(_ testCase: WatcherEventNameCase) throws {
        let harness = try makeHarness(testCase)
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
