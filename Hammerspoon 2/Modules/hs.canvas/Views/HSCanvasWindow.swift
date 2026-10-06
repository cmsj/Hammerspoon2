//
//  HSCanvasWindow.swift
//  Hammerspoon 2
//

import AppKit

/// The window an `HSCanvas` is shown in.
///
/// SwiftUI delivers mouse events to gestures from within `NSWindow.sendEvent(_:)`, before
/// AppKit calls the hit view's `mouseDown`/`rightMouseDown`, and `DragGesture` doesn't
/// report which button or modifiers began a press. So this records that from each
/// mouse-down here, ahead of SwiftUI, into the content view's `pressState`.
@MainActor
final class HSCanvasWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let hostingView = contentView as? HSCanvasDragHostingView {
            hostingView.pressState.button = HSCanvasPressState.button(for: event.type, modifiers: event.modifierFlags)
        }
        super.sendEvent(event)
    }
}
