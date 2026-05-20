//
//  HSWeakObjectSet.swift
//  Hammerspoon 2
//

import Foundation

/// A set of weak references to objects, keyed by ObjectIdentifier for O(1) add/remove.
///
/// Entries zero out when the referenced object is deallocated. Compaction (removal of dead
/// entries) occurs on `allObjects` access.
///
/// This is the canonical storage for module child objects (HSTimer, HSHotkey, etc.) that
/// must be trackable for shutdown() cleanup while still being garbage-collectible by the JS
/// engine when the user drops their JavaScript reference. The underlying OS keeps active
/// objects alive independently (run-loop Timer, Carbon event handler, CLLocationManager
/// delegate, etc.), so weak module-level tracking is safe.
///
/// Preferred over NSHashTable.weakObjects(), which has documented autoreleasepool
/// interactions that can cause entries to persist or zero unpredictably.
///
/// Usage:
/// ```swift
/// private var timers = HSWeakObjectSet<HSTimer>()
///
/// func create(...) -> HSTimer {
///     let t = HSTimer(...)
///     timers.add(t)
///     return t
/// }
///
/// func shutdown() {
///     for t in timers.allObjects { t.stop() }
///     timers.removeAllObjects()
/// }
/// ```
final class HSWeakObjectSet<T: AnyObject> {
    private struct WeakBox {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    private var storage: [ObjectIdentifier: WeakBox] = [:]

    /// All currently-alive objects in the set. Dead entries are compacted on each access.
    var allObjects: [T] {
        compact()
        return storage.values.compactMap(\.value)
    }

    /// Add an object to the set. Replaces any existing entry for the same identity.
    func add(_ object: T) {
        storage[ObjectIdentifier(object)] = WeakBox(object)
        DispatchQueue.main.async {
            self.compact()
        }
    }

    /// Remove a specific object from the set.
    func remove(_ object: T) {
        storage.removeValue(forKey: ObjectIdentifier(object))
        DispatchQueue.main.async {
            self.compact()
        }
    }

    /// Remove all entries from the set.
    func removeAllObjects() {
        storage.removeAll()
    }

    // MARK: - Private

    private func compact() {
        storage = storage.filter { $0.value.value != nil }
    }
}
