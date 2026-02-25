//
//  HSUITextPrompt.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 21/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit

/// # HSUITextPrompt
///
/// **A modal dialog with text input**
///
/// Shows a blocking dialog with a text input field. The callback receives both the
/// button index and the entered text.
///
/// ## Example
///
/// ```javascript
/// hs.ui.textPrompt("Enter your name")
///     .informativeText("Please provide your full name")
///     .defaultText("John Doe")
///     .buttons(["OK", "Cancel"])
///     .onButton((buttonIndex, text) => {
///         if (buttonIndex === 0) {
///             print("User entered: " + text);
///         }
///     })
///     .show();
/// ```
@objc protocol HSUITextPromptAPI: HSTypeAPI, JSExport {
    /// Set additional informative text below the main message
    /// - Parameter text: The informative text
    /// - Returns: Self for chaining
    @objc func informativeText(_ text: String) -> HSUITextPrompt

    /// Set the default text in the input field
    /// - Parameter text: Default text value
    /// - Returns: Self for chaining
    @objc func defaultText(_ text: String) -> HSUITextPrompt

    /// Set custom button labels
    /// - Parameter labels: Array of button labels (default: ["OK", "Cancel"])
    /// - Returns: Self for chaining
    @objc func buttons(_ labels: [String]) -> HSUITextPrompt

    /// Set the callback for button presses
    /// - Parameter callback: Function receiving (buttonIndex, inputText)
    /// - Returns: Self for chaining
    @objc func onButton(_ callback: JSValue) -> HSUITextPrompt

    /// Show the prompt dialog
    @objc func show()
}

@MainActor
@objc class HSUITextPrompt: NSObject, HSUITextPromptAPI {
    @objc var typeName = "HSUITextPrompt"

    var message: String
    var informativeText: String?
    var defaultText: String = ""
    var buttons: [String] = ["OK", "Cancel"]

    private var buttonCallback: JSValue?
    private weak var module: HSUIModule?

    init(message: String, module: HSUIModule) {
        self.message = message
        self.module = module
        super.init()
    }

    // MARK: - Builder Methods

    @objc func informativeText(_ text: String) -> HSUITextPrompt {
        self.informativeText = text
        return self
    }

    @objc func defaultText(_ text: String) -> HSUITextPrompt {
        self.defaultText = text
        return self
    }

    @objc func buttons(_ labels: [String]) -> HSUITextPrompt {
        if !labels.isEmpty {
            self.buttons = labels
        }
        return self
    }

    @objc func onButton(_ callback: JSValue) -> HSUITextPrompt {
        self.buttonCallback = callback
        return self
    }

    // MARK: - Display

    @objc func show() {
        let alert = NSAlert()
        alert.messageText = message
        if let info = informativeText {
            alert.informativeText = info
        }

        // Add buttons in reverse order (NSAlert adds them right-to-left)
        for button in buttons.reversed() {
            alert.addButton(withTitle: button)
        }

        // Create text field
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = defaultText
        textField.placeholderString = ""
        alert.accessoryView = textField

        // Show the alert
        let response = alert.runModal()

        // Calculate button index (first button is .alertFirstButtonReturn)
        let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

        // Get the text input
        let inputText = textField.stringValue

        // Invoke callback
        if let callback = buttonCallback {
            callback.call(withArguments: [buttonIndex, inputText])

            // Check for JavaScript errors
            if let context = callback.context,
               let exception = context.exception,
               !exception.isUndefined {
                AKError("hs.ui.textPrompt: Error in callback: \(exception.toString() ?? "unknown error")")
                context.exception = nil
            }
        }
    }
}
