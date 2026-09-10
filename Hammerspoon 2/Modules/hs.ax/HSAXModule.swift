//
//  AXModule.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AppKit
import ApplicationServices
import AXSwift

// MARK: - Declare our JavaScript API

/// # Accessibility API Module
///
/// This module provides access to macOS's powerful **Accessibility API**, allowing you to:
/// - Inspect UI elements in any application
/// - Monitor window and element changes
/// - Programmatically interact with UI elements
///
/// ## Basic Usage
///
/// ```js
/// // Get the focused UI element
/// const element = hs.ax.focusedElement();
/// console.log(element.role, element.title);
///
/// // Watch for window creation events on an application
/// const app = hs.application.frontmost();
/// hs.ax.addWatcher(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
///     console.log("New window:", element.title);
/// });
///
/// // Watch a specific element (e.g. a text field found via findByRole) for value changes
/// const field = hs.ax.findByRole(hs.ax.roles.textField, app.axElement())[0];
/// hs.ax.addWatcher(field, hs.ax.notificationTypes.valueChanged, (notification, element) => {
///     console.log("Field changed:", element.value);
/// });
/// ```
///
/// **Note:** Requires accessibility permissions in System Preferences.
@objc protocol HSAXModuleAPI: JSExport {
    /// Get the system-wide accessibility element
    /// - Returns: The system-wide AXElement, or nil if accessibility is not available
    /// - Example:
    /// ```js
    /// const sys = hs.ax.systemWideElement()
    /// ```
    @objc func systemWideElement() -> HSAXElement?

    /// Get the accessibility element for an application
    /// - Parameters:
    ///   - element: An HSApplication object
    /// - Returns: The AXElement for the application, or nil if accessibility is not available
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const ax = hs.ax.applicationElement(app)
    /// ```
    @objc func applicationElement(_ element: HSApplication) -> HSAXElement?

    /// Get the accessibility element for a window
    /// - Parameters:
    ///   - window: An HSWindow  object
    /// - Returns: The AXElement for the window, or nil if accessibility is not available
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// const ax = hs.ax.windowElement(win)
    /// ```
    @objc func windowElement(_ window: HSWindow) -> HSAXElement?

    /// Get the accessibility element at the specific screen position
    /// - Parameter point: An HSPoint object containing screen coordinates
    /// - Returns: The AXElement at that position, or nil if none found
    /// - Example:
    /// ```js
    /// const el = hs.ax.elementAtPoint({x: 100, y: 200})
    /// ```
    @objc func elementAtPoint(_ point: HSPoint) -> HSAXElement?

    /// A dictionary containing all of the notification types that can be used with hs.ax.addWatcher()
    /// - Example:
    /// ```js
    /// console.log(Object.keys(hs.ax.notificationTypes))
    /// ```
    @objc var notificationTypes: [String: String] { get }

    /// A dictionary containing all of the known accessibility roles that elements can have, for use with hs.ax.findByRole() and similar
    /// - Example:
    /// ```js
    /// console.log(Object.keys(hs.ax.roles))
    /// ```
    @objc var roles: [String: String] { get }

    /// Add a watcher for AX events on a specific element
    /// - Parameters:
    ///   - element: An HSAXElement to watch. This can be an application element (to receive notifications for the whole app's hierarchy) or any specific descendant element (e.g. a single text field)
    ///   - notification: An event name
    ///   - listener: {(notification: string, element: HSAXElement) => void} A function called with the notification name and the accessibility element it applies to
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// hs.ax.addWatcher(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
    ///     console.log("New window:", element.title)
    /// })
    /// ```
    @objc func addWatcher(_ element: HSAXElement, _ notification: String, _ listener: JSFunction)

    /// Remove a watcher for AX events on a specific element
    /// - Parameters:
    ///   - element: The HSAXElement that was passed to addWatcher()
    ///   - notification: The event name to stop watching
    ///   - listener: The function/lambda provided when adding the watcher
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// hs.ax.removeWatcher(app.axElement(), hs.ax.notificationTypes.windowCreated, myHandler)
    /// ```
    @objc func removeWatcher(_ element: HSAXElement, _ notification: String, _ listener: JSFunction)

    /// Fetch the focused UI element
    /// - Returns: An HSAXElement representing the focused UI element, or nil if none was found
    /// - Example:
    /// ```js
    /// const el = hs.ax.focusedElement()
    /// console.log(el.role + " " + el.title)
    /// ```
    @objc func focusedElement() -> HSAXElement?

    /// Find AX elements matching a given role
    /// - Parameters:
    ///   - role: The role name to search for (e.g. "AXButton", or hs.ax.roles.button)
    ///   - parent: An HSAXElement to search within
    /// - Returns: An array of matching HSAXElement objects
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const buttons = hs.ax.findByRole(hs.ax.roles.button, app.axElement())
    /// ```
    @objc func findByRole(_ role: String, _ parent: HSAXElement) -> [HSAXElement]

    /// Find AX elements whose title contains a given string
    /// - Parameters:
    ///   - title: The string to search for within element titles
    ///   - parent: An HSAXElement to search within
    /// - Returns: An array of matching HSAXElement objects
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const matches = hs.ax.findByTitle("OK", app.axElement())
    /// ```
    @objc func findByTitle(_ title: String, _ parent: HSAXElement) -> [HSAXElement]

    /// Print the accessibility hierarchy of an element to the Console
    /// - Parameters:
    ///   - element?: An HSAXElement to print. If omitted, the system-wide element is used
    ///   - maxDepth?: Maximum number of levels to traverse. Defaults to 5
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// hs.ax.printHierarchy(app.axElement(), 3)
    /// ```
    @objc func printHierarchy(_ element: HSAXElement?, _ maxDepth: Int)

    // NOTE: These are private API for the companion JS file only
    /// SKIP_DOCS
    @objc(_addWatcher:::) func _addWatcher(_ element: HSAXElement, notification: String, callback: JSFunction)
    /// SKIP_DOCS
    @objc(_removeWatcher::) func _removeWatcher(_ element: HSAXElement, notification: String)

    /// Swift-retained storage for the JS AXModuleWatcherEmitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSAXModule: NSObject, HSModuleAPI, HSAXModuleAPI {
    var moduleName = "hs.ax"
    let engineID: UUID

    // Store observers by PID
    private var observers: [pid_t: Observer] = [:]

    // Identifies a single watcher: a specific element and notification pair
    private struct WatcherKey: Hashable {
        let element: UIElement
        let notification: String
    }

    // Store watchers by element+notification, so multiple elements (e.g. two different
    // text fields) can each have their own watcher for the same notification type
    private var watchers: [WatcherKey: HSAXWatcherObject] = [:]

    // Notification types exposed to JavaScript
    @objc var _notificationTypes: [String: String] = [:]

    // Element roles exposed to JavaScript
    @objc var _roles: [String: String] = [:]

    // Swift-retained storage for the JS watcher emitter
    @objc var _watcherEmitter: JSFunction? = nil

    // MARK: - Module lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        // Build the notification types dictionary directly from the system's AX notification
        // constants, rather than a third-party library's potentially stale mirror of them.
        let notifications: [String] = [
            // Focus
            kAXMainWindowChangedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXFocusedUIElementChangedNotification as String,
            // Application
            kAXApplicationActivatedNotification as String,
            kAXApplicationDeactivatedNotification as String,
            kAXApplicationHiddenNotification as String,
            kAXApplicationShownNotification as String,
            // Window
            kAXWindowCreatedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            // Drawer, sheet, help
            kAXDrawerCreatedNotification as String,
            kAXSheetCreatedNotification as String,
            kAXHelpTagCreatedNotification as String,
            // Element
            kAXValueChangedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXElementBusyChangedNotification as String,
            // Menu
            kAXMenuOpenedNotification as String,
            kAXMenuClosedNotification as String,
            kAXMenuItemSelectedNotification as String,
            // Table/outline
            kAXRowCountChangedNotification as String,
            kAXRowExpandedNotification as String,
            kAXRowCollapsedNotification as String,
            // Cell-based table
            kAXSelectedCellsChangedNotification as String,
            // Layout area
            kAXUnitsChangedNotification as String,
            kAXSelectedChildrenMovedNotification as String,
            // Other
            kAXSelectedChildrenChangedNotification as String,
            kAXResizedNotification as String,
            kAXMovedNotification as String,
            kAXCreatedNotification as String,
            kAXSelectedRowsChangedNotification as String,
            kAXSelectedColumnsChangedNotification as String,
            kAXSelectedTextChangedNotification as String,
            kAXTitleChangedNotification as String,
            kAXLayoutChangedNotification as String,
            kAXAnnouncementRequestedNotification as String,
        ]
        for rawName in notifications {
            _notificationTypes[Self.camelCaseKey(fromRawAXName: rawName)] = rawName
        }

        // Build the roles dictionary. Copied from AXSwift's UIElement.Role, rather than
        // depending on that library's static properties directly, since new roles are
        // unlikely to require an AXSwift update to become usable here.
        let roleNames: [String] = [
            "AXUnknown", "AXButton", "AXRadioButton", "AXCheckBox", "AXSlider", "AXTabGroup",
            "AXTextField", "AXStaticText", "AXTextArea", "AXScrollArea", "AXPopUpButton",
            "AXMenuButton", "AXTable", "AXApplication", "AXGroup", "AXRadioGroup", "AXList",
            "AXScrollBar", "AXValueIndicator", "AXImage", "AXMenuBar", "AXMenu", "AXMenuItem",
            "AXMenuBarItem", "AXColumn", "AXRow", "AXToolbar", "AXBusyIndicator",
            "AXProgressIndicator", "AXWindow", "AXDrawer", "AXSystemWide", "AXOutline",
            "AXIncrementor", "AXBrowser", "AXComboBox", "AXSplitGroup", "AXSplitter",
            "AXColorWell", "AXGrowArea", "AXSheet", "AXHelpTag", "AXMatte", "AXRuler",
            "AXRulerMarker", "AXLink", "AXDisclosureTriangle", "AXGrid", "AXRelevanceIndicator",
            "AXLevelIndicator", "AXCell", "AXPopover", "AXLayoutArea", "AXLayoutItem", "AXHandle",
        ]
        for rawName in roleNames {
            _roles[Self.camelCaseKey(fromRawAXName: rawName)] = rawName
        }

        super.init()
        AKGarbage("Init of \(self.moduleName)")
    }

    /// Convert a raw "AXFoo" constant name into the camelCase key used to expose it to JavaScript
    private static func camelCaseKey(fromRawAXName rawName: String) -> String {
        var name = rawName
        if name.hasPrefix("AX") {
            name = String(name.dropFirst(2)) // Remove "AX" prefix
        }
        // Convert to camelCase starting with lowercase
        if let first = name.first {
            name = first.lowercased() + name.dropFirst()
        }
        return name
    }

    func shutdown() {
        // Clean up all watchers
        for key in Array(watchers.keys) {
            if let watcherObject = watchers[key] {
                do {
                    let pid = try watcherObject.element.pid()
                    if let observer = observers[pid] {
                        do {
                            try observer.removeNotification(watcherObject.notification, forElement: watcherObject.element)
                            AKDebug("hs.ax: Removed watcher for \(watcherObject.notification.rawValue)")
                        } catch {
                            AKError("hs.ax: Error removing watcher: \(error)")
                        }
                    }
                } catch {
                    AKError("hs.ax: Error getting PID during shutdown: \(error)")
                }
            }
        }
        watchers.removeAll()

        // Stop all observers
        for (_, observer) in observers {
            observer.stop()
        }
        observers.removeAll()

        _watcherEmitter = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
        shutdown()
    }

    @objc func toString() -> String {
        let n = watchers.count
        return "<\(moduleName): \(n) watcher\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - API Implementation

    @objc func systemWideElement() -> HSAXElement? {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.systemWideElement(): Accessibility permissions not granted")
            return nil
        }

        return HSAXElement(element: SystemWideElement(AXUIElementCreateSystemWide()))
    }

    @objc func applicationElement(_ element: HSApplication) -> HSAXElement? {
        return element.axElement()
    }

    @objc func windowElement(_ window: HSWindow) -> HSAXElement? {
        return window.axElement()
    }

    @objc func elementAtPoint(_ point: HSPoint) -> HSAXElement? {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.elementAtPosition(): Accessibility permissions not granted")
            return nil
        }

        let position = point.point

        do {
            let systemWide = SystemWideElement(AXUIElementCreateSystemWide())

            if let element: UIElement = try systemWide.elementAtPosition(position) {
                return HSAXElement(element: element)
            }

            return nil
        } catch {
            AKError("hs.ax.elementAtPosition(): Failed to get element at (\(position.x), \(position.y)): \(error.localizedDescription)")
            return nil
        }
    }

    @objc var notificationTypes: [String: String] {
        return _notificationTypes
    }

    @objc var roles: [String: String] {
        return _roles
    }

    // MARK: - Watcher Management

    @objc func addWatcher(_ element: HSAXElement, _ notification: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [element, notification, listener])
    }

    @objc func removeWatcher(_ element: HSAXElement, _ notification: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [element, notification, listener])
    }

    @objc(_addWatcher:::) func _addWatcher(_ element: HSAXElement, notification: String, callback: JSFunction) {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.addWatcher(): Accessibility permissions not granted")
            return
        }

        let pid = pid_t(element.pid)
        guard pid > 0 else {
            AKError("hs.ax.addWatcher(): Could not get PID for element")
            return
        }

        let key = WatcherKey(element: element.element, notification: notification)

        // Check if we already have a watcher for this combination
        if watchers.keys.contains(key) {
            AKWarning("hs.ax.addWatcher(): There is already a watcher for \(notification) on this element. Refusing to create a second.")
            return
        }

        // Parse the notification type
        let notifType = UIElement.AXNotification(rawValue: notification)

        // Get or create observer for this PID
        if !observers.keys.contains(pid) {
            do {
                let observer = try Observer(processID: pid) { [weak self] (observer: Observer, element: UIElement, notification: UIElement.AXNotification, info: [String: AnyObject]?) in
                    // This closure is called when any notification on this PID fires
                    guard let self = self else { return }
                    self.handleNotification(element: element, notification: notification)
                }
                observers[pid] = observer
                AKDebug("hs.ax.addWatcher(): Created observer for PID \(pid)")
            } catch {
                AKError("hs.ax.addWatcher(): Failed to create observer for PID \(pid): \(error)")
                return
            }
        }

        guard let observer = observers[pid] else {
            AKError("hs.ax.addWatcher(): Observer not found for PID \(pid)")
            return
        }

        // Create the watcher object
        let watcherObject = HSAXWatcherObject(element: element.element, notification: notifType, callback: callback)
        watchers[key] = watcherObject

        // Add the notification to the observer
        do {
            try observer.addNotification(notifType, forElement: element.element)
            AKDebug("hs.ax.addWatcher(): Added watcher for \(notification) on PID \(pid)")
        } catch {
            AKError("hs.ax.addWatcher(): Failed to add notification: \(error)")
            watchers.removeValue(forKey: key)
        }
    }

    @objc(_removeWatcher::) func _removeWatcher(_ element: HSAXElement, notification: String) {
        let pid = pid_t(element.pid)
        let key = WatcherKey(element: element.element, notification: notification)

        guard let watcherObject = watchers[key] else {
            AKDebug("hs.ax.removeWatcher(): No watcher found for \(notification) on this element")
            return
        }

        guard let observer = observers[pid] else {
            AKDebug("hs.ax.removeWatcher(): No observer found for PID \(pid)")
            watchers.removeValue(forKey: key)
            return
        }

        // Remove the notification from the observer
        do {
            try observer.removeNotification(watcherObject.notification, forElement: watcherObject.element)
            AKDebug("hs.ax.removeWatcher(): Removed watcher for \(notification) on PID \(pid)")
        } catch {
            AKError("hs.ax.removeWatcher(): Failed to remove notification: \(error)")
        }

        watchers.removeValue(forKey: key)

        // If there are no more watchers for this PID, clean up the observer
        let remainingWatchers = watchers.keys.filter { (try? $0.element.pid()) == pid }
        if remainingWatchers.isEmpty {
            observer.stop()
            observers.removeValue(forKey: pid)
            AKDebug("hs.ax.removeWatcher(): Removed observer for PID \(pid) (no more watchers)")
        }
    }

    /// Handle a notification from the observer
    private func handleNotification(element: UIElement, notification: UIElement.AXNotification) {
        let key = WatcherKey(element: element, notification: notification.rawValue)

        guard let watcherObject = watchers[key] else {
            // This can happen if we're watching multiple notifications on an element
            // and we only have watchers for some of them
            return
        }

        let wrappedElement = HSAXElement(element: element)
        let notificationValue = notification.rawValue
        let notificationName = _notificationTypes.firstKey(forValue: notificationValue) ?? notificationValue

        watcherObject.handleEvent(element: wrappedElement, notification: notificationName)
    }

    // MARK: - Helper Methods

    func isAccessibilityEnabled() -> Bool {
        return PermissionsManager.shared.check(.accessibility)
    }

    func requestAccessibility() {
        PermissionsManager.shared.request(.accessibility)
    }

    // MARK: - Convenience API

    @objc func focusedElement() -> HSAXElement? {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.focusedElement(): Accessibility permissions not granted")
            return nil
        }

        let systemWide = SystemWideElement(AXUIElementCreateSystemWide())
        let attr = UIElement.Attribute(rawValue: "AXFocusedUIElement")
        guard let element: UIElement = try? systemWide.attribute(attr) else {
            return nil
        }
        return HSAXElement(element: element)
    }

    @objc func findByRole(_ role: String, _ parent: HSAXElement) -> [HSAXElement] {
        var results: [HSAXElement] = []
        var stack = [parent]

        while !stack.isEmpty {
            let element = stack.removeLast()
            if element.role == role {
                results.append(element)
            }
            stack.append(contentsOf: element.children())
        }

        return results
    }

    @objc func findByTitle(_ title: String, _ parent: HSAXElement) -> [HSAXElement] {
        var results: [HSAXElement] = []
        var stack = [parent]

        while !stack.isEmpty {
            let element = stack.removeLast()
            if let elementTitle = element.title, elementTitle.contains(title) {
                results.append(element)
            }
            stack.append(contentsOf: element.children())
        }

        return results
    }

    @objc func printHierarchy(_ element: HSAXElement?, _ maxDepth: Int) {
        let cap = maxDepth > 0 ? maxDepth : 5
        _printHierarchy(element ?? systemWideElement(), depth: 0, maxDepth: cap)
    }

    private func _printHierarchy(_ element: HSAXElement?, depth: Int, maxDepth: Int) {
        guard let element else { return }

        let indent = String(repeating: "  ", count: depth)
        let role = element.role ?? "unknown"
        let titleStr = element.title.map { " \"\($0)\"" } ?? ""
        AKDebug("\(indent)\(role)\(titleStr)")

        guard depth < maxDepth else { return }
        for child in element.children() {
            _printHierarchy(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
