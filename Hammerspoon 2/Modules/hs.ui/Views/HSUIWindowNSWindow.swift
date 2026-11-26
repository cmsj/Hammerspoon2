//
//  HSUIWindowNSWindow.swift
//  Hammerspoon 2
//

import AppKit

/// The window an `HSUIWindow` is shown in.
@MainActor
final class HSUIWindowNSWindow: NSWindow {
    // AppKit moves a window that overlaps the menu bar down below it. A titled window keeps
    // that, so its title bar isn't hidden behind the menu bar, but a borderless overlay goes
    // exactly where it was asked to, matching hs.canvas.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard styleMask.contains(.titled) else { return frameRect }
        return super.constrainFrameRect(frameRect, to: screen)
    }
}
