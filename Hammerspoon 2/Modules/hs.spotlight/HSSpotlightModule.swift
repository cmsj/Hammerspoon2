//
//  HSSpotlightModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Module API protocol

/// Query the macOS Spotlight metadata database.
///
/// `hs.spotlight` wraps `NSMetadataQuery` to let you search for files and other
/// metadata objects indexed by Spotlight. Queries use `NSPredicate` syntax with
/// `kMDItem*` attribute keys (see `hs.spotlight.attribute` for common shortcuts).
///
/// ## Quick start
///
/// ```js
/// // Find all PDFs in the home directory and log their paths
/// const q = hs.spotlight.create()
/// q.setQuery("kMDItemContentType == 'com.adobe.pdf'")
///  .setScopes([hs.spotlight.scope.home])
///  .setCallback((event) => {
///      if (event === 'didFinish') {
///          console.log('Found ' + q.count + ' PDFs')
///          q.results().forEach(item =>
///              console.log(item.valueForAttribute(hs.spotlight.attribute.path))
///          )
///          q.stop()
///      }
///  })
///  .start()
/// ```
///
/// ## One-shot search convenience
///
/// ```js
/// const q = hs.spotlight.search(
///     "kMDItemDisplayName BEGINSWITH 'Invoice'",
///     (event) => {
///         if (event === 'didFinish') {
///             console.log('Found ' + q.count + ' invoices')
///             q.stop()
///         }
///     }
/// )
/// ```
///
/// ## Grouping results by attribute
///
/// ```js
/// const q = hs.spotlight.create()
/// q.setQuery("kMDItemContentTypeTree == 'public.image'")
///  .setScopes([hs.spotlight.scope.home])
///  .setGroupingAttributes([hs.spotlight.attribute.kind])
///  .setCallback((event) => {
///      if (event === 'didFinish') {
///          q.groups().forEach(g =>
///              console.log(g.value() + ': ' + g.count + ' images')
///          )
///          q.stop()
///      }
///  })
///  .start()
/// ```
///
/// ## Monitoring for live changes
///
/// ```js
/// // Keep the query running to receive live-update events
/// const q = hs.spotlight.create()
/// q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
///  .setScopes(['/Applications'])
///  .setCallback((event, update) => {
///      if (event === 'didFinish') {
///          console.log('Initial scan: ' + q.count + ' apps')
///      } else if (event === 'didUpdate') {
///          console.log('App list changed — now ' + q.count + ' apps')
///          if (update) console.log('Added: ' + update.added.length)
///      }
///  })
///  .start()
/// // Call q.stop() when you no longer want live updates
/// ```
@objc protocol HSSpotlightModuleAPI: JSExport {

    // MARK: Factory

    /// Creates and returns a new, unconfigured Spotlight query.
    ///
    /// Configure it with `setQuery()`, `setScopes()`, and `setCallback()`, then call `start()`.
    /// The query is automatically stopped and released when the module shuts down.
    /// - Returns: A new `HSSpotlightQuery`
    /// - Example:
    /// ```js
    /// const q = hs.spotlight.create()
    /// q.setQuery("kMDItemKind == 'PDF Document'")
    ///  .setCallback((event) => { if (event === 'didFinish') q.stop() })
    ///  .start()
    /// ```
    @objc func create() -> HSSpotlightQuery

    /// Convenience helper that creates, configures, and starts a query in one call.
    ///
    /// Equivalent to `create().setQuery(predicate).setCallback(callback).start()`.
    /// Call `q.stop()` from inside `callback` (when `event === 'didFinish'`) to end
    /// the search once you have what you need.
    /// - Parameters:
    ///   - predicate: An NSPredicate-format query string
    ///   - callback: A function called with `(event, update?)` lifecycle events
    /// - Returns: The `HSSpotlightQuery` object (use to stop the search early)
    /// - Example:
    /// ```js
    /// const q = hs.spotlight.search(
    ///     "kMDItemDisplayName BEGINSWITH 'Report'",
    ///     (event) => {
    ///         if (event === 'didFinish') {
    ///             console.log('Found ' + q.count + ' reports')
    ///             q.stop()
    ///         }
    ///     }
    /// )
    /// ```
    @objc func search(_ predicate: String, _ callback: JSFunction) -> HSSpotlightQuery

    // MARK: Constants

    /// Predefined search scope constants for use with `HSSpotlightQuery.setScopes()`.
    ///
    /// | Key | Description |
    /// |-----|-------------|
    /// | `home` | The current user's home directory |
    /// | `computer` | All locally mounted volumes |
    /// | `network` | Network-mounted volumes |
    /// | `applications` | Common locations for .app bundles |
    /// | `icloud` | iCloud Documents |
    /// | `icloudData` | iCloud Data (non-document ubiquitous files) |
    ///
    /// - Example:
    /// ```js
    /// q.setScopes(hs.spotlight.scope.home)
    /// q.setScopes(hs.spotlight.scope.computer)
    /// q.setScopes(hs.spotlight.scope.home + ['/Volumes/ExternalDrive'])
    /// ```
    @objc var scope: [String: [String]] { get }

    /// Common Spotlight metadata attribute key shortcuts.
    ///
    /// These are plain `kMDItem*` string values — using them is equivalent to typing
    /// the raw key name, but they provide autocomplete and avoid typos.
    ///
    /// | Key | Attribute | Description |
    /// |-----|-----------|-------------|
    /// | `path` | `kMDItemPath` | Absolute filesystem path |
    /// | `displayName` | `kMDItemDisplayName` | User-visible display name |
    /// | `fsName` | `kMDItemFSName` | Filename on disk |
    /// | `contentType` | `kMDItemContentType` | UTI content type |
    /// | `contentTypeTree` | `kMDItemContentTypeTree` | Full UTI conformance tree |
    /// | `kind` | `kMDItemKind` | Finder "Kind" string |
    /// | `fileSize` | `kMDItemFSSize` | File size in bytes |
    /// | `creationDate` | `kMDItemFSCreationDate` | Filesystem creation date |
    /// | `modifiedDate` | `kMDItemFSContentChangeDate` | Last content modification date |
    /// | `lastUsedDate` | `kMDItemLastUsedDate` | Last time the item was opened |
    /// | `useCount` | `kMDItemUseCount` | Number of times opened |
    /// | `authors` | `kMDItemAuthors` | Document authors |
    /// | `title` | `kMDItemTitle` | Document title |
    /// | `comment` | `kMDItemComment` | User comment |
    /// | `keywords` | `kMDItemKeywords` | Tags/keywords |
    /// | `durationSeconds` | `kMDItemDurationSeconds` | Media duration in seconds |
    /// | `pixelWidth` | `kMDItemPixelWidth` | Image/video width in pixels |
    /// | `pixelHeight` | `kMDItemPixelHeight` | Image/video height in pixels |
    /// | `whereFroms` | `kMDItemWhereFroms` | Download source URLs |
    /// | `bundleIdentifier` | `kMDItemCFBundleIdentifier` | App bundle identifier |
    ///
    /// - Example:
    /// ```js
    /// const name = item.valueForAttribute(hs.spotlight.attribute.displayName)
    /// const size = item.valueForAttribute(hs.spotlight.attribute.fileSize)
    /// q.setSortDescriptors([{ attribute: hs.spotlight.attribute.modifiedDate, ascending: false }])
    /// ```
    @objc var attribute: [String: String] { get }
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSpotlightModule: NSObject, HSModuleAPI, HSSpotlightModuleAPI {
    var name = "hs.spotlight"
    let engineID: UUID

    private var queries = HSWeakObjectSet<HSSpotlightQuery>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    func shutdown() {
        queries.allObjects.forEach { q in q.destroy() }
        queries.removeAllObjects()
        AKTrace("Shutdown of \(name): \(engineID)")
    }

    // MARK: - HSSpotlightModuleAPI

    @objc func create() -> HSSpotlightQuery {
        let q = HSSpotlightQuery()
        queries.add(q)
        return q
    }

    @objc func search(_ predicate: String, _ callback: JSFunction) -> HSSpotlightQuery {
        let q = create()
        _ = q.setQuery(predicate)
        _ = q.setCallback(callback)
        _ = q.start()
        return q
    }

    @objc var scope: [String: [String]] {
        [
            "home":      [NSMetadataQueryUserHomeScope],
            "computer":  [NSMetadataQueryLocalComputerScope],
            "network":   [NSMetadataQueryNetworkScope],
            "applications": ["/Applications", "/System/Applications", "~/Applications"],
            "icloud":    [NSMetadataQueryUbiquitousDocumentsScope],
            "icloudData": [NSMetadataQueryUbiquitousDataScope],
        ]
    }

    @objc var attribute: [String: String] {
        [
            "path":             "kMDItemPath",
            "displayName":      "kMDItemDisplayName",
            "fsName":           "kMDItemFSName",
            "contentType":      "kMDItemContentType",
            "contentTypeTree":  "kMDItemContentTypeTree",
            "kind":             "kMDItemKind",
            "fileSize":         "kMDItemFSSize",
            "creationDate":     "kMDItemFSCreationDate",
            "modifiedDate":     "kMDItemFSContentChangeDate",
            "lastUsedDate":     "kMDItemLastUsedDate",
            "useCount":         "kMDItemUseCount",
            "authors":          "kMDItemAuthors",
            "title":            "kMDItemTitle",
            "comment":          "kMDItemComment",
            "keywords":         "kMDItemKeywords",
            "durationSeconds":  "kMDItemDurationSeconds",
            "pixelWidth":       "kMDItemPixelWidth",
            "pixelHeight":      "kMDItemPixelHeight",
            "whereFroms":       "kMDItemWhereFroms",
            "bundleIdentifier": "kMDItemCFBundleIdentifier",
        ]
    }
}
