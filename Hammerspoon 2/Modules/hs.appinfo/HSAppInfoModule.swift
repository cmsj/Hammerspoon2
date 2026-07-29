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
    let machineName = Host.current().localizedName ?? "(unknown machine name)"
    let pid = Int(ProcessInfo.processInfo.processIdentifier)
    let arguments = ProcessInfo.processInfo.arguments
    let environment = ProcessInfo.processInfo.environment
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let osVersionParts = ProcessInfo.processInfo.operatingSystemVersion
    let cpuCount = ProcessInfo.processInfo.processorCount
    let ramAmount: Int = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024)

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

    /// The filesystem path to the main Hammerspoon 2 configuration file
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.configPath)
    /// ```
    @objc var configPath: String { get }

    /// The filesystem path to the directory Hammerspoon 2 loaded its config from
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.configDir)
    /// ```
    @objc var configDir: String { get }

    /// The user-assigned name of this Mac, as shown in System Settings > Sharing
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.machineName)
    /// ```
    @objc var machineName: String { get }
    
    /// Hammerspoon 2's Process Identifier (PID)
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.pid)
    /// ```
    @objc var pid: Int { get }

    /// The command-line arguments Hammerspoon 2 was launched with
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.arguments.join(" "))
    /// ```
    @objc var arguments: [String] { get }

    /// The environment variables Hammerspoon 2 was launched with
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.environment["PATH"])
    /// ```
    @objc var environment: [String: String] { get }

    /// The version of macOS Hammerspoon 2 is currently running on (e.g., "Version 26.5.2 (Build 25F84)")
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.osVersion)
    /// ```
    @objc var osVersion: String { get }

    /// The version of macOS Hammerspoon 2 is currently running on, broken into its numeric components
    ///
    /// Keys: `major`, `minor`, `patch`.
    /// - Example:
    /// ```js
    /// const v = hs.appinfo.osVersionParts
    /// console.log(v.major + "." + v.minor + "." + v.patch)
    /// ```
    @objc var osVersionParts: [String: Int] { get }

    /// The number of logical CPU cores available on this Mac
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.cpuCount)
    /// ```
    @objc var cpuCount: Int { get }

    /// The amount of physical RAM installed on this Mac, in gigabytes
    /// - Example:
    /// ```js
    /// console.log(hs.appinfo.ramAmount)
    /// ```
    @objc var ramAmount: Int { get }
}

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
        _machineName = appData.machineName
        _pid = appData.pid
        _arguments = appData.arguments
        _environment = appData.environment
        _osVersion = appData.osVersion
        _osVersionParts = [
            "major": appData.osVersionParts.majorVersion,
            "minor": appData.osVersionParts.minorVersion,
            "patch": appData.osVersionParts.patchVersion
            ]
        _cpuCount = appData.cpuCount
        _ramAmount = appData.ramAmount

        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
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
    private let _machineName: String
    private let _pid: Int
    private let _arguments: [String]
    private let _environment: [String: String]
    private let _osVersion: String
    private let _osVersionParts: [String: Int]
    private let _cpuCount: Int
    private let _ramAmount: Int

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
    @objc var configPath: String { SettingsManager.shared.configLocation.path }
    @objc var configDir: String {
        "/\(SettingsManager.shared.configLocation.pathComponents.dropFirst().dropLast().joined(separator: "/"))"
    }
    @objc var machineName: String { _machineName }
    @objc var pid: Int { _pid }
    @objc var arguments: [String] { _arguments }
    @objc var environment: [String: String] { _environment }
    @objc var osVersion: String { _osVersion }
    @objc var osVersionParts: [String: Int] { _osVersionParts }
    @objc var cpuCount: Int { _cpuCount }
    @objc var ramAmount: Int { _ramAmount }
}
