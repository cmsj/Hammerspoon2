//
//  HSApplication.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 20/10/2025.
//

import Foundation
import JavaScriptCore
import Cocoa
import AXSwift

/// Object representing an application
@objc protocol HSApplicationAPI: JSExport {
    /// POSIX Process Identifier
    @objc var pid: Int { get }

    /// Bundle Identifier (e.g. com.apple.Safari)
    @objc var bundleID: String? { get }

    /// The application's title
    @objc var title: String? { get }

    /// Location of the application on disk
    @objc var bundlePath: String? { get }

    /// Is the application hidden
    @objc var isHidden: Bool { get set }

    /// Is the application focused
    @objc var isActive: Bool { get }

    /// Terminate the application
    @objc func kill() -> Bool

    /// Force-terminate the application
    @objc func kill9() -> Bool

    /// The main window of this application, or nil if there is no main window
    @objc var mainWindow: HSWindow? { get }

    /// The focused window of this application, or nil if there is no focused window
    @objc var focusedWindow: HSWindow? { get }

    /// All windows of this application
    @objc var allWindows: [HSWindow] { get }

    /// All visible (ie non-hidden) windows of this application
    @objc var visibleWindows: [HSWindow] { get }

    /// The application's HSAXElement object, for use with the hs.ax APIs
    @objc func axElement() -> HSAXElement?
}

@_documentation(visibility: private)
@objc class HSApplication: NSObject, HSApplicationAPI {
    let runningApplication: NSRunningApplication
    let axUIElement: Application?

    init(runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        self.axUIElement = Application(runningApplication)
    }

    deinit {
        print("deinit of \(self): \(self.runningApplication.localizedName ?? "UNKNOWN")")
    }

    @objc var pid: Int { Int(self.runningApplication.processIdentifier) }
    @objc var bundleID: String? { self.runningApplication.bundleIdentifier }
    @objc var title: String? { self.runningApplication.localizedName }
    @objc var bundlePath: String? { self.runningApplication.bundleURL?.path(percentEncoded: false) }

    @objc var isHidden: Bool {
        get {
            let value = try? self.axUIElement?.attribute(.hidden) as Bool?
            return value ?? false
        }
        set { try? self.axUIElement?.setAttribute(.hidden, value: newValue) }
    }
    @objc var isActive: Bool { self.runningApplication.isActive }

    @objc func kill() -> Bool {
        return self.runningApplication.terminate()
    }

    @objc func kill9() -> Bool {
        return self.runningApplication.forceTerminate()
    }

    @objc var mainWindow: HSWindow? {
        guard let mainWindow: UIElement = try? self.axUIElement?.attribute(.mainWindow) else {
            return nil
        }
        return HSWindow(element: mainWindow, app: self.runningApplication)
    }

    @objc var focusedWindow: HSWindow? {
        guard let focusedWindow: UIElement = try? self.axUIElement?.attribute(.focusedWindow) else {
            return nil
        }
        return HSWindow(element: focusedWindow, app: self.runningApplication)
    }

    @objc var allWindows: [HSWindow] {
        guard let allWindows: [UIElement] = try? self.axUIElement?.arrayAttribute(.windows) else {
            return []
        }
        return allWindows.compactMap { HSWindow(element: $0, app: self.runningApplication) }
    }

    @objc var visibleWindows: [HSWindow] {
        return allWindows.filter { $0.isVisible }
    }

    @objc func axElement() -> HSAXElement? {
        guard let axApp = Application(self.runningApplication) else {
            AKError("hs.application.axElement(): Failed to create AXElement for \(self.title ?? "unknown")")
            return nil
        }
        return HSAXElement(element: axApp)
    }
}
