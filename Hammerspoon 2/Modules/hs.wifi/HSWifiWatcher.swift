//
//  HSWifiWatcher.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

let wifiWatcherValidEvents: Set<String> = [
    "ssidChange", "bssidChange", "countryCodeChange", "linkChange",
    "linkQualityChange", "modeChange", "powerChange", "scanCacheUpdated"
]

// MARK: - Watcher API protocol

/// A Wi-Fi event watcher that monitors changes to a Wi-Fi interface.
///
/// Create via `hs.wifi.addWatcher()`. Set a callback with `setCallback()`, then
/// call `start()` to begin receiving events. By default only `"ssidChange"` is
/// watched; use the `events` property to watch other event types.
///
/// The callback receives `(event, info)`:
///
/// | Event | Info keys |
/// |-------|-----------|
/// | `"ssidChange"` | `interface: string` |
/// | `"bssidChange"` | `interface: string` |
/// | `"countryCodeChange"` | `interface: string` |
/// | `"linkChange"` | `interface: string` |
/// | `"linkQualityChange"` | `interface: string`, `rssi: number`, `transmitRate: number` |
/// | `"modeChange"` | `interface: string` |
/// | `"powerChange"` | `interface: string` |
/// | `"scanCacheUpdated"` | `interface: string` |
///
/// Example:
/// ```js
/// const w = hs.wifi.addWatcher()
/// w.setCallback((event, info) => {
///     console.log(event + " on " + info.interface)
/// }).start()
/// ```
@objc protocol HSWifiWatcherAPI: HSTypeAPI, JSExport {

    /// The unique identifier assigned to this watcher.
    /// - Example:
    /// ```js
    /// const w = hs.wifi.addWatcher()
    /// console.log(w.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The event types this watcher will invoke its callback for. Defaults to
    /// `["ssidChange"]`. Unrecognized values are ignored with a console warning;
    /// see `hs.wifi.watcherEventTypes` for the list of valid values. Can be
    /// changed while the watcher is running.
    /// - Example:
    /// ```js
    /// const w = hs.wifi.addWatcher()
    /// w.events = ["ssidChange", "powerChange"]
    /// ```
    @objc var events: [String] { get set }

    /// Starts monitoring the event types configured in `events`.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// const w = hs.wifi.addWatcher()
    /// w.setCallback((ev, info) => console.log(ev)).start()
    /// ```
    @objc @discardableResult func start() -> HSWifiWatcher

    /// Stops monitoring Wi-Fi events.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.stop()
    /// ```
    @objc @discardableResult func stop() -> HSWifiWatcher

    /// Sets the callback function invoked when a watched Wi-Fi event occurs.
    /// - Parameter fn: {(event: string, info: Record<string, any>) => void} Called with the event name and an info dictionary; see type documentation for event names and info keys.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.setCallback((event, info) => {
    ///     if (event === "powerChange") console.log("power changed on " + info.interface)
    /// })
    /// ```
    @objc func setCallback(_ fn: JSFunction) -> HSWifiWatcher

    /// Stops the watcher and releases all resources. Called automatically during shutdown.
    /// - Example:
    /// ```js
    /// w.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWifiWatcher: NSObject, HSWifiWatcherAPI {
    @objc var typeName = "HSWifiWatcher"
    @objc let identifier = UUID().uuidString
    weak var module: HSWifiModule?
    private var callback: JSCallback?
    private var isRunning = false
    private var _events: [String] = ["ssidChange"]
    // The subset of `_events` the module has confirmed is actually registered with CoreWLAN.
    // Retrying start() only (re)attempts names missing from this set, so a partially-successful
    // registration is never double-counted against the module's shared ref counts.
    var registeredEvents: Set<String> = []

    @objc var events: [String] {
        get { _events }
        set {
            let filtered = newValue.filter { wifiWatcherValidEvents.contains($0) }
            if filtered.count != newValue.count {
                AKWarning("HSWifiWatcher(\(identifier)).events: ignoring unrecognized event name(s); valid values are \(wifiWatcherValidEvents.sorted().joined(separator: ", "))")
            }
            guard !filtered.isEmpty else {
                AKWarning("HSWifiWatcher(\(identifier)).events: refusing to set an empty event list")
                return
            }
            let wasRunning = isRunning
            if wasRunning, let module { registeredEvents = module.stopWatching(self) }
            _events = filtered
            if wasRunning {
                guard let module else {
                    isRunning = true
                    return
                }
                registeredEvents = module.startWatching(self)
                isRunning = Set(_events).isSubset(of: registeredEvents)
                if !isRunning {
                    AKWarning("HSWifiWatcher(\(identifier)).events: failed to register one or more event types; call start() again to retry")
                }
            }
        }
    }

    override init() {
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSWifiWatcher(\(identifier))")
    }

    func destroy() {
        _ = stop()
        callback?.detach(from: self)
        callback = nil
        module = nil
    }

    @objc @discardableResult func start() -> HSWifiWatcher {
        guard !isRunning else { return self }
        guard let module else {
            isRunning = true
            return self
        }
        registeredEvents = module.startWatching(self)
        guard Set(_events).isSubset(of: registeredEvents) else {
            AKWarning("HSWifiWatcher(\(identifier)).start(): failed to register one or more event types; call start() again to retry")
            return self
        }
        isRunning = true
        AKTrace("HSWifiWatcher(\(identifier)).start(): Started")
        return self
    }

    @objc @discardableResult func stop() -> HSWifiWatcher {
        guard isRunning else { return self }
        if let module { registeredEvents = module.stopWatching(self) }
        isRunning = false
        AKTrace("HSWifiWatcher(\(identifier)).stop(): Stopped")
        return self
    }

    @objc func setCallback(_ fn: JSFunction) -> HSWifiWatcher {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    /// Invoked by HSWifiModule when a watched event fires. Filters on this
    /// watcher's current running state and event subscription.
    func fire(event: String, info: [String: Any]) {
        guard isRunning, _events.contains(event) else { return }
        _ = callback?.value?.call(withArguments: [event, info])
    }
}
