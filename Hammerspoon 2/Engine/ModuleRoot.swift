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
@_spi(HammerspoonHost) import HammerspoonSDK

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

    /// Crash the app on purpose, to test crash reporting
    /// SKIP_DOCS
    @objc func _crash()

    /// Get every object that is currently active: running tasks, scheduled timers, started
    /// watchers and so on. An active object keeps running, and its callbacks keep being called,
    /// until it finishes or you stop it, whether or not you kept a reference to it. Use this to
    /// find something you started and lost track of.
    /// - Returns: {any[]} The active objects
    /// - Example:
    /// ```js
    /// hs.activeObjects().forEach(obj => console.log(obj.toString()))
    /// ```
    @objc func activeObjects() -> JSValue

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

    /// {(() => void) | null} Called when Hammerspoon 2 is launched again while it's already
    /// running (e.g. from Finder, Spotlight or `open -a`), or when its Dock icon is clicked, or null
    /// to remove it. It's only called when Settings → Advanced → "When launched while running" is
    /// set to "Call hs.onRelaunch". If it's set to that and no callback is set (for example because
    /// your config failed to load), the Console is shown instead, so you can always get back to it.
    /// - Example:
    /// ```js
    /// // Reload the config when the Dock icon is clicked
    /// hs.onRelaunch = () => hs.reload()
    ///
    /// // Remove it again
    /// hs.onRelaunch = null
    /// ```
    @objc var onRelaunch: JSFunction? { get set }

    /// {((path: string) => void) | null} Called when a file or folder is opened with Hammerspoon 2,
    /// e.g. by dropping it on the Dock icon, choosing Hammerspoon 2 from Finder's "Open With" menu,
    /// or `open -a "Hammerspoon 2" file.txt`, or null to remove it. It's called once for each item,
    /// with its path. Spoons (`.spoon2` files) are installed rather than passed to it, unless
    /// "Install Spoons when opened" is turned off in the Advanced tab of Settings.
    /// Items opened before your config has loaded (for example, the one that launched
    /// Hammerspoon 2) are passed to it once your config has loaded.
    /// - Example:
    /// ```js
    /// hs.onOpenFile = (path) => console.log(`Opened ${path}`)
    ///
    /// // Remove it again
    /// hs.onOpenFile = null
    /// ```
    @objc var onOpenFile: JSFunction? { get set }

    // Modules
    @objc var appinfo: HSAppInfoModule { get }
    @objc var application: HSApplicationModule { get }
    @objc var chooser: HSChooserModule { get }
    @objc var docs: HSDocsModule { get }
    @objc var dockicon: HSDockIconModule { get }
    @objc var eventtap: HSEventTapModule { get }
    @objc var audiodevice: HSAudioDeviceModule { get }
    @objc var ax: HSAXModule { get }
    @objc var bonjour: HSBonjourModule { get }
    @objc var camera: HSCameraModule { get }
    @objc var canvas: HSCanvasModule { get }
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
    @objc var socket: HSSocketModule { get }
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
    @objc var bluetooth: HSBluetoothModule { get }
    @objc var mqtt: HSMQTTModule { get }
    @objc var keyboard: HSKeyboardModule { get }
    @objc var shortcuts: HSShortcutsModule { get }
    @objc var sound: HSSoundModule { get }
    @objc var network: HSNetworkModule { get }
    @objc var window: HSWindowModule { get }
    @objc var mouse: HSMouseModule { get }
    @objc var plist: HSPlistModule { get }
    @objc var userdefaults: HSUserDefaultsModule { get }
    @objc var wifi: HSWifiModule { get }
    @objc var spoons: HSSpoonsModule { get }
}

@_documentation(visibility: private)
@objc class ModuleRoot: NSObject, ModuleRootAPI {
    let engineID: UUID
    let settings: SettingsManagerProtocol
    let spoonManager: SpoonManager
    let extensionLoader: ExtensionLoader
    @objc var modules: [String: HSModuleAPI] = [:]

    // Each module's JS wrapper, held so it's never garbage collected. Module properties are
    // computed, so nothing in JS holds the wrapper. Without this, callbacks a module owns
    // (`JSCallback(owner: module)`) and properties its hs.foo.js sets on it would be collected.
    // Retains the JSContext, so shutdown() must release it.
    private var moduleWrappers: [String: JSValue] = [:]

    private var _onRelaunch: JSCallback?
    private var _onOpenFile: JSCallback?

    // The context the modules were first used from, recorded with their wrappers, so shutdown()
    // can drop any pins its modules left behind.
    private var context: JSContext?

    /// - Parameters:
    ///   - spoonManager: Defaults to one using `settings`, so hs.spoons uses the same config
    ///     directory as everything else
    ///   - extensionLoader: Loads extensions for `require('ext:<name>')`. Defaults to the shared
    ///     one, since extension code is loaded once per process.
    init(engineID: UUID, settings: SettingsManagerProtocol = SettingsManager.shared, spoonManager: SpoonManager? = nil,
         extensionLoader: ExtensionLoader? = nil) {
        self.engineID = engineID
        self.settings = settings
        self.spoonManager = spoonManager ?? SpoonManager(settings: settings)
        self.extensionLoader = extensionLoader ?? .shared
        super.init()
    }

    private func getOrCreate<T>(name: String, type: T.Type) -> T where T: HSModuleAPI {
        getOrCreate(name: name) { type.init(engineID: engineID) }
    }

    /// - Parameter make: Creates the module, for one that needs more than its engine ID
    private func getOrCreate<T>(name: String, make: () -> T) -> T where T: HSModuleAPI {
        if let result = modules[name] as? T {
            pinWrapper(of: result, named: name)
            return result
        } else {
            AKDebug("Loading module: \(name)")
            let module = make()
            modules[name] = module
            pinWrapper(of: module, named: name)

            if let moduleJS = Bundle.main.url(forResource: "hs.\(name)", withExtension: "js") {
                try? _ = JSEngine.shared.evalFromURL(moduleJS)
            }

            return module
        }
    }

    /// This engine's instance of an extension's module, for `require('ext:<name>')`. The first
    /// time it's asked for, the extension is loaded (if no earlier engine loaded it), its module
    /// is created, and its enhancement script, if it has one, is run with the module as `ext`.
    /// - Parameter name: The extension's name
    /// - Throws: `ExtensionError` if the extension can't be loaded
    /// - Returns: The module
    func extensionModule(named name: String) throws(ExtensionError) -> any HSModuleAPI {
        let key = "ext:\(name)"
        if let module = modules[key] {
            pinWrapper(of: module, named: key)
            return module
        }

        let loaded = try extensionLoader.load(named: name)
        AKDebug("Loading extension module: \(name)")
        let module = loaded.moduleType.init(engineID: engineID)
        modules[key] = module
        pinWrapper(of: module, named: key)

        if let context = JSContext.current() {
            do {
                try NullReturnsInstaller.installExtensions(in: context, from: extensionLoader)
            } catch {
                AKError("ModuleRoot: couldn't make \(name)'s methods return null: \(error.localizedDescription)")
            }
            if let script = loaded.manifest.enhancementScriptURL,
               !runEnhancementScript(script, for: module, in: context) {
                // Half set up, so it's dropped, and the next require() starts again
                module.shutdown()
                modules[key] = nil
                moduleWrappers[key] = nil
            }
        }
        return module
    }

    /// Runs an extension's enhancement script as the body of a function whose one argument,
    /// `ext`, is the module. Anything it throws is rethrown from the `require()` that loaded it.
    /// - Returns: Whether it ran without throwing
    private func runEnhancementScript(_ url: URL, for module: any HSModuleAPI, in context: JSContext) -> Bool {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            context.exception = JSValue(newErrorFromMessage: "Couldn't read the extension's script, \(url.path)", in: context)
            return false
        }
        let previousHandler = context.exceptionHandler
        var thrown: JSValue?
        context.exceptionHandler = { _, exception in
            thrown = exception
        }
        // The newline keeps line numbers accurate after the first line, as require() does
        let function = context.evaluateScript("(function (ext) {\n" + source + "\n})", withSourceURL: url)
        if thrown == nil, let function, function.isObject {
            function.call(withArguments: [module])
        }
        context.exceptionHandler = previousHandler
        guard let thrown else { return true }
        context.exception = thrown
        return false
    }

    // Pins lazily, on JS access, since that's when the current context is known
    private func pinWrapper(of module: HSModuleAPI, named name: String) {
        guard moduleWrappers[name] == nil, let context = JSContext.current() else { return }
        moduleWrappers[name] = JSValue(object: module, in: context)
        self.context = self.context ?? context
    }

    /// Shuts down every module, then drops any pins they left behind
    /// - Returns: A description of each object that was still active after its module shut down.
    ///   This should always be empty; anything in it is a module bug, already logged.
    @discardableResult
    func shutdown() -> [String] {
        let names = Array(modules.keys)
        for moduleName in names {
            AKDebug("Destroying module: \(moduleName)")
            modules[moduleName]?.shutdown()
        }

        // A module's shutdown() should have dropped all its pins. One that didn't would keep its
        // object's wrapper, and with it this whole context, alive after reload.
        var leftovers: [String] = []
        if let context {
            leftovers = HSActiveObjects.removeAll(in: context)
            for object in leftovers {
                AKError("ModuleRoot: \(object) was still active after its module shut down")
            }
        }

        _onRelaunch?.detach(from: self)
        _onRelaunch = nil
        _onOpenFile?.detach(from: self)
        _onOpenFile = nil

        modules.removeAll()
        moduleWrappers.removeAll()
        context = nil
        return leftovers
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

    @objc func _crash() {
        AKWarning("hs._crash() called, crashing on purpose")
        fatalError("hs._crash() was called")
    }

    @objc func activeObjects() -> JSValue {
        // swiftlint:disable force_unwrapping
        let context = JSContext.current()!
        let result = JSValue(newArrayIn: context)!
        // swiftlint:enable force_unwrapping

        for (index, wrapper) in HSActiveObjects.wrappers(in: context).enumerated() {
            result.setValue(wrapper, at: index)
        }
        return result
    }

    // MARK: - Console
    @objc func openConsole() {
        if let url = URL(string: "hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func closeConsole() {
        if let url = URL(string: "hammerspoon2://closeConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Relaunch
    @objc var onRelaunch: JSValue? {
        get { _onRelaunch?.value }
        set {
            _onRelaunch?.detach(from: self)
            _onRelaunch = nil
            guard let newValue, !newValue.isNull, !newValue.isUndefined else { return }
            _onRelaunch = JSCallback(value: newValue, owner: self)
        }
    }

    /// Calls `hs.onRelaunch`, if it's set
    /// - Returns: `true` if there was a callback to call, whether or not it threw
    @discardableResult
    func callOnRelaunch() -> Bool {
        guard let callback = _onRelaunch?.value else { return false }
        callback.call(withArguments: [])
        return true
    }

    // MARK: - Open file
    @objc var onOpenFile: JSValue? {
        get { _onOpenFile?.value }
        set {
            _onOpenFile?.detach(from: self)
            _onOpenFile = nil
            guard let newValue, !newValue.isNull, !newValue.isUndefined else { return }
            _onOpenFile = JSCallback(value: newValue, owner: self)
        }
    }

    /// Calls `hs.onOpenFile` with `path`, if it's set
    /// - Parameter path: The path of the file or folder that was opened
    /// - Returns: `true` if there was a callback to call, whether or not it threw
    @discardableResult
    func callOnOpenFile(_ path: String) -> Bool {
        guard let callback = _onOpenFile?.value else { return false }
        callback.call(withArguments: [path])
        return true
    }

    @objc func clearConsole() {
        Task { @MainActor in
            HammerspoonLog.shared.clearLog()
        }
    }

    // Modules
    // swiftlint:disable colon opening_brace comma
    @objc var appinfo:      HSAppInfoModule         { getOrCreate(name: "appinfo",      type: HSAppInfoModule.self)}
    @objc var application:  HSApplicationModule     { getOrCreate(name: "application",  type: HSApplicationModule.self)}
    @objc var chooser:      HSChooserModule         { getOrCreate(name: "chooser",      type: HSChooserModule.self)}
    @objc var docs:         HSDocsModule            { getOrCreate(name: "docs",         type: HSDocsModule.self)}
    @objc var dockicon:     HSDockIconModule        { getOrCreate(name: "dockicon",     type: HSDockIconModule.self)}
    @objc var eventtap:     HSEventTapModule        { getOrCreate(name: "eventtap",     type: HSEventTapModule.self)}
    @objc var audiodevice:  HSAudioDeviceModule     { getOrCreate(name: "audiodevice",  type: HSAudioDeviceModule.self)}
    @objc var ax:           HSAXModule              { getOrCreate(name: "ax",           type: HSAXModule.self)}
    @objc var bonjour:      HSBonjourModule         { getOrCreate(name: "bonjour",      type: HSBonjourModule.self)}
    @objc var camera:       HSCameraModule          { getOrCreate(name: "camera",       type: HSCameraModule.self)}
    @objc var canvas:       HSCanvasModule          { getOrCreate(name: "canvas",       type: HSCanvasModule.self)}
    @objc var fs:           HSFSModule              { getOrCreate(name: "fs",           type: HSFSModule.self)}
    @objc var hashing:      HSHashModule            { getOrCreate(name: "hashing",      type: HSHashModule.self)}
    @objc var hotkey:       HSHotkeyModule          { getOrCreate(name: "hotkey",       type: HSHotkeyModule.self)}
    @objc var keycodes:     HSKeycodesModule        { getOrCreate(name: "keycodes",     type: HSKeycodesModule.self)}
    @objc var http:         HSHTTPModule            { getOrCreate(name: "http",         type: HSHTTPModule.self)}
    @objc var httpserver:   HSHTTPServerModule      { getOrCreate(name: "httpserver",   type: HSHTTPServerModule.self)}
    @objc var locale:       HSLocaleModule          { getOrCreate(name: "locale",       type: HSLocaleModule.self)}
    @objc var location:     HSLocationModule        { getOrCreate(name: "location",     type: HSLocationModule.self)}
    @objc var menubar:      HSMenuBarModule         { getOrCreate(name: "menubar",      type: HSMenuBarModule.self)}
    @objc var midi:         HSMIDIModule            { getOrCreate(name: "midi",         type: HSMIDIModule.self)}
    @objc var notify:       HSNotifyModule          { getOrCreate(name: "notify",       type: HSNotifyModule.self)}
    @objc var ocr:          HSOCRModule             { getOrCreate(name: "ocr",          type: HSOCRModule.self)}
    @objc var osascript:    HSOSAScriptModule       { getOrCreate(name: "osascript",    type: HSOSAScriptModule.self)}
    @objc var pasteboard:   HSPasteboardModule      { getOrCreate(name: "pasteboard",   type: HSPasteboardModule.self)}
    @objc var permissions:  HSPermissionsModule     { getOrCreate(name: "permissions",  type: HSPermissionsModule.self)}
    @objc var screen:       HSScreenModule          { getOrCreate(name: "screen",       type: HSScreenModule.self)}
    @objc var serial:       HSSerialModule          { getOrCreate(name: "serial",       type: HSSerialModule.self)}
    @objc var sharing:      HSSharingModule         { getOrCreate(name: "sharing",      type: HSSharingModule.self)}
    @objc var socket:       HSSocketModule          { getOrCreate(name: "socket",       type: HSSocketModule.self)}
    @objc var spotlight:    HSSpotlightModule       { getOrCreate(name: "spotlight",    type: HSSpotlightModule.self)}
    @objc var streamdeck:   HSStreamDeckModule      { getOrCreate(name: "streamdeck",   type: HSStreamDeckModule.self)}
    @objc var task:         HSTaskModule            { getOrCreate(name: "task",         type: HSTaskModule.self)}
    @objc var power:        HSPowerModule           { getOrCreate(name: "power",        type: HSPowerModule.self)}
    @objc var timer:        HSTimerModule           { getOrCreate(name: "timer",        type: HSTimerModule.self)}
    @objc var translation:  HSTranslationModule     { getOrCreate(name: "translation",  type: HSTranslationModule.self)}
    @objc var ui:           HSUIModule              { getOrCreate(name: "ui",           type: HSUIModule.self)}
    @objc var ipc:          HSIPCModule             { getOrCreate(name: "ipc",          type: HSIPCModule.self)}
    @objc var urlevent:     HSURLEventModule        { getOrCreate(name: "urlevent",     type: HSURLEventModule.self)}
    @objc var usb:          HSUSBModule             { getOrCreate(name: "usb",          type: HSUSBModule.self)}
    @objc var bluetooth:    HSBluetoothModule       { getOrCreate(name: "bluetooth",    type: HSBluetoothModule.self)}
    @objc var mqtt:         HSMQTTModule            { getOrCreate(name: "mqtt",         type: HSMQTTModule.self)}
    @objc var keyboard:     HSKeyboardModule        { getOrCreate(name: "keyboard",     type: HSKeyboardModule.self)}
    @objc var shortcuts:    HSShortcutsModule       { getOrCreate(name: "shortcuts",    type: HSShortcutsModule.self)}
    @objc var sound:        HSSoundModule           { getOrCreate(name: "sound",        type: HSSoundModule.self)}
    @objc var network:      HSNetworkModule         { getOrCreate(name: "network",      type: HSNetworkModule.self)}
    @objc var window:       HSWindowModule          { getOrCreate(name: "window",       type: HSWindowModule.self)}
    @objc var mouse:        HSMouseModule           { getOrCreate(name: "mouse",        type: HSMouseModule.self)}
    @objc var plist:        HSPlistModule           { getOrCreate(name: "plist",        type: HSPlistModule.self)}
    @objc var userdefaults: HSUserDefaultsModule    { getOrCreate(name: "userdefaults", type: HSUserDefaultsModule.self)}
    @objc var wifi:         HSWifiModule            { getOrCreate(name: "wifi",         type: HSWifiModule.self)}
    @objc var spoons:       HSSpoonsModule          { getOrCreate(name: "spoons") { HSSpoonsModule(engineID: engineID, spoonManager: spoonManager) }}
    // swiftlint:enable colon opening_brace comma
}

// MARK: - JSContextInstallable

struct ModuleRootInstaller: JSContextInstallable {
    let moduleRoot: ModuleRoot

    func install(in context: JSContext) throws {
        context.setObject(moduleRoot, forKeyedSubscript: "hs" as NSString)
    }
}
