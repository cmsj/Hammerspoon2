//
//  UIElement+Frame.swift
//  Hammerspoon 2
//

import AXSwift
import CoreGraphics

extension UIElement {
    /// Sets an element's position and size so that it ends up with exactly `frame`, even when that
    /// moves it to another screen.
    ///
    /// Applications constrain a window's size to the screen they think it is on, and they don't
    /// notice a move to another screen straight away. Setting position then size can therefore
    /// clip the new size to the old screen (#423), and setting size then position can push a
    /// window that has grown too big for its old screen to a different position. Setting size,
    /// position, then size again avoids both, and is what Hammerspoon 1 does.
    func setFrameAcrossScreens(_ frame: CGRect) throws {
        try setAttribute(.size, value: frame.size)
        try setAttribute(.position, value: frame.origin)
        try setAttribute(.size, value: frame.size)
    }
}
