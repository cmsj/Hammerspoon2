//
//  HSMenuBarModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - JavaScript API Protocol

/// Module for creating and managing macOS system menu bar items.
///
/// Menu bar items appear in the right side of the macOS menu bar (alongside the clock, Wi-Fi icon, etc.).
/// Each item can display a title, an icon, or both, and can open a menu or invoke a callback when clicked.
///
/// ## Creating a simple title item
///
/// ```js
/// const item = hs.menubar.create()
/// item.setTitle("Hello")
/// item.setClickCallback(() => console.log("clicked!"))
/// ```
///
/// ## Creating an icon item with a static menu
///
/// ```js
/// const item = hs.menubar.create()
/// item.setIcon(HSImage.fromSymbol("star.fill"))
/// item.setTooltip("My automation")
/// item.setMenu([
///     { title: "Reload config", fn: () => hs.reload() },
///     { title: "-" },
///     { title: "Remove item", fn: () => item.destroy() }
/// ])
/// ```
///
/// ## Creating an item with a dynamic menu
///
/// ```js
/// const item = hs.menubar.create()
/// item.setTitle("Dynamic")
/// item.setMenu(() => [
///     { title: "Time: " + new Date().toLocaleTimeString() },
///     { title: "-" },
///     { title: "Close", fn: () => item.destroy() }
/// ])
/// ```
@objc protocol HSMenuBarModuleAPI: JSExport {
    /// Create a new menu bar item
    /// - Parameter hidden?: Pass true to create the item hidden (not shown in the menu bar). Defaults to false (immediately visible).
    /// - Returns: A new HSMenuBarItem
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// const hidden = hs.menubar.create(true)  // not shown yet
    /// hidden.setTitle("Ready")
    /// hidden.show()
    /// ```
    @objc func create(_ hidden: Bool) -> HSMenuBarItem
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSMenuBarModule: NSObject, HSModuleAPI, HSMenuBarModuleAPI {
    var name = "hs.menubar"
    let engineID: UUID

    private var items = HSWeakObjectSet<HSMenuBarItem>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for item in items.allObjects {
            item.destroy()
        }
        items.removeAllObjects()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    @objc func create(_ hidden: Bool) -> HSMenuBarItem {
        let item = HSMenuBarItem(inMenuBar: !hidden)
        items.add(item)
        return item
    }
}
