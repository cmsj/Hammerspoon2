//
//  HSSpotlightItem.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// An individual result returned by a Spotlight query.
///
/// Instances are returned by `HSSpotlightQuery.results()` and related methods.
/// Do not instantiate `HSSpotlightItem` directly.
///
/// Metadata values are read via `valueForAttribute()` using standard `kMDItem*` keys.
/// Call `attributes()` to discover which keys are populated on a particular item.
/// Common attribute key shortcuts live in `hs.spotlight.attribute`.
@objc protocol HSSpotlightItemAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this result object (UUID string).
    @objc var identifier: String { get }

    /// Returns the list of metadata attribute names present on this item.
    ///
    /// The list is typically not exhaustive — some attributes (such as `kMDItemPath`)
    /// may be readable via `valueForAttribute()` even when absent from this list.
    /// - Returns: An array of attribute name strings
    /// - Example:
    /// ```js
    /// const item = q.results()[0]
    /// console.log('Attributes: ' + item.attributes().join(', '))
    /// ```
    @objc func attributes() -> [String]

    /// Returns the value for a specific metadata attribute, or `null` if absent.
    ///
    /// The return type depends on the attribute: common types include strings, numbers,
    /// dates, and arrays of strings. `NSURL`-typed values are automatically converted
    /// to their string representation.
    /// - Parameter key: An attribute key such as `"kMDItemPath"` or `hs.spotlight.attribute.path`
    /// - Returns: The attribute value, or null
    /// - Example:
    /// ```js
    /// const path = item.valueForAttribute(hs.spotlight.attribute.path)
    /// const name = item.valueForAttribute('kMDItemDisplayName')
    /// console.log(name + ' at ' + path)
    /// ```
    @objc func valueForAttribute(_ key: String) -> Any?
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpotlightItem: NSObject, HSSpotlightItemAPI {
    @objc var typeName = "HSSpotlightItem"
    @objc let identifier = UUID().uuidString

    private let item: NSMetadataItem

    init(item: NSMetadataItem) {
        self.item = item
        super.init()
    }

    isolated deinit {
//        AKTrace("deinit of HSSpotlightItem(\(identifier))")
    }

    @objc func attributes() -> [String] {
        item.attributes
    }

    @objc func valueForAttribute(_ key: String) -> Any? {
        guard let raw = item.value(forAttribute: key) else { return nil }
        return Self.bridge(raw)
    }

    // MARK: - Internal bridging helper

    /// Converts arbitrary metadata values into types that JavaScriptCore can bridge.
    /// URLs become their absolute-string form; everything else passes through as NSObject.
    static func bridge(_ value: Any) -> Any? {
        switch value {
        case let url as URL:
            return url.absoluteString as NSString
        case let url as NSURL:
            return (url.absoluteString ?? "") as NSString
        case let arr as [Any]:
            return arr.map { bridge($0) ?? NSNull() } as NSArray
        case let obj as NSObject:
            return obj
        default:
            return nil
        }
    }
}
