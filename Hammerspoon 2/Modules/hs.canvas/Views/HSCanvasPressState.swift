//
//  HSCanvasPressState.swift
//  Hammerspoon 2
//

import AppKit

/// Tracks the canvas's left-button presses for `HSCanvasRenderView`'s `DragGesture`.
///
/// `DragGesture` doesn't say which modifiers began a press, or mark where one press ends
/// and the next begins, and SwiftUI can cancel it without calling `onEnded` -- for
/// example when the right button is pressed mid-drag, or when the window is hidden or a
/// context menu takes over before the release. So `HSCanvasWindow` reports every left
/// mouse-down here via `pressBegan(modifiers:)`, before SwiftUI sees it, and the gesture
/// asks this object what to report rather than keeping its own state.
///
/// Right-button presses aren't tracked here: `DragGesture` doesn't fire for them, and
/// `HSCanvasDragHostingView` delivers them from AppKit instead.
@MainActor
final class HSCanvasPressState {
    enum Button {
        /// A plain left click: reported as `mouseDown`/`mouseUp`.
        case left
        /// A Ctrl-click, the standard macOS secondary click: reported as
        /// `rightMouseDown`/`rightMouseUp`.
        case controlClick
    }

    /// Advanced on every left mouse-down, so each press is distinct from the one before.
    private var latestPressID = 0
    private var latestPressButton: Button = .left
    /// The latest press whose mouse-down has been reported. Never cleared, so a gesture
    /// update can't report the same press twice.
    private var reportedPressID = 0
    /// The button of the press whose mouse-down has been reported but whose mouse-up
    /// hasn't, if any.
    private var openPressButton: Button?

    /// Records a left mouse-down. Called by `HSCanvasWindow` before SwiftUI sees the event.
    /// The button is fixed here, so releasing Ctrl before the mouse button still ends a
    /// Ctrl-click as `rightMouseUp`.
    func pressBegan(modifiers: NSEvent.ModifierFlags) {
        latestPressID &+= 1
        latestPressButton = modifiers.contains(.control) ? .controlClick : .left
    }

    /// For `DragGesture.onChanged`: returns the button to report a mouse-down as if the
    /// gesture belongs to a press that hasn't been reported yet, or `nil` if it doesn't
    /// (a later update of the same press, or a gesture with no recorded press behind it).
    /// A previous press whose gesture was cancelled is simply abandoned.
    func gestureChanged() -> Button? {
        guard latestPressID != reportedPressID else { return nil }
        reportedPressID = latestPressID
        openPressButton = latestPressButton
        return latestPressButton
    }

    /// For `DragGesture.onEnded`: returns the button to report a mouse-up as, or `nil` if
    /// no mouse-down is outstanding.
    func gestureEnded() -> Button? {
        defer { openPressButton = nil }
        return openPressButton
    }
}
