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
///             console.log("Saving...");
///         } else if (index === 1) {
///             console.log("Discarding changes...");
///         }
///     })
///     .show();
/// ```
@objc protocol HSUIDialogAPI: HSTypeAPI, JSExport {
    /// Set additional informative text below the main message
    /// - Parameter text: The informative text
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.dialog("Save?").informativeText("Unsaved changes").show()
    /// ```
    @objc func informativeText(_ text: String) -> HSUIDialog

    /// Set custom button labels
    /// - Parameter labels: Array of button labels (default: ["OK"])
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.dialog("Save?").buttons(["Save", "Discard", "Cancel"]).show()
    /// ```
    @objc func buttons(_ labels: [String]) -> HSUIDialog

    /// Set the dialog style
    /// - Parameter style: Style name (e.g., "informational", "warning", "critical")
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.dialog("Delete?").style("critical").show()
    /// ```
    @objc func style(_ style: String) -> HSUIDialog

    /// Set the callback for button presses
    /// - Parameter callback: {(buttonIndex: number) => void} Function receiving the 0-based index of the button the user pressed
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.dialog("Confirm?")
    ///     .onButton((i) => console.log("button", i))
    ///     .show()
    /// ```
    @objc func onButton(_ callback: JSFunction) -> HSUIDialog

    /// Show the dialog
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.dialog("Hello").show()
    /// ```
    @objc func show() -> HSUIDialog

    /// Close the dialog programmatically
    /// - Example:
    /// ```js
    /// const d = hs.ui.dialog("Hello").show()
    /// d.close()
    /// ```
    @objc func close()
}

@MainActor
@objc class HSUIDialog: NSObject, HSUIDialogAPI, NSWindowDelegate {
    @objc var typeName = "HSUIDialog"

    var message: String
    var informativeText: String?
    var buttons: [String] = ["OK"]
    var style: String = "informational"

    private var buttonCallback: JSFunction?
    private var nsWindow: NSWindow?
    private let dialogID: UUID = UUID()
    private weak var module: HSUIModule?

    init(message: String, module: HSUIModule) {
        self.message = message
        self.module = module
        super.init()
    }

    deinit {
        // In the normal shutdown path close() has already been called, so nsWindow is nil
        // and this is a no-op. In the unexpected edge case where the object is freed without
        // close() being called, dispatch AppKit cleanup to the main thread without retaining
        // self (capturing only the NSWindow and UUID values).
        guard let window = nsWindow else { return }
        let id = dialogID
        let capturedModule = module
        DispatchQueue.main.async {
            capturedModule?.unregister(dialog: id)
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
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

    @objc func onButton(_ callback: JSFunction) -> HSUIDialog {
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

        module?.unregister(dialog: dialogID)

        // Explicitly nil the contentView so UIDialogView (which holds a strong ref back
        // to self) is released synchronously before AppKit's async window cleanup runs.
        nsWindow?.contentView = nil
        nsWindow?.delegate = nil
        nsWindow?.orderOut(nil)
        nsWindow?.close()
        nsWindow = nil

        // Release the callback so its captured JSValue doesn't hold the old JSContext alive.
        buttonCallback = nil
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
