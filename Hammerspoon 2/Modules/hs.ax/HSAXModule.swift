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
/// // Watch an application's element for window creation events. Notifications bubble up
/// // from anywhere in the application's hierarchy, so this fires for every new window,
/// // not just one specific window.
/// const app = hs.application.frontmost();
/// hs.ax.on(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
///     console.log("New window:", element.title);
/// });
///
/// // Watch a specific element (e.g. a text field found via findByRole) for value changes.
/// // Watching a specific element scopes the notification to just that element, rather
/// // than the whole application's hierarchy.
/// const field = hs.ax.findByRole(hs.ax.roles.textField, app.axElement())[0];
/// hs.ax.on(field, hs.ax.notificationTypes.valueChanged, (notification, element) => {
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

    /// A dictionary containing all of the notification types that can be used with hs.ax.on()
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

    /// Register a listener for AX events on a specific element
    /// - Parameters:
    ///   - element: An HSAXElement to watch. Passing an application's element causes matching notifications to bubble up from anywhere in that application's hierarchy (e.g. AXWindowCreated for any window in the app, not just one); passing a specific descendant element scopes the notification to just that element
    ///   - notification: {string | string[]} An event name, or an array of event names, to watch for with the same listener
    ///   - listener: {(notification: string, element: HSAXElement) => void} A function called with the notification name and the accessibility element it applies to
    /// - Throws: true
    /// - Note: If a watcher can't be started, the `Error` says why, and when the Accessibility API reported an error its `code` property is that error's name: e.g. `"kAXErrorAPIDisabled"` (the application has turned the Accessibility API off, as Firefox in kiosk mode does, so retrying won't help), `"kAXErrorNotificationUnsupported"` (the element doesn't send that notification) or `"kAXErrorCannotComplete"` (the application didn't respond, e.g. because it is still starting up).
    /// - Note: When `notification` is an array, registration is all-or-nothing: if any one of them fails, none are left registered.
    /// - Note: Listeners are removed automatically when the watched element is destroyed, or when its application quits, so there is no need to call `off` in either case (doing so is harmless). A listener registered for `uIElementDestroyed` is still called for the element's destruction before it is removed.
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// try {
    ///     hs.ax.on(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
    ///         console.log("New window:", element.title)
    ///     })
    ///
    ///     // Watch for several notifications with the same handler
    ///     hs.ax.on(app.axElement(), [hs.ax.notificationTypes.windowCreated, hs.ax.notificationTypes.windowMoved], (notification, element) => {
    ///         console.log(notification, element.title)
    ///     })
    /// } catch (err) {
    ///     console.error(err.message, err.code)
    /// }
    /// ```
    @objc func on(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction)

    /// Remove a previously registered listener for AX events on a specific element
    ///
    /// Listeners for an element that has been destroyed, or whose application has quit, are removed automatically, so this is only needed to stop watching an element that still exists.
    /// - Parameters:
    ///   - element: The HSAXElement that was passed to `on`
    ///   - notification: {string | string[]} The event name, or array of event names, to stop watching
    ///   - listener: The function/lambda provided when adding the watcher
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// hs.ax.off(app.axElement(), hs.ax.notificationTypes.windowCreated, myHandler)
    /// ```
    @objc func off(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction)

    /// Register a listener that fires at most once for AX events on a specific element
    /// - Parameters:
    ///   - element: An HSAXElement to watch - see `on` for the application-vs-descendant bubbling behavior
    ///   - notification: {string | string[]} An event name, or an array of event names, to watch for with the same listener
    ///   - listener: {(notification: string, element: HSAXElement) => void} Called once (per registered notification name), then automatically removed
    /// - Throws: true
    /// - Note: A failure to start the watcher throws an `Error` with a `code`, as for `on`.
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// try {
    ///     hs.ax.once(app.axElement(), hs.ax.notificationTypes.windowCreated, (notification, element) => {
    ///         console.log("First new window:", element.title)
    ///     })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func once(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction)

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
    @objc(_addWatcher:::) func _addWatcher(_ element: HSAXElement, notification: String, listener: JSFunction) -> [String: String]?
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

    // This module's registrations with the shared, process-wide AX observers
    private var axClient: AXObserverHub.Client?

    // Identifies a single watcher: a specific element and notification pair
    private struct WatcherKey: Hashable {
        let element: UIElement
        let notification: String
    }

    // Store watchers by element+notification, so multiple elements (e.g. two different
    // text fields) can each have their own watcher for the same notification type
    private var watchers: [WatcherKey: HSAXWatcherObject] = [:]

    private static let destroyedNotification = UIElement.AXNotification(rawValue: kAXUIElementDestroyedNotification as String)

    // Notification types exposed to JavaScript
    @objc var _notificationTypes: [String: String] = [:]

    // Element roles exposed to JavaScript
    @objc var _roles: [String: String] = [:]

    // Swift-retained storage for the JS watcher emitter
    @objc var _watcherEmitter: JSFunction?

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

        axClient = AXObserverHub.shared.makeClient { [weak self] element, notification, _ in
            self?.handleNotification(element: element, notification: notification)
        }

        // Drop the watchers of an application that quits (issue #299). Selector-based rather
        // than block-based, so the notification's userInfo needn't cross a @Sendable closure.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

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
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Clean up all watchers, and with them this module's AX registrations
        axClient?.invalidate()
        watchers.removeAll()

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

    @objc func on(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction) {
        guard let ctx = JSContext.current() else { return }
        guard let notifications = Self.notificationStrings(from: notification), !notifications.isEmpty else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.ax.on(): notification must be a string or a non-empty array of strings", in: ctx)
            return
        }
        guard let emitter = _watcherEmitter else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.ax.on(): watcher emitter is unavailable", in: ctx)
            return
        }
        // callCapturingException, not plain invokeMethod: a throw from inside the emitter (e.g.
        // an invalid listener, or native registration failing) must reach this call's own JS
        // caller - see callCapturingException's doc comment for why invokeMethod alone can't.
        // onEach rolls back any notifications it already registered before rethrowing.
        _ = ctx.callCapturingException { emitter.invokeMethod("onEach", withArguments: [element, notifications, listener]) }
    }

    @objc func off(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction) {
        guard let notifications = Self.notificationStrings(from: notification) else {
            AKError("hs.ax.off(): notification must be a string or an array of strings")
            return
        }
        for notif in notifications {
            _watcherEmitter?.invokeMethod("off", withArguments: [element, notif, listener])
        }
    }

    @objc func once(_ element: HSAXElement, _ notification: JSValue, _ listener: JSFunction) {
        guard let ctx = JSContext.current() else { return }
        guard let notifications = Self.notificationStrings(from: notification), !notifications.isEmpty else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.ax.once(): notification must be a string or a non-empty array of strings", in: ctx)
            return
        }
        guard let emitter = _watcherEmitter else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.ax.once(): watcher emitter is unavailable", in: ctx)
            return
        }
        _ = ctx.callCapturingException { emitter.invokeMethod("onceEach", withArguments: [element, notifications, listener]) }
    }

    /// Accepts either a single notification name string, or an array of them
    private static func notificationStrings(from value: JSValue) -> [String]? {
        if value.isString, let str = value.toString() {
            return [str]
        }
        if value.isArray, let strings = value.toArray() as? [String] {
            return strings
        }
        return nil
    }

    /// - Returns: nil if the watcher was registered (or already was), otherwise why it couldn't be: a `reason`, and the Accessibility error's name as `code` when there was one. The JS companion file throws these as the Error from on()/once(), and doesn't retain its listener bucket.
    @objc(_addWatcher:::) func _addWatcher(_ element: HSAXElement, notification: String, listener: JSFunction) -> [String: String]? {
        guard isAccessibilityEnabled() else {
            return watcherFailure("Hammerspoon does not have Accessibility permission")
        }

        let pid = pid_t(element.pid)
        guard pid > 0 else {
            return watcherFailure("could not get the element's process ID")
        }

        let key = WatcherKey(element: element.element, notification: notification)

        // Check if we already have a watcher for this combination
        if watchers.keys.contains(key) {
            AKWarning("hs.ax.on(): There is already a watcher for \(notification) on this element. Refusing to create a second.")
            return nil
        }

        // Parse the notification type
        let notifType = UIElement.AXNotification(rawValue: notification)

        guard let axClient else {
            return watcherFailure("the module has shut down")
        }

        // Register the notification with the shared observer for this PID
        do {
            try axClient.add(notifType, element: element.element, pid: pid)
            AKDebug("hs.ax.on(): Added watcher for \(notification) on PID \(pid)")
        } catch {
            return watcherFailure("could not watch PID \(pid)", error: error)
        }

        // Create the watcher object
        let isApplicationElement = element.role == "AXApplication"
        let watcherObject = HSAXWatcherObject(element: element.element, notification: notifType, callback: listener, owner: self, isApplicationElement: isApplicationElement, pid: pid)
        watchers[key] = watcherObject

        // Also watch for the element's destruction, whether or not the caller asked to, so its
        // watchers can be dropped when it goes away (issue #299). Re-adding an already
        // registered notification is not an error. Application elements are skipped: there,
        // AXUIElementDestroyed bubbles up from every descendant, and app termination is caught
        // via NSWorkspace instead.
        if !isApplicationElement {
            do {
                try axClient.add(Self.destroyedNotification, element: element.element, pid: pid)
            } catch {
                // Not fatal: the watcher works, it just can't be cleaned up automatically
                AKDebug("hs.ax.on(): Element does not support \(Self.destroyedNotification.rawValue), so its watchers won't be removed automatically: \(error)")
            }
        }
        return nil
    }

    /// Why `_addWatcher` failed, as the JS companion file reports it (issue #437): `reason`, followed
    /// by the explanation of `error` if there was one, and `error`'s name as `code`. Also logged, so
    /// the failure stays visible when on() is called from a promise callback and the throw becomes
    /// an unhandled rejection.
    private func watcherFailure(_ reason: String?, error: AXError? = nil) -> [String: String] {
        var failure: [String: String] = [:]
        var parts = [reason].compactMap { $0 }
        if let error {
            parts.append("\(error.explanation) (\(error.constantName))")
            failure["code"] = error.constantName
        }
        failure["reason"] = parts.joined(separator: ": ")
        AKError("hs.ax.on(): \(failure["reason"] ?? "")")
        return failure
    }

    @objc(_removeWatcher::) func _removeWatcher(_ element: HSAXElement, notification: String) {
        let key = WatcherKey(element: element.element, notification: notification)

        guard let watcherObject = watchers[key] else {
            AKDebug("hs.ax.off(): No watcher found for \(notification) on this element")
            return
        }

        watchers.removeValue(forKey: key)

        // The element's AXUIElementDestroyed registration is shared with the internal destruction
        // watch made by _addWatcher, so it stays until the element's last watcher goes (or, for an
        // application element, which has no internal watch, until the caller's own watcher for it
        // goes). Removing a registration for an element that has already gone away is harmless.
        let elementHasOtherWatchers = watchers.keys.contains { $0.element == watcherObject.element }
        let isDestroyedWatcher = watcherObject.notification == Self.destroyedNotification
        if !isDestroyedWatcher || watcherObject.isApplicationElement || !elementHasOtherWatchers {
            axClient?.remove(watcherObject.notification, element: watcherObject.element)
        }
        if !watcherObject.isApplicationElement && !elementHasOtherWatchers {
            axClient?.remove(Self.destroyedNotification, element: watcherObject.element)
        }
        AKDebug("hs.ax.off(): Removed watcher for \(notification) on PID \(watcherObject.pid)")
    }

    /// Drops every watcher matching `predicate`, along with its AX registrations, which died
    /// with the element or process. Used when an element is destroyed or its app quits,
    /// so no JS listener ever has to call off() for something that no longer exists (#299).
    private func dropWatchers(where predicate: (WatcherKey, HSAXWatcherObject) -> Bool) {
        let dropped = watchers.filter { predicate($0.key, $0.value) }
        guard !dropped.isEmpty else { return }

        for key in dropped.keys {
            watchers.removeValue(forKey: key)
        }
        for element in Set(dropped.keys.map(\.element)) where !watchers.keys.contains(where: { $0.element == element }) {
            axClient?.removeAll(element: element)
        }

        // Tell the JS emitter, so it drops its matching buckets too
        for key in dropped.keys {
            _ = _watcherEmitter?.invokeMethod("_forget", withArguments: [HSAXElement(element: key.element), key.notification])
        }
        AKDebug("hs.ax: Automatically removed \(dropped.count) watcher\(dropped.count == 1 ? "" : "s") for a destroyed element or terminated application")
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handleApplicationTerminated(pid: app.processIdentifier)
    }

    /// Drops every watcher, and its AX registrations, for a process that has quit.
    /// Internal rather than private so tests can simulate termination without quitting an app.
    func handleApplicationTerminated(pid: pid_t) {
        dropWatchers { _, watcherObject in watcherObject.pid == pid }
        axClient?.removeAll(pid: pid)
    }

    /// The number of registered element+notification watchers, for tests
    var watcherCount: Int { watchers.count }

    /// Handle a notification from the observer
    /// Internal rather than private so tests can simulate AX notification delivery directly,
    /// since this sandbox cannot receive real AXObserver callbacks (see HSAXWatcherRoutingTests).
    func handleNotification(element: UIElement, notification: UIElement.AXNotification) {
        let notificationValue = notification.rawValue
        let elementPid = try? element.pid()

        // AX delivers the notification with the element it actually happened on. For a watcher
        // registered directly on that element, this is an exact match. But for a watcher
        // registered on an application element (to catch e.g. AXWindowCreated anywhere in the
        // app), AX delivers the specific descendant that changed - not the application element -
        // so those watchers are matched by PID instead of by an exact element match.
        let matchedWatchers = watchers.compactMap { key, watcherObject -> HSAXWatcherObject? in
            guard key.notification == notificationValue else { return nil }
            if key.element == element {
                return watcherObject
            }
            if watcherObject.isApplicationElement, let elementPid, (try? key.element.pid()) == elementPid {
                return watcherObject
            }
            return nil
        }

        if !matchedWatchers.isEmpty {
            // matchedWatchers can be empty if we're watching multiple notifications on an
            // element and only have watchers for some of them, or if this is the internal
            // destruction watch made by _addWatcher
            let wrappedElement = HSAXElement(element: element)
            let notificationName = _notificationTypes.firstKey(forValue: notificationValue) ?? notificationValue

            for watcherObject in matchedWatchers {
                watcherObject.handleEvent(element: wrappedElement, notification: notificationName)
            }
        }

        // Once the element is gone, none of its watchers can fire again. This runs after the
        // listeners above, so a uIElementDestroyed listener still hears about it, and it copes
        // with those listeners having already called off() themselves.
        if notification == Self.destroyedNotification {
            dropWatchers { key, _ in key.element == element }
        }
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
