//
//  HSSpotlightQuery.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// A configurable Spotlight search query that can be started, stopped, and queried for results.
///
/// Create instances via `hs.spotlight.create()` or the convenience helper `hs.spotlight.search()`.
/// Configure the query with chainable setter methods, register a callback, then call `start()`.
///
/// Results accumulate during the initial gathering phase (`"didStart"` → `"inProgress"` → `"didFinish"`)
/// and continue to update during the live-monitoring phase (`"didUpdate"`). Stop explicitly
/// with `stop()` when you no longer need live updates.
///
/// - Example:
/// ```js
/// const q = hs.spotlight.create()
/// q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
///  .setScopes([hs.spotlight.scope.computer])
///  .setCallback((event) => {
///      if (event === 'didFinish') {
///          console.log('Found ' + q.count + ' applications')
///          q.results().forEach(item =>
///              console.log(item.valueForAttribute(hs.spotlight.attribute.displayName))
///          )
///          q.stop()
///      }
///  })
///  .start()
/// ```
@objc protocol HSSpotlightQueryAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this query object (UUID string).
    @objc var identifier: String { get }

    /// The number of results gathered so far.
    /// - Example:
    /// ```js
    /// console.log('Results so far: ' + q.count)
    /// ```
    @objc var count: Int { get }

    /// Whether the query is currently running (gathering or monitoring for live updates).
    /// - Example:
    /// ```js
    /// if (!q.isRunning) q.start()
    /// ```
    @objc var isRunning: Bool { get }

    /// Whether the query is in the initial gathering phase.
    ///
    /// `true` from `"didStart"` until `"didFinish"`; `false` thereafter while live-monitoring.
    /// - Example:
    /// ```js
    /// if (q.isGathering) console.log('Still collecting initial results…')
    /// ```
    @objc var isGathering: Bool { get }

    /// Sets the NSPredicate query string for this search.
    ///
    /// The string must be a valid `NSPredicate` format expression using `kMDItem*` attribute
    /// keys and MDQuery operators (`==`, `!=`, `<`, `>`, `BEGINSWITH`, `CONTAINS`, etc.).
    ///
    /// If the query is already running when this is called, it is stopped and restarted
    /// automatically.
    /// - Parameter predicate: An NSPredicate-format query string
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// // Find PDFs larger than 1 MB
    /// q.setQuery("kMDItemContentType == 'com.adobe.pdf' AND kMDItemFSSize > 1048576")
    ///
    /// // Find items whose display name begins with "Report"
    /// q.setQuery("kMDItemDisplayName BEGINSWITH 'Report'")
    ///
    /// // Find images taken in 2024
    /// q.setQuery("kMDItemContentTypeTree == 'public.image' AND kMDItemContentCreationDate >= $time.iso('2024-01-01')")
    /// ```
    @objc @discardableResult func setQuery(_ predicate: String) -> HSSpotlightQuery

    /// Sets the search scopes that restrict where Spotlight looks.
    ///
    /// Pass an array of predefined scope strings from `hs.spotlight.scope`, absolute
    /// directory paths, or a mix of both. Paths beginning with `~` are expanded to the
    /// user's home directory.
    ///
    /// When not set, the query defaults to `hs.spotlight.scope.computer`.
    /// - Parameter scopes: An array of scope-constant strings or absolute directory paths
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// // Home directory only
    /// q.setScopes([hs.spotlight.scope.home])
    ///
    /// // Specific folder
    /// q.setScopes(['/Users/alice/Documents'])
    ///
    /// // Mix of predefined scope and a folder
    /// q.setScopes([hs.spotlight.scope.home, '/Volumes/ExternalDrive/Projects'])
    /// ```
    @objc @discardableResult func setScopes(_ scopes: JSValue) -> HSSpotlightQuery

    /// Sets sort descriptors that control the order of results.
    ///
    /// Pass an array of objects, each with:
    /// - `attribute` (string): a `kMDItem*` key to sort on
    /// - `ascending` (boolean): `true` for ascending order (optional, defaults to `true`)
    ///
    /// - Parameter descriptors: An array of sort descriptor objects
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// q.setSortDescriptors([
    ///     { attribute: hs.spotlight.attribute.fsName, ascending: true },
    ///     { attribute: hs.spotlight.attribute.fileSize, ascending: false }
    /// ])
    /// ```
    @objc @discardableResult func setSortDescriptors(_ descriptors: JSValue) -> HSSpotlightQuery

    /// Sets the attributes by which results will be grouped.
    ///
    /// When grouping attributes are set, use `groups()` to retrieve results organised into
    /// `HSSpotlightGroup` objects. Specifying multiple attributes creates nested subgroups
    /// accessible via `group.subgroups()`.
    /// - Parameter attrs: An array of attribute name strings
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// // Group image results by content type
    /// q.setQuery("kMDItemContentTypeTree == 'public.image'")
    ///  .setGroupingAttributes([hs.spotlight.attribute.contentType])
    ///  .setCallback((event) => {
    ///      if (event === 'didFinish') {
    ///          q.groups().forEach(g =>
    ///              console.log(g.value() + ': ' + g.count + ' images')
    ///          )
    ///      }
    ///  })
    ///  .start()
    /// ```
    @objc @discardableResult func setGroupingAttributes(_ attrs: JSValue) -> HSSpotlightQuery

    /// Sets the attributes for which aggregate value-list summaries are computed.
    ///
    /// After the query finishes, `valueLists()` returns aggregate data for each specified
    /// attribute: distinct values and the number of results carrying each value.
    /// - Parameter attrs: An array of attribute name strings
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// q.setValueListAttributes([hs.spotlight.attribute.kind])
    ///  .setCallback((event) => {
    ///      if (event === 'didFinish') {
    ///          q.valueLists().forEach(vl => {
    ///              console.log('=== ' + vl.attribute + ' ===')
    ///              vl.values.forEach(v =>
    ///                  console.log('  ' + v.value + ': ' + v.count + ' items')
    ///              )
    ///          })
    ///      }
    ///  })
    ///  .start()
    /// ```
    @objc @discardableResult func setValueListAttributes(_ attrs: JSValue) -> HSSpotlightQuery

    /// Registers a callback that receives query lifecycle events.
    ///
    /// The callback is called with:
    /// - `event` (string): one of `"didStart"`, `"inProgress"`, `"didFinish"`, `"didUpdate"`
    /// - `update` (object, `"didUpdate"` only): `{ added, changed, removed }` — each an array
    ///   of `HSSpotlightItem` objects describing what changed in this update cycle
    ///
    /// - Parameter fn: A JavaScript function `(event, update?) => void`
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// q.setCallback((event, update) => {
    ///     if (event === 'didFinish') {
    ///         console.log('Initial gather complete — ' + q.count + ' results')
    ///     } else if (event === 'didUpdate') {
    ///         const added = update ? update.added.length : 0
    ///         console.log(added + ' items added in this update')
    ///     }
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ fn: JSValue) -> HSSpotlightQuery

    /// Starts the query.
    ///
    /// The query must have a predicate set (via `setQuery()`) before calling `start()`.
    /// Calling `start()` on an already-running query is a no-op.
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// q.setQuery("kMDItemKind == 'Application'").setCallback(handler).start()
    /// ```
    @objc @discardableResult func start() -> HSSpotlightQuery

    /// Stops the query while preserving accumulated results.
    ///
    /// After stopping, `results()`, `count`, `groups()`, and `valueLists()` continue to
    /// return the last gathered data. Call `start()` again to resume.
    /// - Returns: this query, for chaining
    /// - Example:
    /// ```js
    /// q.stop()
    /// console.log('Final result count: ' + q.count)
    /// ```
    @objc @discardableResult func stop() -> HSSpotlightQuery

    /// Returns the current results as an array of `HSSpotlightItem` objects.
    ///
    /// The result set is briefly frozen during access to ensure consistency. Safe to call
    /// from within a query callback.
    /// - Returns: An array of `HSSpotlightItem` objects (may be empty if the query has not run)
    /// - Example:
    /// ```js
    /// const items = q.results()
    /// items.forEach(item =>
    ///     console.log(item.valueForAttribute(hs.spotlight.attribute.path))
    /// )
    /// ```
    @objc func results() -> [HSSpotlightItem]

    /// Returns grouped results when grouping attributes have been configured.
    ///
    /// Returns an empty array if `setGroupingAttributes()` was not called.
    /// - Returns: An array of `HSSpotlightGroup` objects
    /// - Example:
    /// ```js
    /// q.groups().forEach(group =>
    ///     console.log(group.attribute + ' = ' + group.value() + ' (' + group.count + ' items)')
    /// )
    /// ```
    @objc func groups() -> [HSSpotlightGroup]

    /// Returns aggregate value-list summaries for attributes set via `setValueListAttributes()`.
    ///
    /// Each entry is a plain object with:
    /// - `attribute` (string): the attribute name
    /// - `values` (array): objects with `value` and `count` keys for each distinct value
    ///
    /// Returns an empty array if `setValueListAttributes()` was not called.
    /// - Returns: An array of summary objects
    /// - Example:
    /// ```js
    /// q.valueLists().forEach(vl =>
    ///     vl.values.forEach(v =>
    ///         console.log(vl.attribute + ': ' + v.value + ' (' + v.count + ')')
    ///     )
    /// )
    /// ```
    @objc func valueLists() -> [[String: Any]]

}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSpotlightQuery: NSObject, HSSpotlightQueryAPI {
    @objc var typeName = "HSSpotlightQuery"
    @objc let identifier = UUID().uuidString

    private let query = NSMetadataQuery()
    private var callback: JSCallback?

    override init() {
        super.init()
        setupNotifications()
        AKTrace("Init of HSSpotlightQuery(\(identifier))")
    }

    isolated deinit {
        destroy()
        AKTrace("deinit of HSSpotlightQuery(\(identifier))")
    }

    // MARK: - Notification setup
    // Selector-based observers are used (not block-based) so that NSNotificationCenter's
    // ObjC dispatch bypasses Swift's strict-Sendable checks on notification.userInfo.
    // NSMetadataQuery guarantees delivery on the thread the query was started on (main thread).

    private func setupNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidStartGathering),
                           name: .NSMetadataQueryDidStartGathering, object: query)
        center.addObserver(self, selector: #selector(handleGatheringProgress),
                           name: .NSMetadataQueryGatheringProgress, object: query)
        center.addObserver(self, selector: #selector(handleDidFinishGathering),
                           name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(handleDidUpdate(_:)),
                           name: .NSMetadataQueryDidUpdate, object: query)
    }

    private func tearDownNotifications() {
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidStartGathering,  object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryGatheringProgress,  object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate,          object: query)
    }

    @objc private func handleDidStartGathering()   { fireSimpleCallback("didStart") }
    @objc private func handleGatheringProgress()   { fireSimpleCallback("inProgress") }
    @objc private func handleDidFinishGathering()  { fireSimpleCallback("didFinish") }

    private func fireSimpleCallback(_ event: String) {
        guard let cb = callback else { return }
        _ = cb.call(withArguments: [event])
    }

    @objc private func handleDidUpdate(_ notification: Notification) {
        guard let cb = callback else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let info    = notification.userInfo
        let added   = (info?[NSMetadataQueryUpdateAddedItemsKey]   as? [NSMetadataItem] ?? []).map { HSSpotlightItem(item: $0) }
        let changed = (info?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []).map { HSSpotlightItem(item: $0) }
        let removed = (info?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] ?? []).map { HSSpotlightItem(item: $0) }
        let update: [String: Any] = ["added": added, "changed": changed, "removed": removed]
        _ = cb.call(withArguments: ["didUpdate", update])
    }

    // MARK: - HSSpotlightQueryAPI

    @objc var count: Int       { query.resultCount }
    @objc var isRunning: Bool  { query.isStarted && !query.isStopped }
    @objc var isGathering: Bool { query.isGathering }

    @objc @discardableResult func setQuery(_ predicate: String) -> HSSpotlightQuery {
        guard !predicate.isEmpty else {
            AKError("hs.spotlight.setQuery(): predicate must not be empty")
            return self
        }
        let wasRunning = isRunning
        if wasRunning { query.stop() }
        guard let pred = NSPredicate(fromMetadataQueryString: predicate) else {
            AKError("hs.spotlight.setQuery(): invalid predicate syntax — \(predicate)")
            if wasRunning { _ = start() }
            return self
        }
        query.predicate = pred
        if wasRunning { _ = start() }
        return self
    }

    @objc @discardableResult func setScopes(_ scopes: JSValue) -> HSSpotlightQuery {
        guard scopes.isArray, let arr = scopes.toArray() as? [String] else {
            AKWarning("hs.spotlight.setScopes(): expected an array of strings")
            return self
        }
        query.searchScopes = arr.map { scope -> Any in
            if scope.hasPrefix("/") || scope.hasPrefix("~") {
                return URL(fileURLWithPath: (scope as NSString).expandingTildeInPath)
            }
            return scope
        }
        return self
    }

    @objc @discardableResult func setSortDescriptors(_ descriptors: JSValue) -> HSSpotlightQuery {
        guard descriptors.isArray, let arr = descriptors.toArray() else {
            AKWarning("hs.spotlight.setSortDescriptors(): expected an array")
            return self
        }
        query.sortDescriptors = arr.compactMap { item -> NSSortDescriptor? in
            guard let dict = item as? [String: Any],
                  let attr = dict["attribute"] as? String else { return nil }
            let ascending = dict["ascending"] as? Bool ?? true
            return NSSortDescriptor(key: attr, ascending: ascending)
        }
        return self
    }

    @objc @discardableResult func setGroupingAttributes(_ attrs: JSValue) -> HSSpotlightQuery {
        guard attrs.isArray, let arr = attrs.toArray() as? [String] else {
            AKWarning("hs.spotlight.setGroupingAttributes(): expected an array of strings")
            return self
        }
        query.groupingAttributes = arr
        return self
    }

    @objc @discardableResult func setValueListAttributes(_ attrs: JSValue) -> HSSpotlightQuery {
        guard attrs.isArray, let arr = attrs.toArray() as? [String] else {
            AKWarning("hs.spotlight.setValueListAttributes(): expected an array of strings")
            return self
        }
        query.valueListAttributes = arr
        return self
    }

    @objc @discardableResult func setCallback(_ fn: JSValue) -> HSSpotlightQuery {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    @objc @discardableResult func start() -> HSSpotlightQuery {
        guard query.predicate != nil else {
            AKError("hs.spotlight.start(): no predicate set — call setQuery() first")
            return self
        }
        guard !isRunning else { return self }
        if !query.start() {
            AKError("hs.spotlight.start(): NSMetadataQuery.start() returned false — check the predicate syntax")
        }
        return self
    }

    @objc @discardableResult func stop() -> HSSpotlightQuery {
        query.stop()
        return self
    }

    @objc func results() -> [HSSpotlightItem] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        return (0..<query.resultCount).compactMap { index in
            (query.result(at: index) as? NSMetadataItem).map { HSSpotlightItem(item: $0) }
        }
    }

    @objc func groups() -> [HSSpotlightGroup] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        return query.groupedResults.map { HSSpotlightGroup(group: $0) }
    }

    @objc func valueLists() -> [[String: Any]] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        return query.valueLists.map { attribute, tuples in
            let values: [[String: Any]] = tuples.compactMap { tuple in
                guard let v = tuple.value else { return nil }
                return ["value": HSSpotlightItem.bridge(v) ?? NSNull(), "count": tuple.count]
            }
            return ["attribute": attribute, "values": values]
        }
    }

    func destroy() {
        _ = stop()
        tearDownNotifications()
        callback?.detach(from: self)
        callback = nil
    }
}
