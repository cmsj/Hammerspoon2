//
//  AXObjectCache.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import AXSwift

/// Hands out one `HSWindow` per window and one `HSApplication` per running application, rather
/// than a new object each time one is asked for.
///
/// This saves making (and later collecting) a native object and its JavaScript wrapper every time
/// a window or application is handed to JavaScript, which `hs.windowfilter` and window-heavy
/// scripts do a great deal of. It also means that, for as long as JavaScript holds on to one, the
/// same window or application comes back as the same JavaScript object, so `===` and `Map` keys
/// work.
///
/// The cache only holds its objects weakly, so it never keeps one alive by itself and needs no
/// cleaning up. `WindowTracker` holds the ones for the windows and applications it tracks, for as
/// long as it tracks them, so those are kept between uses.
///
/// `HSWindow` and `HSApplication` read everything live, holding no state of their own beyond what
/// identifies their window or application, so one object can safely be shared, including between
/// engines.
@_documentation(visibility: private)
@MainActor
final class AXObjectCache {
    static let shared = AXObjectCache()

    private struct WeakWindow {
        weak var window: HSWindow?
    }

    private struct WeakApplication {
        weak var application: HSApplication?
    }

    private var windows: [Int: WeakWindow] = [:]
    private var applications: [pid_t: WeakApplication] = [:]
    private var additionsSincePrune = 0

    /// How many objects to add between dropping the entries of the ones that have gone
    private static let pruneInterval = 256

    private init() {}

    /// The window for an element, made the first time it's asked for
    /// - Parameters:
    ///   - element: The window's accessibility element
    ///   - app: The application it belongs to
    ///   - id: Its window ID, if already known; read from `element` otherwise
    func window(element: UIElement, app: NSRunningApplication, id: Int? = nil) -> HSWindow {
        let id = id ?? Int(WindowEnumerator.windowID(of: element))
        // A window whose ID can't be read can't be told apart from others
        guard id > 0 else { return HSWindow(element: element, app: app, id: id) }
        if let existing = windows[id]?.window, existing.app.processIdentifier == app.processIdentifier {
            return existing
        }
        let window = HSWindow(element: element, app: app, id: id)
        windows[id] = WeakWindow(window: window)
        noteAddition()
        return window
    }

    /// The application for a running application, made the first time it's asked for
    func application(for app: NSRunningApplication) -> HSApplication {
        let pid = app.processIdentifier
        if let existing = applications[pid]?.application, Self.isSameProcess(existing.runningApplication, app) {
            return existing
        }
        let application = HSApplication(runningApplication: app)
        applications[pid] = WeakApplication(application: application)
        noteAddition()
        return application
    }

    /// Whether two running applications are the same process, rather than one that has quit and
    /// another that was given its PID since
    nonisolated static func isSameProcess(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        lhs === rhs || (lhs.processIdentifier == rhs.processIdentifier
                        && lhs.launchDate == rhs.launchDate
                        && lhs.executableURL == rhs.executableURL)
    }

    private func noteAddition() {
        additionsSincePrune += 1
        guard additionsSincePrune >= Self.pruneInterval else { return }
        additionsSincePrune = 0
        windows = windows.filter { $0.value.window != nil }
        applications = applications.filter { $0.value.application != nil }
    }
}
