//
//  AXMessagingTimeout.swift
//  Hammerspoon 2
//

import Foundation
import ApplicationServices

/// The process-wide Accessibility messaging timeout: how long an Accessibility request waits for
/// an application to answer before giving up.
///
/// The user chooses it with `hs.accessibilityTimeout`. Code that asks many applications for
/// things at once (e.g. `hs.window.allWindows()`) shortens it for a while with
/// `withAXTimeoutLimit(_:_:)`, so one hung application can't stall everything.
///
/// The Accessibility API can set this timeout but not read it, so it's tracked here, and every
/// change to it must go through this type.
@_documentation(visibility: private)
@MainActor
enum AXMessagingTimeout {
    /// The timeout the user chose, in seconds. 0 means the macOS default (about 6 seconds).
    private(set) static var configured: Double = 0

    /// The timeout last given to the Accessibility API, for tests
    private(set) static var applied: Double = 0

    /// The limits of the `withAXTimeoutLimit` calls in progress, innermost last
    private static var limits: [Double] = []

    /// The timeout in effect now
    static var current: Double { limits.last ?? configured }

    /// Whether `seconds` can be used as a timeout: 0, or a positive number that's still positive
    /// and finite once converted to the `Float` the Accessibility API takes (so e.g. 1e-50,
    /// which would round to 0 and select the macOS default, isn't)
    nonisolated static func isValid(_ seconds: Double) -> Bool {
        if seconds == 0 { return true }
        let converted = Float(seconds)
        return converted > 0 && converted.isFinite
    }

    /// Sets the timeout the user chose
    /// - Parameter seconds: The timeout in seconds, or 0 for the macOS default. Must be valid.
    static func configure(_ seconds: Double) {
        precondition(isValid(seconds), "Invalid Accessibility timeout: \(seconds)")
        configured = seconds
        // A limit in progress keeps applying; this takes effect when the outermost one ends
        if limits.isEmpty {
            apply(seconds)
        }
    }

    /// Goes back to the macOS default, e.g. when the config is reloaded
    static func reset() {
        configure(0)
    }

    /// Runs `body` with the timeout at most `limit`
    static func withLimit<T>(_ limit: Double, _ body: () throws -> T) rethrows -> T {
        let effective = shorter(limit, current)
        limits.append(effective)
        apply(effective)
        defer {
            limits.removeLast()
            apply(current)
        }
        return try body()
    }

    /// The shorter of two timeouts, where 0 means the (long) macOS default
    private static func shorter(_ first: Double, _ second: Double) -> Double {
        if first == 0 { return second }
        if second == 0 { return first }
        return min(first, second)
    }

    private static func apply(_ seconds: Double) {
        guard seconds != applied else { return }
        let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Float(seconds))
        if error == .success {
            applied = seconds
        } else {
            AKError("Unable to set the Accessibility timeout to \(seconds)s: \(error.rawValue)")
        }
    }
}

/// Runs `body` with the Accessibility messaging timeout at most `limit` seconds, then puts the
/// timeout back as it was. Use it around code that asks many applications for things, so one
/// that's hung or slow can't stall it. Calls can be nested; the shortest limit applies.
/// - Parameters:
///   - limit: The longest the timeout may be, in seconds. A shorter `hs.accessibilityTimeout`
///     is kept.
///   - body: The code to run
/// - Returns: What `body` returns
@MainActor
func withAXTimeoutLimit<T>(_ limit: Double, _ body: () throws -> T) rethrows -> T {
    try AXMessagingTimeout.withLimit(limit, body)
}
