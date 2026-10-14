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
    /// - Note: A showing dialog, and its callback, stay alive until it's closed, even if you don't keep a reference to it
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

    @objc func toString() -> String {
        return "<\(typeName): \(message)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    var message: String
    var informativeText: String?
    var buttons: [String] = ["OK"]
    var style: String = "informational"

    private var buttonCallback: JSCallback?
    private weak var module: HSUIModule?

    // A showing dialog is active: it stays on screen, with its callback, until it's closed,
    // even if the user dropped their reference to it.
    private var nsWindow: NSWindow? {
        didSet {
            module?.dialogs.setActive(self, nsWindow != nil)
        }
    }

    init(message: String, module: HSUIModule) {
        self.message = message
        self.module = module
        super.init()
        module.dialogs.add(self)
    }

    deinit {
        // In the normal shutdown path close() has already been called, so nsWindow is nil
        // and this is a no-op. In the unexpected edge case where the object is freed without
        // close() being called, dispatch AppKit cleanup to the main thread without retaining
        // self (capturing only the NSWindow and UUID values).
        guard let window = nsWindow else { return }
        DispatchQueue.main.async {
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
        buttonCallback?.detach(from: self)
        buttonCallback = JSCallback(value: callback, owner: self)
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

        return self
    }

    @objc func close() {
        guard nsWindow != nil else { return } // Already closed

        // Explicitly nil the contentView so UIDialogView (which holds a strong ref back
        // to self) is released synchronously before AppKit's async window cleanup runs.
        nsWindow?.contentView = nil
        nsWindow?.delegate = nil
        nsWindow?.orderOut(nil)
        nsWindow?.close()
        nsWindow = nil

        buttonCallback?.detach(from: self)
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

    // Internal rather than private so tests can press buttons
    func handleButtonPress(buttonIndex: Int) {
        // Invoke callback
        Task { @MainActor in
            guard let callback = self.buttonCallback?.value else {
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

extension HSUIDialog: HSTrackedObject {
    /// Closes the dialog, at module shutdown
    func destroy() {
        close()
    }
}
