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
    /// - Parameter hsPoint: An HSPoint object containing screen coordinates
    /// - Returns: The AXElement at that position, or nil if none found
    @objc func elementAtPoint(_ point: HSPoint) -> HSAXElement?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSAXModule: NSObject, HSModuleAPI, HSAXModuleAPI {
    var name = "hs.ax"

    // MARK: - Module lifecycle
    override required init() { super.init() }

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
}
