//
//  HSUIDialog.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

/// # HSUIDialog
///
/// **A modal dialog with customizable buttons**
///
/// Shows a blocking dialog with a message, optional informative text, and custom buttons.
/// Use the callback to respond to button presses.
///
/// ## Example
///
/// ```javascript
/// hs.ui.dialog("Save changes?")
///     .informativeText("Your document has unsaved changes.")
///     .buttons(["Save", "Don't Save", "Cancel"])
///     .onButton((index) => {
///         if (index === 0) {
///             print("Saving...");
///         } else if (index === 1) {
///             print("Discarding changes...");
///         }
///     })
///     .show();
/// ```
@objc protocol HSUIDialogAPI: HSTypeAPI, JSExport {
    /// Set additional informative text below the main message
    /// - Parameter text: The informative text
    /// - Returns: Self for chaining
    @objc func informativeText(_ text: String) -> HSUIDialog

    /// Set custom button labels
    /// - Parameter labels: Array of button labels (default: ["OK"])
    /// - Returns: Self for chaining
    @objc func buttons(_ labels: [String]) -> HSUIDialog

    /// Set the dialog style
    /// - Parameter style: Style name (e.g., "informational", "warning", "critical")
    /// - Returns: Self for chaining
    @objc func style(_ style: String) -> HSUIDialog

    /// Set the callback for button presses
    /// - Parameter callback: Function receiving button index (0-based)
    /// - Returns: Self for chaining
    @objc func onButton(_ callback: JSValue) -> HSUIDialog

    /// Show the dialog
    /// - Returns: Self for chaining
    @objc func show() -> HSUIDialog

    /// Close the dialog programmatically
    @objc func close()
}

@MainActor
@objc class HSUIDialog: NSObject, HSUIDialogAPI, NSWindowDelegate {
    @objc var typeName = "HSUIDialog"

    var message: String
    var informativeText: String?
    var buttons: [String] = ["OK"]
    var style: String = "informational"

    private var buttonCallback: JSValue?
    private var nsWindow: NSWindow?
    private let dialogID: UUID = UUID()
    private weak var module: HSUIModule?

    init(message: String, module: HSUIModule) {
        self.message = message
        self.module = module
        super.init()
    }

    isolated deinit {
        close()
        AKTrace("deinit of HSUIDialog: \(dialogID)")
    }

    // MARK: - Builder Methods

    @objc func informativeText(_ text: String) -> HSUIDialog {
        self.informativeText = text
        return self
    }

    @objc func buttons(_ labels: [String]) -> HSUIDialog {
        if !labels.isEmpty {
            self.buttons = labels
        }
        return self
    }

    @objc func style(_ style: String) -> HSUIDialog {
        self.style = style
        return self
    }

    @objc func onButton(_ callback: JSValue) -> HSUIDialog {
        self.buttonCallback = callback
        return self
    }

    // MARK: - Display

    @objc func show() -> HSUIDialog {
        guard let screen = NSScreen.main else {
            AKError("hs.ui.dialog: Unable to find main screen")
            return self
        }

        // Calculate dialog size based on content
        let dialogWidth: CGFloat = 400
        let dialogHeight: CGFloat = 200
        let dialogFrame = CGRect(
            x: (screen.visibleFrame.width - dialogWidth) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - dialogHeight) / 2 + screen.visibleFrame.origin.y,
            width: dialogWidth,
            height: dialogHeight
        )

        let window = NSWindow(
            contentRect: dialogFrame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let contentView = UIDialogView(dialog: self) { [weak self] buttonIndex in
            self?.handleButtonPress(buttonIndex: buttonIndex)
        }
        window.contentView = NSHostingView(rootView: contentView)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.title = "Hammerspoon"
        window.delegate = self

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.nsWindow = window

        // Register with module to prevent premature deallocation
        module?.register(self, id: dialogID)

        return self
    }

    @objc func close() {
        guard nsWindow != nil else { return } // Already closed

        // Unregister from module
        module?.unregister(dialog: dialogID)

        nsWindow?.delegate = nil
        nsWindow?.orderOut(nil)
        nsWindow?.close()
        nsWindow = nil
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        // Window is being closed by user clicking close button
        // Call close() to clean up and unregister
        Task { @MainActor in
            self.close()
        }
    }

    // MARK: - Callback Handling

    private func handleButtonPress(buttonIndex: Int) {
        // Invoke callback
        Task { @MainActor in
            guard let callback = self.buttonCallback else {
                // No callback, just close the dialog
                close()
                return
            }

            callback.call(withArguments: [buttonIndex])

            // Check for JavaScript errors
            if let context = callback.context,
               let exception = context.exception,
               !exception.isUndefined {
                AKError("hs.ui.dialog: Error in callback: \(exception.toString() ?? "unknown error")")
                context.exception = nil
            }

            // Close the dialog after callback
            close()
        }
    }
}
