//
//  HSLocationGeocoder.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//

import Foundation
import JavaScriptCore
import CoreLocation
import MapKit

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
/// | `fullAddress` | string | Full formatted address (e.g. "1 Apple Park Way, Cupertino, CA 95014, United States") |
/// | `shortAddress` | string | Abbreviated address (e.g. "Cupertino, CA") |
/// | `locality` | string | City |
/// | `country` | string | Country name |
/// | `countryCode` | string | ISO country code |
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

    static func placemarkTable(from item: MKMapItem) -> [String: Any] {
        var d: [String: Any] = [:]
        if let name = item.name                    { d["name"]         = name }
        if let addr = item.address {
            d["fullAddress"] = addr.fullAddress
            if let short = addr.shortAddress       { d["shortAddress"] = short }
        }
        if let reps = item.addressRepresentations {
            if let city    = reps.cityName         { d["locality"]     = city }
            if let country = reps.regionName       { d["country"]      = country }
            if let region  = reps.region           { d["countryCode"]  = region.identifier }
        }
        d["location"] = HSLocationModule.locationTable(from: item.location)
        return d
    }

    @objc func lookupAddress(_ address: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                guard let request = MKGeocodingRequest(addressString: address) else {
                    holder.rejectWithMessage("Failed to create geocoding request")
                    return
                }
                do {
                    let mapItems = try await request.mapItems
                    let tables = mapItems.map { HSLocationGeocoder.placemarkTable(from: $0) }
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
            Task { @MainActor in
                guard let request = MKReverseGeocodingRequest(location: loc) else {
                    holder.rejectWithMessage("Failed to create reverse geocoding request")
                    return
                }
                do {
                    let mapItems = try await request.mapItems
                    let tables = mapItems.map { HSLocationGeocoder.placemarkTable(from: $0) }
                    holder.resolveWith(tables)
                } catch {
                    holder.rejectWithMessage(error.localizedDescription)
                }
            }
        }
    }
}
