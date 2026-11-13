//
//  TestExtension.swift
//  Hammerspoon 2 Test Extension
//
//  A third-party extension, built the way anyone else's would be: compiled against the
//  HammerspoonSDK framework, with no access to the app's own code. The extension tests load it
//  with `require('ext:hs2.testextension')`.
//
//  build-test-extension.sh (next to this file) compiles it into a bundle, and the test target's
//  "Build Test Extension" phase runs that script.
//
//  This folder belongs to the test target, which compiles every Swift file in it.
//  TEST_EXTENSION is only set by build-test-extension.sh, so the test bundle gets nothing from
//  this file.
//

#if TEST_EXTENSION

import Foundation
import JavaScriptCore
import HammerspoonSDK

/// The extension's API, as JavaScript sees it. JavaScript runs on the main thread, and the SDK's
/// protocols are main-actor isolated, so this is too.
@MainActor
@objc protocol HS2TestExtensionAPI: JSExport {
    /// Adds two numbers
    @objc func add(_ a: Double, _ b: Double) -> Double

    /// Always returns nil, which should reach JavaScript as null
    @objc func nothing() -> HSColor?

    /// A colour, made with one of the SDK's shared types
    @objc func red() -> HSColor

    /// Makes a ticker that calls `callback` every `interval` seconds once it's started
    @objc func makeTicker(_ interval: Double, _ callback: JSValue) -> HS2TestTicker

    /// Set by the extension's enhancement script
    @objc var greet: JSValue? { get set }
}

/// The extension's module. Its Objective-C name is given explicitly, with a prefix, because the
/// Objective-C class namespace is shared with Hammerspoon 2 and every other extension.
@MainActor
@objc(HS2TestExtensionModule)
final class TestExtensionModule: NSObject, HSModuleAPI, HS2TestExtensionAPI {
    let moduleName = "hs2.testextension"
    let engineID: UUID
    @objc var greet: JSValue?

    private let tickers = HSObjectTracker<HS2TestTicker>()

    init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    func shutdown() {
        tickers.shutdown()
        greet = nil
    }

    func toString() -> String {
        "<\(moduleName)>"
    }

    func add(_ a: Double, _ b: Double) -> Double {
        a + b
    }

    func nothing() -> HSColor? {
        nil
    }

    func red() -> HSColor {
        HSColor.rgb(1, 0, 0, 1)
    }

    func makeTicker(_ interval: Double, _ callback: JSValue) -> HS2TestTicker {
        let ticker = HS2TestTicker(interval: interval, callback: callback, tracker: tickers)
        tickers.add(ticker)
        return ticker
    }
}

/// The ticker's API, as JavaScript sees it
@MainActor
@objc protocol HS2TestTickerAPI: HSTypeAPI, JSExport {
    /// Starts calling back
    @objc @discardableResult func start() -> HS2TestTicker

    /// Stops calling back
    @objc @discardableResult func stop() -> HS2TestTicker

    /// Whether it's calling back
    @objc var isRunning: Bool { get }
}

/// A child object that stays alive while it's running, whether or not JavaScript holds it, using
/// the SDK's `HSObjectTracker` and `JSCallback`.
@MainActor
@objc(HS2TestTicker)
final class HS2TestTicker: NSObject, HS2TestTickerAPI, HSTrackedObject {
    @objc let typeName = "HS2TestTicker"
    private let interval: Double
    private var callback: JSCallback?
    private weak var tracker: HSObjectTracker<HS2TestTicker>?

    private var timer: Timer? {
        didSet { tracker?.setActive(self, timer != nil) }
    }

    init(interval: Double, callback: JSValue, tracker: HSObjectTracker<HS2TestTicker>) {
        self.interval = interval
        self.tracker = tracker
        super.init()
        self.callback = JSCallback(value: callback, owner: self)
    }

    isolated deinit {
        destroy()
    }

    func destroy() {
        stop()
        callback?.detach(from: self)
        callback = nil
    }

    func toString() -> String {
        "<HS2TestTicker \(isRunning ? "running" : "stopped")>"
    }

    var isRunning: Bool {
        timer != nil
    }

    @discardableResult func start() -> HS2TestTicker {
        guard timer == nil else { return self }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.callback?.call(withArguments: [])
            }
        }
        return self
    }

    @discardableResult func stop() -> HS2TestTicker {
        timer?.invalidate()
        timer = nil
        return self
    }
}

#endif
