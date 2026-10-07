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
/// each one to `pressState`, which must be the content view's own -- `HSCanvas.show()`
/// passes in `HSCanvasDragHostingView.pressState`. Without those reports the gesture
/// delivers no clicks at all, so the press state is required at init rather than looked
/// up from `contentView` later.
@MainActor
final class HSCanvasWindow: NSWindow {
    private let pressState: HSCanvasPressState

    init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool, pressState: HSCanvasPressState) {
        self.pressState = pressState
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            pressState.pressBegan(modifiers: event.modifierFlags)
        }
        super.sendEvent(event)
    }
}
