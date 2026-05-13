//
//  PermissionsModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore
import AVFoundation

// MARK: - Declare our JavaScript API

/// Module for checking and requesting system permissions
@objc protocol HSPermissionsModuleAPI: JSExport {
    /// Check if the app has Accessibility permission
    /// - Returns: true if permission is granted, false otherwise
    @objc func checkAccessibility() -> Bool

    /// Request Accessibility permission (shows system dialog if not granted)
    @objc func requestAccessibility()

    /// Check if the app has Screen Recording permission
    /// - Returns: true if permission is granted, false otherwise
    @objc func checkScreenRecording() -> Bool

    /// Request Screen Recording permission
    /// - Note: This will trigger a screen capture which prompts the system dialog
    @objc func requestScreenRecording()

    /// Check if the app has Camera permission
    /// - Returns: true if permission is granted, false otherwise
    @objc func checkCamera() -> Bool

    /// Request Camera permission (shows system dialog if not granted)
    /// - Returns: {Promise<boolean>} A Promise that resolves to true if granted, false if denied
    @objc func requestCamera() -> JSPromise?

    /// Check if the app has Microphone permission
    /// - Returns: true if permission is granted, false otherwise
    @objc func checkMicrophone() -> Bool

    /// Request Microphone permission (shows system dialog if not granted)
    /// - Returns: {Promise<boolean>} A Promise that resolves to true if granted, false if denied
    @objc func requestMicrophone() -> JSPromise?

    /// Check if the app has permission to display notifications.
    ///
    /// The result is cached from the last request or check; the cache is refreshed asynchronously,
    /// so the very first call in a session may return `false` before the cached value is populated.
    /// Use `requestNotifications()` on first launch to ensure the result is accurate.
    /// - Returns: true if notification permission is granted
    @objc func checkNotifications() -> Bool

    /// Request notification permission (shows the system dialog if the user has not yet decided).
    ///
    /// It is safe to call this on every launch — the dialog only appears once; subsequent calls
    /// resolve immediately with the previously granted or denied state.
    /// - Returns: {Promise<boolean>} A Promise that resolves to true if granted, false if denied
    @objc func requestNotifications() -> JSPromise?
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSPermissionsModule: NSObject, HSModuleAPI, HSPermissionsModuleAPI {
    var name = "hs.permissions"

    // MARK: - Module lifecycle
    override required init() { super.init() }

    func shutdown() {}

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Accessibility

    @objc func checkAccessibility() -> Bool {
        return PermissionsManager.shared.check(.accessibility)
    }

    @objc func requestAccessibility() {
        PermissionsManager.shared.request(.accessibility)
    }

    // MARK: - Screen Recording
    @objc func checkScreenRecording() -> Bool {
        return PermissionsManager.shared.check(.screencapture)
    }

    @objc func requestScreenRecording() {
        PermissionsManager.shared.request(.screencapture)
    }

    // MARK: - Camera

    @objc func checkCamera() -> Bool {
        return PermissionsManager.shared.check(.camera)
    }

    @objc func requestCamera() -> JSPromise? {
        return JSEngine.shared.createPromise { holder in
            PermissionsManager.shared.request(.camera) { result in
                Task { @MainActor in
                    holder.resolveWith(result)
                }
            }
        }
    }

    // MARK: - Microphone

    @objc func checkMicrophone() -> Bool {
        return PermissionsManager.shared.check(.microphone)
    }

    @objc func requestMicrophone() -> JSPromise? {
        return JSEngine.shared.createPromise { holder in
            PermissionsManager.shared.request(.microphone) { result in
                Task { @MainActor in
                    holder.resolveWith(result)
                }
            }
        }
    }

    // MARK: - Notifications

    @objc func checkNotifications() -> Bool {
        return PermissionsManager.shared.check(.notifications)
    }

    @objc func requestNotifications() -> JSPromise? {
        return JSEngine.shared.createPromise { holder in
            PermissionsManager.shared.request(.notifications) { result in
                Task { @MainActor in
                    holder.resolveWith(result)
                }
            }
        }
    }
}
