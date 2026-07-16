//
//  HSMenuBarItem.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

// MARK: - JavaScript API Protocol

/// Object representing a macOS system menu bar item.
/// Create instances with `hs.menubar.create()`.
@objc protocol HSMenuBarItemAPI: HSTypeAPI, JSExport {
    /// Set the icon displayed in the menu bar
    /// - Parameter image: An HSImage object, or null to remove the icon
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.setIcon(HSImage.fromSymbol("star.fill"))
    /// ```
    @objc func setIcon(_ image: HSImage?)

    /// Set the tooltip shown when hovering over the menu bar item
    /// - Parameter tooltip: Tooltip text, or null to remove the tooltip
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.setTooltip("My menu bar item")
    /// ```
    @objc func setTooltip(_ tooltip: String?)

    /// Set a callback invoked when the item is clicked (only fires when no menu is set)
    /// - Parameter fn: {(() => void) | null} A function to call on click, or null to remove the callback
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Click me"
    /// item.setClickCallback(() => console.log("clicked!"))
    /// ```
    @objc func setClickCallback(_ fn: JSFunction)

    /// Set the menu for this item. Pass an array of menu item objects for a static menu,
    /// or a function that returns an array for a dynamic menu populated each time it opens.
    ///
    /// Menu item object keys:
    /// - `title` (string, required): The item label. Use `"-"` for a separator line.
    /// - `fn` (function): Callback invoked when the item is chosen.
    /// - `checked` (boolean): If true, a checkmark is shown next to the item.
    /// - `disabled` (boolean): If true, the item is greyed out and cannot be chosen.
    /// - `tooltip` (string): Tooltip shown when hovering over the item.
    /// - `icon` (HSImage): Icon shown to the left of the title.
    /// - `menu` (array): Nested array of menu item objects to create a submenu.
    ///
    /// - Parameter menuOrFn: {Array<Record<string, any>> | (() => Array<Record<string, any>>) | null} Array of menu item objects, a function returning such an array, or null to remove the menu
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Menu"
    /// item.setMenu([
    ///     { title: "Option A", fn: () => console.log("A") },
    ///     { title: "-" },
    ///     { title: "Option B", checked: true, fn: () => console.log("B") }
    /// ])
    /// ```
    @objc func setMenu(_ menuOrFn: JSValue)

    /// Remove this item from the menu bar. The item is retained and can be shown again with show().
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.hide()
    /// ```
    @objc func hide()

    /// Show this item in the menu bar.
    /// - Example:
    /// ```js
    /// item.show()
    /// ```
    @objc func show()

    /// Check if this item is currently visible in the menu bar.
    /// - Returns: true if the item is visible in the menu bar
    /// - Example:
    /// ```js
    /// const visible = item.isVisible()
    /// ```
    @objc func isVisible() -> Bool

    /// Get or set the menu item's title.
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Hello"
    /// console.log(item.title)
    /// ```
    @objc var title: String? { get set }

    /// Permanently remove this item from the menu bar and release all resources.
    ///
    /// After calling `destroy()`, the item is no longer usable.
    /// This is called automatically on `hs.reload()`. Use `hide()` instead
    /// if you only want to temporarily remove the item without freeing it.
    ///
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSMenuBarItem: NSObject, HSMenuBarItemAPI {
    @objc var typeName = "HSMenuBarItem"

    private var statusItem: NSStatusItem?
    private var _title: String?
    private var _icon: NSImage?
    private var _clickCallback: JSCallback?
    private var _menuCallback: JSCallback?
    private var menuDelegate: MenuBarDelegate?
    private var menuItemHandlers: [MenuItemHandler] = []

    init(inMenuBar: Bool) {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = inMenuBar
        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked)
        statusItem = item
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSMenuBarItem")
    }

    @objc func destroy() {
        clearMenuHandlers()
        _clickCallback?.detach(from: self)
        _clickCallback = nil
        _menuCallback?.detach(from: self)
        _menuCallback = nil
        menuDelegate = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Button click

    @objc private func statusButtonClicked() {
        guard let callback = _clickCallback?.value else { return }
        callback.call(withArguments: [])
        logJSException(from: callback, context: "click callback")
    }

    // MARK: - API

    @objc func setIcon(_ imageValue: HSImage?) {
        guard let imageValue else {
            _icon = nil
            updateButton()
            return
        }
        _icon = imageValue.image

        updateButton()
    }

    @objc func setTooltip(_ tooltipValue: String?) {
        statusItem?.button?.toolTip = tooltipValue
    }

    @objc func setClickCallback(_ fnValue: JSFunction) {
        _clickCallback?.detach(from: self)
        if fnValue.isNull || fnValue.isUndefined || !fnValue.isObject {
            _clickCallback = nil
        } else {
            _clickCallback = JSCallback(value: fnValue, owner: self)
        }
    }

    @objc func setMenu(_ menuOrFn: JSValue) {
        _menuCallback?.detach(from: self)
        _menuCallback = nil
        menuDelegate = nil

        if menuOrFn.isNull || menuOrFn.isUndefined {
            statusItem?.menu = nil
            clearMenuHandlers()
        } else if menuOrFn.isArray {
            let menu = buildStaticMenu(from: menuOrFn)
            statusItem?.menu = menu
        } else if menuOrFn.isObject {
            _menuCallback = JSCallback(value: menuOrFn, owner: self)
            let menu = NSMenu()
            menu.autoenablesItems = false
            let delegate = MenuBarDelegate(item: self)
            menuDelegate = delegate
            menu.delegate = delegate
            statusItem?.menu = menu
        } else {
            AKError("hs.menubar.setMenu: Expected an array, function, or null")
        }
    }

    @objc func hide() {
        statusItem?.isVisible = false
    }

    @objc func show() {
        statusItem?.isVisible = true
    }

    @objc func isVisible() -> Bool {
        return statusItem?.isVisible ?? false
    }

    @objc var title: String? {
        get { return _title }
        set {
            if newValue == "" {
                _title = nil
            } else {
                _title = newValue
            }
            updateButton()
        }
    }

    // MARK: - Dynamic menu population (called by delegate)

    func populateDynamicMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        clearMenuHandlers()

        guard let callbackValue = _menuCallback?.value else { return }
        let result = callbackValue.call(withArguments: [])

        logJSException(from: callbackValue, context: "menu callback")

        guard let result, result.isArray else {
            AKError("hs.menubar: Menu callback must return an array")
            return
        }

        for item in buildNSMenuItems(from: result) {
            menu.addItem(item)
        }
    }

    // MARK: - Private helpers

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        if let icon = _icon {
            button.image = icon
            if let title = _title, !title.isEmpty {
                button.imagePosition = .imageLeft
                button.title = title
            } else {
                button.imagePosition = .imageOnly
                button.title = ""
            }
        } else if let title = _title, !title.isEmpty {
            button.image = nil
            button.title = title
        } else {
            button.image = nil
            button.title = "?"
        }
    }

    private func clearMenuHandlers() {
        for handler in menuItemHandlers {
            handler.detach(from: self)
        }
        menuItemHandlers.removeAll()
    }

    private func buildStaticMenu(from jsArray: JSValue) -> NSMenu {
        clearMenuHandlers()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in buildNSMenuItems(from: jsArray) {
            menu.addItem(item)
        }
        return menu
    }

    private func buildNSMenuItems(from jsArray: JSValue) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let count = Int(jsArray.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        for i in 0..<count {
            if let jsItem = jsArray.objectAtIndexedSubscript(i),
               let item = buildNSMenuItem(from: jsItem) {
                items.append(item)
            }
        }
        return items
    }

    private func buildNSMenuItem(from jsItem: JSValue) -> NSMenuItem? {
        guard let titleValue = jsItem.objectForKeyedSubscript("title"),
              !titleValue.isUndefined,
              let title = titleValue.toString() else { return nil }

        if title == "-" || title == "---" {
            return NSMenuItem.separator()
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        let disabled: Bool
        if let dv = jsItem.objectForKeyedSubscript("disabled"), dv.isBoolean {
            disabled = dv.toBool()
        } else {
            disabled = false
        }
        item.isEnabled = !disabled

        if let cv = jsItem.objectForKeyedSubscript("checked"), cv.isBoolean, cv.toBool() {
            item.state = .on
        } else {
            item.state = .off
        }

        if let tv = jsItem.objectForKeyedSubscript("tooltip"),
           !tv.isUndefined, !tv.isNull,
           let tip = tv.toString() {
            item.toolTip = tip
        }

        if let iv = jsItem.objectForKeyedSubscript("icon"),
           let hsImage = iv.toObjectOf(HSImage.self) as? HSImage,
           let img = hsImage.image.copy() as? NSImage {
            img.size = NSSize(width: 16, height: 16)
            item.image = img
        }

        if let fv = jsItem.objectForKeyedSubscript("fn"),
           fv.isObject, !fv.isNull, !fv.isUndefined {
            let handler = MenuItemHandler(value: fv, owner: self)
            menuItemHandlers.append(handler)
            item.target = handler
            item.action = #selector(MenuItemHandler.invoke(_:))
            item.isEnabled = !disabled
        }

        if let sv = jsItem.objectForKeyedSubscript("menu"), sv.isArray {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for subItem in buildNSMenuItems(from: sv) {
                submenu.addItem(subItem)
            }
            item.submenu = submenu
        }

        return item
    }

    private func logJSException(from value: JSValue, context label: String) {
        guard let ctx = value.context,
              let exception = ctx.exception,
              !exception.isUndefined else { return }
        AKError("hs.menubar: Error in \(label): \(exception.toString() ?? "unknown error")")
        ctx.exception = nil
    }
}

// MARK: - Menu Delegate

private class MenuBarDelegate: NSObject, NSMenuDelegate {
    weak var item: HSMenuBarItem?

    init(item: HSMenuBarItem) {
        self.item = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            item?.populateDynamicMenu(menu)
        }
    }
}

// MARK: - Menu Item Handler

@MainActor
private class MenuItemHandler: NSObject {
    private var callback: JSCallback?

    init(value: JSValue, owner: AnyObject) {
        self.callback = JSCallback(value: value, owner: owner)
        super.init()
    }

    func detach(from owner: AnyObject) {
        callback?.detach(from: owner)
        callback = nil
    }

    @objc func invoke(_ sender: Any?) {
        guard let value = callback?.value else { return }
        value.call(withArguments: [])
        if let ctx = value.context,
           let exception = ctx.exception,
           !exception.isUndefined {
            AKError("hs.menubar: Error in menu item callback: \(exception.toString() ?? "unknown error")")
            ctx.exception = nil
        }
    }
}
