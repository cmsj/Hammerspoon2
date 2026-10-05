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
import UniformTypeIdentifiers

// MARK: - Declare our JavaScript API

/// Module for interacting with applications
@objc protocol HSApplicationModuleAPI: JSExport {
    /// Fetch all running applications
    /// - Returns: An array of all currently running applications
    /// - Example:
    /// ```js
    /// const apps = hs.application.runningApplications()
    /// apps.forEach(a => console.log(a.title))
    /// ```
    @objc func runningApplications() -> [HSApplication]

    /// Fetch the first running application that matches a name
    /// - Parameter name: The applicaiton name to search for
    /// - Returns: The first matching application, or nil if none matched
    /// - Example:
    /// ```js
    /// const safari = hs.application.matchingName("Safari")
    /// ```
    @objc func matchingName(_ name: String) -> HSApplication?

    /// Fetch the first running application that matches a Bundle ID
    /// - Parameter bundleID: The identifier to search for
    /// - Returns: The first matching application, or nil if none matched
    /// - Example:
    /// ```js
    /// const safari = hs.application.matchingBundleID("com.apple.Safari")
    /// ```
    @objc func matchingBundleID(_ bundleID: String) -> HSApplication?

    /// Fetch the running application that matches a POSIX PID
    /// - Parameter pid: The PID to search for
    /// - Returns: The matching application, or nil if none matched
    /// - Example:
    /// ```js
    /// const app = hs.application.fromPID(1234)
    /// ```
    @objc func fromPID(_ pid: Int) -> HSApplication?

    /// Fetch the currently focused application
    /// - Returns: The matching application, or nil if none matched
    /// - Example:
    /// ```js
    /// const app = hs.application.frontmost()
    /// console.log(app.title)
    /// ```
    @objc func frontmost() -> HSApplication?

    /// Fetch the application which currently owns the menu bar
    /// - Returns: The matching application, or nil if none matched
    /// - Example:
    /// ```js
    /// const owner = hs.application.menuBarOwner()
    /// ```
    @objc func menuBarOwner() -> HSApplication?

    /// Fetch the filesystem path for an application
    /// - Parameter bundleID: The application bundle identifier to search for (e.g. "com.apple.Safari")
    /// - Returns: The application's filesystem path, or nil if it was not found
    /// - Example:
    /// ```js
    /// const path = hs.application.pathForBundleID("com.apple.Safari")
    /// ```
    @objc func pathForBundleID(_ bundleID: String) -> String?

    /// Fetch filesystem paths for an application
    /// - Parameter bundleID: The application bundle identifier to search for (e.g. "com.apple.Safari")
    /// - Returns: An array of strings containing any filesystem paths that were found
    /// - Example:
    /// ```js
    /// const paths = hs.application.pathsForBundleID("com.apple.Safari")
    /// ```
    @objc func pathsForBundleID(_ bundleID: String) -> [String]

    /// SKIP_DOCS
    /// Fetch a dictionary of information about an application bundle, given its path
    /// - Parameter bundlePath: The path to a bundle (e.g. "/Applications/Safari.app")
    /// - Returns: A dictionary of information about the bundle
    @objc func infoForBundlePath(_ bundlePath: String) -> [String: Any]?

    /// Fetch filesystem path for an application able to open a given file type
    /// - Parameter fileType: The file type to search for. This can be a UTType identifier, a MIME type, or a filename extension
    /// - Returns: The path to an application for the given filetype, or il if none were found
    /// - Example:
    /// ```js
    /// const path = hs.application.pathForFileType("public.html")
    /// ```
    @objc func pathForFileType(_ fileType: String) -> String?

    /// Fetch filesystem paths for applications able to open a given file type
    /// - Parameter fileType: The file type to search for. This can be a UTType identifier, a MIME type, or a filename extension
    /// - Returns: An array of strings containing the filesystem paths for any applications that were found
    /// - Example:
    /// ```js
    /// const paths = hs.application.pathsForFileType("png")
    /// ```
    @objc func pathsForFileType(_ fileType: String) -> [String]

    /// Launch an application, or give it focus if it's already running
    /// - Parameter bundleID: A bundle identifier for the app to launch/focus (e.g. "com.apple.Safari")
    /// - Returns: {Promise<boolean>} A Promise that resolves to true if successful, false otherwise
    /// - Example:
    /// ```js
    /// hs.application.launchOrFocus("com.apple.Safari").then(ok => console.log(ok))
    /// ```
    @objc func launchOrFocus(_ bundleID: String) -> JSPromise?

    // NOTE: These are not documented because they are private API for our JavaScript code
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()

    /// Swift-retained storage for the JS watcher emitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSApplicationEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.application.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Implementations

/// Events emitted by hs.application's watcher
nonisolated enum HSApplicationEvent: String, HSEventName {
    case willLaunch, didLaunch, didTerminate, didHide, didUnhide, didActivate, didDeactivate
}

class HSApplicationWatcherObject {
    let callback: JSFunction

    static let notificationToEventName: [NSNotification.Name: HSApplicationEvent] = [
        NSWorkspace.willLaunchApplicationNotification: .willLaunch,
        NSWorkspace.didLaunchApplicationNotification: .didLaunch,
        NSWorkspace.didTerminateApplicationNotification: .didTerminate,
        NSWorkspace.didHideApplicationNotification: .didHide,
        NSWorkspace.didUnhideApplicationNotification: .didUnhide,
        NSWorkspace.didActivateApplicationNotification: .didActivate,
        NSWorkspace.didDeactivateApplicationNotification: .didDeactivate,
    ]

    init(callback: JSFunction) {
        self.callback = callback
    }

    @objc func handleEvent(notification: NSNotification) {
        guard let eventName = Self.notificationToEventName[notification.name] else {
            AKError("hs.application: received unknown notification: \(notification.name)")
            return
        }
        let eventApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.asHSApplication()
        callback.call(withArguments: [eventName.rawValue, eventApp as Any])
    }
}

@_documentation(visibility: private)
@MainActor
@objc class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationModuleAPI {
    var moduleName = "hs.application"
    let engineID: UUID
    private var watcher: HSApplicationWatcherObject? = nil

    // Swift-retained storage for the JS-defined watcher emitter instance
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSApplicationEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
        shutdown()
    }

    @objc func toString() -> String {
        let n = runningApplications().count
        return "<\(moduleName): \(n) running app\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - API relating to running applications
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

    @objc func fromPID(_ pid: Int) -> HSApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid })?.asHSApplication()
    }

    @objc func frontmost() -> HSApplication? {
        return NSWorkspace.shared.frontmostApplication?.asHSApplication()
    }

    @objc func menuBarOwner() -> HSApplication? {
        return NSWorkspace.shared.menuBarOwningApplication?.asHSApplication()
    }

    @objc(_addWatcher:) func _addWatcher(listener: JSFunction) -> Bool {
        if watcher != nil {
            AKWarning("hs.application._addWatcher(): Already watching. Refusing to create a second.")
            return false
        }

        let watcherObject = HSApplicationWatcherObject(callback: listener)
        let selector = #selector(HSApplicationWatcherObject.handleEvent(notification:))

        for notificationName in HSApplicationWatcherObject.notificationToEventName.keys {
            AKDebug("hs.application._addWatcher(): Registering for \(notificationName.rawValue)")
            NSWorkspace.shared.notificationCenter.addObserver(watcherObject,
                                                              selector: selector,
                                                              name: notificationName,
                                                              object: nil)
        }

        watcher = watcherObject
        return true
    }

    @objc func _removeWatcher() {
        guard let watcherObject = watcher else { return }

        for notificationName in HSApplicationWatcherObject.notificationToEventName.keys {
            NSWorkspace.shared.notificationCenter.removeObserver(watcherObject as Any,
                                                                 name: notificationName,
                                                                 object: nil)
        }

        watcher = nil
        AKDebug("hs.application._removeWatcher(): Removed all application event watchers")
    }

    // MARK: - API for application information
    @objc func pathForBundleID(_ bundleID: String) -> String? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false)
    }

    @objc func pathsForBundleID(_ bundleID: String) -> [String] {
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).compactMap { $0.path(percentEncoded: false) }
    }

    @objc func infoForBundlePath(_ bundlePath: String) -> [String: Any]? {
        guard let app = Bundle(path: bundlePath) else {
            return nil
        }
        return app.infoDictionary
    }

    private func fileTypeToUTType(_ fileType: String) -> UTType? {
        var utType: UTType? = nil

        utType = UTType(fileType)
        if utType == nil {
            utType = UTType(mimeType: fileType)
        }
        if utType == nil {
            utType = UTType(filenameExtension: fileType)
        }

        return utType
    }

    @objc func pathForFileType(_ fileType: String) -> String? {
        guard let utType = fileTypeToUTType(fileType) else {
            AKError("Unable to resolve file type: \(fileType)")
            return nil
        }

        return NSWorkspace.shared.urlForApplication(toOpen: utType)?.path(percentEncoded: false)
    }

    @objc func pathsForFileType(_ fileType: String) -> [String] {
        guard let utType = fileTypeToUTType(fileType) else {
            AKError("Unable to resolve file type: \(fileType)")
            return []
        }

        return NSWorkspace.shared.urlsForApplications(toOpen: utType).compactMap { $0.path(percentEncoded: false) }
    }

    @objc func launchOrFocus(_ bundleID: String) -> JSPromise? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return JSEngine.shared.createResolvedPromise(with: false)
        }

        return JSEngine.shared.createPromise { holder in
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                Task { @MainActor in
                    if let error = error {
                        AKError("hs.application.launchOrFocus: \(error.localizedDescription)")
                        holder.resolveWith(false)
                    } else {
                        holder.resolveWith(app != nil)
                    }
                }
            }
        }
    }
}

