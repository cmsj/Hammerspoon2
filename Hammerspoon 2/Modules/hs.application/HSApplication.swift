//
//  HSApplication.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 20/10/2025.
//

import Foundation
import JavaScriptCore
import Cocoa
import AXSwift

/// Object representing an application. You should not instantiate this directly in JavaScript, but rather, use the methods from hs.application which will return appropriate HSApplication objects.
@objc protocol HSApplicationAPI: HSTypeAPI, JSExport {
    /// POSIX Process Identifier
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.pid)
    /// ```
    @objc var pid: Int { get }

    /// Bundle Identifier (e.g. com.apple.Safari)
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.bundleID)
    /// ```
    @objc var bundleID: String? { get }

    /// The application's title
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.title)
    /// ```
    @objc var title: String? { get }

    /// Location of the application on disk
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.bundlePath)
    /// ```
    @objc var bundlePath: String? { get }

    /// Is the application hidden
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Safari")
    /// app.isHidden = true
    /// ```
    @objc var isHidden: Bool { get set }

    /// Is the application focused
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.isActive)
    /// ```
    @objc var isActive: Bool { get }

    /// Terminate the application
    /// - Returns: True if the application was terminated, otherwise false
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Calculator")
    /// app.kill()
    /// ```
    @objc func kill() -> Bool

    /// Force-terminate the application
    /// - Returns: True if the application was force-terminated, otherwise false
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Calculator")
    /// app.kill9()
    /// ```
    @objc func kill9() -> Bool

    /// The main window of this application, or nil if there is no main window
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const win = app.mainWindow
    /// ```
    @objc var mainWindow: HSWindow? { get }

    /// The focused window of this application, or nil if there is no focused window
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const win = app.focusedWindow
    /// ```
    @objc var focusedWindow: HSWindow? { get }

    /// All windows of this application
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// app.allWindows.forEach(w => console.log(w.title))
    /// ```
    @objc var allWindows: [HSWindow] { get }

    /// All visible (ie non-hidden) windows of this application
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.visibleWindows.length)
    /// ```
    @objc var visibleWindows: [HSWindow] { get }

    /// The application's HSAXElement object, for use with the hs.ax APIs
    /// - Returns: An HSAXElement object, or nil if it could not be obtained
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const ax = app.axElement()
    /// ```
    @objc func axElement() -> HSAXElement?

    /// Bring this application to the foreground
    /// - Parameter allWindows?: Pass true to raise all application windows. Defaults to false.
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Safari")
    /// app.activate()
    /// app.activate(true)
    /// ```
    @objc func activate(_ allWindows: Bool)

    /// Hide this application and all its windows
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Safari")
    /// app.hide()
    /// ```
    @objc func hide()

    /// Unhide this application
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Safari")
    /// app.unhide()
    /// ```
    @objc func unhide()

    /// Whether the application process is still running
    /// - Returns: true if the application is running, false if it has terminated
    /// - Example:
    /// ```js
    /// const app = hs.application.matchingName("Calculator")
    /// app.kill()
    /// console.log(app.isRunning)
    /// ```
    @objc var isRunning: Bool { get }

    /// The kind of application: "standard" (regular dock app), "accessory" (no dock), or "background" (agent)
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.kind)
    /// ```
    @objc var kind: String { get }

    /// Get the full menu structure of this application
    /// - Note: This traverses the accessibility hierarchy and may be slow for apps with large menus.
    /// - Returns: An array of top-level menu objects, each with title and items keys, or null if unavailable
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// app.getMenuItems().forEach(m => console.log(m.title))
    /// ```
    @objc func getMenuItems() -> [[String: Any]]?

    /// Find a menu item by searching all menus for a matching title (case-insensitive)
    /// - Parameter name: The menu item title to search for
    /// - Returns: An object with title and enabled keys, or null if not found
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const item = app.findMenuItemByName("Select All")
    /// console.log(item.enabled)
    /// ```
    @objc func findMenuItemByName(_ name: String) -> [String: Any]?

    /// Find a menu item by following a hierarchical path of titles
    /// - Parameter path: An array of menu titles forming a path from the top-level menu to the item, e.g. ["Edit", "Select All"]
    /// - Returns: An object with title and enabled keys, or null if not found
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const item = app.findMenuItemByPath(["Edit", "Select All"])
    /// console.log(item.enabled)
    /// ```
    @objc func findMenuItemByPath(_ path: [String]) -> [String: Any]?

    /// Click a menu item found by searching all menus for a matching title (case-insensitive)
    /// - Parameter name: The menu item title to search for
    /// - Returns: true if the menu item was found and clicked, false otherwise
    /// - Example:
    /// ```js
    /// const safari = hs.application.matchingName("Safari")
    /// safari.selectMenuItemByName("New Window")
    /// ```
    @objc func selectMenuItemByName(_ name: String) -> Bool

    /// Click a menu item found by following a hierarchical path of titles
    /// - Parameter path: An array of menu titles forming a path from the top-level menu to the item, e.g. ["File", "New Window"]
    /// - Returns: true if the menu item was found and clicked, false otherwise
    /// - Example:
    /// ```js
    /// const safari = hs.application.matchingName("Safari")
    /// safari.selectMenuItemByPath(["File", "New Window"])
    /// ```
    @objc func selectMenuItemByPath(_ path: [String]) -> Bool

    /// Find windows whose title contains the given string (case-insensitive)
    /// - Parameter pattern: A string to search for in window titles
    /// - Returns: An array of matching HSWindow objects
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// app.findWindow("untitled").forEach(w => console.log(w.title))
    /// ```
    @objc func findWindow(_ pattern: String) -> [HSWindow]

    /// Get the first window with exactly the given title
    /// - Parameter title: The exact window title to search for
    /// - Returns: The matching HSWindow, or null if not found
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const win = app.getWindow("index.html")
    /// ```
    @objc func getWindow(_ title: String) -> HSWindow?
}

@_documentation(visibility: private)
@objc class HSApplication: NSObject, HSApplicationAPI {
    @objc var typeName = "HSApplication"
    let runningApplication: NSRunningApplication
    let axUIElement: Application?

    init(runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        self.axUIElement = Application(runningApplication)
    }

    deinit {
//        AKDebug("deinit of \(self): \(self.runningApplication.localizedName ?? "UNKNOWN")")
    }

    @objc var pid: Int { Int(self.runningApplication.processIdentifier) }
    @objc var bundleID: String? { self.runningApplication.bundleIdentifier }
    @objc var title: String? { self.runningApplication.localizedName }
    @objc var bundlePath: String? { self.runningApplication.bundleURL?.path(percentEncoded: false) }

    @objc var isHidden: Bool {
        get {
            let value = try? self.axUIElement?.attribute(.hidden) as Bool?
            return value ?? false
        }
        set { try? self.axUIElement?.setAttribute(.hidden, value: newValue) }
    }
    @objc var isActive: Bool { self.runningApplication.isActive }

    @objc func kill() -> Bool {
        return self.runningApplication.terminate()
    }

    @objc func kill9() -> Bool {
        return self.runningApplication.forceTerminate()
    }

    @objc var mainWindow: HSWindow? {
        guard let mainWindow: UIElement = try? self.axUIElement?.attribute(.mainWindow) else {
            return nil
        }
        return HSWindow(element: mainWindow, app: self.runningApplication)
    }

    @objc var focusedWindow: HSWindow? {
        guard let focusedWindow: UIElement = try? self.axUIElement?.attribute(.focusedWindow) else {
            return nil
        }
        return HSWindow(element: focusedWindow, app: self.runningApplication)
    }

    @objc var allWindows: [HSWindow] {
        guard let allWindows: [UIElement] = try? self.axUIElement?.arrayAttribute(.windows) else {
            return []
        }
        return allWindows.compactMap { HSWindow(element: $0, app: self.runningApplication) }
    }

    @objc var visibleWindows: [HSWindow] {
        return allWindows.filter { $0.isVisible }
    }

    @objc func axElement() -> HSAXElement? {
        guard let axApp = Application(self.runningApplication) else {
            AKError("hs.application.axElement(): Failed to create AXElement for \(self.title ?? "unknown")")
            return nil
        }
        return HSAXElement(element: axApp)
    }

    // MARK: - Focus and visibility

    @objc func activate(_ allWindows: Bool) {
        let options: NSApplication.ActivationOptions = allWindows ? [.activateAllWindows] : []
        runningApplication.activate(options: options)
    }

    @objc func hide() {
        runningApplication.hide()
    }

    @objc func unhide() {
        runningApplication.unhide()
    }

    @objc var isRunning: Bool {
        !runningApplication.isTerminated
    }

    @objc var kind: String {
        switch runningApplication.activationPolicy {
        case .regular:    return "standard"
        case .accessory:  return "accessory"
        case .prohibited: return "background"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Window search

    @objc func findWindow(_ pattern: String) -> [HSWindow] {
        let lower = pattern.lowercased()
        return allWindows.filter { ($0.title ?? "").lowercased().contains(lower) }
    }

    @objc func getWindow(_ title: String) -> HSWindow? {
        return allWindows.first { $0.title == title }
    }

    // MARK: - Menu traversal

    @objc func getMenuItems() -> [[String: Any]]? {
        guard let menuBar: UIElement = try? axUIElement?.attribute(.menuBar) else {
            AKError("hs.application.getMenuItems: Failed to get menu bar for \(self.title ?? "unknown")")
            return nil
        }
        guard let menuBarItems: [UIElement] = try? menuBar.arrayAttribute(.children) else {
            return []
        }
        return menuBarItems.compactMap { menuBarItemToDict($0) }
    }

    @objc func findMenuItemByName(_ name: String) -> [String: Any]? {
        guard let element = findMenuElement(byName: name) else { return nil }
        return menuElementToDict(element)
    }

    @objc func findMenuItemByPath(_ path: [String]) -> [String: Any]? {
        guard let element = findMenuElement(byPath: path) else { return nil }
        return menuElementToDict(element)
    }

    @objc func selectMenuItemByName(_ name: String) -> Bool {
        guard let element = findMenuElement(byName: name) else { return false }
        return pressMenuElement(element, context: "selectMenuItemByName")
    }

    @objc func selectMenuItemByPath(_ path: [String]) -> Bool {
        guard let element = findMenuElement(byPath: path) else { return false }
        return pressMenuElement(element, context: "selectMenuItemByPath")
    }

    private func menuBarItems() -> [UIElement]? {
        guard let menuBar: UIElement = try? axUIElement?.attribute(.menuBar) else { return nil }
        return try? menuBar.arrayAttribute(.children)
    }

    private func findMenuElement(byName name: String) -> UIElement? {
        guard let items = menuBarItems() else { return nil }
        let target = name.lowercased()
        for barItem in items {
            if let found = searchMenuElement(withTitle: target, in: barItem) { return found }
        }
        return nil
    }

    private func findMenuElement(byPath path: [String]) -> UIElement? {
        guard let items = menuBarItems(), let first = path.first else { return nil }
        guard let topItem = items.first(where: {
            ((try? $0.attribute(.title) as String?) ?? "").lowercased() == first.lowercased()
        }) else { return nil }
        return path.count == 1 ? topItem : navigateMenuPath(Array(path.dropFirst()), from: topItem)
    }

    private func menuElementToDict(_ element: UIElement) -> [String: Any] {
        let title: String = (try? element.attribute(.title)) ?? ""
        let enabled: Bool = (try? element.attribute(.enabled)) ?? false
        return ["title": title, "enabled": enabled]
    }

    private func pressMenuElement(_ element: UIElement, context: String) -> Bool {
        do {
            try element.performAction(.press)
            return true
        } catch {
            AKError("hs.application.\(context): \(error.localizedDescription)")
            return false
        }
    }

    private func searchMenuElement(withTitle title: String, in element: UIElement) -> UIElement? {
        guard let children: [UIElement] = try? element.arrayAttribute(.children) else { return nil }
        for child in children {
            let childTitle = ((try? child.attribute(.title) as String?) ?? "").lowercased()
            if childTitle == title { return child }
            if let found = searchMenuElement(withTitle: title, in: child) { return found }
        }
        return nil
    }

    private func navigateMenuPath(_ path: [String], from element: UIElement) -> UIElement? {
        let children = submenuElements(of: element)
        let target = path[0].lowercased()
        for child in children {
            let childTitle = ((try? child.attribute(.title) as String?) ?? "").lowercased()
            if childTitle == target {
                return path.count == 1 ? child : navigateMenuPath(Array(path.dropFirst()), from: child)
            }
        }
        return nil
    }

    /// Menu bar items and menu items with submenus expose their actual items one level below
    /// their direct children, behind an intermediate `AXMenu` container.
    private func submenuElements(of element: UIElement) -> [UIElement] {
        guard let children: [UIElement] = try? element.arrayAttribute(.children) else { return [] }
        guard let menu = children.first, let items: [UIElement] = try? menu.arrayAttribute(.children) else {
            return children
        }
        return items
    }

    private func menuBarItemToDict(_ element: UIElement) -> [String: Any]? {
        let title: String = (try? element.attribute(.title)) ?? ""
        var dict: [String: Any] = ["title": title]
        if let children: [UIElement] = try? element.arrayAttribute(.children),
           let menu = children.first,
           let items: [UIElement] = try? menu.arrayAttribute(.children) {
            dict["items"] = items.compactMap { menuItemToDict($0) }
        }
        return dict
    }

    private func menuItemToDict(_ element: UIElement) -> [String: Any]? {
        if (try? element.role()?.rawValue) == "AXMenuItemSeparator" {
            return ["title": "-", "isSeparator": true]
        }
        let title: String = (try? element.attribute(.title)) ?? ""
        let enabled: Bool = (try? element.attribute(.enabled)) ?? false
        var dict: [String: Any] = ["title": title, "enabled": enabled]
        if let children: [UIElement] = try? element.arrayAttribute(.children),
           let submenu = children.first,
           let submenuItems: [UIElement] = try? submenu.arrayAttribute(.children) {
            dict["items"] = submenuItems.compactMap { menuItemToDict($0) }
        }
        return dict
    }
}
