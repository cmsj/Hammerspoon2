//
//  WindowModule.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AppKit
import AXSwift

// MARK: - Declare our JavaScript API

/// Module for interacting with windows
@objc protocol HSWindowModuleAPI: JSExport {
    /// Get the currently focused window
    /// - Returns: The focused window, or nil if none
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// console.log(win && win.title)
    /// ```
    @objc func focusedWindow() -> HSWindow?

    /// Get all windows from all applications
    /// - Returns: An array of all windows
    /// - Example:
    /// ```js
    /// const wins = hs.window.allWindows()
    /// console.log(wins.length)
    /// ```
    @objc func allWindows() -> [HSWindow]

    /// Get all visible (not minimized) windows
    /// - Returns: An array of visible windows
    /// - Example:
    /// ```js
    /// const vis = hs.window.visibleWindows()
    /// ```
    @objc func visibleWindows() -> [HSWindow]

    /// Get windows for a specific application
    /// - Parameter app: An HSApplication object
    /// - Returns: An array of windows for that application
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const wins = hs.window.windowsForApp(app)
    /// ```
    @objc func windowsForApp(_ app: HSApplication) -> [HSWindow]

    /// Get all windows on a specific screen
    /// - Parameter screenIndex: The screen index (0 for main screen)
    /// - Returns: An array of windows on that screen
    /// - Example:
    /// ```js
    /// const wins = hs.window.windowsOnScreen(0)
    /// ```
    @objc func windowsOnScreen(_ screenIndex: Int) -> [HSWindow]

    /// Get the window at a specific screen position
    /// - Parameters:
    ///   - point: An HSPoint containing the coordinates
    /// - Returns: The topmost window at that position, or nil if none
    /// - Example:
    /// ```js
    /// const win = hs.window.windowAtPoint({x: 500, y: 300})
    /// ```
    @objc func windowAtPoint(_ point: HSPoint) -> HSWindow?

    /// Get ordered windows (front to back)
    /// - Returns: An array of windows in z-order
    /// - Example:
    /// ```js
    /// const wins = hs.window.orderedWindows()
    /// ```
    @objc func orderedWindows() -> [HSWindow]

    /// Capture the current on-screen contents of the window with the given ID.
    ///
    /// Requires **Screen Recording** permission.
    ///
    /// - Parameters:
    ///   - id: The window's underlying ID (see the `id` property on `hs.window` objects).
    ///   - keepTransparency?: Whether to preserve the window's alpha channel. If `false` (the default), transparent regions are filled with an opaque black background.
    /// - Returns: {Promise<HSImage>} Resolves with the captured image, or rejects if no window with that ID can be found, or the capture fails.
    /// - Example:
    /// ```js
    /// hs.window.snapshotForID(12345).then(img => img.saveToFile("/tmp/window.png"))
    /// ```
    @objc func snapshotForID(_ id: Int, _ keepTransparency: Bool) -> JSPromise?

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.window.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var focused: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var findByTitle: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var currentWindows: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var moveToLeftHalf: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var moveToRightHalf: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var maximize: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var cycleWindows: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var grid: JSValue? { get set }

    /// SKIP_DOCS
    @objc var tiling: JSValue? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWindowModule: NSObject, HSModuleAPI, HSWindowModuleAPI {
    var moduleName = "hs.window"
    let engineID: UUID

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        focused = nil
        findByTitle = nil
        currentWindows = nil
        moveToLeftHalf = nil
        moveToRightHalf = nil
        maximize = nil
        cycleWindows = nil
        grid = nil
        tiling = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): focused '\(focusedWindow()?.title ?? "none")'>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Swift-retained storage for JS-defined functions
    @objc var focused: JSFunction? = nil
    @objc var findByTitle: JSFunction? = nil
    @objc var currentWindows: JSFunction? = nil
    @objc var moveToLeftHalf: JSFunction? = nil
    @objc var moveToRightHalf: JSFunction? = nil
    @objc var maximize: JSFunction? = nil
    @objc var cycleWindows: JSFunction? = nil
    @objc var grid: JSValue? = nil
    @objc var tiling: JSValue? = nil

    // MARK: - Helper Methods
    private func checkAccessibility() -> Bool {
        guard AXIsProcessTrusted() else {
            AKError("hs.window: Accessibility permissions not granted")
            return false
        }
        return true
    }

    private func getWindowElements(for app: NSRunningApplication) -> [UIElement] {
        guard let axApp = Application(app) else {
            return []
        }

        do {
            let windows: [UIElement] = try axApp.windows() ?? []
            return windows
        } catch {
            AKDebug("Failed to get windows for \(app.localizedName ?? "unknown"): \(error.localizedDescription)")
            return []
        }
    }

    /// Apps with an activation policy of `.prohibited` are background/helper
    /// processes that don't respond to the Accessibility APIs, so querying
    /// them stalls on a system timeout instead of returning quickly.
    private func candidateApplications() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
    }

    // MARK: - API Implementation

    @objc func focusedWindow() -> HSWindow? {
        guard checkAccessibility() else { return nil }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard let axApp = Application(frontApp) else {
            return nil
        }

        do {
            guard let focusedWindow: UIElement = try axApp.attribute(.focusedWindow) else {
                return nil
            }

            return HSWindow(element: focusedWindow, app: frontApp)
        } catch {
            AKDebug("Failed to get focused window: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func allWindows() -> [HSWindow] {
        guard checkAccessibility() else { return [] }

        var windows: [HSWindow] = []

        // Reduce the Accessibility API timeout to avoid weird/dead apps from making this take ages to respond
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        defer { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0) }

        for app in candidateApplications() {
            let windowElements = getWindowElements(for: app)
            windows.append(contentsOf: windowElements.map { HSWindow(element: $0, app: app) })
        }

        return windows
    }

    @objc func visibleWindows() -> [HSWindow] {
        return allWindows().filter { !$0.isMinimized }
    }

    @objc func windowsForApp(_ app: HSApplication) -> [HSWindow] {
        guard checkAccessibility() else { return [] }

        let windowElements = getWindowElements(for: app.runningApplication)
        return windowElements.map { HSWindow(element: $0, app: app.runningApplication) }
    }

    @objc func windowsOnScreen(_ screenIndex: Int) -> [HSWindow] {
        let screens = NSScreen.screens
        guard screenIndex >= 0 && screenIndex < screens.count else {
            AKWarning("hs.window.windowsOnScreen(): Invalid screen index \(screenIndex)")
            return []
        }

        let screen = screens[screenIndex]
        let screenFrame = screen.frame

        let result = visibleWindows().filter { window in
            guard let frame = window.frame else {
                return false
            }

            let windowRect = CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
            return screenFrame.intersects(windowRect)
        }

        return result
    }

    @objc func windowAtPoint(_ point: HSPoint) -> HSWindow? {
        guard checkAccessibility() else { return nil }

        do {
            let systemWide = SystemWideElement(AXUIElementCreateSystemWide())
            let position = point.point

            guard let element: UIElement = try systemWide.elementAtPosition(position) else {
                return nil
            }

            // Walk up the hierarchy to find the window
            var current: UIElement? = element
            while let elem = current {
                if let role = try? elem.role(), role == .window {
                    // Find the app for this window
                    let pid = try? elem.pid()
                    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
                        return HSWindow(element: elem, app: app)
                    }
                }

                current = try? elem.attribute(.parent)
            }

            return nil
        } catch {
            AKError("hs.window.windowAtPosition(): Failed: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func orderedWindows() -> [HSWindow] {
        guard checkAccessibility() else { return [] }

        // Get windows from apps in activation order
        var orderedApps: [NSRunningApplication] = []

        // Start with frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            orderedApps.append(frontApp)
        }

        // Add other apps
        for app in candidateApplications() {
            if !orderedApps.contains(app) {
                orderedApps.append(app)
            }
        }

        var windows: [HSWindow] = []
        for app in orderedApps {
            let appWindows = getWindowElements(for: app).map { HSWindow(element: $0, app: app) }
            windows.append(contentsOf: appWindows)
        }

        return windows
    }

    @objc func snapshotForID(_ id: Int, _ keepTransparency: Bool = false) -> JSPromise? {
        guard id > 0, let windowID = CGWindowID(exactly: id) else {
            return JSEngine.shared.createPromise { holder in
                Task.detached {
                    await holder.rejectWithMessage("hs.window.snapshotForID: invalid window ID \(id)")
                }
            }
        }
        return captureWindowSnapshot(windowID: windowID, keepTransparency: keepTransparency)
    }
}
