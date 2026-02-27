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

/// # hs.ui
///
/// **Create custom user interfaces, alerts, dialogs, and file pickers**
///
/// The `hs.ui` module provides a set of tools for creating custom user interfaces
/// in Hammerspoon with SwiftUI-like declarative syntax.
///
/// ## Key Features
///
/// - **Custom Windows**: Build custom UI windows with shapes, text, and layouts
/// - **Alerts**: Display temporary on-screen notifications
/// - **Dialogs**: Show modal dialogs with custom buttons and callbacks
/// - **Text Input**: Prompt users for text input
/// - **File Pickers**: Let users select files or directories
///
/// ## Basic Examples
///
/// ### Simple Alert
/// ```javascript
/// hs.ui.alert("Task completed!")
///     .duration(3)
///     .show();
/// ```
///
/// ### Dialog with Buttons
/// ```javascript
/// hs.ui.dialog("Save changes?")
///     .informativeText("Your document has unsaved changes.")
///     .buttons(["Save", "Don't Save", "Cancel"])
///     .onButton((index) => {
///         if (index === 0) print("Saving...");
///     })
///     .show();
/// ```
///
/// ### Text Input Prompt
/// ```javascript
/// hs.ui.textPrompt("Enter your name")
///     .defaultText("John Doe")
///     .onButton((buttonIndex, text) => {
///         print("User entered: " + text);
///     })
///     .show();
/// ```
///
/// ### File Picker
/// ```javascript
/// hs.ui.filePicker()
///     .message("Choose a file")
///     .allowedFileTypes(["txt", "md"])
///     .onSelection((path) => {
///         if (path) print("Selected: " + path);
///     })
///     .show();
/// ```
///
/// ### Custom Window
/// ```javascript
/// hs.ui.window({x: 100, y: 100, w: 300, h: 200})
///     .vstack()
///         .spacing(10)
///         .padding(20)
///         .text("Hello, World!")
///             .font(HSFont.title())
///             .foregroundColor("#FFFFFF")
///         .rectangle()
///             .fill("#4A90E2")
///             .cornerRadius(10)
///             .frame({w: "100%", h: 60})
///     .end()
///     .backgroundColor("#2C3E50")
///     .show();
/// ```
///
/// ## Complete Example: Status Dashboard
///
/// Here's a more complex example showing how to build an interactive status dashboard
/// that combines multiple UI elements:
///
/// ```javascript
/// // Create a status dashboard window
/// const statusWindow = hs.ui.window({x: 100, y: 100, w: 400, h: 500})
///     .vstack()
///         .spacing(15)
///         .padding(20)
///
///         // Header
///         .text("System Status Dashboard")
///             .font(HSFont.largeTitle())
///             .foregroundColor("#FFFFFF")
///
///         // Status cards
///         .hstack()
///             .spacing(10)
///             .vstack()
///                 .spacing(5)
///                 .rectangle()
///                     .fill("#4CAF50")
///                     .cornerRadius(8)
///                     .frame({w: 180, h: 100})
///                 .text("CPU: 45%")
///                     .font(HSFont.headline())
///                     .foregroundColor("#FFFFFF")
///             .end()
///             .vstack()
///                 .spacing(5)
///                 .rectangle()
///                     .fill("#2196F3")
///                     .cornerRadius(8)
///                     .frame({w: 180, h: 100})
///                 .text("Memory: 8.2GB")
///                     .font(HSFont.headline())
///                     .foregroundColor("#FFFFFF")
///             .end()
///         .end()
///
///         // Activity indicator with image
///         .hstack()
///             .spacing(10)
///             .image(HSImage.fromName("NSComputer"))
///                 .resizable()
///                 .aspectRatio("fit")
///                 .frame({w: 64, h: 64})
///             .vstack()
///                 .text("System Running")
///                     .font(HSFont.title())
///                 .text("All services operational")
///                     .font(HSFont.caption())
///                     .foregroundColor("#A0A0A0")
///             .end()
///         .end()
///
///         // Circle status indicators
///         .hstack()
///             .spacing(20)
///             .circle()
///                 .fill("#4CAF50")
///                 .frame({w: 30, h: 30})
///             .circle()
///                 .fill("#FFC107")
///                 .frame({w: 30, h: 30})
///             .circle()
///                 .fill("#F44336")
///                 .frame({w: 30, h: 30})
///         .end()
///     .end()
///     .backgroundColor("#2C3E50");
///
/// // Show the dashboard
/// statusWindow.show();
///
/// // Later, interact with dialogs
/// hs.ui.dialog("Shutdown system?")
///     .informativeText("This will close all applications.")
///     .buttons(["Shutdown", "Cancel"])
///     .onButton((index) => {
///         if (index === 0) {
///             hs.ui.alert("Shutting down...")
///                 .duration(3)
///                 .show();
///         }
///     })
///     .show();
/// ```
@objc protocol HSUIModuleAPI: JSExport {
    /// Create a custom UI window
    ///
    /// Creates a borderless window that can contain custom UI elements built using a declarative,
    /// SwiftUI-like syntax with shapes, text, and layout containers.
    ///
    /// - Parameter dict: Dictionary with keys: `x`, `y`, `w`, `h` (all numbers)
    /// - Returns: An `HSUIWindow` object for chaining
    ///
    /// **Basic Example:**
    /// ```javascript
    /// // Simple colored window
    /// hs.ui.window({x: 100, y: 100, w: 400, h: 300})
    ///     .rectangle()
    ///         .fill("#FF0000")
    ///         .frame({w: "100%", h: "100%"})
    ///     .show();
    /// ```
    ///
    /// **Advanced Example:**
    /// ```javascript
    /// // Notification card with image and text
    /// hs.ui.window({x: 50, y: 50, w: 350, h: 120})
    ///     .hstack()
    ///         .spacing(15)
    ///         .padding(15)
    ///         // Icon
    ///         .image(HSImage.fromName("NSInfo"))
    ///             .resizable()
    ///             .aspectRatio("fit")
    ///             .frame({w: 48, h: 48})
    ///         // Content
    ///         .vstack()
    ///             .spacing(5)
    ///             .text("New Message")
    ///                 .font(HSFont.headline())
    ///                 .foregroundColor("#FFFFFF")
    ///             .text("You have 3 unread messages")
    ///                 .font(HSFont.subheadline())
    ///                 .foregroundColor("#CCCCCC")
    ///         .end()
    ///     .end()
    ///     .backgroundColor("#1E1E1E")
    ///     .show();
    /// ```
    @objc func window(_ dict: [String: Any]) -> HSUIWindow

    /// Create a temporary on-screen alert
    ///
    /// Displays a temporary notification that automatically dismisses after the specified duration.
    /// Similar to the old `hs.alert` module but with more features.
    ///
    /// - Parameter message: The message text to display
    /// - Returns: An `HSUIAlert` object for chaining
    ///
    /// **Basic Example:**
    /// ```javascript
    /// hs.ui.alert("Task completed successfully!")
    ///     .duration(3)
    ///     .show();
    /// ```
    ///
    /// **Styled Example:**
    /// ```javascript
    /// // Success notification with custom styling
    /// hs.ui.alert("✓ File saved successfully")
    ///     .font(HSFont.headline())
    ///     .duration(5)
    ///     .padding(30)
    ///     .backgroundColor("#4CAF50")
    ///     .foregroundColor("#FFFFFF")
    ///     .show();
    ///
    /// // Warning alert
    /// hs.ui.alert("⚠ Low battery")
    ///     .font(HSFont.body())
    ///     .duration(10)
    ///     .backgroundColor("#FFC107")
    ///     .foregroundColor("#000000")
    ///     .show();
    /// ```
    @objc func alert(_ message: String) -> HSUIAlert

    /// Create a modal dialog with buttons
    ///
    /// Shows a blocking dialog with customizable message, informative text, and buttons.
    /// Use the callback to handle button presses.
    ///
    /// - Parameter message: The main message text
    /// - Returns: An `HSUIDialog` object for chaining
    ///
    /// **Simple Example:**
    /// ```javascript
    /// hs.ui.dialog("Continue with this action?")
    ///     .buttons(["Continue", "Cancel"])
    ///     .onButton((index) => {
    ///         if (index === 0) {
    ///             console.log("User chose to continue");
    ///         }
    ///     })
    ///     .show();
    /// ```
    ///
    /// **Detailed Example:**
    /// ```javascript
    /// // Confirmation dialog with multiple options
    /// hs.ui.dialog("Save changes?")
    ///     .informativeText("Your document has unsaved changes. What would you like to do?")
    ///     .buttons(["Save", "Don't Save", "Cancel"])
    ///     .onButton((index) => {
    ///         if (index === 0) {
    ///             console.log("Saving document...");
    ///             // Save logic here
    ///         } else if (index === 1) {
    ///             console.log("Discarding changes...");
    ///             // Close without saving
    ///         }
    ///         // index === 2 is Cancel - do nothing
    ///     })
    ///     .show();
    /// ```
    @objc func dialog(_ message: String) -> HSUIDialog

    /// Create a text input prompt
    ///
    /// Shows a modal dialog with a text input field. The callback receives the button index
    /// and the entered text.
    ///
    /// - Parameter message: The prompt message
    /// - Returns: An `HSUITextPrompt` object for chaining
    ///
    /// **Simple Example:**
    /// ```javascript
    /// hs.ui.textPrompt("Enter your name")
    ///     .onButton((buttonIndex, text) => {
    ///         if (buttonIndex === 0) {
    ///             console.log("Hello, " + text + "!");
    ///         }
    ///     })
    ///     .show();
    /// ```
    ///
    /// **Detailed Example:**
    /// ```javascript
    /// // Git commit message prompt
    /// hs.ui.textPrompt("Git Commit")
    ///     .informativeText("Enter your commit message:")
    ///     .defaultText("Update documentation")
    ///     .buttons(["Commit", "Cancel"])
    ///     .onButton((buttonIndex, text) => {
    ///         if (buttonIndex === 0 && text.length > 0) {
    ///             // Execute git commit
    ///             hs.task.new("/usr/bin/git", ["commit", "-m", text])
    ///                 .start();
    ///             hs.ui.alert("✓ Committed: " + text)
    ///                 .duration(3)
    ///                 .show();
    ///         }
    ///     })
    ///     .show();
    /// ```
    @objc func textPrompt(_ message: String) -> HSUITextPrompt

    /// Create a file or directory picker
    ///
    /// Shows a standard macOS file picker dialog. Can be configured to select files,
    /// directories, or both, with support for file type filtering and multiple selection.
    ///
    /// - Returns: An `HSUIFilePicker` object for chaining
    ///
    /// **Simple File Picker:**
    /// ```javascript
    /// hs.ui.filePicker()
    ///     .message("Choose a file to open")
    ///     .allowedFileTypes(["txt", "md", "js"])
    ///     .onSelection((path) => {
    ///         if (path) {
    ///             console.log("Selected: " + path);
    ///         }
    ///     })
    ///     .show();
    /// ```
    ///
    /// **Directory Picker:**
    /// ```javascript
    /// hs.ui.filePicker()
    ///     .message("Select backup directory")
    ///     .canChooseFiles(false)
    ///     .canChooseDirectories(true)
    ///     .allowsMultipleSelection(false)
    ///     .onSelection((path) => {
    ///         if (path) {
    ///             console.log("Backing up to: " + path);
    ///             // Perform backup to selected directory
    ///         }
    ///     })
    ///     .show();
    /// ```
    ///
    /// **Multiple File Selection:**
    /// ```javascript
    /// // Select multiple images for processing
    /// hs.ui.filePicker()
    ///     .message("Choose images to convert")
    ///     .allowedFileTypes(["jpg", "png", "gif"])
    ///     .allowsMultipleSelection(true)
    ///     .onSelection((paths) => {
    ///         if (paths && paths.length > 0) {
    ///             console.log("Converting " + paths.length + " images...");
    ///             paths.forEach((path, index) => {
    ///                 console.log("  " + (index + 1) + ": " + path);
    ///                 // Convert each image
    ///             });
    ///         }
    ///     })
    ///     .show();
    /// ```
    @objc func filePicker() -> HSUIFilePicker
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

    @objc func textPrompt(_ message: String) -> HSUITextPrompt {
        // Use assumeIsolated since JSContext evaluates on main thread
        return MainActor.assumeIsolated {
            let prompt = HSUITextPrompt(message: message, module: self)
            return prompt
        }
    }

    @objc func filePicker() -> HSUIFilePicker {
        // Use assumeIsolated since JSContext evaluates on main thread
        return MainActor.assumeIsolated {
            let picker = HSUIFilePicker(module: self)
            return picker
        }
    }
}
