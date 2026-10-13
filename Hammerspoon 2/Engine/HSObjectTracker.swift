//
//  HSObjectTracker.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Tracks the child objects a module has handed to JavaScript (HSTimer, HSTask, etc.), and keeps
/// the active ones alive.
///
/// This is the one place a module's child objects are retained from Swift. Do not use
/// `selfRetain = self`, strong child collections, or any other mechanism alongside it.
///
/// **Tracking (weak):** every child is added when it's created, so `shutdown()` can reach it.
/// Membership is weak: an inactive child the user has dropped is ordinary garbage, and is
/// collected by JS GC as usual. Entries zero out when the object is deallocated, and are
/// compacted lazily.
///
/// **Active (pinned):** while a child has pending activity, i.e. it can still call back into
/// JavaScript or has a user-visible effect (a running task, a scheduled timer, a started
/// watcher), it must stay alive with its callbacks, whether or not the user kept a reference.
/// JavaScript garbage collection must be unobservable, so collecting a running timer (and so
/// stopping it) isn't allowed. This is the "pending activity" rule from Node (active handles),
/// the HTML spec, and WebKit's `ActiveDOMObject::hasPendingActivity()`.
///
/// `setActive(_:_:in:)` pins the child by holding its JS *wrapper*, not just the Swift object:
/// a `JSCallback` only survives while its owner's wrapper is reachable, so retaining the Swift
/// object alone keeps it alive with its callbacks silently collected.
///
/// **Rules for child objects:**
/// - Derive activity from a single piece of state, and call `setActive` only from that state's
///   `didSet`. Then every path that ends the activity (stop, natural completion, failure,
///   `destroy()`) un-pins it automatically, and a missed call site can't leak the object.
/// - Hold the tracker `weak`; the module owns it.
///
/// **Why this can't leak across reloads:** pins live here, not in the objects, and
/// `removeAllObjects()` (called from the module's `shutdown()`) drops all of them at once. A child
/// that fails to un-pin itself is kept alive until the next reload at worst, never beyond it, so
/// it can't keep an old `JSContext` alive. A pinned object is alive, so it's always still tracked
/// and `shutdown()` always reaches it.
///
/// Active objects are also recorded in `HSActiveObjects`, so they can be listed per context, for
/// users (`hs.activeObjects()`) and for tests (`JSTestHarness` fails a test that ends with objects
/// still active).
///
/// Preferred over NSHashTable.weakObjects(), which has documented autoreleasepool
/// interactions that can cause entries to persist or zero unpredictably.
///
/// Usage:
/// ```swift
/// // In the module
/// private var timers = HSObjectTracker<HSTimer>()
///
/// func create(...) -> HSTimer {
///     let t = HSTimer(..., tracker: timers)
///     timers.add(t)
///     return t
/// }
///
/// func shutdown() {
///     for t in timers.allObjects { t.destroy() }
///     timers.removeAllObjects()
/// }
///
/// // In the child
/// private weak var tracker: HSObjectTracker<HSTimer>?
/// private var timer: Timer? {
///     didSet { tracker?.setActive(self, timer != nil, in: JSContext.current() ?? callback?.value?.context) }
/// }
/// ```
final class HSObjectTracker<T: AnyObject> {
    private struct WeakBox {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    private var storage: [ObjectIdentifier: WeakBox] = [:]

    /// All currently-alive objects, active or not. Dead entries are compacted on each access.
    var allObjects: [T] {
        compact()
        return storage.values.compactMap(\.value)
    }

    /// The number of objects currently active
    var activeCount: Int {
        HSActiveObjects.count(trackedBy: ObjectIdentifier(self))
    }

    /// Add an object. Replaces any existing entry for the same identity.
    func add(_ object: T) {
        storage[ObjectIdentifier(object)] = WeakBox(object)
        DispatchQueue.main.async {
            self.compact()
        }
    }

    /// Remove a specific object, un-pinning it if it was active.
    func remove(_ object: T) {
        HSActiveObjects.remove(object)
        storage.removeValue(forKey: ObjectIdentifier(object))
        DispatchQueue.main.async {
            self.compact()
        }
    }

    /// Remove all objects and drop every pin. Call this at the end of the module's `shutdown()`,
    /// after destroying the objects.
    func removeAllObjects() {
        let released = HSActiveObjects.removeAll(trackedBy: ObjectIdentifier(self))
        if released > 0 {
            AKDebug("HSObjectTracker<\(T.self)>: released \(released) active object\(released == 1 ? "" : "s") at shutdown")
        }
        storage.removeAll()
    }

    /// Marks an object active (pinned, so it and its callbacks stay alive) or inactive (ordinary
    /// garbage once JS drops it). Setting the state it's already in does nothing. Call this only
    /// from the `didSet` of the state that defines the object's activity.
    /// - Parameters:
    ///   - object: The object
    ///   - active: Whether the object has pending activity
    ///   - context: The JSContext the object's wrapper lives in. Only used when becoming active.
    func setActive(_ object: T, _ active: Bool, in context: JSContext?) {
        if active {
            storage[ObjectIdentifier(object)] = WeakBox(object)
            HSActiveObjects.insert(object, trackedBy: ObjectIdentifier(self), in: context)
        } else {
            HSActiveObjects.remove(object)
        }
    }

    /// Whether an object is currently active
    func isActive(_ object: T) -> Bool {
        HSActiveObjects.contains(object)
    }

    // MARK: - Private

    private func compact() {
        storage = storage.filter { $0.value.value != nil }
    }
}

/// The record of every active object, across all trackers. Owned by `HSObjectTracker`; nothing
/// else should insert or remove entries.
enum HSActiveObjects {
    private struct Entry {
        let tracker: ObjectIdentifier
        weak var object: AnyObject?
        /// Holds the object's JS wrapper, which keeps the object and its callbacks alive.
        /// nil if no JSContext was available, in which case the object is only counted.
        let wrapper: JSValue?
        let contextRef: JSGlobalContextRef?
    }

    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func insert(_ object: AnyObject, trackedBy tracker: ObjectIdentifier, in context: JSContext?) {
        if let existing = entries[ObjectIdentifier(object)], existing.object === object { return }

        let wrapper = context.flatMap { JSValue(object: object, in: $0) }
        if wrapper == nil {
            AKError("HSObjectTracker: no JSContext available, \(object) may be garbage collected while active")
        }
        entries[ObjectIdentifier(object)] = Entry(tracker: tracker,
                                                  object: object,
                                                  wrapper: wrapper,
                                                  contextRef: context?.jsGlobalContextRef)
    }

    static func remove(_ object: AnyObject) {
        entries.removeValue(forKey: ObjectIdentifier(object))
    }

    static func contains(_ object: AnyObject) -> Bool {
        live.contains { $0.object === object }
    }

    static func count(trackedBy tracker: ObjectIdentifier) -> Int {
        live.count(where: { $0.tracker == tracker })
    }

    /// Drops every pin held for a tracker, returning how many there were
    static func removeAll(trackedBy tracker: ObjectIdentifier) -> Int {
        let ids = entries.filter { $0.value.tracker == tracker }.keys
        let released = ids.count(where: { entries[$0]?.object != nil })
        for id in ids {
            entries.removeValue(forKey: id)
        }
        return released
    }

    /// The JS wrappers of every active object in a context
    static func wrappers(in context: JSContext) -> [JSValue] {
        live.filter { $0.contextRef == context.jsGlobalContextRef }.compactMap(\.wrapper)
    }

    /// Entries whose object is still alive. An object pinned without a context isn't retained,
    /// and if it's deallocated without un-pinning itself, its identifier could be reused, so
    /// entries are always matched on the object, not just its identifier.
    private static var live: [Entry] {
        entries = entries.filter { $0.value.object != nil }
        return Array(entries.values)
    }
}
