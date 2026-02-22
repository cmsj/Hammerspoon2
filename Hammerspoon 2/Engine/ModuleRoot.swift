//
//  ModuleRoot.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 27/09/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

@_documentation(visibility: private)
@objc protocol ModuleRootAPI: JSExport {
    // Core
    @objc func reload()

    // Modules
    @objc var alert: HSAlertModule { get }
    @objc var appinfo: HSAppInfoModule { get }
    @objc var application: HSApplicationModule { get }
    @objc var ax: HSAXModule { get }
    @objc var console: HSConsoleModule { get }
    @objc var hashing: HSHashModule { get }
    @objc var hotkey: HSHotkeyModule { get }
    @objc var permissions: HSPermissionsModule { get }
    @objc var task: HSTaskModule { get }
    @objc var timer: HSTimerModule { get }
    @objc var ui: HSUIModule { get }
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
    @objc var alert: HSAlertModule { get { getOrCreate(name: "alert", type: HSAlertModule.self)}}
    @objc var appinfo: HSAppInfoModule { get { getOrCreate(name: "appinfo", type: HSAppInfoModule.self)}}
    @objc var application: HSApplicationModule { get { getOrCreate(name: "application", type: HSApplicationModule.self)}}
    @objc var ax: HSAXModule { get { getOrCreate(name: "ax", type: HSAXModule.self)}}
    @objc var console: HSConsoleModule { get { getOrCreate(name: "console", type: HSConsoleModule.self)}}
    @objc var hashing: HSHashModule { get { getOrCreate(name: "hashing", type: HSHashModule.self)}}
    @objc var hotkey: HSHotkeyModule { get { getOrCreate(name: "hotkey", type: HSHotkeyModule.self)}}
    @objc var permissions: HSPermissionsModule { get { getOrCreate(name: "permissions", type: HSPermissionsModule.self)}}
    @objc var task: HSTaskModule { get { getOrCreate(name: "task", type: HSTaskModule.self)}}
    @objc var timer: HSTimerModule { get { getOrCreate(name: "timer", type: HSTimerModule.self)}}
    @objc var ui: HSUIModule { get { getOrCreate(name: "ui", type: HSUIModule.self)}}
    @objc var window: HSWindowModule { get { getOrCreate(name: "window", type: HSWindowModule.self)}}
}

// MARK: - JSContextInstallable

struct ModuleRootInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        context.setObject(ModuleRoot(), forKeyedSubscript: "hs" as NSString)
    }
}
