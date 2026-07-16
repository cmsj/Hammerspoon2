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
///     autoreleasepool {
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
/// Use `autoreleasepool {}` (not `do {}`): `JSValue` objects returned by `harness.eval()`
/// are autoreleased into the current pool, and each `JSValue` holds a **strong** reference
/// to its `JSContext`. Without a local pool, those `JSValue`s land in the test runner's
/// outer pool and keep the `JSContext` alive after the harness goes out of scope, preventing
/// the JSC bridge from releasing tracked objects. The `autoreleasepool {}` drains those
/// `JSValue`s before `assertNoLeaks()` runs.
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
    /// Drains the run loop for `timeout` seconds before checking to flush any pending
    /// autorelease pools or deferred Foundation work (e.g. a `Timer`'s target reference
    /// being released asynchronously after invalidation). Always drains the main run loop
    /// so that AppKit/SwiftUI cleanup and `@MainActor` tasks complete before the check.
    /// Call this only after all strong references to the tracked objects are gone — i.e.,
    /// after the `do {}` block that held the harness and JSValue locals has ended.
    ///
    /// - Parameter timeout: How long to drain the run loop. Default 50 ms is sufficient for
    ///   pure-Swift objects. Pass a higher value for objects whose cleanup involves AppKit
    ///   window teardown or SwiftUI rendering pipelines (e.g., `HSUIWindow`).
    func assertNoLeaks(timeout: TimeInterval = 0.05, sourceLocation: SourceLocation = #_sourceLocation) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: timeout))
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
