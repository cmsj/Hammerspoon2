//
//  WeakLeakTracker.swift
//  Hammerspoon 2Tests
//

import Foundation
import Testing

/// Tracks Swift objects by weak reference and asserts they are all deallocated after teardown.
///
/// Use this in integration tests to verify that child objects created by modules
/// (HSTimer, HSHotkey, HSEventTap, etc.) do not leak after a simulated `hs.reload()`.
///
/// ## Pattern
///
/// ```swift
/// @Test func timerDoesNotLeakAfterReload() {
///     let tracker = WeakLeakTracker()
///     do {
///         let harness = JSTestHarness()
///         harness.loadModule(HSTimerModule.self, as: "timer")
///         harness.eval("var t = hs.timer.create(60, function() {}, false)")
///         if let obj = harness.evalValue("t")?.toObjectOf(HSTimer.self) as? HSTimer {
///             tracker.track(obj)
///         }
///         harness.eval("t = null")
///         harness.shutdownForLeakTest()
///     }
///     tracker.assertNoLeaks()
/// }
/// ```
///
/// The `do {}` block ensures all `JSValue` locals (which hold strong ObjC refs) and the
/// harness itself go out of scope before `assertNoLeaks()` is called.
/// `shutdownForLeakTest()` must be called **inside** the block so the synchronous GC
/// can run while the `JSContext` is still alive to release bridge objects.
final class WeakLeakTracker {
    private struct Entry {
        let name: String
        let ref: () -> AnyObject?
    }
    private var entries: [Entry] = []

    /// Track `object` by weak reference.
    ///
    /// Uses the dynamic type name as the display label if `name` is omitted.
    func track<T: AnyObject>(_ object: T, name: String? = nil) {
        let displayName = name ?? "\(type(of: object))"
        entries.append(Entry(name: displayName, ref: { [weak object] in object }))
    }

    /// Assert that all tracked objects have been deallocated.
    ///
    /// Drains the run loop for 50 ms before checking to flush any pending autorelease
    /// pools or deferred Foundation work (e.g. a `Timer`'s target reference being
    /// released asynchronously after invalidation). Call this only after all strong
    /// references to the tracked objects are gone — i.e., after the `do {}` block
    /// that held the harness and JSValue locals has ended.
    func assertNoLeaks(sourceLocation: SourceLocation = #_sourceLocation) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        for entry in entries {
            if let alive = entry.ref() {
                Issue.record(
                    "Memory leak: \(entry.name) (\(type(of: alive))) was not deallocated after shutdown",
                    sourceLocation: sourceLocation
                )
            }
        }
    }
}
