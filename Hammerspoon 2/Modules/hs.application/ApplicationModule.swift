//
//  Applications.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/10/2025.
//

import Foundation
import JavaScriptCore
import AppKit
import AXSwift

// MARK: - Declare our JavaScript API

/// Module for interacting with applications
@objc protocol HSApplicationsAPI: JSExport {
    /// Fetch all running applications
    /// - Returns: An array of all currently running applications
    @objc func runningApplications() -> [HSApplication]
    /// Fetch the first application that matches a name
    /// - Parameter name: The applicaiton name to search for
    /// - Returns: The first matching application, or nil if none matched
    @objc func matchingName(_ name: String) -> HSApplication?
    /// Fetch the first application that matches a Bundle ID
    /// - Parameter bundleID: The identifier to search for
    /// - Returns: The first matching application, or nil if none matched
    @objc func matchingBundleID(_ bundleID: String) -> HSApplication?
    /// Fetch the application that matches a POSIX PID
    /// - Parameter pid: The PID to search for
    /// - Returns: The matching application, or nil if none matched
    @objc func matchingPID(_ pid: Int) -> HSApplication?
    /// Fetch the currently focused application
    /// - Returns: The matching application, or nil if none matched
    @objc func frontmost() -> HSApplication?
}

// MARK: - Implementations

@_documentation(visibility: private)
@objc class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    var name = "hs.application"

    override required init() {}
    deinit {
        print("Deinit of \(name)")
    }

    @objc func runningApplications() -> [HSApplication] {
        let apps = NSWorkspace.shared.runningApplications.compactMap { $0.asHSApplication() }
        return apps
    }

    @objc func matchingName(_ name: String) -> HSApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.asHSApplication()
    }

    @objc func matchingBundleID(_ bundleID: String) -> HSApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.asHSApplication()
    }

    @objc func matchingPID(_ pid: Int) -> HSApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid })?.asHSApplication()
    }

    @objc func frontmost() -> HSApplication? {
        return NSWorkspace.shared.frontmostApplication?.asHSApplication()
    }
}



