//
//  HSCanvasWindow.swift
//  Hammerspoon 2
//

import AppKit

/// The window an `HSCanvas` is shown in.
///
/// SwiftUI delivers mouse events to gestures from within `NSWindow.sendEvent(_:)`, before
/// AppKit calls the hit view's `mouseDown`, so this is the only place that sees each
/// left mouse-down (and its modifiers) ahead of the canvas's `DragGesture`. It reports
/// each one to the content view's `pressState`.
@MainActor
final class HSCanvasWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let hostingView = contentView as? HSCanvasDragHostingView {
            hostingView.pressState.pressBegan(modifiers: event.modifierFlags)
        }
        super.sendEvent(event)
    }
}
