//
//  ModuleRoot.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 27/09/2025.
//

import Foundation
import AppKit
import JavaScriptCore
import JavaScriptCoreExtras

@_documentation(visibility: private)
@objc protocol ModuleRootAPI: JSExport {
    // Core
    /// Destroy the current JavaScript runtime and start a new one, loading all configuration from disk again
    /// - Example:
    /// ```js
    /// hs.reload()
    /// ```
    @objc func reload()

    /// Force garbage collection of JavaScript objects that no longer have any references
    /// - Note: This uses private macOS API
    /// - Example:
    /// ```js
    /// hs.collectGarbage()
    /// ```
    @objc func collectGarbage()

    @objc func openConsole()
    @objc func closeConsole()
    @objc func clearConsole()
    @objc func openSettings()

    // Modules
    @objc var appinfo: HSAppInfoModule { get }
    @objc var application: HSApplicationModule { get }
    @objc var chooser: HSChooserModule { get }
    @objc var docs: HSDocsModule { get }
    @objc var eventtap: HSEventTapModule { get }
    @objc var audiodevice: HSAudioDeviceModule { get }
    @objc var ax: HSAXModule { get }
    @objc var bonjour: HSBonjourModule { get }
    @objc var camera: HSCameraModule { get }
    @objc var fs: HSFSModule { get }
    @objc var hashing: HSHashModule { get }
    @objc var hotkey: HSHotkeyModule { get }
    @objc var keycodes: HSKeycodesModule { get }
    @objc var http: HSHTTPModule { get }
    @objc var httpserver: HSHTTPServerModule { get }
    @objc var location: HSLocationModule { get }
    @objc var menubar: HSMenuBarModule { get }
    @objc var notify: HSNotifyModule { get }
    @objc var ocr: HSOCRModule { get }
    @objc var osascript: HSOSAScriptModule { get }
    @objc var pasteboard: HSPasteboardModule { get }
    @objc var permissions: HSPermissionsModule { get }
    @objc var screen: HSScreenModule { get }
    @objc var spotlight: HSSpotlightModule { get }
    @objc var task: HSTaskModule { get }
    @objc var power: HSPowerModule { get }
    @objc var timer: HSTimerModule { get }
    @objc var translation: HSTranslationModule { get }
    @objc var ui: HSUIModule { get }
    @objc var urlevent: HSURLEventModule { get }
    @objc var ipc: HSIPCModule { get }
    @objc var usb: HSUSBModule { get }
    @objc var window: HSWindowModule { get }
}

@_documentation(visibility: private)
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    let engineID: UUID
    @objc var modules: [String: HSModuleAPI] = [:]

    init(engineID: UUID) {
        self.engineID = engineID
        super.init()
    }

    private func getOrCreate<T>(name: String, type: T.Type) -> T where T:HSModuleAPI {
        if let result = modules[name] as? T {
            return result
        } else {
            AKTrace("Loading module: \(name)")
            let module = type.init(engineID: engineID)
            modules[name] = module

            if let moduleJS = Bundle.main.url(forResource: "hs.\(name)", withExtension: "js") {
                try? _ = JSEngine.shared.evalFromURL(moduleJS)
            }

            return module
        }
    }

    func shutdown() {
        let names = Array(modules.keys)
        for moduleName in names {
            AKTrace("Destroying module: \(moduleName)")
            modules[moduleName]?.shutdown()
        }
        modules.removeAll()
    }

    // MARK: - ModuleRootAPI conformance

    // Core
    @objc func reload() {
        do {
            try ManagerManager.shared.reload()
        } catch {
            AKError("Unable to reload config: \(error.localizedDescription)")
        }
    }

    @objc func collectGarbage() {
        // For now we're using a private API synchronous garbage collector
//        unsafe JavaScriptCore.JSGarbageCollect(JSContext.current().jsGlobalContextRef)
        unsafe JSSynchronousGarbageCollectForDebugging(JSContext.current().jsGlobalContextRef)
    }

    // MARK: - Console
    @objc func openConsole() {
        if let url = URL(string:"hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func closeConsole() {
        if let url = URL(string:"hammerspoon2://closeConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func clearConsole() {
        Task { @MainActor in
            HammerspoonLog.shared.clearLog()
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let url = URL(string:"hammerspoon2://openSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // Modules
    @objc var appinfo: HSAppInfoModule { get { getOrCreate(name: "appinfo", type: HSAppInfoModule.self)}}
    @objc var application: HSApplicationModule { get { getOrCreate(name: "application", type: HSApplicationModule.self)}}
    @objc var chooser: HSChooserModule { get { getOrCreate(name: "chooser", type: HSChooserModule.self)}}
    @objc var docs: HSDocsModule { get { getOrCreate(name: "docs", type: HSDocsModule.self)}}
    @objc var eventtap: HSEventTapModule { get { getOrCreate(name: "eventtap", type: HSEventTapModule.self)}}
    @objc var audiodevice: HSAudioDeviceModule { get { getOrCreate(name: "audiodevice", type: HSAudioDeviceModule.self)}}
    @objc var ax: HSAXModule { get { getOrCreate(name: "ax", type: HSAXModule.self)}}
    @objc var bonjour: HSBonjourModule { get { getOrCreate(name: "bonjour", type: HSBonjourModule.self)}}
    @objc var camera: HSCameraModule { get { getOrCreate(name: "camera", type: HSCameraModule.self)}}
    @objc var fs: HSFSModule { get { getOrCreate(name: "fs", type: HSFSModule.self)}}
    @objc var hashing: HSHashModule { get { getOrCreate(name: "hashing", type: HSHashModule.self)}}
    @objc var hotkey: HSHotkeyModule { get { getOrCreate(name: "hotkey", type: HSHotkeyModule.self)}}
    @objc var keycodes: HSKeycodesModule { get { getOrCreate(name: "keycodes", type: HSKeycodesModule.self)}}
    @objc var http: HSHTTPModule { get { getOrCreate(name: "http", type: HSHTTPModule.self)}}
    @objc var httpserver: HSHTTPServerModule { get { getOrCreate(name: "httpserver", type: HSHTTPServerModule.self)}}
    @objc var location: HSLocationModule { get { getOrCreate(name: "location", type: HSLocationModule.self)}}
    @objc var menubar: HSMenuBarModule { get { getOrCreate(name: "menubar", type: HSMenuBarModule.self)}}
    @objc var notify: HSNotifyModule { get { getOrCreate(name: "notify", type: HSNotifyModule.self)}}
    @objc var ocr: HSOCRModule { get { getOrCreate(name: "ocr", type: HSOCRModule.self)}}
    @objc var osascript: HSOSAScriptModule { get { getOrCreate(name: "osascript", type: HSOSAScriptModule.self)}}
    @objc var pasteboard: HSPasteboardModule { get { getOrCreate(name: "pasteboard", type: HSPasteboardModule.self)}}
    @objc var permissions: HSPermissionsModule { get { getOrCreate(name: "permissions", type: HSPermissionsModule.self)}}
    @objc var screen: HSScreenModule { get { getOrCreate(name: "screen", type: HSScreenModule.self)}}
    @objc var spotlight: HSSpotlightModule { get { getOrCreate(name: "spotlight", type: HSSpotlightModule.self)}}
    @objc var task: HSTaskModule { get { getOrCreate(name: "task", type: HSTaskModule.self)}}
    @objc var power: HSPowerModule { get { getOrCreate(name: "power", type: HSPowerModule.self)}}
    @objc var timer: HSTimerModule { get { getOrCreate(name: "timer", type: HSTimerModule.self)}}
    @objc var translation: HSTranslationModule { get { getOrCreate(name: "translation", type: HSTranslationModule.self)}}
    @objc var ui: HSUIModule { get { getOrCreate(name: "ui", type: HSUIModule.self)}}
    @objc var ipc: HSIPCModule { get { getOrCreate(name: "ipc", type: HSIPCModule.self)}}
    @objc var urlevent: HSURLEventModule { get { getOrCreate(name: "urlevent", type: HSURLEventModule.self)}}
    @objc var usb: HSUSBModule { get { getOrCreate(name: "usb", type: HSUSBModule.self)}}
    @objc var window: HSWindowModule { get { getOrCreate(name: "window", type: HSWindowModule.self)}}
}

// MARK: - JSContextInstallable

struct ModuleRootInstaller: JSContextInstallable {
    let engineID: UUID

    func install(in context: JSContext) throws {
        context.setObject(ModuleRoot(engineID: engineID), forKeyedSubscript: "hs" as NSString)
    }
}
