//
//  HSLocationModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//

import Foundation
import JavaScriptCore
import CoreLocation

// MARK: - Module API protocol

/// Determine the Mac's location via macOS Location Services.
///
/// Location data is obtained through WiFi network scanning and, where available, GPS
/// hardware. User permission is required — call `hs.permissions.requestLocation()`
/// before using any tracking features.
///
/// The module exposes a `geocoder` sub-object for forward/reverse geocoding without
/// requiring Location Services.
///
/// ## locationTable
///
/// A `locationTable` is a plain JS object with the following keys:
///
/// | Key | Type | Description |
/// |-----|------|-------------|
/// | `latitude` | number | Degrees north (positive) or south (negative) |
/// | `longitude` | number | Degrees east (positive) or west (negative) |
/// | `altitude` | number | Metres above sea level (`0` if unknown) |
/// | `horizontalAccuracy` | number | Uncertainty radius in metres (`-1` if invalid) |
/// | `verticalAccuracy` | number | Altitude accuracy in metres (`-1` if invalid) |
/// | `course` | number | Direction of travel in degrees (`-1` if invalid) |
/// | `speed` | number | Metres per second (`-1` if invalid) |
/// | `timestamp` | number | Seconds since the Unix epoch |
@objc protocol HSLocationModuleAPI: JSExport {

    /// Returns true if Location Services are enabled system-wide.
    /// - Returns: true if enabled, false otherwise
    /// - Example:
    /// ```js
    /// hs.location.servicesEnabled() // → true or false
    /// ```
    @objc func servicesEnabled() -> Bool

    /// Returns the app's current Location Services authorization status as a string.
    /// - Returns: `"authorized"`, `"denied"`, `"restricted"`, or `"notDetermined"`
    /// - Example:
    /// ```js
    /// const status = hs.location.authorizationStatus()
    /// if (status === 'notDetermined') hs.permissions.requestLocation()
    /// ```
    @objc func authorizationStatus() -> String

    /// Returns the most recently cached location as a locationTable, or null.
    ///
    /// Activates Location Services if not already running. The cache is updated
    /// periodically while any watcher is running.
    /// - Returns: a locationTable, or null if no cached location is available
    /// - Example:
    /// ```js
    /// const loc = hs.location.get()
    /// if (loc) console.log(loc.latitude, loc.longitude)
    /// ```
    @objc func get() -> [AnyHashable: Any]?

    /// Calculates the straight-line distance in metres between two locationTables.
    ///
    /// Does not require Location Services.
    /// - Parameters:
    ///   - from: locationTable with at least `latitude` and `longitude`
    ///   - to: locationTable with at least `latitude` and `longitude`
    /// - Returns: distance in metres, or `-1` if either table is invalid
    /// - Example:
    /// ```js
    /// const d = hs.location.distance(
    ///     { latitude: 51.5074, longitude: -0.1278 },
    ///     { latitude: 48.8566, longitude:  2.3522 }
    /// ) // → ~341,000 metres
    /// ```
    @objc(distance::) func distance(_ from: JSValue, _ to: JSValue) -> Double

    /// Returns the time of sunrise for the given coordinates and date as seconds
    /// since the Unix epoch, or null if the sun does not rise on that date (polar
    /// night). Pass a JS `Date` for `date`, or omit/pass null to use today.
    /// - Parameters:
    ///   - latitude: degrees north (positive) or south (negative)
    ///   - longitude: degrees east (positive) or west (negative)
    ///   - date: optional JS `Date`; defaults to today
    /// - Returns: seconds since epoch of sunrise, or null
    /// - Example:
    /// ```js
    /// const rise = hs.location.sunrise(51.5, -0.1)
    /// console.log(new Date(rise * 1000).toTimeString())
    /// ```
    @objc(sunrise:::) func sunrise(_ latitude: Double, _ longitude: Double, _ date: JSValue) -> NSNumber?

    /// Returns the time of sunset for the given coordinates and date as seconds
    /// since the Unix epoch, or null if the sun does not set on that date (midnight
    /// sun). Pass a JS `Date` for `date`, or omit/pass null to use today.
    /// - Parameters:
    ///   - latitude: degrees north (positive) or south (negative)
    ///   - longitude: degrees east (positive) or west (negative)
    ///   - date: optional JS `Date`; defaults to today
    /// - Returns: seconds since epoch of sunset, or null
    /// - Example:
    /// ```js
    /// const set = hs.location.sunset(51.5, -0.1)
    /// console.log(new Date(set * 1000).toTimeString())
    /// ```
    @objc(sunset:::) func sunset(_ latitude: Double, _ longitude: Double, _ date: JSValue) -> NSNumber?

    /// Creates a new location watcher object. Call `.start()` on it to begin
    /// receiving updates. The watcher is automatically stopped when the module
    /// shuts down.
    /// - Returns: an HSLocationWatcher
    /// - Example:
    /// ```js
    /// const w = hs.location.addWatcher()
    /// w.setCallback((event, data) => console.log(event, data))
    /// w.start()
    /// ```
    @objc func addWatcher() -> HSLocationWatcher

    /// Removes a previously created watcher and stops it if running.
    /// - Parameter watcher: the watcher returned by `addWatcher()`
    /// - Example:
    /// ```js
    /// const w = hs.location.addWatcher()
    /// w.start()
    /// hs.location.removeWatcher(w)
    /// ```
    @objc func removeWatcher(_ watcher: HSLocationWatcher)

    /// The geocoder subobject for forward and reverse geocoding.
    /// - Example:
    /// ```js
    /// hs.location.geocoder.lookupAddress("1 Infinite Loop, Cupertino").then(places => {
    ///     console.log(places[0].locality)
    /// })
    /// ```
    @objc var geocoder: HSLocationGeocoder { get }
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSLocationModule: NSObject, HSModuleAPI, HSLocationModuleAPI, CLLocationManagerDelegate {
    var name = "hs.location"
    let engineID: UUID
    private let _geocoder = HSLocationGeocoder()
    private var locationManager: CLLocationManager
    private var _lastLocation: CLLocation?
    // Weak refs: watchers stay active while CLLocationManager is alive inside them;
    // weak refs allow dropped watchers to be GC'd without an explicit removeWatcher() call.
    private var watchers = HSWeakObjectSet<HSLocationWatcher>()

    @objc var geocoder: HSLocationGeocoder { _geocoder }

    required init(engineID: UUID) {
        self.engineID = engineID
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for watcher in watchers.allObjects { watcher.stop() }
        watchers.removeAllObjects()
        locationManager.stopUpdatingLocation()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
        shutdown()
    }

    // MARK: CLLocationManagerDelegate (for get())

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated {
            if let loc = last { _lastLocation = loc }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore errors from the one-shot get() request
    }

    // MARK: - HSLocationModuleAPI

    func servicesEnabled() -> Bool {
        CLLocationManager.locationServicesEnabled()
    }

    func authorizationStatus() -> String {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: return "authorized"
        case .denied:                        return "denied"
        case .restricted:                    return "restricted"
        default:                             return "notDetermined"
        }
    }

    func get() -> [AnyHashable: Any]? {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestLocation()  // one-shot; result arrives in delegate
        }
        guard let loc = _lastLocation ?? locationManager.location else { return nil }
        return HSLocationModule.locationTable(from: loc)
    }

    @objc(distance::) func distance(_ from: JSValue, _ to: JSValue) -> Double {
        guard let fromLoc = Self.clLocation(from: from),
              let toLoc   = Self.clLocation(from: to) else { return -1 }
        return fromLoc.distance(from: toLoc)
    }

    @objc(sunrise:::) func sunrise(_ latitude: Double, _ longitude: Double, _ date: JSValue) -> NSNumber? {
        let d = Self.date(from: date)
        return Self.sunTime(latitude: latitude, longitude: longitude, date: d, isSunrise: true).map { NSNumber(value: $0.timeIntervalSince1970) }
    }

    @objc(sunset:::) func sunset(_ latitude: Double, _ longitude: Double, _ date: JSValue) -> NSNumber? {
        let d = Self.date(from: date)
        return Self.sunTime(latitude: latitude, longitude: longitude, date: d, isSunrise: false).map { NSNumber(value: $0.timeIntervalSince1970) }
    }

    func addWatcher() -> HSLocationWatcher {
        let w = HSLocationWatcher()
        watchers.add(w)
        return w
    }

    func removeWatcher(_ watcher: HSLocationWatcher) {
        watcher.stop()
        watchers.remove(watcher)
    }

    // MARK: - Helpers

    static func locationTable(from loc: CLLocation) -> [AnyHashable: Any] {
        [
            "latitude":           loc.coordinate.latitude,
            "longitude":          loc.coordinate.longitude,
            "altitude":           loc.altitude,
            "horizontalAccuracy": loc.horizontalAccuracy,
            "verticalAccuracy":   loc.verticalAccuracy,
            "course":             loc.course,
            "speed":              loc.speed,
            "timestamp":          loc.timestamp.timeIntervalSince1970
        ]
    }

    static func clLocation(from val: JSValue) -> CLLocation? {
        guard val.isObject,
              let dict = val.toDictionary(),
              let lat  = dict["latitude"]  as? Double,
              let lon  = dict["longitude"] as? Double else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    private static func date(from val: JSValue) -> Date {
        if !val.isUndefined, !val.isNull,
           let ns = val.toObject() as? NSDate {
            return ns as Date
        }
        return Date()
    }

    // USNO algorithm for sunrise/sunset
    private static func sunTime(latitude: Double, longitude: Double,
                                 date: Date, isSunrise: Bool) -> Date? {
        let toRad = Double.pi / 180.0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }

        let a   = (14 - month) / 12
        let y   = year + 4800 - a
        let m   = month + 12 * a - 3
        let jdn = Double(day + (153*m + 2)/5 + 365*y + y/4 - y/100 + y/400 - 32045)

        let n       = jdn - 2451545.0
        let jStar   = n - longitude / 360.0
        let Msun    = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360.0)
        let Mrad    = Msun * toRad
        let C       = 1.9148*sin(Mrad) + 0.0200*sin(2*Mrad) + 0.0003*sin(3*Mrad)
        let lambda  = (Msun + C + 180 + 102.9372).truncatingRemainder(dividingBy: 360.0)
        let lambdaR = lambda * toRad
        let jTransit = 2451545.0 + jStar + 0.0053*sin(Mrad) - 0.0069*sin(2*lambdaR)
        let sinD    = sin(lambdaR) * sin(23.4397 * toRad)
        let cosD    = cos(asin(sinD))
        let latRad  = latitude * toRad
        let cosW    = (sin(-0.8333 * toRad) - sin(latRad) * sinD) / (cos(latRad) * cosD)
        guard cosW >= -1 && cosW <= 1 else { return nil }
        let omega   = acos(cosW) * 180.0 / .pi
        let jEvent  = jTransit + (isSunrise ? -omega : omega) / 360.0
        let unix    = (jEvent - 2440587.5) * 86400.0
        return Date(timeIntervalSince1970: unix)
    }
}
