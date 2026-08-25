//
//  HSUIAlert.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

/// # HSUIAlert
///
/// **A temporary on-screen notification**
///
/// Displays a message that automatically fades out after a specified duration.
/// Without an explicit `.position()`, multiple alerts stack vertically and
/// stay centered as they appear and disappear. With `.position()`, the alert
/// appears at the given coordinates regardless of other alerts.
///
/// ## Example
///
/// ```javascript
/// hs.ui.alert("Task completed!")
///     .font(HSFont.headline())
///     .duration(5)
///     .padding(30)
///     .show();
/// ```
@objc protocol HSUIAlertAPI: HSTypeAPI, JSExport {
    /// Set the font for the alert text
    /// - Parameter font: An HSFont object (e.g., `HSFont.headline()`)
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.alert("Hello").font(HSFont.headline()).show()
    /// ```
    @objc func font(_ font: HSFont) -> HSUIAlert

    /// Set how long the alert is displayed
    /// - Parameter seconds: Duration in seconds (default: 5.0)
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.alert("Hello").duration(3).show()
    /// ```
    @objc func duration(_ seconds: Double) -> HSUIAlert

    /// Set the padding around the alert text
    /// - Parameter points: Padding in points (default: 20)
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.alert("Hello").padding(30).show()
    /// ```
    @objc func padding(_ points: Double) -> HSUIAlert

    /// Set a custom position for the alert
    ///
    /// When a position is set, the alert is shown at those coordinates and will not
    /// be stacked with other alerts. Coordinates are in points from the top-left of
    /// the visible screen area (below the menu bar), with y increasing downward.
    ///
    /// - Parameter dict: Dictionary with `x` and `y` coordinates
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.alert("Hello").position({x: 100, y: 100}).show()
    /// ```
    @objc func position(_ dict: [String: Any]) -> HSUIAlert

    /// Show the alert
    /// - Returns: Self for chaining (can store reference to close manually)
    /// - Example:
    /// ```js
    /// hs.ui.alert("Hello").show()
    /// ```
    @objc func show() -> HSUIAlert

    /// Close the alert immediately
    /// - Example:
    /// ```js
    /// const a = hs.ui.alert("Hello").show()
    /// a.close()
    /// ```
    @objc func close()
}

@MainActor
@objc class HSUIAlert: NSObject, HSUIAlertAPI, NSWindowDelegate {
    @objc var typeName = "HSUIAlert"

    @objc func toString() -> String {
        return "<\(typeName): \(message)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    var message: String
    var font: Font = .title
    var duration: Double = 5.0
    var padding: CGFloat?
    var position: CGPoint?

    private var nsWindow: NSWindow?
    let alertID: UUID = UUID()
    private var isStacked = false
    private var isShowing = false
    private var dismissTask: Task<Void, Never>?
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
        let id = alertID
        let capturedModule = module
        DispatchQueue.main.async {
            capturedModule?.unregister(alert: id)
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
    }

    // MARK: - Builder Methods

    @objc func font(_ font: HSFont) -> HSUIAlert {
        self.font = font.font
        return self
    }

    @objc func duration(_ seconds: Double) -> HSUIAlert {
        self.duration = seconds
        return self
    }

    @objc func padding(_ points: Double) -> HSUIAlert {
        self.padding = CGFloat(points)
        return self
    }

    @objc func position(_ dict: [String: Any]) -> HSUIAlert {
        let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
        self.position = CGPoint(x: x, y: y)
        return self
    }

    // MARK: - Display

    @objc func show() -> HSUIAlert {
        guard !isShowing else { return self }
        isShowing = true

        module?.register(self, id: alertID)

        let dismissDelay: Double
        if position != nil {
            showStandalone()
            dismissDelay = duration
        } else {
            isStacked = true
            module?.showAlertInStack(self)
            // Stacked alerts rely on close() triggering the SwiftUI transition for the
            // final 0.2s of fade-out, so the dismiss fires 0.2s earlier than standalone.
            dismissDelay = duration - 0.2
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dismissDelay))
            self?.close()
        }

        return self
    }

    private func showStandalone() {
        guard let screen = NSScreen.main else {
            AKError("hs.ui.alert: Unable to find main screen")
            return
        }

        let window = NSWindow(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = UIAlertView(alert: self)
        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.delegate = self

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.nsWindow = window
    }

    @objc func close() {
        guard isShowing else { return }
        isShowing = false
        dismissTask?.cancel()
        dismissTask = nil

        if isStacked {
            isStacked = false
            module?.unregister(alert: alertID)
            module?.removeAlertFromStack(self)
        } else {
            module?.unregister(alert: alertID)
            nsWindow?.delegate = nil
            nsWindow?.orderOut(nil)
            nsWindow?.close()
            nsWindow = nil
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.close()
        }
    }
}
