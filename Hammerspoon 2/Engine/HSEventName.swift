//
//  HSEventName.swift
//  Hammerspoon 2
//

import Foundation

/// The set of event names a watcher module can emit through its `on`/`off`/`once` API.
///
/// Each watcher module declares one enum conforming to this, emits events only via its cases'
/// `rawValue`s, and exposes `allNames` to its JS enhancement script as `_eventNames`. The
/// enhancement script hands that list to its `LazyWatcherEmitter` (see Engine/engine.js), which
/// then rejects any other name passed to `on()`/`once()` - so a typo throws instead of silently
/// registering a listener that can never fire (issue #253).
///
/// Because emission goes through the enum, the compiler guarantees every name the module can
/// actually emit is in the list. `scripts/check-event-names.js` (run by `npm run docs:test`)
/// separately checks that the event unions in the module's `on`/`off`/`once` docstrings match
/// these enums, which it finds by looking for conformances to this protocol.
nonisolated protocol HSEventName: RawRepresentable, CaseIterable, Sendable where RawValue == String {}

nonisolated extension HSEventName {
    /// Every event name, in declaration order.
    static var allNames: [String] { allCases.map(\.rawValue) }
}
