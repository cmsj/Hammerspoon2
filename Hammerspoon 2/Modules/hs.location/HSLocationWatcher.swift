//
//  HSLocationWatcher.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//

import Foundation
import JavaScriptCore
import CoreLocation

// MARK: - Watcher API protocol

/// An independent location tracking object.
///
/// Create via `hs.location.addWatcher()`. Call `start()` to begin receiving
/// updates, and set a callback to handle them.
///
/// The callback receives `(event, data)`:
///
/// | Event | Data |
/// |-------|------|
/// | `"location"` | a locationTable |
/// | `"error"` | an error message string |
/// | `"authorizationChanged"` | the new status string (`"authorized"`, `"denied"`, `"restricted"`, `"notDetermined"`) |
///
/// Example:
/// ```js
/// const w = hs.location.addWatcher()
/// w.setCallback((event, data) => {
///     if (event === 'location') console.log(data.latitude, data.longitude)
/// })
/// w.start()
/// ```
@objc protocol HSLocationWatcherAPI: HSTypeAPI, JSExport {
    /// The unique identifier assigned to this watcher.
    /// - Example:
    /// ```js
    /// const w = hs.location.addWatcher()
    /// console.log(w.identifier)
    /// ```
    @objc var identifier: String { get }

    /// Starts location updates. The callback must be set first.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// const w = hs.location.addWatcher()
    /// w.setCallback((ev, d) => console.log(ev, d)).start()
    /// ```
    @objc @discardableResult func start() -> HSLocationWatcher

    /// Stops location updates.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.stop()
    /// ```
    @objc @discardableResult func stop() -> HSLocationWatcher

    /// Sets the callback function invoked when location events occur.
    /// - Parameter fn: `function(event, data)` — see type documentation for event names
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.setCallback((event, data) => {
    ///     if (event === 'location') console.log(data.latitude, data.longitude)
    /// })
    /// ```
    @objc func setCallback(_ fn: JSValue) -> HSLocationWatcher

    /// Returns the most recently received location, or null if none yet.
    /// - Returns: a locationTable, or null
    /// - Example:
    /// ```js
    /// const loc = w.location()
    /// if (loc) console.log(`${loc.latitude}, ${loc.longitude}`)
    /// ```
    @objc func location() -> [AnyHashable: Any]?

    /// The minimum distance in metres the device must move before a new update
    /// is delivered. Defaults to `kCLDistanceFilterNone` (all movements reported).
    /// - Example:
    /// ```js
    /// w.distanceFilter = 50  // only update after moving 50 m
    /// ```
    @objc var distanceFilter: Double { get set }
}

// MARK: - Watcher implementation

@_documentation(visibility: private)
@MainActor
@objc class HSLocationWatcher: NSObject, HSLocationWatcherAPI, CLLocationManagerDelegate {
    @objc var typeName = "HSLocationWatcher"
    @objc let identifier = UUID().uuidString
    private let manager = CLLocationManager()
    private var callback: JSCallback?
    private var _lastLocation: CLLocation?

    @objc var distanceFilter: Double {
        get { manager.distanceFilter }
        set { manager.distanceFilter = newValue }
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    isolated deinit {
        destroy()
    }

    func destroy() {
        _ = stop()
        callback?.detach(from: self)
        callback = nil
        manager.delegate = nil
    }

    @objc @discardableResult func start() -> HSLocationWatcher {
        manager.startUpdatingLocation()
        AKTrace("HSLocationWatcher(\(identifier)).start(): Started")
        return self
    }

    @objc @discardableResult func stop() -> HSLocationWatcher {
        manager.stopUpdatingLocation()
        AKTrace("HSLocationWatcher(\(identifier)).stop(): Stopped")
        return self
    }

    @objc func setCallback(_ fn: JSValue) -> HSLocationWatcher {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    @objc func location() -> [AnyHashable: Any]? {
        _lastLocation.map { HSLocationModule.locationTable(from: $0) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastLoc = locations.last
        MainActor.assumeIsolated {
            if let loc = lastLoc {
                _lastLocation = loc
                _ = callback?.value?.call(withArguments: ["location", HSLocationModule.locationTable(from: loc)])
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            _ = callback?.value?.call(withArguments: ["error", message])
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        MainActor.assumeIsolated {
            let status: String
            switch auth {
            case .authorized, .authorizedAlways: status = "authorized"
            case .denied:                        status = "denied"
            case .restricted:                    status = "restricted"
            default:                             status = "notDetermined"
            }
            _ = callback?.value?.call(withArguments: ["authorizationChanged", status])
        }
    }
}
