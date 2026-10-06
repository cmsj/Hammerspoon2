//
//  HSCanvasPressState.swift
//  Hammerspoon 2
//

import AppKit

/// What began the current canvas press.
///
/// SwiftUI's `DragGesture` doesn't say which button or modifiers began a press, so
/// `HSCanvasWindow` records that here from the raw `NSEvent` before SwiftUI sees it, and
/// `HSCanvasRenderView` reads it when its `DragGesture` begins.
@MainActor
final class HSCanvasPressState {
    enum Source {
        /// A plain left click: reported as `mouseDown`/`mouseUp`.
        case leftButton
        /// A Ctrl-click, the standard macOS secondary click. It arrives as a left-button
        /// press, so it reaches `DragGesture`, but it's reported as
        /// `rightMouseDown`/`rightMouseUp`.
        case controlClick
        /// A real right-button press. `DragGesture` doesn't fire for these, so
        /// `HSCanvasDragHostingView` delivers them from AppKit instead. Recorded so the
        /// gesture can ignore one if SwiftUI ever does start delivering them, rather than
        /// reporting it twice.
        case rightButton
    }

    var source: Source = .leftButton

    /// Classifies a mouse-down event by what began the press.
    nonisolated static func source(for type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Source {
        switch type {
        case .rightMouseDown:
            return .rightButton
        case .leftMouseDown where modifiers.contains(.control):
            return .controlClick
        default:
            return .leftButton
        }
    }
}
