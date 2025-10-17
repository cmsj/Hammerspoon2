//
//  Applications.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/10/2025.
//

import Foundation
import JavaScriptCore
import AppKit

/// Module for interacting with applications
@objc protocol HSApplicationsAPI: JSExport {
    /// Fetch all running applications
    /// - Returns: An array of all currently running applications
    @objc func runningApplications() -> [NSRunningApplication]
    /// Fetch the first application that matches a name
    /// - Parameter name: The applicaiton name to search for
    /// - Returns: The first matching application, or nil if none matched
    @objc func matchingName(_ name: String) -> NSRunningApplication?
    /// Fetch the first application that matches a Bundle ID
    /// - Parameter bundleID: The identifier to search for
    /// - Returns: The first matching application, or nil if none matched
    @objc func matchingBundleID(_ bundleID: String) -> NSRunningApplication?
    /// Fetch the application that matches a POSIX PID
    /// - Parameter pid: The PID to search for
    /// - Returns: The matching application, or nil if none matched
    @objc func matchingPID(_ pid: Int) -> NSRunningApplication?
}
// hs.application.matchingName("lol")

@objc class HSApplications: NSObject, HSModule, HSApplicationsAPI {
    @objc var name = "Applications"

    var accessibilityManager = AccessibilityManager.shared

    required override init() {}

    @objc func runningApplications() -> [NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications
        return apps
    }

    @objc func matchingName(_ name: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first(where: { $0.localizedName == name })
    }

    @objc func matchingBundleID(_ bundleID: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first(where: { $0.bundleIdentifier == bundleID })
    }

    @objc func matchingPID(_ pid: Int) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first(where: { $0.processIdentifier == pid })
    }
}

