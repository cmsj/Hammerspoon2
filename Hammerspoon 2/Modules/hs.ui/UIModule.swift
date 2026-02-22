//
//  UIModule.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit

// MARK: - Declare our JavaScript API

/// Module for creating custom UI windows and dialogs
@objc protocol HSUIModuleAPI: JSExport {
    /// Create a new UI window with a frame dictionary
    /// - Parameter dict: Dictionary with x, y, w, h keys
    /// - Returns: An HSUIWindow object
    @objc func window(_ dict: [String: Any]) -> HSUIWindow

    /// Create a simple alert (similar to hs.alert but part of hs.ui)
    /// - Parameter message: The message to display
    /// - Returns: An HSUIAlert object
    @objc func alert(_ message: String) -> HSUIAlert

    /// Create a dialog with buttons
    /// - Parameter message: The message to display
    /// - Returns: An HSUIDialog object
    @objc func dialog(_ message: String) -> HSUIDialog
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSUIModule: NSObject, HSModuleAPI, HSUIModuleAPI {
    var name = "hs.ui"

    // Keep strong references to active windows to prevent premature deallocation
    private var activeWindows: [UUID: HSUIWindow] = [:]
    private var activeAlerts: [UUID: HSUIAlert] = [:]
    private var activeDialogs: [UUID: HSUIDialog] = [:]

    // MARK: - Module lifecycle
    override required init() {
        super.init()
    }

    func shutdown() {
        // Close all windows
        for window in activeWindows.values {
            window.close()
        }
        activeWindows.removeAll()

        // Close all alerts
        for alert in activeAlerts.values {
            alert.close()
        }
        activeAlerts.removeAll()

        // Close all dialogs
        for dialog in activeDialogs.values {
            dialog.close()
        }
        activeDialogs.removeAll()
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Object Registration (called by UI objects when shown/closed)

    func register(_ window: HSUIWindow, id: UUID) {
        activeWindows[id] = window
    }

    func unregister(window id: UUID) {
        activeWindows.removeValue(forKey: id)
    }

    func register(_ alert: HSUIAlert, id: UUID) {
        activeAlerts[id] = alert
    }

    func unregister(alert id: UUID) {
        activeAlerts.removeValue(forKey: id)
    }

    func register(_ dialog: HSUIDialog, id: UUID) {
        activeDialogs[id] = dialog
    }

    func unregister(dialog id: UUID) {
        activeDialogs.removeValue(forKey: id)
    }

    // MARK: - Factory Methods

    @objc func window(_ dict: [String: Any]) -> HSUIWindow {
        // Use assumeIsolated since JSContext evaluates on main thread
        return MainActor.assumeIsolated {
            let window = HSUIWindow(dict: dict, module: self)
            return window
        }
    }

    @objc func alert(_ message: String) -> HSUIAlert {
        // Use assumeIsolated since JSContext evaluates on main thread
        return MainActor.assumeIsolated {
            let alert = HSUIAlert(message: message, module: self)
            return alert
        }
    }

    @objc func dialog(_ message: String) -> HSUIDialog {
        // Use assumeIsolated since JSContext evaluates on main thread
        return MainActor.assumeIsolated {
            let dialog = HSUIDialog(message: message, module: self)
            return dialog
        }
    }
}
