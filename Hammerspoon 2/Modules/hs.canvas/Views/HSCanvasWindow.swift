//
//  HSCanvasWindow.swift
//  Hammerspoon 2
//

import AppKit

/// The window an `HSCanvas` is shown in.
///
/// It's an `NSPanel` (as Hammerspoon 1's was) because only a panel honours the
/// `.nonactivatingPanel` style: an `NSWindow` silently drops it. That style is what
/// `clickActivating(false)` sets, and while Hammerspoon has a Dock icon it's also the only
/// way a window can appear on another application's fullscreen Space.
///
/// SwiftUI delivers mouse events to gestures from within `NSWindow.sendEvent(_:)`, before
/// AppKit calls the hit view's `mouseDown`, so this is the only place that sees each
/// left mouse-down (and its modifiers) ahead of the canvas's `DragGesture`. It reports
/// each one to `pressState`, which must be the content view's own -- `HSCanvas.show()`
/// passes in `HSCanvasDragHostingView.pressState`. Without those reports the gesture
/// delivers no clicks at all, so the press state is required at init rather than looked
/// up from `contentView` later.
@MainActor
final class HSCanvasWindow: NSPanel {
    private let pressState: HSCanvasPressState

    /// The accessibility subrole to report, or nil for AppKit's own with `.Hammerspoon`
    /// appended (see `accessibilitySubrole()`)
    var subroleOverride: String?

    init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool, pressState: HSCanvasPressState) {
        self.pressState = pressState
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        // Panels hide whenever their application isn't frontmost unless told otherwise, and
        // Hammerspoon is almost never frontmost
        hidesOnDeactivate = false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            pressState.pressBegan(modifiers: event.modifierFlags)
        }
        super.sendEvent(event)
    }

    // AppKit moves a window that overlaps the menu bar down below it, so a canvas couldn't
    // cover the top of a screen. Like v1, put the canvas exactly where it was asked to go.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // AppKit reports a non-activating panel as an AXSystemDialog, which window managers (and
    // hs.windowfilter's default roles) treat as a window to manage. Like v1, report a subrole
    // nothing recognises, unless the script has chosen one.
    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        if let subroleOverride {
            return NSAccessibility.Subrole(rawValue: subroleOverride)
        }
        let standard = super.accessibilitySubrole()?.rawValue ?? NSAccessibility.Subrole.unknown.rawValue
        return NSAccessibility.Subrole(rawValue: standard + ".Hammerspoon")
    }
}
