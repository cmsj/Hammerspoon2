//
//  HSDockIconModule.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - JavaScript API Protocol

/// Module for customising Hammerspoon's own Dock icon.
///
/// The Dock icon is only shown when the "Show in" setting in Hammerspoon's Settings includes the Dock.
///
/// ## Adding items to the Dock icon's menu
///
/// ```js
/// hs.dockicon.setMenu([
///     { title: "Reload config", fn: () => hs.reload() },
///     { title: "-" },
///     { title: "Open Console", fn: () => hs.openConsole() }
/// ])
/// ```
@objc protocol HSDockIconModuleAPI: JSExport {
    /// Set extra items for the menu shown when the Dock icon is right-clicked (or Control-clicked, or held).
    ///
    /// The items appear above the Dock's own items (Options, Show All Windows, Hide and Quit).
    /// Pass an array of menu item objects for a static menu, or a function that returns an array for a menu
    /// populated each time it opens. The function receives one argument: the modifier keys held when the menu
    /// opened, in the same form as `hs.eventtap.currentModifiers()`.
    ///
    /// Menu item object keys are the same as for `HSMenuBarItem.setMenu()`:
    /// - `title` (string, required): The item label. Use `"-"` for a separator line.
    /// - `fn` (function): Callback invoked when the item is chosen.
    /// - `checked` (boolean): If true, a checkmark is shown next to the item.
    /// - `disabled` (boolean): If true, the item is greyed out and cannot be chosen.
    /// - `tooltip` (string): Tooltip shown when hovering over the item.
    /// - `color` (HSColor or hex string): The colour of the item's title text.
    /// - `icon` (HSImage): Icon shown to the left of the title.
    /// - `menu` (array): Nested array of menu item objects to create a submenu.
    ///
    /// The menu is removed when the config is reloaded.
    ///
    /// - Parameter menuOrFn: {Array<Record<string, any>> | ((modifiers: string[]) => Array<Record<string, any>>) | null} Array of menu item objects, a function returning such an array, or null to remove the extra items
    /// - Example:
    /// ```js
    /// hs.dockicon.setMenu([
    ///     { title: "Reload config", fn: () => hs.reload() },
    ///     { title: "-" },
    ///     { title: "Layouts", menu: [
    ///         { title: "Coding", fn: () => console.log("coding") },
    ///         { title: "Writing", fn: () => console.log("writing") }
    ///     ] }
    /// ])
    ///
    /// // Rebuilt every time the menu opens
    /// hs.dockicon.setMenu((modifiers) => [
    ///     { title: "Opened at " + new Date().toLocaleTimeString(), disabled: true },
    ///     ...(modifiers.includes("alt") ? [{ title: "Advanced", fn: () => console.log("advanced") }] : [])
    /// ])
    ///
    /// // Remove the extra items
    /// hs.dockicon.setMenu(null)
    /// ```
    @objc func setMenu(_ menuOrFn: JSValue)
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSDockIconModule: NSObject, HSModuleAPI, HSDockIconModuleAPI {
    var moduleName = "hs.dockicon"
    let engineID: UUID

    /// The menu set with an array, if any
    private var staticMenu: NSMenu?
    /// The function set to build the menu each time it opens, if any
    private var menuCallback: JSCallback?
    /// Handlers for the items of the static menu, or of the dynamic menu most recently built. A dynamic
    /// menu's are kept until the next one is built, so that they outlive the menu being open.
    private var menuItemHandlers: [JSMenuItemHandler] = []
    /// Incremented whenever the menu is replaced, so that building a menu (which runs JS) can tell if it
    /// was replaced meanwhile
    private var menuGeneration = 0

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        clearMenu()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - API

    @objc func setMenu(_ menuOrFn: JSValue) {
        clearMenu()
        let generation = menuGeneration

        if menuOrFn.isNull || menuOrFn.isUndefined {
            return
        } else if menuOrFn.isArray {
            var builder = makeMenuBuilder()
            let menu = builder.makeMenu(from: menuOrFn)
            guard store(builder.handlers, ifStill: generation) else { return }
            staticMenu = menu
        } else if menuOrFn.isFunction {
            menuCallback = JSCallback(value: menuOrFn, owner: self)
        } else {
            AKError("hs.dockicon.setMenu: Expected an array, function, or null")
        }
    }

    // MARK: - Dock menu (called by AppDelegate)

    /// The extra items for the Dock icon's menu, or nil if there are none. For a dynamic menu, this calls
    /// the menu function, so it's called each time the menu opens.
    func makeDockMenu() -> NSMenu? {
        if let staticMenu {
            return staticMenu
        }
        guard let callback = menuCallback?.value else { return nil }

        let generation = menuGeneration
        let modifiers = CGEventFlags.modifierNames(from: CGEventSource.flagsState(.combinedSessionState))
        let result = callback.call(withArguments: [modifiers])
        logJSException(from: callback, context: "menu callback")

        // If the function set a new array menu, show that instead, whatever the function returned
        guard generation == menuGeneration else { return staticMenu }

        guard let result, result.isArray else {
            AKError("hs.dockicon: Menu callback must return an array")
            return nil
        }

        var builder = makeMenuBuilder()
        let menu = builder.makeMenu(from: result)
        // If an entry's properties set a new array menu, show that instead
        guard store(builder.handlers, ifStill: generation) else { return staticMenu }
        return menu
    }

    // MARK: - Private helpers

    private func clearMenu() {
        menuGeneration += 1
        staticMenu = nil
        menuCallback?.detach(from: self)
        menuCallback = nil
        menuItemHandlers.detachAll(from: self)
    }

    private func makeMenuBuilder() -> JSMenuBuilder {
        JSMenuBuilder(owner: self, logPrefix: "hs.dockicon")
    }

    /// Stores the handlers for a newly built menu, returning false (and detaching them) if the menu was
    /// replaced or removed while it was being built, e.g. by a menu item's properties calling `setMenu()`
    private func store(_ handlers: [JSMenuItemHandler], ifStill generation: Int) -> Bool {
        guard generation == menuGeneration else {
            var orphaned = handlers
            orphaned.detachAll(from: self)
            return false
        }
        menuItemHandlers.detachAll(from: self)
        menuItemHandlers = handlers
        return true
    }

    private func logJSException(from value: JSValue, context label: String) {
        guard let ctx = value.context,
              let exception = ctx.exception,
              !exception.isUndefined else { return }
        AKError("hs.dockicon: Error in \(label): \(exception.toString() ?? "unknown error")")
        ctx.exception = nil
    }
}
