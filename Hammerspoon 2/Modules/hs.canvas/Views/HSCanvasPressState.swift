//
//  HSCanvasPressState.swift
//  Hammerspoon 2
//

import AppKit

/// Which mouse button the current canvas press should be reported as.
///
/// SwiftUI's `DragGesture` fires for both left and right presses but doesn't say which
/// button (or which modifiers) produced them, so `HSCanvasWindow` records that here from
/// the raw `NSEvent` before SwiftUI sees it. `HSCanvasRenderView` reads it when its
/// `DragGesture` begins.
@MainActor
final class HSCanvasPressState {
    enum Button {
        case primary, secondary
    }

    var button: Button = .primary

    /// Maps a mouse-down event to the button it's reported as. A right-button press is
    /// secondary, and so is a Ctrl-click, the standard macOS secondary click, so both
    /// are delivered as `rightMouseDown`/`rightMouseUp` rather than `mouseDown`/`mouseUp`.
    nonisolated static func button(for type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Button {
        switch type {
        case .rightMouseDown:
            return .secondary
        case .leftMouseDown where modifiers.contains(.control):
            return .secondary
        default:
            return .primary
        }
    }
}
