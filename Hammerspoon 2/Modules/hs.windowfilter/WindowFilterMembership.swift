//
//  WindowFilterMembership.swift
//  Hammerspoon 2
//

import Foundation

/// A window filter's set of allowed windows, and the events it emits as windows join and leave it.
///
/// Each window change is processed on its own, as in Hammerspoon 1:
///
/// - A window that becomes allowed emits windowAllowed *before* the change's own events, so its
///   listeners know about the window before hearing anything else about it.
/// - The change's own events are emitted if the window is allowed, or has just stopped being
///   allowed, so listeners hear why a window left (e.g. windowMinimized for a filter of visible
///   windows), but never about windows that were never allowed.
/// - Then hasWindow, if this is the first allowed window, and windowsChanged, if the set changed.
/// - Finally windowRejected for a window that has stopped being allowed, and hasNoWindows if it
///   was the last one.
struct WindowFilterMembership {
    /// One event to emit, about `windowID` (nil for a windowsChanged with no windows left)
    struct Emission: Equatable {
        let event: HSWindowFilterEvent
        let windowID: Int?
    }

    private(set) var allowed: Set<Int> = []
    private(set) var hasWindow = false

    /// Starts again from a known set of allowed windows, without emitting anything
    mutating func reset(allowed: Set<Int>) {
        self.allowed = allowed
        hasWindow = !allowed.isEmpty
    }

    /// Records whether a window is allowed, without emitting anything: for a window that already
    /// existed but was only found late
    mutating func record(windowID id: Int, isAllowed: Bool) {
        if isAllowed {
            allowed.insert(id)
        } else {
            allowed.remove(id)
        }
        hasWindow = !allowed.isEmpty
    }

    /// Records whether window `id` is now allowed, after a change that amounted to `events`.
    /// - Returns: The events to emit, in order
    mutating func process(windowID id: Int, events: [HSWindowFilterEvent], isAllowed: Bool) -> [Emission] {
        let wasAllowed = allowed.contains(id)
        var emissions: [Emission] = []

        if isAllowed && !wasAllowed {
            allowed.insert(id)
            emissions.append(Emission(event: .windowAllowed, windowID: id))
        } else if !isAllowed && wasAllowed {
            allowed.remove(id)
        }

        if isAllowed || wasAllowed {
            emissions += events.map { Emission(event: $0, windowID: id) }
        }

        guard isAllowed != wasAllowed else { return emissions }

        if isAllowed && !hasWindow {
            hasWindow = true
            emissions.append(Emission(event: .hasWindow, windowID: id))
        }
        // Any allowed window will do, but the lowest ID keeps it predictable
        emissions.append(Emission(event: .windowsChanged, windowID: allowed.min()))

        if !isAllowed {
            emissions.append(Emission(event: .windowRejected, windowID: id))
            if allowed.isEmpty && hasWindow {
                hasWindow = false
                emissions.append(Emission(event: .hasNoWindows, windowID: id))
            }
        }
        return emissions
    }
}
