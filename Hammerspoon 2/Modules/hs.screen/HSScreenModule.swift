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
/// console.log(s.currentMode());
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
@objc protocol HSScreenModuleAPI: JSExport {
    /// All connected screens.
    /// - Returns: An array of HSScreen objects
    @objc func all() -> [HSScreen]

    /// The screen that currently contains the focused window, or the screen
    /// with the keyboard focus if no window is focused.
    ///
    /// - Returns: An HSScreen object or `null` if no main screen can be determined.
    @objc func main() -> HSScreen?

    /// The primary display — the one that contains the global menu bar.
    ///
    /// - Returns: An HSScreen object or `null` if no primary screen can be determined.
    @objc func primary() -> HSScreen?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSScreenModule: NSObject, HSModuleAPI, HSScreenModuleAPI {
    var name = "hs.screen"

    override required init() { super.init() }

    func shutdown() {}

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
}
