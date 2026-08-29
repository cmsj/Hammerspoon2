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

    /// Open the Hammerspoon Console window
    /// - Example:
    /// ```js
    /// hs.openConsole()
    /// ```
    @objc func openConsole()

    /// Close the Hammerspoon Console window
    /// - Example:
    /// ```js
    /// hs.closeConsole()
    /// ```
    @objc func closeConsole()

    /// Clear the Hammerspoon Console log
    /// - Example:
    /// ```js
    /// hs.clearConsole()
    /// ```
    @objc func clearConsole()

    /// Load a Spoon - a packaged, reusable piece of configuration - by name, from the
    /// `Spoons` directory inside your config directory. A Spoon must contain a well-formed
    /// `spoon.json` (with non-empty `name`, `author`, `version`, and `description` fields)
    /// and an `init.js`, or loading fails with an exception. `init.js` is loaded through the
    /// same `require()` used for the rest of your config, so it can itself `require()`
    /// further files from within the Spoon's own directory using relative paths. On success,
    /// the Spoon's `module.exports` is also stored on `hs.spoons` under its name, so other
    /// code can reach an already-loaded Spoon without needing to call `loadSpoon()` again.
    ///
    /// `init.js` must set `module.exports` to an object (or a function, since functions are
    /// objects too) - loading fails with an exception otherwise. Its `author`, `description`,
    /// and `version` properties are then set from `spoon.json`, overwriting any of the same
    /// name the Spoon's own `init.js` set, so that information is always present and always
    /// reflects what's on disk.
    /// - Parameter name: The Spoon's name, matching its directory name under `Spoons/`
    /// - Returns: Whatever the Spoon's `init.js` assigned to `module.exports`
    /// - Example:
    /// ```js
    /// const MySpoon = hs.loadSpoon("MySpoon")
    /// console.log(MySpoon.version)
    /// // ...later, from anywhere...
    /// hs.spoons.MySpoon.doSomething()
    /// ```
    @objc func loadSpoon(_ name: String) -> JSValue?

    /// A namespace holding every Spoon loaded so far via `loadSpoon()`, keyed by name -
    /// e.g. a Spoon loaded with `hs.loadSpoon("MySpoon")` is also reachable as
    /// `hs.spoons.MySpoon`. Empty until at least one Spoon has been loaded.
    /// - Example:
    /// ```js
    /// hs.loadSpoon("MySpoon")
    /// hs.spoons.MySpoon.doSomething()
    /// ```
    @objc var spoons: JSValue? { get }

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
    @objc var locale: HSLocaleModule { get }
    @objc var location: HSLocationModule { get }
    @objc var menubar: HSMenuBarModule { get }
    @objc var midi: HSMIDIModule { get }
    @objc var notify: HSNotifyModule { get }
    @objc var ocr: HSOCRModule { get }
    @objc var osascript: HSOSAScriptModule { get }
    @objc var pasteboard: HSPasteboardModule { get }
    @objc var permissions: HSPermissionsModule { get }
    @objc var screen: HSScreenModule { get }
    @objc var serial: HSSerialModule { get }
    @objc var sharing: HSSharingModule { get }
    @objc var spotlight: HSSpotlightModule { get }
    @objc var streamdeck: HSStreamDeckModule { get }
    @objc var task: HSTaskModule { get }
    @objc var power: HSPowerModule { get }
    @objc var timer: HSTimerModule { get }
    @objc var translation: HSTranslationModule { get }
    @objc var ui: HSUIModule { get }
    @objc var urlevent: HSURLEventModule { get }
    @objc var ipc: HSIPCModule { get }
    @objc var usb: HSUSBModule { get }
    @objc var keyboard: HSKeyboardModule { get }
    @objc var shortcuts: HSShortcutsModule { get }
    @objc var sound: HSSoundModule { get }
    @objc var network: HSNetworkModule { get }
    @objc var window: HSWindowModule { get }
    @objc var mouse: HSMouseModule { get }
    @objc var plist: HSPlistModule { get }
    @objc var userdefaults: HSUserDefaultsModule { get }
    @objc var wifi: HSWifiModule { get }
}

@_documentation(visibility: private)
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    let engineID: UUID
    let settings: SettingsManagerProtocol
    let spoonManager: SpoonManager
    @objc var modules: [String: HSModuleAPI] = [:]

    init(engineID: UUID, settings: SettingsManagerProtocol = SettingsManager.shared, spoonManager: SpoonManager = .shared) {
        self.engineID = engineID
        self.settings = settings
        self.spoonManager = spoonManager
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

    // MARK: - Spoons

    // Backing store for the `spoons` namespace, created lazily on first use so a config that
    // never loads a Spoon never allocates it. Kept as one persistent JSValue (not rebuilt from
    // a Swift dictionary) so its object identity is stable across accesses.
    private var _spoons: JSValue?

    private func spoonsObject(in context: JSContext) -> JSValue {
        if let existing = _spoons { return existing }
        let obj = JSValue(newObjectIn: context)!
        _spoons = obj
        return obj
    }

    @objc var spoons: JSValue? {
        guard let context = JSContext.current() else { return nil }
        return spoonsObject(in: context)
    }

    @objc func loadSpoon(_ name: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }

        func fail(_ message: String) -> JSValue? {
            context.exception = JSValue(newErrorFromMessage: "hs.loadSpoon(): \(message)", in: context)
            return nil
        }

        let spoonDir = settings.configLocation
            .deletingLastPathComponent()
            .appendingPathComponent("Spoons")
            .appendingPathComponent(name)
        let initJSURL = spoonDir.appendingPathComponent("init.js")

        let metadata: SpoonMetadata
        do {
            metadata = try spoonManager.validateSpoon(at: spoonDir)
        } catch {
            return fail("'\(name)' \(error.localizedDescription)")
        }

        guard let requireFn = context.globalObject.objectForKeyedSubscript("require"), !requireFn.isUndefined else {
            return fail("require() is not available")
        }

        // If init.js itself throws, require() already leaves context.exception set - leave it
        // as-is rather than overwriting it with our own message.
        let result = requireFn.call(withArguments: [initJSURL.path])
        if context.exception != nil {
            return result
        }

        guard let result, result.isObject else {
            return fail("'\(name)' must set module.exports to an object")
        }

        // Authoritative from spoon.json, so these always reflect it even if the Spoon's own
        // init.js also happens to set properties of the same name.
        result.setValue(metadata.author, forProperty: "author")
        result.setValue(metadata.description, forProperty: "description")
        result.setValue(metadata.version, forProperty: "version")
        spoonsObject(in: context).setValue(result, forProperty: name)
        return result
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
    @objc var locale: HSLocaleModule { get { getOrCreate(name: "locale", type: HSLocaleModule.self)}}
    @objc var location: HSLocationModule { get { getOrCreate(name: "location", type: HSLocationModule.self)}}
    @objc var menubar: HSMenuBarModule { get { getOrCreate(name: "menubar", type: HSMenuBarModule.self)}}
    @objc var midi: HSMIDIModule { get { getOrCreate(name: "midi", type: HSMIDIModule.self)}}
    @objc var notify: HSNotifyModule { get { getOrCreate(name: "notify", type: HSNotifyModule.self)}}
    @objc var ocr: HSOCRModule { get { getOrCreate(name: "ocr", type: HSOCRModule.self)}}
    @objc var osascript: HSOSAScriptModule { get { getOrCreate(name: "osascript", type: HSOSAScriptModule.self)}}
    @objc var pasteboard: HSPasteboardModule { get { getOrCreate(name: "pasteboard", type: HSPasteboardModule.self)}}
    @objc var permissions: HSPermissionsModule { get { getOrCreate(name: "permissions", type: HSPermissionsModule.self)}}
    @objc var screen: HSScreenModule { get { getOrCreate(name: "screen", type: HSScreenModule.self)}}
    @objc var serial: HSSerialModule { get { getOrCreate(name: "serial", type: HSSerialModule.self)}}
    @objc var sharing: HSSharingModule { get { getOrCreate(name: "sharing", type: HSSharingModule.self)}}
    @objc var spotlight: HSSpotlightModule { get { getOrCreate(name: "spotlight", type: HSSpotlightModule.self)}}
    @objc var streamdeck: HSStreamDeckModule { get { getOrCreate(name: "streamdeck", type: HSStreamDeckModule.self)}}
    @objc var task: HSTaskModule { get { getOrCreate(name: "task", type: HSTaskModule.self)}}
    @objc var power: HSPowerModule { get { getOrCreate(name: "power", type: HSPowerModule.self)}}
    @objc var timer: HSTimerModule { get { getOrCreate(name: "timer", type: HSTimerModule.self)}}
    @objc var translation: HSTranslationModule { get { getOrCreate(name: "translation", type: HSTranslationModule.self)}}
    @objc var ui: HSUIModule { get { getOrCreate(name: "ui", type: HSUIModule.self)}}
    @objc var ipc: HSIPCModule { get { getOrCreate(name: "ipc", type: HSIPCModule.self)}}
    @objc var urlevent: HSURLEventModule { get { getOrCreate(name: "urlevent", type: HSURLEventModule.self)}}
    @objc var usb: HSUSBModule { get { getOrCreate(name: "usb", type: HSUSBModule.self)}}
    @objc var keyboard: HSKeyboardModule { get { getOrCreate(name: "keyboard", type: HSKeyboardModule.self)}}
    @objc var shortcuts: HSShortcutsModule { get { getOrCreate(name: "shortcuts", type: HSShortcutsModule.self)}}
    @objc var sound: HSSoundModule { get { getOrCreate(name: "sound", type: HSSoundModule.self)}}
    @objc var network: HSNetworkModule { get { getOrCreate(name: "network", type: HSNetworkModule.self)}}
    @objc var window: HSWindowModule { get { getOrCreate(name: "window", type: HSWindowModule.self)}}
    @objc var mouse: HSMouseModule { get { getOrCreate(name: "mouse", type: HSMouseModule.self)}}
    @objc var plist: HSPlistModule { get { getOrCreate(name: "plist", type: HSPlistModule.self)}}
    @objc var userdefaults: HSUserDefaultsModule { get { getOrCreate(name: "userdefaults", type: HSUserDefaultsModule.self)}}
    @objc var wifi: HSWifiModule { get { getOrCreate(name: "wifi", type: HSWifiModule.self)}}
}

// MARK: - JSContextInstallable

struct ModuleRootInstaller: JSContextInstallable {
    let engineID: UUID

    func install(in context: JSContext) throws {
        context.setObject(ModuleRoot(engineID: engineID), forKeyedSubscript: "hs" as NSString)
    }
}
