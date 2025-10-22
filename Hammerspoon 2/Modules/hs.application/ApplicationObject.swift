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

    @objc func kill() -> Bool
    @objc func kill9() -> Bool
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
}
