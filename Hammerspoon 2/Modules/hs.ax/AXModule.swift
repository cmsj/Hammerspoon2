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
    @objc var notificationTypes: [String:String] { get }

    @_documentation(visibility: private)
    @objc func _createObserver(_ pid: Int) -> HSAXObserver?

    @objc func addWatcher(_ application: HSApplication, _ notification: String, _ callback: JSValue) -> HSAXObserver?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSAXModule: NSObject, HSModuleAPI, HSAXModuleAPI {
    var name = "hs.ax"
    private var watchers: [pid_t:HSAXObserver] = [:]

    @objc var _notificationTypes: [String:String] = [:]

    // MARK: - Module lifecycle
    override required init() {
        for notificationType in UIElement.AXNotification.allCases {
            var name = notificationType.rawValue
            if name.hasPrefix("AX") {
                name = name.deletingPrefix("AX")
            }
            name.lowerFirstLetter()

            _notificationTypes[name] = notificationType.rawValue
        }
        super.init()
    }

    func shutdown() {
        // No cleanup needed for this module
    }

    deinit {
        print("Deinit of \(name)")
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

    func isAccessibilityEnabled() -> Bool {
        return PermissionsManager.shared.check(.accessibility)
    }

    func requestAccessibility() {
        PermissionsManager.shared.request(.accessibility)
    }

    @objc var notificationTypes: [String:String] {
        return _notificationTypes
    }

    @objc func _createObserver(_ pid: Int) -> HSAXObserver? {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.createObserver(): Accessibility permissions not granted")
            return nil
        }

        return HSAXObserver(pid: pid_t(pid))
    }

    @objc func addWatcher(_ application: HSApplication, _ notification: String, _ callback: JSValue) -> HSAXObserver? {
        guard isAccessibilityEnabled() else {
            AKError("hs.ax.addWatcher(): Accessibility permissions not granted")
            return nil
        }

        let pid = application.runningApplication.processIdentifier
        if !watchers.keys.contains(pid) {
            watchers[pid] = HSAXObserver(pid: pid)
        }

        let watcher = watchers[pid]

        return watcher
    }
}
