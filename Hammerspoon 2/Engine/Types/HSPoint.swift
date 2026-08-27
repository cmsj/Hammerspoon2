//
//  CGGeometry.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 03/11/2025.
//

import Foundation
import JavaScriptCore
import CoreGraphics

// ---------------------------------------------------------------
// MARK: - Existing Bridge Classes (from before)
// ---------------------------------------------------------------

/// This is a JavaScript object used to represent coordinates, or "points", as used in various places throughout Hammerspoon's API, particularly where dealing with positions on a screen. Behind the scenes it is a wrapper for the CGPoint type in Swift/ObjectiveC.
@objc protocol HSPointAPI: HSTypeAPI, JSExport {
    /// A coordinate for the x-axis position of this point
    var x: Double { get set }

    /// A coordinate for the y-axis position of this point
    var y: Double { get set }
    
    /// Create a new HSPoint object
    /// - Parameters:
    ///   - x: A coordinate for this point on the x-axis
    ///   - y: A coordinate for this point on the y-axis
    init(x: Double, y: Double)

    /// Returns the angle between the positive x axis and this point, treated as a vector
    /// - Returns: A number containing the angle in radians
    /// - Example:
    /// ```
    /// new HSPoint(1, 1).angle() // 0.7853981633974483 (pi/4)
    /// ```
    @objc func angle() -> Double

    /// Returns the angle between the positive x axis and the vector from this point to another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A number containing the angle in radians, or 0 if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSPoint(0, 0).angleTo(new HSPoint(1, 1)) // 0.7853981633974483
    /// ```
    @objc func angleTo(_ other: JSValue) -> Double

    /// Finds the distance between this point and another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A number containing the distance, or 0 if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSPoint(0, 0).distance(new HSPoint(3, 4)) // 5.0
    /// ```
    @objc func distance(_ other: JSValue) -> Double

    /// Checks if this point is equal to another point
    /// - Parameter other: An HSPoint to compare against
    /// - Returns: `true` if both points have the same x and y coordinates, otherwise `false`
    /// - Example:
    /// ```
    /// new HSPoint(1, 2).equals(new HSPoint(1, 2)) // true
    /// ```
    @objc func equals(_ other: HSPoint) -> Bool

    /// Truncates the coordinates of this point towards negative infinity
    /// - Returns: A new HSPoint with the x and y coordinates floored to the nearest integer
    /// - Example:
    /// ```
    /// new HSPoint(1.7, -1.2).floor() // new HSPoint(1, -2)
    /// ```
    @objc func floor() -> HSPoint

    /// Checks if this point lies inside a given rect
    /// - Parameter rect: An HSRect to check against
    /// - Returns: `true` if this point lies within the bounds of `rect`, otherwise `false`
    /// - Example:
    /// ```
    /// new HSPoint(5, 5).inside(new HSRect(0, 0, 10, 10)) // true
    /// ```
    @objc func inside(_ rect: HSRect) -> Bool

    /// Moves this point by an offset
    /// - Parameter offset: {HSPoint | HSSize} An HSPoint (using its x/y), or an HSSize (using its w/h)
    /// - Returns: A new HSPoint moved by the given offset, or an unchanged copy of this point if `offset` is not an HSPoint or HSSize
    /// - Example:
    /// ```
    /// new HSPoint(1, 1).move(new HSPoint(2, 3)) // new HSPoint(3, 4)
    /// ```
    @objc func move(_ offset: JSValue) -> HSPoint

    /// Normalizes this point, treated as a vector, to a length of 1
    /// - Returns: A new HSPoint with the same direction as this point but a length of 1, or `new HSPoint(0, 0)` if this point has zero length
    /// - Example:
    /// ```
    /// new HSPoint(3, 4).normalize() // new HSPoint(0.6, 0.8)
    /// ```
    @objc func normalize() -> HSPoint

    /// Rotates this point counter-clockwise around another point
    /// - Parameters:
    ///   - aroundPoint: The HSPoint to rotate around
    ///   - times: The number of 90 degree counter-clockwise rotations to perform
    /// - Returns: A new HSPoint containing the rotated coordinates
    /// - Example:
    /// ```
    /// new HSPoint(1, 0).rotateCCW(new HSPoint(0, 0), 1) // new HSPoint(0, 1)
    /// ```
    @objc func rotateCCW(_ aroundPoint: HSPoint, _ times: Int) -> HSPoint

    /// Scales this point, treated as a vector
    /// - Parameter factor: {number | HSSize | HSPoint} A number to scale both coordinates uniformly, or an HSSize/HSPoint to scale the x and y coordinates independently
    /// - Returns: A new HSPoint scaled by the given factor, or an unchanged copy of this point if `factor` is not a number, HSSize or HSPoint
    /// - Example:
    /// ```
    /// new HSPoint(2, 3).scale(2) // new HSPoint(4, 6)
    /// ```
    @objc func scale(_ factor: JSValue) -> HSPoint

    /// Returns the vector from this point to another point or rect's center
    /// - Parameter other: {HSPoint | HSRect} An HSPoint, or an HSRect (whose center will be used)
    /// - Returns: A new HSPoint representing the vector, or `new HSPoint(0, 0)` if `other` is not an HSPoint or HSRect
    /// - Example:
    /// ```
    /// new HSPoint(1, 1).vector(new HSPoint(4, 5)) // new HSPoint(3, 4)
    /// ```
    @objc func vector(_ other: JSValue) -> HSPoint
}

@objc class HSPoint: NSObject, HSPointAPI {
    @objc var typeName = "HSPoint"

    @objc func toString() -> String {
        return "<\(typeName): (\(x), \(y))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    var point: CGPoint

    var x: Double {
        get { Double(point.x) }
        set { point.x = CGFloat(newValue) }
    }

    var y: Double {
        get { Double(point.y) }
        set { point.y = CGFloat(newValue) }
    }

    required init(x: Double, y: Double) {
        point = CGPoint(x: x, y: y)
    }

    @objc func angle() -> Double {
        atan2(y, x)
    }

    @objc func angleTo(_ other: JSValue) -> Double {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSPoint: angleTo() requires an HSPoint or HSRect")
            return 0
        }
        return atan2(otherCenter.y - y, otherCenter.x - x)
    }

    @objc func distance(_ other: JSValue) -> Double {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSPoint: distance() requires an HSPoint or HSRect")
            return 0
        }
        let dx = otherCenter.x - x
        let dy = otherCenter.y - y
        return (dx * dx + dy * dy).squareRoot()
    }

    @objc func equals(_ other: HSPoint) -> Bool {
        x == other.x && y == other.y
    }

    @objc func floor() -> HSPoint {
        HSPoint(x: Foundation.floor(x), y: Foundation.floor(y))
    }

    @objc func inside(_ rect: HSRect) -> Bool {
        x >= rect.x && y >= rect.y && x <= rect.x + rect.w && y <= rect.y + rect.h
    }

    @objc func move(_ offset: JSValue) -> HSPoint {
        guard let (dx, dy) = offset.toGeometryOffset() else {
            AKError("HSPoint: move() requires an HSPoint or HSSize")
            return HSPoint(x: x, y: y)
        }
        return HSPoint(x: x + dx, y: y + dy)
    }

    @objc func normalize() -> HSPoint {
        let length = (x * x + y * y).squareRoot()
        guard length > 0 else { return HSPoint(x: 0, y: 0) }
        return HSPoint(x: x / length, y: y / length)
    }

    @objc func rotateCCW(_ aroundPoint: HSPoint, _ times: Int = 1) -> HSPoint {
        var rx = x
        var ry = y
        for _ in 0..<max(times, 0) {
            let previousX = rx
            rx = aroundPoint.x - (ry - aroundPoint.y)
            ry = aroundPoint.y + (previousX - aroundPoint.x)
        }
        return HSPoint(x: rx, y: ry)
    }

    @objc func scale(_ factor: JSValue) -> HSPoint {
        guard let (sx, sy) = factor.toGeometryScaleFactors() else {
            AKError("HSPoint: scale() requires a number, HSSize or HSPoint")
            return HSPoint(x: x, y: y)
        }
        return HSPoint(x: x * sx, y: y * sy)
    }

    @objc func vector(_ other: JSValue) -> HSPoint {
        guard let otherCenter = other.toGeometryCenter() else {
            AKError("HSPoint: vector() requires an HSPoint or HSRect")
            return HSPoint(x: 0, y: 0)
        }
        return HSPoint(x: otherCenter.x - x, y: otherCenter.y - y)
    }
}

// ---------------------------------------------------------------
// MARK: - Conversion Helpers (Bridge Layer)
// ---------------------------------------------------------------

// --- CGPoint <-> HSPoint ---
extension CGPoint: JSConvertible {
    typealias BridgeType = HSPoint

    init(from bridge: HSPoint) {
        self.init(x: bridge.x, y: bridge.y)
    }

    func toBridge() -> HSPoint {
        HSPoint(x: Double(x), y: Double(y))
    }
}


