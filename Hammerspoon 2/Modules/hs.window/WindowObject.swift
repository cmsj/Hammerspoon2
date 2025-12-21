//
//  WindowObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AppKit
import AXSwift

/// Object representing a window
@objc protocol HSWindowAPI: HSTypeAPI, JSExport {
    // MARK: - Basic Properties

    /// The window's title
    @objc var title: String? { get }

    /// The application that owns this window
    @objc var application: HSApplication? { get }

    /// The process ID of the application that owns this window
    @objc var pid: Int { get }

    // MARK: - Window State

    /// Whether the window is minimized
    @objc var isMinimized: Bool { get set }

    /// Whether the window is visible (not minimized or hidden)
    @objc var isVisible: Bool { get }

    /// Whether the window is focused
    @objc var isFocused: Bool { get }

    /// Whether the window is fullscreen
    @objc var isFullscreen: Bool { get set }

    /// Whether the window is standard (has a titlebar)
    @objc var isStandard: Bool { get }

    // MARK: - Geometry

    /// The window's position on screen {x: Int, y: Int}
    @objc var position: HSPoint? { get set }

    /// The window's size {w: Int, h: Int}
    @objc var size: HSSize? { get set }

    /// The window's frame {x: Int, y: Int, w: Int, h: Int}
    @objc var frame: HSRect? { get set }

    // MARK: - Actions

    /// Focus this window
    /// - Returns: true if successful
    @objc func focus() -> Bool

    /// Minimize this window
    /// - Returns: true if successful
    @objc func minimize() -> Bool

    /// Unminimize this window
    /// - Returns: true if successful
    @objc func unminimize() -> Bool

    /// Raise this window to the front
    /// - Returns: true if successful
    @objc func raise() -> Bool

    /// Toggle fullscreen mode
    /// - Returns: true if successful
    @objc func toggleFullscreen() -> Bool

    /// Close this window
    /// - Returns: true if successful
    @objc func close() -> Bool

    /// Center the window on the screen
    /// - Returns: true if successful
    @objc func centerOnScreen()

    // MARK: - Advanced

    /// Get the underlying AXElement
    /// - Returns: The accessibility element for this window
    @objc func axElement() -> HSAXElement
}

@_documentation(visibility: private)
@objc class HSWindow: NSObject, HSWindowAPI {
    @objc var typeName = "HSWindow"
    let element: UIElement
    let app: NSRunningApplication

    init(element: UIElement, app: NSRunningApplication) {
        self.element = element
        self.app = app
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSWindow: \(self.title ?? "unknown")")
    }

    // MARK: - Basic Properties

    @objc var title: String? {
        return try? element.attribute(.title)
    }

    @objc var application: HSApplication? {
        return HSApplication(runningApplication: app)
    }

    @objc var pid: Int {
        let pid = try? Int(element.pid())
        return pid ?? -1
    }

    // MARK: - Window State

    @objc var isMinimized: Bool {
        get {
            let minimized: Bool? = try? element.attribute(.minimized)
            return minimized ?? false
        }
        set {
            do {
                try element.setAttribute(.minimized, value: newValue)
            } catch {
                AKError("Failed to set minimized: \(error.localizedDescription)")
            }
        }
    }

    @objc var isVisible: Bool {
        return !isMinimized && !app.isHidden
    }

    @objc var isFocused: Bool {
        let focused: Bool? = try? element.attribute(.focused)
        return focused ?? false
    }

    @objc var isFullscreen: Bool {
        get {
            let fullscreen: Bool? = try? element.attribute(.fullScreen)
            return fullscreen ?? false
        }
        set {
            do {
                try element.setAttribute(.fullScreen, value: newValue)
            } catch {
                AKError("Failed to set fullscreen: \(error.localizedDescription)")
            }
        }
    }

    @objc var isStandard: Bool {
        guard let subrole = try? element.subrole() else {
            return false
        }
        return subrole == .standardWindow
    }

    // MARK: - Geometry

    @objc var position: HSPoint? {
        get {
            guard let pos: CGPoint = try? element.attribute(.position) else {
                return nil
            }
            return pos.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try element.setAttribute(.position, value: newValue.point)
            } catch {
                AKError("Failed to set position: \(error.localizedDescription)")
            }
        }
    }

    @objc var size: HSSize? {
        get {
            guard let sz: CGSize = try? element.attribute(.size) else {
                return nil
            }
            return sz.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try element.setAttribute(.size, value: newValue.size)
            } catch {
                AKError("Failed to set size: \(error.localizedDescription)")
            }
        }
    }

    @objc var frame: HSRect? {
        get {
            guard let frame: CGRect = try? element.attribute(.frame) else {
                return nil
            }

            return frame.toBridge()
        }
        set {
            guard let newValue = newValue else {
                return
            }

            do {
                try element.setAttribute(.position, value: newValue.origin.point)
                try element.setAttribute(.size, value: newValue.size.size)
            } catch {
                AKError("Failed to set frame: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions

    @objc func focus() -> Bool {
        do {
            try element.setAttribute(.focused, value: true)

            // Also activate the application
            app.activate()

            return true
        } catch {
            AKError("Failed to focus window: \(error.localizedDescription)")
            return false
        }
    }

    @objc func minimize() -> Bool {
        do {
            try element.setAttribute(.minimized, value: true)
            return true
        } catch {
            AKError("Failed to minimize window: \(error.localizedDescription)")
            return false
        }
    }

    @objc func unminimize() -> Bool {
        do {
            try element.setAttribute(.minimized, value: false)
            return true
        } catch {
            AKError("Failed to unminimize window: \(error.localizedDescription)")
            return false
        }
    }

    @objc func raise() -> Bool {
        do {
            try element.performAction(.raise)
            return true
        } catch {
            AKError("Failed to raise window: \(error.localizedDescription)")
            return false
        }
    }

    @objc func toggleFullscreen() -> Bool {
        isFullscreen = !isFullscreen
        return true
    }

    @objc func close() -> Bool {
        do {
            // First try the AXPress action on the close button
            if let closeButton: UIElement = try? element.attribute(.closeButton) {
                try closeButton.performAction(.press)
                return true
            }

            // Fallback: Try AXCancel action
            try element.performAction(.cancel)
            return true
        } catch {
            AKError("Failed to close window: \(error.localizedDescription)")
            return false
        }
    }

    @objc func centerOnScreen() {
        guard let screen = NSScreen.main else {
            return
        }

        guard let sz = size else {
            return
        }

        let screenFrame = screen.visibleFrame
        let centerX = Int(screenFrame.midX) - Int(sz.w) / 2
        let centerY = Int(screenFrame.midY) - Int(sz.h) / 2

        position = HSPoint(x: Double(centerX), y: Double(centerY))
    }

    // MARK: - Advanced

    @objc func axElement() -> HSAXElement {
        return HSAXElement(element: element)
    }
}
