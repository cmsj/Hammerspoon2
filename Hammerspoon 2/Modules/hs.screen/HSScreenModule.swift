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
/// const all    = hs.screen.allScreens();   // [HSScreen, ...]
/// const main   = hs.screen.mainScreen();   // screen containing the focused window
/// const primary = hs.screen.primaryScreen(); // screen with the global menu bar
/// ```
///
/// ## Navigation
///
/// ```javascript
/// const right = hs.screen.mainScreen().toEast();
/// if (right) console.log("Screen to the right:", right.name);
/// ```
///
/// ## Display modes
///
/// ```javascript
/// const s = hs.screen.primaryScreen();
/// console.log(s.currentMode());
/// // → { width: 1440, height: 900, scale: 2, frequency: 60 }
///
/// s.setMode(1920, 1080, 1, 60);
/// ```
///
/// ## Screenshots
///
/// ```javascript
/// const img = hs.screen.mainScreen().snapshot();
/// if (img) img.saveToFile("/tmp/screen.png");
/// ```
@objc protocol HSScreenModuleAPI: JSExport {
    /// All connected screens.
    @objc func allScreens() -> [HSScreen]

    /// The screen that currently contains the focused window, or the screen
    /// with the keyboard focus if no window is focused.
    ///
    /// Returns `null` if no main screen can be determined.
    @objc func mainScreen() -> HSScreen?

    /// The primary display — the one that contains the global menu bar.
    @objc func primaryScreen() -> HSScreen
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSScreenModule: NSObject, HSModuleAPI, HSScreenModuleAPI {
    var name = "hs.screen"

    override required init() { super.init() }

    func shutdown() {}

    @objc func allScreens() -> [HSScreen] {
        NSScreen.screens.map { HSScreen(screen: $0) }
    }

    @objc func mainScreen() -> HSScreen? {
        guard let main = NSScreen.main else { return nil }
        return HSScreen(screen: main)
    }

    @objc func primaryScreen() -> HSScreen {
        // NSScreen.screens[0] is always the primary display on macOS.
        HSScreen(screen: NSScreen.screens[0])
    }
}
