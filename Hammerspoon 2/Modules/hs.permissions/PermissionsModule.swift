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
    /// - Returns: A Promise that resolves to true if granted, false if denied
    @objc func requestCamera() -> JSValue?

    /// Check if the app has Microphone permission
    /// - Returns: true if permission is granted, false otherwise
    @objc func checkMicrophone() -> Bool

    /// Request Microphone permission (shows system dialog if not granted)
    /// - Returns: A Promise that resolves to true if granted, false if denied
    @objc func requestMicrophone() -> JSValue?
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

    @objc func requestCamera() -> JSValue? {
        return JSEngine.shared.createPromise { holder in
            PermissionsManager.shared.request(.camera) { result in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        holder.resolveWith(result)
                    }
                }
            }
        }
    }

    // MARK: - Microphone

    @objc func checkMicrophone() -> Bool {
        return PermissionsManager.shared.check(.microphone)
    }

    @objc func requestMicrophone() -> JSValue? {
        return JSEngine.shared.createPromise { holder in
            PermissionsManager.shared.request(.microphone) { result in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        holder.resolveWith(result)
                    }
                }
            }
        }
    }
}
