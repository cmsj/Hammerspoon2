//
//  HSLocationGeocoder.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//

import Foundation
import JavaScriptCore
import CoreLocation

// MARK: - Geocoder API protocol

/// Converts between coordinates and human-readable addresses.
///
/// Does not require Location Services but does require network access. Results may
/// be rate-limited by the system.
///
/// ## placemarkTable
///
/// A `placemarkTable` has these keys (any of which may be absent if not relevant):
///
/// | Key | Type | Description |
/// |-----|------|-------------|
/// | `name` | string | Place name |
/// | `locality` | string | City |
/// | `subLocality` | string | Neighbourhood |
/// | `thoroughfare` | string | Street name |
/// | `subThoroughfare` | string | Street number |
/// | `administrativeArea` | string | State / province |
/// | `subAdministrativeArea` | string | County |
/// | `country` | string | Country name |
/// | `countryCode` | string | ISO country code |
/// | `postalCode` | string | Postal / ZIP code |
/// | `ocean` | string | Ocean name |
/// | `inlandWater` | string | Inland water body name |
/// | `location` | locationTable | The locationTable for this placemark |
@objc protocol HSLocationGeocoderAPI: JSExport {
    /// Geocodes an address string into an array of placemarkTables.
    ///
    /// Returns a Promise that resolves with an array of placemarkTable objects
    /// (sorted by relevance) or rejects with an error message.
    /// - Parameter address: a free-form address string in any locale
    /// - Returns: {Promise<[[String:Any]]>} a Promise resolving to an array of placemarkTables
    /// - Example:
    /// ```js
    /// hs.location.geocoder.lookupAddress("Apple Park, Cupertino")
    ///     .then(p => console.log(p[0].locality, p[0].countryCode))
    /// ```
    @objc func lookupAddress(_ address: String) -> JSPromise?

    /// Reverse-geocodes a locationTable into an array of placemarkTables.
    ///
    /// Returns a Promise that resolves with matching placemarks or rejects with
    /// an error.
    /// - Parameter locationTable: an object with at least `latitude` and `longitude`
    /// - Returns: {Promise<[[String:Any]]>} a Promise resolving to an array of placemarkTables
    /// - Example:
    /// ```js
    /// hs.location.geocoder.lookupLocation({ latitude: 37.3349, longitude: -122.0090 })
    ///     .then(p => console.log(p[0].name))
    /// ```
    @objc func lookupLocation(_ locationTable: [String: Double]) -> JSPromise?
}

// MARK: - Geocoder implementation

@_documentation(visibility: private)
@MainActor
@objc class HSLocationGeocoder: NSObject, HSLocationGeocoderAPI {
    // CLGeocoder deprecated in macOS 26; no non-deprecated replacement exists yet.
    @available(macOS, deprecated: 26.0)
    private let geocoder = CLGeocoder()

    // Convert CLPlacemark to a plain JS-compatible dictionary
    static func placemarkTable(from pm: CLPlacemark) -> [String: Any] {
        var d: [String: Any] = [:]
        if let v = pm.name                  { d["name"]                  = v }
        if let v = pm.locality              { d["locality"]              = v }
        if let v = pm.subLocality           { d["subLocality"]           = v }
        if let v = pm.thoroughfare          { d["thoroughfare"]          = v }
        if let v = pm.subThoroughfare       { d["subThoroughfare"]       = v }
        if let v = pm.administrativeArea    { d["administrativeArea"]    = v }
        if let v = pm.subAdministrativeArea { d["subAdministrativeArea"] = v }
        if let v = pm.country               { d["country"]               = v }
        if let v = pm.isoCountryCode        { d["countryCode"]           = v }
        if let v = pm.postalCode            { d["postalCode"]            = v }
        if let v = pm.ocean                 { d["ocean"]                 = v }
        if let v = pm.inlandWater           { d["inlandWater"]           = v }
        if let loc = pm.location            { d["location"]              = HSLocationModule.locationTable(from: loc) }
        return d
    }

    @objc func lookupAddress(_ address: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor [self] in
                do {
                    let placemarks = try await self.geocoder.geocodeAddressString(address)
                    let tables = placemarks.map { HSLocationGeocoder.placemarkTable(from: $0) }
                    holder.resolveWith(tables)
                } catch {
                    holder.rejectWithMessage(error.localizedDescription)
                }
            }
        }
    }

    @objc func lookupLocation(_ locationTable: [String: Double]) -> JSPromise? {
        guard let loc = HSLocationModule.clLocation(from: locationTable) else {
            AKError("hs.location.geocoder.lookupLocation(): invalid locationTable — needs latitude and longitude")
            return nil
        }
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor [self] in
                do {
                    let placemarks = try await self.geocoder.reverseGeocodeLocation(loc)
                    let tables = placemarks.map { HSLocationGeocoder.placemarkTable(from: $0) }
                    holder.resolveWith(tables)
                } catch {
                    holder.rejectWithMessage(error.localizedDescription)
                }
            }
        }
    }
}
