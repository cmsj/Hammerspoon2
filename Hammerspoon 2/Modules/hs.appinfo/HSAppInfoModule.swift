//
//  AppInfoModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

func readFromInfoPlist(withKey key: String) -> String? {
    return Bundle.main.infoDictionary?[key] as? String
}

struct HSAppInfoData {
    let appName = readFromInfoPlist(withKey: "CFBundleName") ?? "(unknown app name)"
    let displayName = readFromInfoPlist(withKey: "CFBundleDisplayName") ?? "(unknown app display name)"
    let version = readFromInfoPlist(withKey: "CFBundleShortVersionString") ?? "(unknown app version)"
    let build = readFromInfoPlist(withKey: "CFBundleVersion") ?? "(unknown build number)"
    let minimumOSVersion = readFromInfoPlist(withKey: "LSMinimumSystemVersion") ?? "(unknown minimum OS version)"
    let copyrightNotice = readFromInfoPlist(withKey: "NSHumanReadableCopyright") ?? "(unknown copyright notice)"
    let bundleIdentifier = readFromInfoPlist(withKey: "CFBundleIdentifier") ?? "(unknown bundle identifier)"
    let bundlePath = Bundle.main.bundlePath
    let resourcePath = Bundle.main.resourcePath ?? "(unknown resource path)"
}

/// Module for accessing information about the Hammerspoon application itself
@objc protocol HSAppInfoModuleAPI: JSExport {
    /// The application's internal name (e.g., "Hammerspoon 2")
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.appName)
    /// ```
    @objc var appName: String { get }

    /// The application's display name shown to users
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.displayName)
    /// ```
    @objc var displayName: String { get }

    /// The application's version string (e.g., "2.0.0")
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.version)
    /// ```
    @objc var version: String { get }

    /// The application's build number
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.build)
    /// ```
    @objc var build: String { get }

    /// The minimum macOS version required to run this application
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.minimumOSVersion)
    /// ```
    @objc var minimumOSVersion: String { get }

    /// The copyright notice for this application
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.copyrightNotice)
    /// ```
    @objc var copyrightNotice: String { get }

    /// The application's bundle identifier (e.g., "com.hammerspoon.Hammerspoon-2")
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.bundleIdentifier)
    /// ```
    @objc var bundleIdentifier: String { get }

    /// The filesystem path to the application bundle
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.bundlePath)
    /// ```
    @objc var bundlePath: String { get }

    /// The filesystem path to the application's resource directory
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.resourcePath)
    /// ```
    @objc var resourcePath: String { get }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSAppInfoModule: NSObject, HSModuleAPI, HSAppInfoModuleAPI {
    var name = "hs.appinfo"
    let engineID: UUID

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        // Read all values from the bundle at initialization time
        // This is more efficient than reading from the plist on every access
        let appData = HSAppInfoData()
        _appName = appData.appName
        _displayName = appData.displayName
        _version = appData.version
        _build = appData.build
        _minimumOSVersion = appData.minimumOSVersion
        _copyrightNotice = appData.copyrightNotice
        _bundleIdentifier = appData.bundleIdentifier
        _bundlePath = appData.bundlePath
        _resourcePath = appData.resourcePath

        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - Private storage

    private let _appName: String
    private let _displayName: String
    private let _version: String
    private let _build: String
    private let _minimumOSVersion: String
    private let _copyrightNotice: String
    private let _bundleIdentifier: String
    private let _bundlePath: String
    private let _resourcePath: String

    // MARK: - Public API

    @objc var appName: String { _appName }
    @objc var displayName: String { _displayName }
    @objc var version: String { _version }
    @objc var build: String { _build }
    @objc var minimumOSVersion: String { _minimumOSVersion }
    @objc var copyrightNotice: String { _copyrightNotice }
    @objc var bundleIdentifier: String { _bundleIdentifier }
    @objc var bundlePath: String { _bundlePath }
    @objc var resourcePath: String { _resourcePath }
}
