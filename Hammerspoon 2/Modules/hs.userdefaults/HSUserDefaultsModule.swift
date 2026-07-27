//
//  HSUserDefaultsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

private let hsUserDefaultsSuiteName = "hs.userdefaults"

/// Module for storing small amounts of data that persists across Hammerspoon restarts.
///
/// Values are stored in a dedicated `UserDefaults` suite named "hs.userdefaults", kept
/// separate from the app's own preferences so it doesn't get confused with Hammerspoon's
/// own configuration when inspected with tools like the `defaults` command line utility.
///
/// JavaScript ↔ storage type mapping:
/// - JavaScript strings, numbers, booleans, arrays and objects round-trip directly
/// - JavaScript `Date` objects round-trip directly (no special API required)
/// - JavaScript `null`/`undefined` are not storable values; use `clear()` to remove a key
///
/// Because the suite is just a standard macOS preferences domain, it can also be inspected
/// and manipulated from the command line with the `defaults` tool:
/// ```sh
/// # Read every value stored by hs.userdefaults
/// defaults read hs.userdefaults
///
/// # Read a single key
/// defaults read hs.userdefaults someKey
///
/// # Write a value from the command line
/// defaults write hs.userdefaults someKey "some value"
///
/// # Delete a key
/// defaults delete hs.userdefaults someKey
/// ```
///
/// - Note: This suite is **not encrypted on disk**. Do not use it to store sensitive
///   information such as passwords, API keys, or tokens.
@objc protocol HSUserDefaultsModuleAPI: JSExport {

    /// Store a value under the given key. The value persists across Hammerspoon restarts.
    /// - Parameters:
    ///   - key: The name of the setting
    ///   - value: A string, number, boolean, Date, array, or object to store
    /// - Example:
    /// ```js
    /// hs.userdefaults.set("username", "chris")
    /// hs.userdefaults.set("launchCount", 42)
    /// hs.userdefaults.set("lastRun", new Date())
    /// ```
    @objc func set(_ key: String, _ value: Any)

    /// Retrieve a previously stored value.
    /// - Parameter key: The name of the setting
    /// - Returns: {any} The stored value, or null if nothing is stored under that key
    /// - Example:
    /// ```js
    /// const username = hs.userdefaults.get("username")
    /// ```
    @objc func get(_ key: String) -> Any?

    /// Delete a previously stored value.
    /// - Parameter key: The name of the setting to remove
    /// - Returns: true if a value existed and was removed, false if the key was not set
    /// - Example:
    /// ```js
    /// hs.userdefaults.clear("username")
    /// ```
    @objc func clear(_ key: String) -> Bool

    /// Get the names of all currently stored settings.
    /// - Returns: An array of setting names
    /// - Example:
    /// ```js
    /// console.log(hs.userdefaults.getKeys())
    /// ```
    @objc func getKeys() -> [String]

    /// Watch a key for changes.
    /// - Parameters:
    ///   - key: The name of the setting to watch
    ///   - listener: {(key: string, newValue: any) => void} Called with the key and its new value whenever it changes
    /// - Example:
    /// ```js
    /// hs.userdefaults.addWatcher("username", (key, newValue) => {
    ///     console.log(key + " changed to " + newValue)
    /// })
    /// ```
    @objc func addWatcher(_ key: String, _ listener: JSFunction)

    /// Remove a previously registered watcher.
    /// - Parameters:
    ///   - key: The name of the setting originally passed to `addWatcher`
    ///   - listener: The function originally passed to `addWatcher`
    /// - Example:
    /// ```js
    /// hs.userdefaults.removeWatcher("username", myHandler)
    /// ```
    @objc func removeWatcher(_ key: String, _ listener: JSFunction)

    // NOTE: These are private API for the companion JS file only
    /// SKIP_DOCS
    @objc(_addWatcher::) func _addWatcher(_ key: String, callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher(_ key: String)
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSUserDefaultsModule: NSObject, HSModuleAPI, HSUserDefaultsModuleAPI {
    var name = "hs.userdefaults"
    let engineID: UUID

    private let suite: UserDefaults?
    private var watcherCallbacks: [String: JSFunction] = [:]

    @objc var _watcherEmitter: JSFunction?

    required init(engineID: UUID) {
        self.engineID = engineID
        self.suite = UserDefaults(suiteName: hsUserDefaultsSuiteName)
        super.init()
        if suite == nil {
            AKError("hs.userdefaults: Failed to create UserDefaults suite '\(hsUserDefaultsSuiteName)'. This module will not function.")
        }
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        if let suite {
            for key in watcherCallbacks.keys {
                suite.removeObserver(self, forKeyPath: key)
            }
        }
        watcherCallbacks.removeAll()
        _watcherEmitter = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
        shutdown()
    }

    // MARK: - Storage

    @objc func set(_ key: String, _ value: Any) {
        guard let suite else {
            AKError("hs.userdefaults.set(): No UserDefaults suite available")
            return
        }
        suite.set(value, forKey: key)
    }

    @objc func get(_ key: String) -> Any? {
        guard let suite else {
            AKError("hs.userdefaults.get(): No UserDefaults suite available")
            return nil
        }
        return suite.object(forKey: key)
    }

    @objc func clear(_ key: String) -> Bool {
        guard let suite else {
            AKError("hs.userdefaults.clear(): No UserDefaults suite available")
            return false
        }
        let existed = suite.object(forKey: key) != nil
        suite.removeObject(forKey: key)
        return existed
    }

    @objc func getKeys() -> [String] {
        guard let suite else {
            AKError("hs.userdefaults.getKeys(): No UserDefaults suite available")
            return []
        }
        return Array(suite.dictionaryRepresentation().keys)
    }

    // MARK: - Watchers

    @objc func addWatcher(_ key: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [key, listener])
    }

    @objc func removeWatcher(_ key: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [key, listener])
    }

    @objc(_addWatcher::) func _addWatcher(_ key: String, callback: JSFunction) {
        guard let suite else {
            AKError("hs.userdefaults.addWatcher(): No UserDefaults suite available")
            return
        }
        guard watcherCallbacks[key] == nil else {
            AKWarning("hs.userdefaults.addWatcher(): Already watching '\(key)'. Refusing to create a second.")
            return
        }
        watcherCallbacks[key] = callback
        unsafe suite.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        AKTrace("hs.userdefaults.addWatcher(): Started watching '\(key)'")
    }

    @objc func _removeWatcher(_ key: String) {
        guard let suite else {
            AKError("hs.userdefaults.removeWatcher(): No UserDefaults suite available")
            return
        }
        guard watcherCallbacks[key] != nil else { return }
        suite.removeObserver(self, forKeyPath: key)
        watcherCallbacks.removeValue(forKey: key)
        AKTrace("hs.userdefaults.removeWatcher(): Stopped watching '\(key)'")
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let keyPath else { return }
        MainActor.assumeIsolated {
            guard let suite, let callback = watcherCallbacks[keyPath] else { return }
            let newValue = suite.object(forKey: keyPath)
            _ = callback.call(withArguments: [keyPath, newValue as Any])
        }
    }
}
