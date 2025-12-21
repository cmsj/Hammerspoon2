//
//  AXModule.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AppKit
import AXSwift

// MARK: - Declare our JavaScript API

/// Module for interacting with the macOS Accessibility API
@objc protocol HSAXModuleAPI: JSExport {
    /// Get the system-wide accessibility element
    /// - Returns: The system-wide AXElement, or nil if accessibility is not available
    @objc func systemWideElement() -> HSAXElement?

    /// Get the accessibility element for an application
    /// - Parameters:
    ///   - element: An HSApplication object
    /// - Returns: The AXElement for the application, or nil if accessibility is not available
    @objc func applicationElement(_ element: HSApplication) -> HSAXElement?

    /// Get the accessibility element for a window
    /// - Parameters:
    ///   - window: An HSWindow  object
    /// - Returns: The AXElement for the window, or nil if accessibility is not available
    @objc func windowElement(_ window: HSWindow) -> HSAXElement?

    /// Get the accessibility element at the specific screen position
    /// - Parameter point: An HSPoint object containing screen coordinates
    /// - Returns: The AXElement at that position, or nil if none found
    @objc func elementAtPoint(_ point: HSPoint) -> HSAXElement?

    /// A dictionary containing all of the notification types that can be used with hs.ax.addWatcher()
    @objc var notificationTypes: [String: String] { get }

    // NOTE: These are private API for JavaScript code to use
    /// SKIP_DOCS
    @objc(_addWatcher:::) func _addWatcher(_ application: HSApplication, notification: String, callback: JSValue)
    /// SKIP_DOCS
    @objc(_removeWatcher::) func _removeWatcher(_ application: HSApplication, notification: String)
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSAXModule: NSObject, HSModuleAPI, HSAXModuleAPI {
    var name = "hs.ax"

    // Store observers by PID
    private var observers: [pid_t: Observer] = [:]

    // Store watchers by a key composed of "pid:notification"
    private var watchers: [String: HSAXWatcherObject] = [:]

    // Notification types exposed to JavaScript
    @objc var _notificationTypes: [String: String] = [:]

    // MARK: - Module lifecycle

    override required init() {
        // Build the notification types dictionary
        for notificationType in UIElement.AXNotification.allCases {
            var name = notificationType.rawValue
            if name.hasPrefix("AX") {
                name = String(name.dropFirst(2)) // Remove "AX" prefix
            }
            // Convert to camelCase starting with lowercase
            if let first = name.first {
                name = first.lowercased() + name.dropFirst()
            }
            _notificationTypes[name] = notificationType.rawValue
        }
        super.init()
    }

    func shutdown() {
        // Clean up all watchers
        for key in watchers.keys {
            if let watcherObject = watchers[key] {
                do {
                    let pid = try watcherObject.element.pid()
                    if let observer = observers[pid] {
                        do {
                            try observer.removeNotification(watcherObject.notification, forElement: watcherObject.element)
                            AKTrace("hs.ax: Removed watcher for \(watcherObject.notification.rawValue)")
                        } catch {
                            AKError("hs.ax: Error removing watcher: \(error)")
                        }
                    }
                } catch {
                    AKError("hs.ax: Error getting PID during shutdown: \(error)")
                }
            }
            watchers.removeValue(forKey: key)
        }

        // Stop all observers
        for (_, observer) in observers {
            observer.stop()
        }
        observers.removeAll()
    }

    isolated deinit {
        print("Deinit of \(name)")
        shutdown()
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

    // MARK: - Watcher Management

    private func makeWatcherKey(pid: pid_t, notification: String) -> String {
        return "\(pid):\(notification)"
    }

    @objc(_addWatcher:::) func _addWatcher(_ application: HSApplication, notification: String, callback: JSValue) {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.addWatcher(): Accessibility permissions not granted")
            return
        }

        let pid = application.runningApplication.processIdentifier
        let key = makeWatcherKey(pid: pid, notification: notification)

        // Check if we already have a watcher for this combination
        if watchers.keys.contains(key) {
            AKWarning("hs.ax.addWatcher(): There is already a watcher for \(notification) on PID \(pid). Refusing to create a second.")
            return
        }

        // Get the application element
        guard let appElement = application.axElement() else {
            AKError("hs.ax.addWatcher(): Could not get AX element for application")
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
                    self.handleNotification(pid: pid, element: element, notification: notification)
                }
                observers[pid] = observer
                AKTrace("hs.ax.addWatcher(): Created observer for PID \(pid)")
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
        let watcherObject = HSAXWatcherObject(element: appElement.element, notification: notifType, callback: callback)
        watchers[key] = watcherObject

        // Add the notification to the observer
        do {
            try observer.addNotification(notifType, forElement: appElement.element)
            AKTrace("hs.ax.addWatcher(): Added watcher for \(notification) on PID \(pid)")
        } catch {
            AKError("hs.ax.addWatcher(): Failed to add notification: \(error)")
            watchers.removeValue(forKey: key)
        }
    }

    @objc(_removeWatcher::) func _removeWatcher(_ application: HSApplication, notification: String) {
        let pid = application.runningApplication.processIdentifier
        let key = makeWatcherKey(pid: pid, notification: notification)

        guard let watcherObject = watchers[key] else {
            AKTrace("hs.ax.removeWatcher(): No watcher found for \(notification) on PID \(pid)")
            return
        }

        guard let observer = observers[pid] else {
            AKTrace("hs.ax.removeWatcher(): No observer found for PID \(pid)")
            watchers.removeValue(forKey: key)
            return
        }

        // Remove the notification from the observer
        do {
            try observer.removeNotification(watcherObject.notification, forElement: watcherObject.element)
            AKTrace("hs.ax.removeWatcher(): Removed watcher for \(notification) on PID \(pid)")
        } catch {
            AKError("hs.ax.removeWatcher(): Failed to remove notification: \(error)")
        }

        watchers.removeValue(forKey: key)

        // If there are no more watchers for this PID, clean up the observer
        let remainingWatchers = watchers.keys.filter { $0.hasPrefix("\(pid):") }
        if remainingWatchers.isEmpty {
            observer.stop()
            observers.removeValue(forKey: pid)
            AKTrace("hs.ax.removeWatcher(): Removed observer for PID \(pid) (no more watchers)")
        }
    }

    /// Handle a notification from the observer
    private func handleNotification(pid: pid_t, element: UIElement, notification: UIElement.AXNotification) {
        let key = makeWatcherKey(pid: pid, notification: notification.rawValue)

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
}
