//
//  NSRunningApplication.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 17/10/2025.
//

import Foundation
import JavaScriptCore
import Cocoa

/// API provided by NSRunningApplication objects
@objc protocol NSRunningApplicationExports: JSExport {
    // MARK: - Hammerspoon provided API
    /// POSIX Process Identifier
    @objc var pid: Int { get }
    /// Bundle Identifier (e.g. com.apple.Safari)
    @objc var bundleID: String? { get }

    // MARK: - macOS provided API
    @objc var isHidden: Bool { get }
    @objc var isActive: Bool { get }

    @objc func hide() -> Bool
    @objc func unhide() -> Bool
}

@objc extension NSRunningApplication: @retroactive JSExport {}
@objc extension NSRunningApplication: @MainActor NSRunningApplicationExports {
    @objc var pid: Int { Int(self.processIdentifier) }
    @objc var bundleID: String? { self.bundleIdentifier }
}
