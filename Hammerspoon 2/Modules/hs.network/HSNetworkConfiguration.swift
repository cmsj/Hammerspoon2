//
//  HSNetworkConfiguration.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import SystemConfiguration

// MARK: - C callback

// File-scope function so it is implicitly @Sendable and compatible with
// SCDynamicStoreCallBack without Swift closure capture restrictions.
// nonisolated: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor would make a global func @MainActor,
// which is incompatible with a @convention(c) C callback. The callback fires on DispatchQueue.main
// (set by SCDynamicStoreSetDispatchQueue), so MainActor.assumeIsolated is correct inside.
private nonisolated func scConfigWatcherCallback(
    _ store: SCDynamicStore,
    _ changedKeys: CFArray,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context = unsafe context else { return }
    let keys = changedKeys as? [String] ?? []   // convert CFArray before crossing isolation boundary
    let watcher = unsafe Unmanaged<HSNetworkConfigurationWatcher>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        watcher.handleChange(changedKeys: keys)
    }
}

// MARK: - Instance protocol

/// A watcher for System Configuration dynamic store key changes. Create with `hs.network.configurationWatcher()`.
@objc protocol HSNetworkConfigurationWatcherAPI: HSTypeAPI, JSExport {

    /// Always `"HSNetworkConfigurationWatcher"`.
    @objc var typeName: String { get }

    /// Specifies which dynamic store keys (or key patterns) to watch for changes.
    ///
    /// Must be called before `start()`. Each element of `keys` is treated as a string literal
    /// when `pattern` is `false` (the default), or as a regular expression when `pattern` is `true`.
    /// Calling `setKeys` again replaces the previous set of watched keys.
    /// - Parameter keys: An array of exact key strings (when `pattern` is `false`) or regular expressions (when `pattern` is `true`).
    /// - Parameter pattern: Pass `true` to treat each element of `keys` as a regular expression; omit or pass `false` for literal key matching.
    /// - Returns: This watcher for chaining.
    /// - Example:
    /// ```js
    /// // Watch a specific literal key
    /// hs.network.configurationWatcher()
    ///   .setKeys(["State:/Network/Global/IPv4"])
    ///   .setCallback((w, keys) => console.log(JSON.stringify(hs.network.configurationStore("State:/Network/Global/IPv4"))))
    ///   .start()
    ///
    /// // Watch all State:/Network keys by pattern
    /// hs.network.configurationWatcher()
    ///   .setKeys(["State:/Network/.*"], true)
    ///   .setCallback((w, keys) => console.log("Changed: " + keys.join(", ")))
    ///   .start()
    /// ```
    @objc @discardableResult func setKeys(_ keys: [String], _ pattern: Bool) -> HSNetworkConfigurationWatcher

    /// Sets the callback invoked when a watched key changes.
    ///
    /// The callback receives `(watcher, changedKeys)` where `changedKeys` is an array of key
    /// strings that changed since the last notification. Call `hs.network.configurationStore()`
    /// inside the callback to read the updated values.
    /// - Parameter callback: {(watcher: HSNetworkConfigurationWatcher, changedKeys: string[]) => void} Called whenever a watched key changes.
    /// - Returns: This watcher for chaining.
    /// - Example:
    /// ```js
    /// w.setCallback((w, keys) => {
    ///   const vals = hs.network.configurationStore(keys[0])
    ///   console.log(JSON.stringify(vals))
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkConfigurationWatcher

    /// Starts watching for dynamic store changes.
    ///
    /// The callback registered with `setCallback()` will be invoked whenever a key matching the
    /// patterns registered with `setKeys()` changes. Call `setKeys()` and `setCallback()` before
    /// calling `start()`.
    /// - Note: A started watcher, and its callback, stay alive until it's stopped, even if you don't keep a reference to it
    /// - Returns: This watcher for chaining.
    /// - Example:
    /// ```js
    /// w.start()
    /// ```
    @objc @discardableResult func start() -> HSNetworkConfigurationWatcher

    /// Stops watching for dynamic store changes.
    ///
    /// The callback will no longer be invoked. Call `start()` again to resume monitoring.
    /// - Returns: This watcher for chaining.
    /// - Example:
    /// ```js
    /// w.stop()
    /// ```
    @objc @discardableResult func stop() -> HSNetworkConfigurationWatcher
}

// MARK: - Instance class

@_documentation(visibility: private)
@MainActor
@objc final class HSNetworkConfigurationWatcher: NSObject, HSNetworkConfigurationWatcherAPI, HSTrackedObject {
    @objc var typeName = "HSNetworkConfigurationWatcher"

    @objc func toString() -> String {
        return "<\(typeName): \(_isWatching ? "watching" : "idle")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    private var store: SCDynamicStore?
    private var _callback: JSCallback?
    private weak var tracker: HSObjectTracker<HSNetworkConfigurationWatcher>?

    // A watching object is active: it stays alive with its callback until it's stopped, even if
    // the user dropped their reference to it. The store's info pointer is unretained, which is
    // safe because stopWatching() (called from destroy(), from deinit) detaches the store from
    // its queue before the watcher is freed.
    private var _isWatching = false {
        didSet { tracker?.setActive(self, _isWatching) }
    }

    init(tracker: HSObjectTracker<HSNetworkConfigurationWatcher>) {
        self.tracker = tracker
        super.init()
        var ctx = unsafe SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        unsafe ctx.info = unsafe Unmanaged.passUnretained(self).toOpaque()
        store = unsafe SCDynamicStoreCreate(
            nil,
            "hs.network.configurationWatcher" as CFString,
            scConfigWatcherCallback,
            &ctx
        )
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit HSNetworkConfigurationWatcher")
    }

    // MARK: - HSNetworkConfigurationWatcherAPI

    @objc @discardableResult func setKeys(_ keys: [String], _ pattern: Bool) -> HSNetworkConfigurationWatcher {
        guard let store = store else { return self }
        if pattern {
            SCDynamicStoreSetNotificationKeys(store, nil, keys as CFArray)
        } else {
            SCDynamicStoreSetNotificationKeys(store, keys as CFArray, nil)
        }
        return self
    }

    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkConfigurationWatcher {
        _callback?.detach(from: self)
        _callback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc @discardableResult func start() -> HSNetworkConfigurationWatcher {
        guard !_isWatching, let store = store else { return self }
        _isWatching = true
        SCDynamicStoreSetDispatchQueue(store, .main)
        AKDebug("HSNetworkConfigurationWatcher.start()")
        return self
    }

    @objc @discardableResult func stop() -> HSNetworkConfigurationWatcher {
        stopWatching()
        return self
    }

    // MARK: - Internal

    func destroy() {
        stopWatching()
        store = nil
        _callback?.detach(from: self)
        _callback = nil
    }

    func handleChange(changedKeys: [String]) {
        guard _isWatching else { return }
        _ = _callback?.call(withArguments: [self, changedKeys])
    }

    // MARK: - Private

    private func stopWatching() {
        guard _isWatching else { return }
        _isWatching = false
        // Remove from the dispatch queue so the callback can't fire after this point, even if
        // un-pinning the watcher releases the last reference to it.
        if let s = store { SCDynamicStoreSetDispatchQueue(s, nil) }
        AKDebug("HSNetworkConfigurationWatcher.stop()")
    }
}
