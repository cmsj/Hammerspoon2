//
//  AppInfo.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 28/09/2025.
//

import Foundation
import JavaScriptCore

@objc protocol HSAppInfoAPI: JSExport {
    @objc var appName: String { get }
    @objc var displayName: String { get }
    @objc var version: String { get }
    @objc var build: String { get }
    @objc var minimumOSVersion: String { get }
    @objc var copyrightNotice: String { get }
    @objc var bundleIdentifier: String { get }
}

@_documentation(visibility: private)
@objc class HSAppInfo: NSObject, HSModuleAPI, HSAppInfoAPI {
    var name = "hs.appinfo"

    deinit {
        print("Deinit of \(name)")
    }

    @objc var appName: String
    @objc var displayName: String
    @objc var version: String
    @objc var build: String
    @objc var minimumOSVersion: String
    @objc var copyrightNotice: String
    @objc var bundleIdentifier: String

    override required init() {
        func readFromInfoPlist(withKey key: String) -> String? {
            return Bundle.main.infoDictionary?[key] as? String
        }

        /// The official app name, defined in your project data.
        appName = readFromInfoPlist(withKey: "CFBundleName") ?? "(unknown app name)"

        /// The official app display name, eventually defined in your 'infoplist'.
        displayName = readFromInfoPlist(withKey: "CFBundleDisplayName") ?? "(unknown app display name)"

        /// The official version, defined in your project data.
        version = readFromInfoPlist(withKey: "CFBundleShortVersionString") ?? "(unknown app version)"

        /// The official 'build', defined in your project data.
        build = readFromInfoPlist(withKey: "CFBundleVersion") ?? "(unknown build number)"

        /// The minimum OS version defined in your project data.
        minimumOSVersion = readFromInfoPlist(withKey: "LSMinimumSystemVersion") ?? "(unknown minimum OSVersion)"

        /// The copyright notice eventually defined in your project data.
        copyrightNotice = readFromInfoPlist(withKey: "NSHumanReadableCopyright") ?? "(unknown copyright notice)"

        /// The official bundle identifier defined in your project data.
        bundleIdentifier = readFromInfoPlist(withKey: "CFBundleIdentifier") ?? "(unknown bundle identifier)"

        super.init()
    }
}
