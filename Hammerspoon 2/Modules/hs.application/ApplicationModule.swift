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

    // NOTE: These are not documented because they are private API for our JavaScript code
    @objc(_addWatcher::) func _addWatcher(eventName: String, callback: JSValue)
    @objc(_removeWatcher:) func _removeWatcher(eventName: String)
}

// MARK: - Implementations

class HSApplicationWatcherObject {
    let eventName: String
    let callback: JSValue

    init(eventName: String, callback: JSValue) {
        self.eventName = eventName
        self.callback = callback
    }

    @objc func handleEvent(notification: NSNotification) {
        let eventApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.asHSApplication()
        callback.call(withArguments: [eventName, eventApp as Any])
    }
}

@_documentation(visibility: private)
@MainActor
@objc class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationsAPI {
    var name = "hs.application"
    private var watchers: [NSNotification.Name:HSApplicationWatcherObject] = [:]

    override required init() {}
    func shutdown() {
        for eventName in watchers.keys {
            if let watcherObject = watchers[eventName] {
                _removeWatcher(eventName: watcherObject.eventName)
            }
        }
    }
    isolated deinit {
        print("Deinit of \(name)")
        shutdown()
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

    func eventNameToEvent(eventName: String) -> NSNotification.Name? {
        var event: NSNotification.Name? = nil

        switch eventName {
        case "willLaunch":
            event = NSWorkspace.willLaunchApplicationNotification
        case "didLaunch":
            event = NSWorkspace.didLaunchApplicationNotification
        case "didTerminate":
            event = NSWorkspace.didTerminateApplicationNotification
        case "didHide":
            event = NSWorkspace.didHideApplicationNotification
        case "didUnhide":
            event = NSWorkspace.didUnhideApplicationNotification
        case "didActivate":
            event = NSWorkspace.didActivateApplicationNotification
        case "didDeactivate":
            event = NSWorkspace.didDeactivateApplicationNotification
        default:
            AKError("hs.application: unknown watcher event: \(eventName)")
        }

        return event
    }

    @objc(_addWatcher::) func _addWatcher(eventName: String, callback: JSValue) {
        guard let event = eventNameToEvent(eventName: eventName) else {
            AKError("hs.application.addWatcher(): Unknown event name: \(eventName)")
            return
        }

        if watchers.keys.contains(event) {
            // No action required, we are already watching for this event
            AKWarning("hs.application.addWatcher(): There is already a watcher for \(eventName). Refusing to create a second.")
            return
        }

        let watcherObject = HSApplicationWatcherObject(eventName: eventName, callback: callback)

        AKTrace("hs.application.addWatcher(): Adding watcher for \(event)")
        let selector = #selector(HSApplicationWatcherObject.handleEvent(notification:))
        NSWorkspace.shared.notificationCenter.addObserver(watcherObject,
                                                          selector: selector,
                                                          name: event, object: nil)

        watchers[event] = watcherObject
    }

    @objc(_removeWatcher:) func _removeWatcher(eventName: String) {
        guard let event = eventNameToEvent(eventName: eventName) else {
            AKError("hs.application.removeWatcher(): Unknown event name: \(eventName)")
            return
        }

        if let watcherObject = watchers[event] {
            AKTrace("hs.application.removeWatcher: Removing watcher for \(event)")
            NSWorkspace.shared.notificationCenter.removeObserver(watcherObject as Any, name: event, object: nil)
            watchers.removeValue(forKey: event)
        }
    }
}

