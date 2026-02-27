//
//  AppInfoModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Module for accessing information about the Hammerspoon application itself
@objc protocol HSAppInfoModuleAPI: JSExport {
    /// The application's internal name (e.g., "Hammerspoon 2")
    @objc var appName: String { get }

    /// The application's display name shown to users
    @objc var displayName: String { get }

    /// The application's version string (e.g., "2.0.0")
    @objc var version: String { get }

    /// The application's build number
    @objc var build: String { get }

    /// The minimum macOS version required to run this application
    @objc var minimumOSVersion: String { get }

    /// The copyright notice for this application
    @objc var copyrightNotice: String { get }

    /// The application's bundle identifier (e.g., "com.hammerspoon.Hammerspoon-2")
    @objc var bundleIdentifier: String { get }

    /// The filesystem path to the application bundle
    @objc var bundlePath: String { get }

    /// The filesystem path to the application's resource directory
    @objc var resourcePath: String { get }
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSAppInfoModule: NSObject, HSModuleAPI, HSAppInfoModuleAPI {
    var name = "hs.appinfo"

    // MARK: - Module lifecycle
    override required init() {
        // Read all values from the bundle at initialization time
        // This is more efficient than reading from the plist on every access
        func readFromInfoPlist(withKey key: String) -> String? {
            return Bundle.main.infoDictionary?[key] as? String
        }

        self._appName = readFromInfoPlist(withKey: "CFBundleName") ?? "(unknown app name)"
        self._displayName = readFromInfoPlist(withKey: "CFBundleDisplayName") ?? "(unknown app display name)"
        self._version = readFromInfoPlist(withKey: "CFBundleShortVersionString") ?? "(unknown app version)"
        self._build = readFromInfoPlist(withKey: "CFBundleVersion") ?? "(unknown build number)"
        self._minimumOSVersion = readFromInfoPlist(withKey: "LSMinimumSystemVersion") ?? "(unknown minimum OS version)"
        self._copyrightNotice = readFromInfoPlist(withKey: "NSHumanReadableCopyright") ?? "(unknown copyright notice)"
        self._bundleIdentifier = readFromInfoPlist(withKey: "CFBundleIdentifier") ?? "(unknown bundle identifier)"
        self._bundlePath = Bundle.main.bundlePath
        self._resourcePath = Bundle.main.resourcePath ?? "(unknown resource path)"

        super.init()
    }

    func shutdown() {}

    deinit {
        print("Deinit of \(name)")
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
