//
//  HSUIFilePicker.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 21/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit
import UniformTypeIdentifiers

/// # HSUIFilePicker
///
/// **A file or directory selection dialog**
///
/// Shows a standard macOS open panel for selecting files or directories. Supports
/// multiple selection, file type filtering, and more.
///
/// ## Examples
///
/// ### File Picker
/// ```javascript
/// hs.ui.filePicker()
///     .message("Choose a file to open")
///     .allowedFileTypes(["txt", "md", "js"])
///     .onSelection((path) => {
///         if (path) {
///             print("Selected: " + path);
///         } else {
///             print("User cancelled");
///         }
///     })
///     .show();
/// ```
///
/// ### Directory Picker with Multiple Selection
/// ```javascript
/// hs.ui.filePicker()
///     .message("Choose directories to backup")
///     .canChooseFiles(false)
///     .canChooseDirectories(true)
///     .allowsMultipleSelection(true)
///     .onSelection((paths) => {
///         if (paths) {
///             paths.forEach(p => print("Dir: " + p));
///         }
///     })
///     .show();
/// ```
@objc protocol HSUIFilePickerAPI: HSTypeAPI, JSExport {
    /// Set the message displayed in the picker
    /// - Parameter text: The message text
    /// - Returns: Self for chaining
    @objc func message(_ text: String) -> HSUIFilePicker

    /// Set the starting directory
    /// - Parameter path: Path to directory (supports `~` for home)
    /// - Returns: Self for chaining
    @objc func defaultPath(_ path: String) -> HSUIFilePicker

    /// Set whether files can be selected
    /// - Parameter value: true to allow file selection (default: true)
    /// - Returns: Self for chaining
    @objc func canChooseFiles(_ value: Bool) -> HSUIFilePicker

    /// Set whether directories can be selected
    /// - Parameter value: true to allow directory selection (default: false)
    /// - Returns: Self for chaining
    @objc func canChooseDirectories(_ value: Bool) -> HSUIFilePicker

    /// Set whether multiple items can be selected
    /// - Parameter value: true to allow multiple selection (default: false)
    /// - Returns: Self for chaining
    @objc func allowsMultipleSelection(_ value: Bool) -> HSUIFilePicker

    /// Restrict to specific file types
    /// - Parameter types: Array of file extensions (e.g., ["txt", "md"])
    /// - Returns: Self for chaining
    @objc func allowedFileTypes(_ types: [String]) -> HSUIFilePicker

    /// Set whether to resolve symbolic links
    /// - Parameter value: true to resolve aliases (default: true)
    /// - Returns: Self for chaining
    @objc func resolvesAliases(_ value: Bool) -> HSUIFilePicker

    /// Set the callback for file selection
    /// - Parameter callback: Function receiving selected path(s) or null if cancelled
    ///   - Single selection: receives a string path or null
    ///   - Multiple selection: receives an array of paths or null
    /// - Returns: Self for chaining
    @objc func onSelection(_ callback: JSValue) -> HSUIFilePicker

    /// Show the file picker dialog
    @objc func show()
}

@MainActor
@objc class HSUIFilePicker: NSObject, HSUIFilePickerAPI {
    @objc var typeName = "HSUIFilePicker"

    var message: String?
    var defaultPath: String?
    var canChooseFiles: Bool = true
    var canChooseDirectories: Bool = false
    var allowsMultipleSelection: Bool = false
    var allowedFileTypes: [String]?
    var resolvesAliases: Bool = true

    private var selectionCallback: JSValue?
    private weak var module: HSUIModule?

    init(module: HSUIModule) {
        self.module = module
        super.init()
    }

    // MARK: - Builder Methods

    @objc func message(_ text: String) -> HSUIFilePicker {
        self.message = text
        return self
    }

    @objc func defaultPath(_ path: String) -> HSUIFilePicker {
        self.defaultPath = path
        return self
    }

    @objc func canChooseFiles(_ value: Bool) -> HSUIFilePicker {
        self.canChooseFiles = value
        return self
    }

    @objc func canChooseDirectories(_ value: Bool) -> HSUIFilePicker {
        self.canChooseDirectories = value
        return self
    }

    @objc func allowsMultipleSelection(_ value: Bool) -> HSUIFilePicker {
        self.allowsMultipleSelection = value
        return self
    }

    @objc func allowedFileTypes(_ types: [String]) -> HSUIFilePicker {
        self.allowedFileTypes = types.isEmpty ? nil : types
        return self
    }

    @objc func resolvesAliases(_ value: Bool) -> HSUIFilePicker {
        self.resolvesAliases = value
        return self
    }

    @objc func onSelection(_ callback: JSValue) -> HSUIFilePicker {
        self.selectionCallback = callback
        return self
    }

    // MARK: - Display

    @objc func show() {
        let panel = NSOpenPanel()

        // Configure panel
        if let msg = message {
            panel.message = msg
        }

        if let defaultPath = defaultPath {
            let expandedPath = NSString(string: defaultPath).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expandedPath)
        }

        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.resolvesAliases = resolvesAliases

        if let types = allowedFileTypes {
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        }

        // Show the panel
        let response = panel.runModal()

        // Prepare result
        var result: Any = NSNull()
        if response == .OK {
            if allowsMultipleSelection {
                result = panel.urls.map { $0.path }
            } else if let url = panel.url {
                result = url.path
            }
        }

        // Invoke callback
        if let callback = selectionCallback {
            callback.call(withArguments: [result])

            // Check for JavaScript errors
            if let context = callback.context,
               let exception = context.exception,
               !exception.isUndefined {
                AKError("hs.ui.filePicker: Error in callback: \(exception.toString() ?? "unknown error")")
                context.exception = nil
            }
        }
    }
}
