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
    ///
    /// This is the window with keyboard focus, which isn't always a window of `hs.application.frontmost()`:
    /// panels that take focus without activating their app (such as Spotlight's search panel) are returned too.
    /// - Returns: The focused window, or nil if none
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// console.log(win && win.title)
    /// ```
    @objc func focusedWindow() -> HSWindow?

    /// Get the frontmost window
    ///
    /// This is the focused window or, if no window has focus (for example when the desktop is clicked, or the
    /// active application has no windows open), the first window from `orderedWindows()`.
    /// - Returns: The frontmost window, or nil if there are no windows
    /// - Example:
    /// ```js
    /// const win = hs.window.frontmostWindow()
    /// console.log(win && win.title)
    /// ```
    @objc func frontmostWindow() -> HSWindow?

    /// Get the window with the given ID
    ///
    /// This is much faster than searching `allWindows()` for the ID, because it only asks the
    /// application that owns the window for its windows. Like `allWindows()`, this can find windows
    /// in native fullscreen and on other Spaces, with the same limitation.
    /// - Parameter id: The window's ID (see the `id` property on `hs.window` objects)
    /// - Returns: The window, or null if there is no window with that ID
    /// - Example:
    /// ```js
    /// const id = hs.window.focusedWindow().id
    /// // ...later
    /// const win = hs.window.forID(id)
    /// if (win) win.focus()
    /// ```
    @objc func forID(_ id: Int) -> HSWindow?

    /// Get all windows from all applications
    ///
    /// This includes windows in native fullscreen and on other Spaces, with one limitation: macOS
    /// only reveals a window on a Space that isn't visible if its app has already handed that
    /// window to an accessibility client, e.g. because Hammerspoon listed it while its Space was
    /// visible. A window that no accessibility client has looked at since it was created is
    /// missing until its Space is next visible, unless it's its app's main or focused window,
    /// which are always included.
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
    ///
    /// Like `allWindows()`, this includes windows in native fullscreen and on other Spaces, with the
    /// same limitation.
    /// - Parameter app: An HSApplication object
    /// - Returns: An array of windows for that application, or an empty array if `app` is null
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// const wins = hs.window.windowsForApp(app)
    /// ```
    @objc func windowsForApp(_ app: HSApplication?) -> [HSWindow]

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

    /// The spaces the window with the given ID is on. This is the same as an `HSWindow`'s
    /// `spaces`, for windows you only have the ID of, such as those from `HSSpace.windowIDs()`
    /// (Hammerspoon can't make `HSWindow` objects for windows on other spaces).
    /// - Parameter id: The window's ID
    /// - Returns: An array of HSSpace objects, empty if there's no such window
    /// - Example:
    /// ```js
    /// for (const id of hs.screen.allSpaces()[0].windowIDs()) {
    ///     console.log(id + " is on " + hs.window.spacesForID(id).length + " space(s)")
    /// }
    /// ```
    @objc func spacesForID(_ id: Int) -> [HSSpace]

    /// Moves the window with the given ID to another space, without switching to it. This is the
    /// same as an `HSWindow`'s `moveToSpace()`, for windows you only have the ID of, such as
    /// those from `HSSpace.windowIDs()`.
    /// - Parameters:
    ///   - id: The window's ID
    ///   - space: The desktop to move the window to
    /// - Returns: {Promise<void>} A Promise that resolves once the window is on that space, or
    ///   rejects with the reason it couldn't be moved
    /// - Example:
    /// ```js
    /// // Gather every window from the main screen's other desktops onto its current space
    /// const screen = hs.screen.main()
    /// const here = screen.currentSpace
    /// for (const space of screen.spaces) {
    ///     if (space.id === here.id || space.type !== "desktop") continue
    ///     for (const id of space.windowIDs()) hs.window.moveToSpaceForID(id, here)
    /// }
    /// ```
    @objc func moveToSpaceForID(_ id: Int, _ space: HSSpace) -> JSPromise?

    /// A list of bundle identifiers to ignore when fetching a list of all windows
    /// Note: This property is writeable, but you cannot mutate the default list in-place. To add or remove entries, assign this to a variable in JavaScript, modify that, and assign it back to this property. Also, if you find commonly used processes that should belong in this by default, please file an issue on GitHub!
    @objc var allWindowsIgnore: [String] { get set }

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

    @objc var allWindowsIgnore: [String] = [
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.Networking",
        "com.apple.WebKit.GPU",
        "com.apple.universalcontrol",
        "com.apple.hiservices-xpcservice",
        "com.hnc.Discord.helper.Renderer"
    ]

    // MARK: - Swift-retained storage for JS-defined functions
    @objc var focused: JSFunction?
    @objc var findByTitle: JSFunction?
    @objc var currentWindows: JSFunction?
    @objc var moveToLeftHalf: JSFunction?
    @objc var moveToRightHalf: JSFunction?
    @objc var maximize: JSFunction?
    @objc var cycleWindows: JSFunction?
    @objc var grid: JSValue?
    @objc var tiling: JSValue?

    // MARK: - Helper Methods
    private func checkAccessibility() -> Bool {
        guard AXIsProcessTrusted() else {
            AKError("hs.window: Accessibility permissions not granted")
            return false
        }
        return true
    }

    /// Apps with an activation policy of `.prohibited` are background/helper
    /// processes that don't respond to the Accessibility APIs, so querying
    /// them stalls on a system timeout instead of returning quickly.
    private func candidateApplications() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter {
            if let bundleID = $0.bundleIdentifier, allWindowsIgnore.contains(bundleID) {
                return false
            }
            return $0.activationPolicy != .prohibited
        }
    }

    // MARK: - API Implementation

    @objc func focusedWindow() -> HSWindow? {
        guard checkAccessibility() else { return nil }

        guard let frontApp = keyboardFocusedApplication(), let axApp = Application(frontApp) else {
            return nil
        }

        do {
            guard let focusedWindow: UIElement = try axApp.attribute(.focusedWindow) else {
                return nil
            }

            return AXObjectCache.shared.window(element: focusedWindow, app: frontApp)
        } catch {
            AKDebug("Failed to get focused window: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func frontmostWindow() -> HSWindow? {
        return focusedWindow() ?? orderedWindows().first
    }

    @objc func forID(_ id: Int) -> HSWindow? {
        guard id > 0, let windowID = CGWindowID(exactly: id), checkAccessibility() else { return nil }

        // Ask the WindowServer which process owns the window, so only that app has to be asked for its windows
        let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] ?? []
        guard let pid = info.first?[kCGWindowOwnerPID as String] as? pid_t,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        return withAXTimeoutLimit(0.25) {
            guard let element = WindowEnumerator.windowElements(for: app).first(where: { WindowEnumerator.windowID(of: $0) == windowID }) else {
                return nil
            }
            return AXObjectCache.shared.window(element: element, app: app)
        }
    }

    @objc func allWindows() -> [HSWindow] {
        guard checkAccessibility() else { return [] }

        // Reduce the Accessibility API timeout to avoid weird/dead apps from making this take ages to respond
        return withAXTimeoutLimit(0.25) {
            var windows: [HSWindow] = []
            let windowServerIDs = WindowEnumerator.windowServerWindowIDs()
            for app in candidateApplications() {
                let windowElements = WindowEnumerator.windowElements(for: app, windowServerIDs: windowServerIDs)
                windows.append(contentsOf: windowElements.map { AXObjectCache.shared.window(element: $0, app: app) })
            }
            return windows
        }
    }

    @objc func visibleWindows() -> [HSWindow] {
        return allWindows().filter { !$0.isMinimized }
    }

    @objc func windowsForApp(_ app: HSApplication?) -> [HSWindow] {
        guard let app, checkAccessibility() else { return [] }

        let windowElements = WindowEnumerator.windowElements(for: app.runningApplication)
        return windowElements.map { AXObjectCache.shared.window(element: $0, app: app.runningApplication) }
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
                        return AXObjectCache.shared.window(element: elem, app: app)
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
        for app in candidateApplications() where !orderedApps.contains(app) {
            orderedApps.append(app)
        }

        let windowServerIDs = WindowEnumerator.windowServerWindowIDs()
        var windows: [HSWindow] = []
        for app in orderedApps {
            let appWindows = WindowEnumerator.windowElements(for: app, windowServerIDs: windowServerIDs).map { AXObjectCache.shared.window(element: $0, app: app) }
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

    // MARK: - Spaces

    @objc func spacesForID(_ id: Int) -> [HSSpace] {
        HSSpaces.shared.spaces(forWindowID: id)
    }

    @objc func moveToSpaceForID(_ id: Int, _ space: HSSpace) -> JSPromise? {
        HSSpaces.shared.moveWindow(id, toSpace: space, function: "hs.window.moveToSpaceForID()")
    }
}
