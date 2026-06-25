//
//  HSSpotlightGroup.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// A grouped set of Spotlight results that share a common metadata attribute value.
///
/// Groups are returned by `HSSpotlightQuery.groups()` when grouping attributes have been
/// configured with `setGroupingAttributes()`. Do not instantiate `HSSpotlightGroup` directly.
///
/// When multiple grouping attributes are specified, groups nest: each group has `subgroups()`
/// containing the next level of grouping.
@objc protocol HSSpotlightGroupAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this group object (UUID string).
    @objc var identifier: String { get }

    /// The metadata attribute name by which results in this group are clustered.
    /// - Example:
    /// ```js
    /// q.groups().forEach(g => console.log('Grouped by: ' + g.attribute))
    /// ```
    @objc var attribute: String { get }

    /// The shared value of the grouping attribute for all results in this group.
    ///
    /// Returns `null` only in the unlikely case that the underlying value cannot be bridged.
    /// - Returns: The attribute value (string, number, Date, etc.) or null
    /// - Example:
    /// ```js
    /// q.groups().forEach(g => console.log(g.attribute + ' = ' + g.value()))
    /// ```
    @objc func value() -> Any?

    /// The number of results contained in this group.
    /// - Example:
    /// ```js
    /// const total = q.groups().reduce((sum, g) => sum + g.count, 0)
    /// console.log('Total results across all groups: ' + total)
    /// ```
    @objc var count: Int { get }

    /// Returns the items contained in this group as an array of `HSSpotlightItem` objects.
    /// - Returns: An array of `HSSpotlightItem` objects
    /// - Example:
    /// ```js
    /// q.groups().forEach(group => {
    ///     console.log(group.value() + ': ' + group.count + ' items')
    ///     group.results().forEach(item =>
    ///         console.log('  ' + item.valueForAttribute('kMDItemPath'))
    ///     )
    /// })
    /// ```
    @objc func results() -> [HSSpotlightItem]

    /// Returns nested subgroups when multiple grouping attributes were specified.
    ///
    /// Returns an empty array if no subgroups exist for this group.
    /// - Returns: An array of `HSSpotlightGroup` objects
    /// - Example:
    /// ```js
    /// // Two-level grouping: contentType → kind
    /// q.groups().forEach(type => {
    ///     type.subgroups().forEach(kind =>
    ///         console.log(type.value() + '/' + kind.value() + ': ' + kind.count)
    ///     )
    /// })
    /// ```
    @objc func subgroups() -> [HSSpotlightGroup]
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpotlightGroup: NSObject, HSSpotlightGroupAPI {
    @objc var typeName = "HSSpotlightGroup"
    @objc let identifier = UUID().uuidString

    private let group: NSMetadataQueryResultGroup

    init(group: NSMetadataQueryResultGroup) {
        self.group = group
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSSpotlightGroup(\(identifier))")
    }

    @objc var attribute: String { group.attribute }

    @objc func value() -> Any? {
        HSSpotlightItem.bridge(group.value)
    }

    @objc var count: Int { group.resultCount }

    @objc func results() -> [HSSpotlightItem] {
        (0..<group.resultCount).compactMap { index in
            (group.result(at: index) as? NSMetadataItem).map { HSSpotlightItem(item: $0) }
        }
    }

    @objc func subgroups() -> [HSSpotlightGroup] {
        (group.subgroups ?? []).map { HSSpotlightGroup(group: $0) }
    }
}
