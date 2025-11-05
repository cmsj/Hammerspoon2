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
    @objc var ax: HSAXModule { get }
    @objc var console: HSConsole { get }
    @objc var permissions: HSPermissions { get }
    @objc var timer: HSTimer { get }
    @objc var hashing: HSHashing { get }
    @objc var window: HSWindowModule { get }
}

@_documentation(visibility: private)
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    @objc var modules: [String: HSModuleAPI] = [:]

    private func getOrCreate<T>(name: String, type: T.Type) -> T where T:HSModuleAPI {
        if let result = modules[name] as? T {
            return result
        } else {
            AKTrace("Loading module: \(name)")
            let module = type.init()
            modules[name] = module

            if let moduleJS = Bundle.main.url(forResource: "hs.\(name)", withExtension: "js") {
                try? _ = JSEngine.shared.evalFromURL(moduleJS)
            }

            return module
        }
    }

    func shutdown() {
        for moduleName in modules.keys {
            AKTrace("Destroying module \(moduleName)")
            let module = modules[moduleName]
            module?.shutdown()
            modules.removeValue(forKey: moduleName)
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
    @objc var ax: HSAXModule { get { getOrCreate(name: "ax", type: HSAXModule.self)}}
    @objc var console: HSConsole { get { getOrCreate(name: "console", type: HSConsole.self)}}
    @objc var permissions: HSPermissions { get { getOrCreate(name: "permissions", type: HSPermissions.self)}}
    @objc var timer: HSTimer { get { getOrCreate(name: "timer", type: HSTimer.self)}}
    @objc var hashing: HSHashing { get { getOrCreate(name: "hashing", type: HSHashing.self)}}
    @objc var window: HSWindowModule { get { getOrCreate(name: "window", type: HSWindowModule.self)}}
}
