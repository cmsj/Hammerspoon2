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

    /// Create a watcher for application events
    /// - Parameters:
    ///    - listener: A javascript function/lambda to call when any application event is received. The function will be called with two parameters: the name of the event, and the associated HSApplication object
    /// - Example:
    /// ```js
    /// hs.application.addWatcher((event, app) => {
    ///     console.log(event, app && app.title)
    /// })
    /// ```
    @objc func addWatcher(_ listener: JSValue)

    /// Remove a watcher for application events
    /// - Parameters:
    ///   - listener: The javascript function/lambda that was previously being used to handle events
    /// - Example:
    /// ```js
    /// hs.application.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSValue)

    // NOTE: These are not documented because they are private API for our JavaScript code
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(callback: JSValue)
    /// SKIP_DOCS
    @objc func _removeWatcher()

    /// Swift-retained storage for the JS ApplicationModuleWatcherEmitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSValue? { get set }
}

// MARK: - Implementations

class HSApplicationWatcherObject {
    let callback: JSValue

    static let notificationToEventName: [NSNotification.Name: String] = [
        NSWorkspace.willLaunchApplicationNotification: "willLaunch",
        NSWorkspace.didLaunchApplicationNotification: "didLaunch",
        NSWorkspace.didTerminateApplicationNotification: "didTerminate",
        NSWorkspace.didHideApplicationNotification: "didHide",
        NSWorkspace.didUnhideApplicationNotification: "didUnhide",
        NSWorkspace.didActivateApplicationNotification: "didActivate",
        NSWorkspace.didDeactivateApplicationNotification: "didDeactivate",
    ]

    init(callback: JSValue) {
        self.callback = callback
    }

    @objc func handleEvent(notification: NSNotification) {
        guard let eventName = Self.notificationToEventName[notification.name] else {
            AKError("hs.application: received unknown notification: \(notification.name)")
            return
        }
        let eventApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.asHSApplication()
        callback.call(withArguments: [eventName, eventApp as Any])
    }
}

@_documentation(visibility: private)
@MainActor
@objc class HSApplicationModule: NSObject, HSModuleAPI, HSApplicationModuleAPI {
    var name = "hs.application"
    let engineID: UUID
    private var watcher: HSApplicationWatcherObject? = nil

    // Swift-retained storage for the JS-defined ApplicationModuleWatcherEmitter instance
    @objc var _watcherEmitter: JSValue? = nil

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
        shutdown()
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

    @objc func addWatcher(_ listener: JSValue) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSValue) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(callback: JSValue) {
        if watcher != nil {
            AKWarning("hs.application._addWatcher(): Already watching. Refusing to create a second.")
            return
        }

        let watcherObject = HSApplicationWatcherObject(callback: callback)
        let selector = #selector(HSApplicationWatcherObject.handleEvent(notification:))

        for notificationName in HSApplicationWatcherObject.notificationToEventName.keys {
            AKTrace("hs.application._addWatcher(): Registering for \(notificationName.rawValue)")
            NSWorkspace.shared.notificationCenter.addObserver(watcherObject,
                                                              selector: selector,
                                                              name: notificationName,
                                                              object: nil)
        }

        watcher = watcherObject
    }

    @objc func _removeWatcher() {
        guard let watcherObject = watcher else { return }

        for notificationName in HSApplicationWatcherObject.notificationToEventName.keys {
            NSWorkspace.shared.notificationCenter.removeObserver(watcherObject as Any,
                                                                 name: notificationName,
                                                                 object: nil)
        }

        watcher = nil
        AKTrace("hs.application._removeWatcher(): Removed all application event watchers")
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

