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

    /// Set a callback invoked when the item is clicked with any mouse button (only fires when no menu is set).
    ///
    /// The callback receives two arguments:
    /// - `button` (string): `"left"`, `"right"` or `"middle"`, or `"buttonN"` for other buttons, numbered
    ///   from 1 (so a mouse's fourth and fifth buttons are `"button4"` and `"button5"`). A Ctrl-click, the
    ///   standard macOS secondary click, is reported as `"right"` (and `modifiers` still includes `"ctrl"`).
    /// - `modifiers` (string[]): The modifier keys held during the click, in the same form as
    ///   `hs.eventtap.currentModifiers()` (e.g. `["cmd", "leftCmd"]`).
    ///
    /// To offer a menu alongside a click action, leave the menu unset and call `popUpMenu()` from this callback.
    ///
    /// - Parameter fn: {((button: string, modifiers: string[]) => void) | null} A function to call on click, or null to remove the callback
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Click me"
    /// item.setClickCallback((button, modifiers) => {
    ///     if (button === "right") {
    ///         item.popUpMenu([{ title: "Quit", fn: () => item.destroy() }])
    ///     } else {
    ///         console.log(`${button} click with ${modifiers.join("+")}`)
    ///     }
    /// })
    /// ```
    @objc func setClickCallback(_ fn: JSFunction)

    /// Set the menu for this item. Pass an array of menu item objects for a static menu,
    /// or a function that returns an array for a dynamic menu populated each time it opens.
    /// The function receives one argument: the modifier keys held when the menu opened, in the same form as
    /// `hs.eventtap.currentModifiers()`.
    ///
    /// While a menu is set, clicking the item opens the menu and the click callback is not called.
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
    /// - Parameter menuOrFn: {Array<Record<string, any>> | ((modifiers: string[]) => Array<Record<string, any>>) | null} Array of menu item objects, a function returning such an array, or null to remove the menu
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Menu"
    /// item.setMenu([
    ///     { title: "Option A", fn: () => console.log("A") },
    ///     { title: "-" },
    ///     { title: "Option B", checked: true, fn: () => console.log("B") }
    /// ])
    ///
    /// // Show extra entries when Option is held
    /// item.setMenu((modifiers) => [
    ///     { title: "Option A", fn: () => console.log("A") },
    ///     ...(modifiers.includes("alt") ? [{ title: "Advanced", fn: () => console.log("advanced") }] : [])
    /// ])
    /// ```
    @objc func setMenu(_ menuOrFn: JSValue)

    /// Immediately open a menu below this item, independently of any menu set with `setMenu()`.
    ///
    /// This is intended to be called from a click callback, so that a single item can perform an action on one
    /// kind of click and offer a menu on another. The menu item objects are the same as for `setMenu()`.
    /// If the item is hidden, the menu opens at the mouse pointer instead.
    ///
    /// - Parameter entries: {Array<Record<string, any>>} Array of menu item objects
    /// - Example:
    /// ```js
    /// const item = hs.menubar.create()
    /// item.title = "Dictate"
    /// item.setClickCallback((button) => {
    ///     if (button === "right") {
    ///         item.popUpMenu([
    ///             { title: "Settings…", fn: () => console.log("settings") },
    ///             { title: "-" },
    ///             { title: "Remove", fn: () => item.destroy() }
    ///         ])
    ///     } else {
    ///         console.log("start dictation")
    ///     }
    /// })
    /// ```
    @objc func popUpMenu(_ entries: JSValue)

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

    @objc func toString() -> String {
        return "<\(typeName): \(_title ?? "untitled")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    private var statusItem: NSStatusItem?
    private var _title: String?
    private var _icon: NSImage?
    private var _clickCallback: JSCallback?
    private var _menuCallback: JSCallback?
    private var menuDelegate: MenuBarDelegate?
    private var menuItemHandlers: [MenuItemHandler] = []
    /// Handlers for the menu most recently opened by popUpMenu(). Kept until the next one opens, so that
    /// they outlive menu tracking however AppKit orders the item action relative to popUp returning.
    private var popUpMenuHandlers: [MenuItemHandler] = []
    /// Event monitors watching for middle and other button clicks, installed while there is a click callback.
    private var otherButtonMonitors: [Any] = []
    /// The button number of an other-button press that began on this item, until it is released.
    private var otherButtonPressed: Int?

    init(inMenuBar: Bool) {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = inMenuBar
        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// The internal object the status item's button sends its action to. Exposed for tests.
    var button: NSStatusBarButton? { statusItem?.button }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSMenuBarItem")
    }

    @objc func destroy() {
        clearMenuHandlers()
        detach(&popUpMenuHandlers)
        _clickCallback?.detach(from: self)
        _clickCallback = nil
        updateOtherButtonMonitoring()
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
        callClickCallback(for: NSApp.currentEvent)
    }

    private func callClickCallback(for event: NSEvent?) {
        guard let callback = _clickCallback?.value else { return }
        callback.call(withArguments: [Self.buttonName(for: event), Self.modifierNames(for: event)])
        logJSException(from: callback, context: "click callback")
    }

    // MARK: - Middle and other button clicks

    // The window server doesn't deliver middle or other button events to status item windows at all: they go
    // to the system's menu bar instead, where a global monitor can see them. A local monitor covers them too,
    // in case they are ever delivered to this app.

    private func updateOtherButtonMonitoring() {
        let wanted = _clickCallback != nil
        if wanted, otherButtonMonitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]
            let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handleOtherButtonEvent(event) }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handleOtherButtonEvent(event) }
                return event
            }
            otherButtonMonitors = [global, local].compactMap { $0 }
        } else if !wanted {
            otherButtonMonitors.forEach(NSEvent.removeMonitor)
            otherButtonMonitors.removeAll()
            otherButtonPressed = nil
        }
    }

    /// Calls the click callback when an other-button press and release both happen over this item.
    func handleOtherButtonEvent(_ event: NSEvent) {
        // As for other clicks, a menu takes over the item and the click callback isn't called
        guard statusItem?.menu == nil, let location = event.cgEvent?.location else { return }
        let isOverItem = itemScreenFrame()?.contains(location) ?? false
        switch event.type {
        case .otherMouseDown:
            otherButtonPressed = isOverItem ? event.buttonNumber : nil
        case .otherMouseUp:
            defer { otherButtonPressed = nil }
            if isOverItem, otherButtonPressed == event.buttonNumber {
                callClickCallback(for: event)
            }
        default:
            break
        }
    }

    /// The item's frame in global display coordinates (top-left origin, as CGEvent locations use), if it is in
    /// the menu bar.
    func itemScreenFrame() -> CGRect? {
        guard statusItem?.isVisible == true,
              let frame = statusItem?.button?.window?.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The name a click callback reports for the button that produced `event`.
    static func buttonName(for event: NSEvent?) -> String {
        guard let event else { return "left" }
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control) ? "right" : "left"
        case .rightMouseDown, .rightMouseUp:
            return "right"
        case .otherMouseDown, .otherMouseUp:
            return event.buttonNumber == 2 ? "middle" : "button\(event.buttonNumber + 1)"
        default:
            // Not a mouse event (e.g. the button was activated through accessibility)
            return "left"
        }
    }

    /// The modifier keys held during `event`, named as `hs.eventtap.currentModifiers()` names them.
    /// Falls back to the current keyboard state when there is no event.
    static func modifierNames(for event: NSEvent?) -> [String] {
        let flags = event?.cgEvent?.flags ?? CGEventSource.flagsState(.combinedSessionState)
        return CGEventFlags.modifierNames(from: flags)
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
        updateOtherButtonMonitoring()
    }

    @objc func setMenu(_ menuOrFn: JSValue) {
        _menuCallback?.detach(from: self)
        _menuCallback = nil
        menuDelegate = nil

        if menuOrFn.isNull || menuOrFn.isUndefined {
            statusItem?.menu = nil
            clearMenuHandlers()
        } else if menuOrFn.isArray {
            clearMenuHandlers()
            var handlers: [MenuItemHandler] = []
            let menu = buildMenu(from: menuOrFn, handlers: &handlers)
            guard store(handlers, in: &menuItemHandlers) else { return }
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

    @objc func popUpMenu(_ entries: JSValue) {
        guard let menu = makePopUpMenu(from: entries) else { return }

        guard let button = statusItem?.button,
              let window = button.window,
              statusItem?.isVisible == true else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }

        // Open where AppKit opens a status item's own menu: just below the item, left-aligned with it.
        let origin = window.frame.origin
        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: origin.x, y: origin.y), in: nil)
        button.highlight(false)
    }

    /// Builds the menu popUpMenu() opens, or returns nil if it can't. Separate from opening it, which is modal,
    /// so tests can check it.
    func makePopUpMenu(from entries: JSValue) -> NSMenu? {
        guard entries.isArray else {
            AKError("hs.menubar.popUpMenu: Expected an array of menu items")
            return nil
        }
        detach(&popUpMenuHandlers)
        var handlers: [MenuItemHandler] = []
        let menu = buildMenu(from: entries, handlers: &handlers)
        guard store(handlers, in: &popUpMenuHandlers) else { return nil }
        return menu
    }

    /// The menu set with setMenu(), if any. Exposed for tests.
    var attachedMenu: NSMenu? { statusItem?.menu }

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
        let result = callbackValue.call(withArguments: [Self.modifierNames(for: NSApp.currentEvent)])

        logJSException(from: callbackValue, context: "menu callback")

        guard let result, result.isArray else {
            AKError("hs.menubar: Menu callback must return an array")
            return
        }

        var handlers: [MenuItemHandler] = []
        let items = buildNSMenuItems(from: result, handlers: &handlers)
        guard store(handlers, in: &menuItemHandlers) else { return }
        for item in items {
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
        detach(&menuItemHandlers)
    }

    /// Stores the handlers for a menu built from JS entries in `list`, returning false if the menu shouldn't be
    /// used. The handlers have to be built into a separate array and stored afterwards, because reading the
    /// entries runs JS, which can destroy this item or set another menu (writing to `list`) meanwhile. Anything
    /// stored in `list` since is detached, and if the item was destroyed, so are the new handlers.
    private func store(_ handlers: [MenuItemHandler], in list: inout [MenuItemHandler]) -> Bool {
        detach(&list)
        guard statusItem != nil else {
            var orphaned = handlers
            detach(&orphaned)
            return false
        }
        list = handlers
        return true
    }

    private func detach(_ handlers: inout [MenuItemHandler]) {
        for handler in handlers {
            handler.detach(from: self)
        }
        handlers.removeAll()
    }

    /// Builds a menu from an array of JS menu item objects, appending the handlers for its items' callbacks
    /// to `handlers`, which must outlive the menu.
    private func buildMenu(from jsArray: JSValue, handlers: inout [MenuItemHandler]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in buildNSMenuItems(from: jsArray, handlers: &handlers) {
            menu.addItem(item)
        }
        return menu
    }

    private func buildNSMenuItems(from jsArray: JSValue, handlers: inout [MenuItemHandler]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let count = Int(jsArray.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        for i in 0..<count {
            if let jsItem = jsArray.objectAtIndexedSubscript(i),
               let item = buildNSMenuItem(from: jsItem, handlers: &handlers) {
                items.append(item)
            }
        }
        return items
    }

    private func buildNSMenuItem(from jsItem: JSValue, handlers: inout [MenuItemHandler]) -> NSMenuItem? {
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
            handlers.append(handler)
            item.target = handler
            item.action = #selector(MenuItemHandler.invoke(_:))
            item.isEnabled = !disabled
        }

        if let sv = jsItem.objectForKeyedSubscript("menu"), sv.isArray {
            item.submenu = buildMenu(from: sv, handlers: &handlers)
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
