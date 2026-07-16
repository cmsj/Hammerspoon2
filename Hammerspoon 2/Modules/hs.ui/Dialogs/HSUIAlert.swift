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
/// Positioned in the center of the screen with a semi-transparent background.
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

    var message: String
    var font: Font = .title
    var duration: Double = 5.0  // Match hs.alert default
    var padding: CGFloat?
    var position: CGPoint?

    private var nsWindow: NSWindow?
    private let alertID: UUID = UUID()
    private weak var module: HSUIModule?
    private var dismissTimer: Timer?

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
        guard let screen = NSScreen.main else {
            AKError("hs.ui.alert: Unable to find main screen")
            return self
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

        // Register with module to prevent premature deallocation
        module?.register(self, id: alertID)

        // Auto-dismiss after duration. Timer uses [weak self] so it does NOT keep the
        // alert alive — if the alert is closed early the timer fires harmlessly on nil.
        // Dispatch to main to satisfy actor isolation (timer fires on main RunLoop anyway).
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }

        return self
    }

    @objc func close() {
        guard nsWindow != nil else { return } // Already closed

        dismissTimer?.invalidate()
        dismissTimer = nil

        // Unregister from module
        module?.unregister(alert: alertID)

        // Explicitly nil the contentView so UIAlertView (which holds a strong ref back
        // to self) is released synchronously before AppKit's async window cleanup runs.
        nsWindow?.contentView = nil
        nsWindow?.delegate = nil
        nsWindow?.orderOut(nil)
        nsWindow?.close()
        nsWindow = nil
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        // Window is being closed (shouldn't normally happen for alerts, but handle it)
        Task { @MainActor in
            self.close()
        }
    }
}
