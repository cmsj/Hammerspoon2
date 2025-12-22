//
//  AlertModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/11/2025.
//


import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

// MARK: - Declare our JavaScript API

/// Module for accessing information about the Hammerspoon application itself
@objc protocol HSAlertModuleAPI: JSExport {
    /// Create a new HSAlert object
    /// - Returns: An HSAlert object
    @objc func newAlert() -> HSAlert
    /// Show an HSAlert object
    /// - Parameter alert: The HSAlert object to show
    @objc func showAlert(_ alert: HSAlert)
    /// Show an alert to the user
    /// - Parameter message: The text to include in the alert
    @objc func show(_ message: String)
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSAlertModule: NSObject, HSModuleAPI, HSAlertModuleAPI {
    var name = "hs.alert"

    // MARK: - Module lifecycle
    override required init() {
        super.init()
    }

    func shutdown() {}

    deinit {
        print("Deinit of \(name)")
    }

    func makeAlertWindow(for screen: NSScreen, message: HSAlert) -> NSWindow {
        let window = NSWindow(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)

        window.contentView = NSHostingView(rootView: AlertView(message: message))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.isReleasedWhenClosed = false

        return window
    }

    @objc func newAlert() -> HSAlert {
        return HSAlert()
    }

    @objc func showAlert(_ alert: HSAlert) {
        guard let screen = NSScreen.main else {
            AKError("Unable to find main screen for alert")
            return
        }

        let window = makeAlertWindow(for: screen, message: alert)

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(alert.expire))
            window.orderOut(nil)
        }
    }

    @objc func show(_ message: String) {
        let alert = newAlert()
        alert.font = .title()
        alert.message = message
        showAlert(alert)
    }
}
