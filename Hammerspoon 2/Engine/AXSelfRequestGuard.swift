//
//  AXSelfRequestGuard.swift
//  Hammerspoon 2
//

import Foundation
import ApplicationServices
import AXSwift

/// Keeps Hammerspoon's Accessibility requests to itself on the main thread.
///
/// An application's Accessibility requests to its own process never leave it: the system calls
/// the application's own `NSAccessibility` implementation directly, on whichever thread made the
/// request, even while the main thread is busy. Requests to Hammerspoon's own windows (e.g. a
/// window filter reading a canvas's frame, or `hs.ax` walking the Console) are fine on the main
/// thread, where they're no different from calling AppKit directly, but made from any other
/// thread they'd run AppKit and SwiftUI code there.
///
/// So every request to Hammerspoon's own process made off the main thread is refused with
/// `kAXErrorCannotComplete`, as if Hammerspoon hadn't answered. Requests made through AXSwift are
/// checked by its request gate (a divergence of Hammerspoon's fork); any made with the C API
/// directly that could reach Hammerspoon's own process must call `refusal(forProcessID:)`
/// themselves (those to the Dock, as `HSMissionControl` makes, can't).
@_documentation(visibility: private)
enum AXSelfRequestGuard {
    /// Hammerspoon's own process ID
    nonisolated static let ownProcessID = getpid()

    /// The error to refuse a request to `processID` with, made on the current thread, or nil to
    /// let it go ahead
    nonisolated static func refusal(forProcessID processID: pid_t) -> AXError? {
        processID == ownProcessID && !Thread.isMainThread ? .cannotComplete : nil
    }

    /// Installs the check into AXSwift. Safe to call more than once.
    nonisolated static func install() {
        UIElement.requestGate = { processID in refusal(forProcessID: processID) }
    }
}
