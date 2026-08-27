//
//  HSRect.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore
import CoreGraphics

// ---------------------------------------------------------------
// MARK: - Existing Bridge Classes (from before)
// ---------------------------------------------------------------

/// This is a JavaScript object used to represent a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGRect type in Swift/ObjectiveC.
@objc protocol HSRectAPI: HSTypeAPI, JSExport {
    /// An x-axis coordinate for the top-left point of the rectangle
    var x: Double { get set }

    /// A y-axis coordinate for the top-left point of the rectangle
    var y: Double { get set }

    /// The width of the rectangle
    var w: Double { get set }

    /// The height of the rectangle
    var h: Double { get set }

    /// The "origin" of the rectangle, ie the coordinates of its top left corner, as an HSPoint object
    var origin: HSPoint { get set }

    /// The size of the rectangle, ie its width and height, as an HSSize object
    var size: HSSize { get set }
    
    /// Create a new HSRect object
    /// - Parameters:
    ///   - x: The x-axis coordinate of the top-left corner
    ///   - y: The y-axis coordinate of the top-left corner
    ///   - w: The width of the rectangle
    ///   - h: The height of the rectangle
    init(x: Double, y: Double, w: Double, h: Double)

    /// Returns the angle between the positive x axis and the vector from this rect's center to another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A number containing the angle in radians, or 0 if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 2, 2).angleTo(new HSPoint(2, 2)) // 0.7853981633974483
    /// ```
    @objc func angleTo(_ other: JSValue) -> Double

    /// Finds the distance between this rect's center and another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A number containing the distance, or 0 if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 2, 2).distance(new HSPoint(4, 5)) // 5.0
    /// ```
    @objc func distance(_ other: JSValue) -> Double

    /// Checks if this rect is equal to another rect
    /// - Parameter other: An HSRect to compare against
    /// - Returns: `true` if both rects have the same origin and size, otherwise `false`
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 10, 10).equals(new HSRect(0, 0, 10, 10)) // true
    /// ```
    @objc func equals(_ other: HSRect) -> Bool

    /// Ensures this rect is fully inside `bounds`, scaling it down (preserving aspect ratio) if it's larger, and moving it if necessary
    /// - Parameter bounds: An HSRect describing the bounds to fit within
    /// - Returns: A new HSRect that fits fully inside `bounds`
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 200, 100).fit(new HSRect(0, 0, 100, 100)) // new HSRect(0, 0, 100, 50)
    /// ```
    @objc func fit(_ bounds: HSRect) -> HSRect

    /// Truncates the origin and size of this rect towards negative infinity
    /// - Returns: A new HSRect with the x, y, w and h values floored to the nearest integer
    /// - Example:
    /// ```
    /// new HSRect(1.7, 1.2, 10.9, 10.1).floor() // new HSRect(1, 1, 10, 10)
    /// ```
    @objc func floor() -> HSRect

    /// Converts a unit rect (coordinates and dimensions between 0 and 1) within a given frame into absolute coordinates
    /// - Parameter frame: An HSRect describing the frame this unit rect is relative to
    /// - Returns: A new HSRect with coordinates and dimensions converted from the 0-1 range into absolute values within `frame`
    /// - Example:
    /// ```
    /// new HSRect(0.5, 0.5, 0.5, 0.5).fromUnitRect(new HSRect(0, 0, 100, 100)) // new HSRect(50, 50, 50, 50)
    /// ```
    @objc func fromUnitRect(_ frame: HSRect) -> HSRect

    /// Checks if this rect lies fully inside another rect
    /// - Parameter rect: An HSRect to check against
    /// - Returns: `true` if this rect lies fully within the bounds of `rect`, otherwise `false`
    /// - Example:
    /// ```
    /// new HSRect(1, 1, 5, 5).inside(new HSRect(0, 0, 10, 10)) // true
    /// ```
    @objc func inside(_ rect: HSRect) -> Bool

    /// Returns the intersection of this rect and another rect
    /// - Parameter rect: An HSRect to intersect with
    /// - Returns: A new HSRect describing the overlapping area, or a zero-sized HSRect if they don't overlap
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 10, 10).intersect(new HSRect(5, 5, 10, 10)) // new HSRect(5, 5, 5, 5)
    /// ```
    @objc func intersect(_ rect: HSRect) -> HSRect

    /// Moves this rect by an offset
    /// - Parameter offset: {HSPoint | HSSize} An HSPoint (using its x/y), or an HSSize (using its w/h)
    /// - Returns: A new HSRect moved by the given offset, or an unchanged copy of this rect if `offset` is not an HSPoint or HSSize
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 10, 10).move(new HSPoint(5, 5)) // new HSRect(5, 5, 10, 10)
    /// ```
    @objc func move(_ offset: JSValue) -> HSRect

    /// Scales the size of this rect, keeping its center constant
    /// - Parameter factor: {number | HSSize | HSPoint} A number to scale both dimensions uniformly, or an HSSize/HSPoint to scale the width and height independently
    /// - Returns: A new HSRect scaled by the given factor, or an unchanged copy of this rect if `factor` is not a positive number, HSSize or HSPoint
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 10, 10).scale(2) // new HSRect(-5, -5, 20, 20)
    /// ```
    @objc func scale(_ factor: JSValue) -> HSRect

    /// Converts this rect into a unit rect (coordinates and dimensions between 0 and 1) within a given frame
    /// - Parameter frame: An HSRect describing the frame this rect is relative to
    /// - Returns: A new HSRect with coordinates and dimensions normalized to the 0-1 range within `frame`
    /// - Example:
    /// ```
    /// new HSRect(50, 50, 50, 50).toUnitRect(new HSRect(0, 0, 100, 100)) // new HSRect(0.5, 0.5, 0.5, 0.5)
    /// ```
    @objc func toUnitRect(_ frame: HSRect) -> HSRect

    /// Returns the smallest rect that encloses both this rect and another rect
    /// - Parameter rect: An HSRect to union with
    /// - Returns: A new HSRect that fully encloses both rects
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 10, 10).union(new HSRect(5, 5, 10, 10)) // new HSRect(0, 0, 15, 15)
    /// ```
    @objc func union(_ rect: HSRect) -> HSRect

    /// Returns the vector from this rect's center to another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A new HSPoint representing the vector, or `new HSPoint(0, 0)` if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSRect(0, 0, 2, 2).vector(new HSPoint(4, 5)) // new HSPoint(3, 4)
    /// ```
    @objc func vector(_ other: JSValue) -> HSPoint
}

@objc class HSRect: NSObject, HSRectAPI {
    @objc var typeName = "HSRect"

    @objc func toString() -> String {
        return "<\(typeName): (\(x), \(y)) \(w)x\(h)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    var rect: CGRect

    var x: Double {
        get { Double(rect.origin.x) }
        set { rect.origin.x = CGFloat(newValue) }
    }
    var y: Double {
        get { Double(rect.origin.y) }
        set { rect.origin.y = CGFloat(newValue) }
    }
    var w: Double {
        get { Double(rect.size.width) }
        set { rect.size.width = CGFloat(newValue) }
    }
    var h: Double {
        get { Double(rect.size.height) }
        set { rect.size.height = CGFloat(newValue) }
    }

    var origin: HSPoint {
        get { HSPoint(x: x, y: y) }
        set { rect.origin = newValue.point }
    }

    var size: HSSize {
        get { HSSize(w: w, h: h) }
        set { rect.size = newValue.size }
    }

    required init(x: Double, y: Double, w: Double, h: Double) {
        rect = CGRect(x: x, y: y, width: w, height: h)
    }

    private var center: CGPoint {
        CGPoint(x: x + w / 2, y: y + h / 2)
    }

    @objc func angleTo(_ other: JSValue) -> Double {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSRect: angleTo() requires an HSPoint or HSRect")
            return 0
        }
        let c = center
        return atan2(otherCenter.y - c.y, otherCenter.x - c.x)
    }

    @objc func distance(_ other: JSValue) -> Double {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSRect: distance() requires an HSPoint or HSRect")
            return 0
        }
        let c = center
        let dx = otherCenter.x - c.x
        let dy = otherCenter.y - c.y
        return (dx * dx + dy * dy).squareRoot()
    }

    @objc func equals(_ other: HSRect) -> Bool {
        x == other.x && y == other.y && w == other.w && h == other.h
    }

    @objc func fit(_ bounds: HSRect) -> HSRect {
        let scaleFactor = min(1, bounds.w / w, bounds.h / h)
        let newW = w * scaleFactor
        let newH = h * scaleFactor

        let newX = min(max(x, bounds.x), bounds.x + bounds.w - newW)
        let newY = min(max(y, bounds.y), bounds.y + bounds.h - newH)

        return HSRect(x: newX, y: newY, w: newW, h: newH)
    }

    @objc func floor() -> HSRect {
        HSRect(x: Foundation.floor(x), y: Foundation.floor(y), w: Foundation.floor(w), h: Foundation.floor(h))
    }

    @objc func fromUnitRect(_ frame: HSRect) -> HSRect {
        guard frame.w > 0, frame.h > 0 else {
            AKError("HSRect: fromUnitRect() requires a frame with a non-zero width and height")
            return HSRect(x: x, y: y, w: w, h: h)
        }
        return HSRect(x: x * frame.w + frame.x,
                      y: y * frame.h + frame.y,
                      w: w * frame.w,
                      h: h * frame.h)
    }

    @objc func inside(_ rect: HSRect) -> Bool {
        x >= rect.x && y >= rect.y && (x + w) <= (rect.x + rect.w) && (y + h) <= (rect.y + rect.h)
    }

    @objc func intersect(_ rect: HSRect) -> HSRect {
        CGRect(from: self).intersection(CGRect(from: rect)).toBridge()
    }

    @objc func move(_ offset: JSValue) -> HSRect {
        guard let (dx, dy) = offset.toGeometryOffset() else {
            AKError("HSRect: move() requires an HSPoint or HSSize")
            return HSRect(x: x, y: y, w: w, h: h)
        }
        return HSRect(x: x + dx, y: y + dy, w: w, h: h)
    }

    @objc func scale(_ factor: JSValue) -> HSRect {
        guard let (sx, sy) = factor.toGeometryScaleFactors() else {
            AKError("HSRect: scale() requires a number, HSSize or HSPoint")
            return HSRect(x: x, y: y, w: w, h: h)
        }
        guard sx > 0, sy > 0 else {
            AKError("HSRect: scale() factor must be greater than 0")
            return HSRect(x: x, y: y, w: w, h: h)
        }
        let newW = w * sx
        let newH = h * sy
        let c = center
        return HSRect(x: c.x - newW / 2, y: c.y - newH / 2, w: newW, h: newH)
    }

    @objc func toUnitRect(_ frame: HSRect) -> HSRect {
        guard frame.w > 0, frame.h > 0 else {
            AKError("HSRect: toUnitRect() requires a frame with a non-zero width and height")
            return HSRect(x: x, y: y, w: w, h: h)
        }
        let clamped = intersect(frame)
        return HSRect(x: (clamped.x - frame.x) / frame.w,
                      y: (clamped.y - frame.y) / frame.h,
                      w: clamped.w / frame.w,
                      h: clamped.h / frame.h)
    }

    @objc func union(_ rect: HSRect) -> HSRect {
        CGRect(from: self).union(CGRect(from: rect)).toBridge()
    }

    @objc func vector(_ other: JSValue) -> HSPoint {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSRect: vector() requires an HSPoint or HSRect")
            return HSPoint(x: 0, y: 0)
        }
        let c = center
        return HSPoint(x: otherCenter.x - c.x, y: otherCenter.y - c.y)
    }
}

// ---------------------------------------------------------------
// MARK: - Conversion Helpers (Bridge Layer)
// ---------------------------------------------------------------

// --- CGRect <-> HSRect ---
extension CGRect: JSConvertible {
    typealias BridgeType = HSRect

    init(from bridge: HSRect) {
        self.init(x: bridge.x, y: bridge.y, width: bridge.w, height: bridge.h)
    }

    func toBridge() -> HSRect {
        HSRect(x: Double(origin.x), y: Double(origin.y),
               w: Double(size.width), h: Double(size.height))
    }
}

