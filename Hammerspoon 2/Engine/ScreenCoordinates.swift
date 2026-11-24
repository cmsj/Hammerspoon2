//
//  ScreenCoordinates.swift
//  Hammerspoon 2
//

import AppKit
import JavaScriptCore

// ---------------------------------------------------------------
// MARK: - Hammerspoon screen coordinates
// ---------------------------------------------------------------
//
// AppKit places windows and screens in global coordinates whose origin is the bottom-left of
// the primary display, with y increasing upward. Hammerspoon's JS APIs (hs.screen, hs.window,
// hs.canvas, hs.ui.window, ...) all use the origin at the *top*-left of the primary display,
// with y increasing downward. Use these helpers wherever a frame crosses between the two.

extension CGRect {
    /// Converts this rect between AppKit global screen coordinates and Hammerspoon's.
    ///
    /// The conversion reflects the rect across the primary display's horizontal midline, so
    /// it's its own inverse: use it in both directions.
    func flippedScreenCoordinates() -> CGRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: origin.x,
                      y: primaryScreenHeight - origin.y - height,
                      width: width,
                      height: height)
    }
}

extension JSValue {
    /// Reads a numeric property, or nil if it's missing or not a number.
    ///
    /// Works for plain `{x, y, w, h}` objects and for geometry types like HSRect and HSPoint,
    /// whose properties are accessors on their prototype.
    func optionalNumber(forProperty name: String) -> Double? {
        guard isObject, let property = forProperty(name), property.isNumber else { return nil }
        return property.toDouble()
    }
}
