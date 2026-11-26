//
//  WindowState.swift
//  Hammerspoon 2
//

import Foundation
import CoreGraphics

/// Everything a window filter's rules can look at for one window, captured at one moment.
///
/// `WindowTracker` keeps one of these up to date for every window it tracks, and the events
/// filters emit are worked out by comparing a window's state before and after a change (see
/// `HSWindowFilterEvent.changes(from:to:)`), so the same logic covers every kind of change.
nonisolated struct WindowState: Equatable {
    var id: Int
    var pid: pid_t
    var appName: String
    var bundleID: String?
    var title: String
    /// The window's accessibility subrole, e.g. AXStandardWindow
    var subrole: String?
    /// Top-left origin, like every other frame in Hammerspoon
    var frame: CGRect
    /// The UUID and name of the screen holding most of the window
    var screenUUID: String?
    var screenName: String?
    var isMinimized: Bool
    var isAppHidden: Bool
    var isFullscreen: Bool
    var hasTitlebar: Bool
    /// Whether the window is on one of the Spaces currently shown
    var isOnCurrentSpace: Bool
    /// Whether it's the focused window of the active application. See `hasFocus`.
    var isFocused: Bool
    var isAppActive: Bool

    /// Not minimized, and its application isn't hidden: the window is shown on some Space
    var isVisible: Bool { !isMinimized && !isAppHidden }

    /// Minimized and hidden windows belong to every Space, as in Hammerspoon 1
    var isInCurrentSpace: Bool { !isVisible || isOnCurrentSpace }

    /// Actually on screen: visible, and on a Space that's shown
    var isOnScreen: Bool { isVisible && isOnCurrentSpace }

    /// Focused, as far as filters are concerned: a hidden or minimized window can't really have
    /// focus. Activating a hidden application focuses its window before unhiding it, so this
    /// makes the window gain focus once it's visible, after windowVisible, rather than while it's
    /// hidden, when a filter of visible windows wouldn't pass the event on.
    var hasFocus: Bool { isFocused && isVisible }
}

/// The events a window filter emits, both those about windows and the ones about the filter's
/// own set of allowed windows
nonisolated enum HSWindowFilterEvent: String, HSEventName {
    case windowCreated
    case windowDestroyed
    case windowMoved
    case windowFullscreened
    case windowUnfullscreened
    case windowMinimized
    case windowUnminimized
    case windowHidden
    case windowUnhidden
    case windowVisible
    case windowNotVisible
    case windowOnScreen
    case windowNotOnScreen
    case windowInCurrentSpace
    case windowNotInCurrentSpace
    case windowFocused
    case windowUnfocused
    case windowTitleChanged
    // About the filter's set of allowed windows
    case windowAllowed
    case windowRejected
    case hasWindow
    case hasNoWindows
    case windowsChanged

    /// The events a window's change from `old` to `new` amounts to, in the order they're
    /// emitted. `old` is nil for a new window, `new` is nil for one that has gone.
    ///
    /// Losses (unfocused, not on screen, not in the current Space, not visible) come first, then
    /// the change itself (created, minimized, hidden, fullscreened, title changed, moved), then
    /// gains (visible, in the current Space, on screen, focused), and destroyed comes last. So,
    /// for example, minimizing the focused window emits windowUnfocused, windowNotOnScreen,
    /// windowNotVisible, windowMinimized.
    static func changes(from old: WindowState?, to new: WindowState?) -> [HSWindowFilterEvent] {
        switch (old, new) {
        case (nil, nil):
            return []

        case let (nil, new?):
            var events: [HSWindowFilterEvent] = [.windowCreated]
            if new.isMinimized { events.append(.windowMinimized) }
            if new.isAppHidden { events.append(.windowHidden) }
            if new.isFullscreen { events.append(.windowFullscreened) }
            if new.isVisible { events.append(.windowVisible) }
            if new.isInCurrentSpace { events.append(.windowInCurrentSpace) }
            if new.isOnScreen { events.append(.windowOnScreen) }
            if new.hasFocus { events.append(.windowFocused) }
            return events

        case let (old?, nil):
            var events: [HSWindowFilterEvent] = []
            if old.hasFocus { events.append(.windowUnfocused) }
            if old.isOnScreen { events.append(.windowNotOnScreen) }
            if old.isInCurrentSpace { events.append(.windowNotInCurrentSpace) }
            if old.isVisible { events.append(.windowNotVisible) }
            events.append(.windowDestroyed)
            return events

        case let (old?, new?):
            var events: [HSWindowFilterEvent] = []
            // Losses
            if old.hasFocus && !new.hasFocus { events.append(.windowUnfocused) }
            if old.isOnScreen && !new.isOnScreen { events.append(.windowNotOnScreen) }
            if old.isInCurrentSpace && !new.isInCurrentSpace { events.append(.windowNotInCurrentSpace) }
            if old.isVisible && !new.isVisible { events.append(.windowNotVisible) }
            // The change itself
            if old.isMinimized != new.isMinimized { events.append(new.isMinimized ? .windowMinimized : .windowUnminimized) }
            if old.isAppHidden != new.isAppHidden { events.append(new.isAppHidden ? .windowHidden : .windowUnhidden) }
            if old.isFullscreen != new.isFullscreen { events.append(new.isFullscreen ? .windowFullscreened : .windowUnfullscreened) }
            if old.title != new.title { events.append(.windowTitleChanged) }
            if old.frame != new.frame { events.append(.windowMoved) }
            // Gains
            if !old.isVisible && new.isVisible { events.append(.windowVisible) }
            if !old.isInCurrentSpace && new.isInCurrentSpace { events.append(.windowInCurrentSpace) }
            if !old.isOnScreen && new.isOnScreen { events.append(.windowOnScreen) }
            if !old.hasFocus && new.hasFocus { events.append(.windowFocused) }
            return events
        }
    }
}
