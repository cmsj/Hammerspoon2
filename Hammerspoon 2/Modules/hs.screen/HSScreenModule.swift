//
//  HSScreenModule.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

// MARK: - JavaScript API

/// Inspect and control the displays attached to the system.
///
/// ## Obtaining screens
///
/// ```javascript
/// const all    = hs.screen.all();   // [HSScreen, ...]
/// const main   = hs.screen.main();   // screen containing the focused window
/// const primary = hs.screen.primary(); // screen with the global menu bar
/// ```
///
/// ## Navigation
///
/// ```javascript
/// const right = hs.screen.main().toEast();
/// if (right) console.log("Screen to the right:", right.name);
/// ```
///
/// ## Display modes
///
/// ```javascript
/// const s = hs.screen.primary();
/// console.log(s.mode);
/// // → { width: 1440, height: 900, scale: 2, frequency: 60 }
///
/// s.setMode(1920, 1080, 1, 60);
/// ```
///
/// ## Screenshots
///
/// ```javascript
/// const img = await hs.screen.main().snapshot();
/// img.saveToFile("/tmp/screen.png");
/// ```
///
/// ## Watching for display changes
///
/// ```javascript
/// hs.screen.addWatcher(() => {
///     console.log("Display configuration changed:", hs.screen.all().length, "screens");
/// });
/// ```
@objc protocol HSScreenModuleAPI: JSExport {
    /// All connected screens.
    /// - Returns: An array of HSScreen objects
    /// - Example:
    /// ```js
    /// const screens = hs.screen.all()
    /// screens.forEach(s => console.log(s.name))
    /// ```
    @objc func all() -> [HSScreen]

    /// The screen that currently contains the focused window, or the screen
    /// with the keyboard focus if no window is focused.
    ///
    /// - Returns: An HSScreen object or `null` if no main screen can be determined.
    /// - Example:
    /// ```js
    /// const main = hs.screen.main()
    /// console.log(main && main.name)
    /// ```
    @objc func main() -> HSScreen?

    /// The primary display — the one that contains the global menu bar.
    ///
    /// - Returns: An HSScreen object or `null` if no primary screen can be determined.
    /// - Example:
    /// ```js
    /// const s = hs.screen.primary()
    /// console.log(s && s.frame)
    /// ```
    @objc func primary() -> HSScreen?

    // MARK: Watcher (Pattern A)

    /// Registers a listener that fires whenever the display configuration changes —
    /// monitors connected/disconnected, resolution or arrangement changed, or the
    /// menu bar moved to a different display.
    ///
    /// The listener receives no arguments; call `all()`/`main()`/`primary()` inside
    /// the callback to inspect the new configuration.
    ///
    /// The OS notification subscription starts lazily on the first listener and
    /// is released automatically when the last listener is removed.
    /// - Parameter listener: {() => void} A function called with no arguments when the display configuration changes.
    /// - Example:
    /// ```js
    /// hs.screen.addWatcher(() => {
    ///     console.log("Screens changed, now: " + hs.screen.all().length)
    /// })
    /// ```
    @objc func addWatcher(_ listener: JSFunction)

    /// Removes a previously registered display-configuration listener.
    /// - Parameter listener: The function originally passed to `addWatcher`.
    /// - Example:
    /// ```js
    /// const handler = () => console.log("screens changed")
    /// hs.screen.addWatcher(handler)
    /// hs.screen.removeWatcher(handler)
    /// ```
    @objc func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSScreenModule: NSObject, HSModuleAPI, HSScreenModuleAPI {
    var moduleName = "hs.screen"
    let engineID: UUID

    @objc var _watcherEmitter: JSFunction? = nil
    private var watcherCallback: JSFunction?
    private var watcherObserver: NSObjectProtocol?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = all().count
        return "<\(moduleName): \(n) display\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func all() -> [HSScreen] {
        NSScreen.screens.map { HSScreen(screen: $0) }
    }

    @objc func main() -> HSScreen? {
        guard let main = NSScreen.main else { return nil }
        return HSScreen(screen: main)
    }

    @objc func primary() -> HSScreen? {
        // NSScreen.screens[0] is always the primary display on macOS.
        guard let primary = NSScreen.screens.first else { return nil }
        return HSScreen(screen: primary)
    }

    // MARK: - Watcher (Pattern A)

    @objc func addWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard watcherCallback == nil else {
            AKWarning("hs.screen._addWatcher: already watching — refusing second subscription")
            return
        }
        watcherCallback = callback

        watcherObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireWatcherEvent() }
        }

        AKTrace("hs.screen._addWatcher: started")
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }

        if let observer = watcherObserver {
            NotificationCenter.default.removeObserver(observer)
            watcherObserver = nil
        }
        watcherCallback = nil

        AKTrace("hs.screen._removeWatcher: stopped")
    }

    private func fireWatcherEvent() {
        _ = watcherCallback?.call(withArguments: [])
    }
}
