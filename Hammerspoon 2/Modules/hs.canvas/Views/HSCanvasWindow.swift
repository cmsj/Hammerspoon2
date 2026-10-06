//
//  HSCanvasWindow.swift
//  Hammerspoon 2
//

import AppKit

/// The window an `HSCanvas` is shown in.
///
/// SwiftUI delivers mouse events to gestures from within `NSWindow.sendEvent(_:)`, before
/// AppKit calls the hit view's `mouseDown`, and `DragGesture` doesn't report which
/// modifiers began a press. So this records what began each press here, ahead of
/// SwiftUI, into the content view's `pressState` -- which is how a Ctrl-click gets
/// reported as a right click.
@MainActor
final class HSCanvasWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let hostingView = contentView as? HSCanvasDragHostingView {
            hostingView.pressState.source = HSCanvasPressState.source(for: event.type, modifiers: event.modifierFlags)
        }
        super.sendEvent(event)
    }
}
