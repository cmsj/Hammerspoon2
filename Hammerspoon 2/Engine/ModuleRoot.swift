//
//  ModuleRoot.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 27/09/2025.
//

import Foundation
import JavaScriptCore

@_documentation(visibility: private)
@objc protocol ModuleRootAPI: JSExport {
    // Core
    @objc func reload()

    // Modules
    @objc var appInfo: HSAppInfo { get }
    @objc var application: HSApplicationModule { get }
    @objc var console: HSConsole { get }
    @objc var permissions: HSPermissions { get }
    @objc var timer: HSTimer { get }
    @objc var hashing: HSHashing { get }
//    @objc var window: HSWindows { get }
}

@_documentation(visibility: private)
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    @objc var modules: [String: HSModuleAPI] = [:]

    private func getOrCreate<T>(name: String, type: T.Type) -> T where T:HSModuleAPI {
        AKTrace("Loading module: \(name)")
        if let result = modules[name] as? T {
            return result
        } else {
            let module = type.init()
            modules[name] = module
            return module
        }
    }

    // MARK: - ModuleRootAPI conformance

    // Core
    @objc func reload() {
        do {
            try ManagerManager.shared.boot()
        } catch {
            AKError("Unable to reload config: \(error.localizedDescription)")
        }
    }

    // Modules
    @objc var appInfo: HSAppInfo { get { getOrCreate(name: "appInfo", type: HSAppInfo.self)}}
    @objc var application: HSApplicationModule { get { getOrCreate(name: "application", type: HSApplicationModule.self)}}
    @objc var console: HSConsole { get { getOrCreate(name: "console", type: HSConsole.self)}}
    @objc var permissions: HSPermissions { get { getOrCreate(name: "permissions", type: HSPermissions.self)}}
    @objc var timer: HSTimer { get { getOrCreate(name: "timer", type: HSTimer.self)}}
    @objc var hashing: HSHashing { get { getOrCreate(name: "hashing", type: HSHashing.self)}}
//    @objc var window: HSWindows { get { getOrCreate(name: "window", type: HSWindows.self)}}
}
