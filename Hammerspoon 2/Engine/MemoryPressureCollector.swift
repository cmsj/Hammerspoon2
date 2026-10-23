//
//  MemoryPressureCollector.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Collects JavaScript garbage when macOS reports that the system is short of memory.
///
/// JSC collects when its own heap has grown enough, so garbage that holds native memory JSC
/// hasn't been told about (see `JSExtraMemory`) can sit uncollected indefinitely. When the system
/// comes under memory pressure, this runs a full collection, which frees the native objects of
/// every collected wrapper before it returns, and then asks malloc to hand freed pages back to
/// the system.
///
/// The pressure is system-wide: it doesn't fire because Hammerspoon itself has grown, only when
/// the whole system needs memory back.
@_documentation(visibility: private)
final class MemoryPressureCollector {
    private weak var context: JSContext?
    private let source: any DispatchSourceMemoryPressure

    init(context: JSContext) {
        self.context = context
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            AKInfo("System memory pressure (\(self.source.data.contains(.critical) ? "critical" : "warning")), collecting JavaScript garbage")
            self.collect()
        }
        source.activate()
    }

    isolated deinit {
        source.cancel()
    }

    /// Run a full, synchronous collection in the context, then release freed malloc pages.
    func collect() {
        guard let context else { return }
        // The synchronous collector runs finalizers before returning, so the native objects behind
        // collected wrappers are freed here, rather than whenever a background sweep gets to them.
        unsafe JSSynchronousGarbageCollectForDebugging(context.jsGlobalContextRef)
        _ = malloc_zone_pressure_relief(nil, 0)
    }
}
