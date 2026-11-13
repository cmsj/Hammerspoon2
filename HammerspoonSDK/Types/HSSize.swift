//
//  HSSize.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 04/11/2025.
//

import Foundation
import JavaScriptCore
import CoreGraphics

// ---------------------------------------------------------------
// MARK: - Existing Bridge Classes (from before)
// ---------------------------------------------------------------

/// This is a JavaScript object used to represent the size of a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGSize type in Swift/ObjectiveC.
@objc public protocol HSSizeAPI: HSTypeAPI, JSExport {
    /// The width of the rectangle
    var w: Double { get set }

    /// The height of the rectangle
    var h: Double { get set }

    /// Create a new HSSize object
    /// - Parameters:
    ///   - w: The width of the rectangle
    ///   - h: The height of the rectangle
    init(w: Double, h: Double)

    /// Returns the angle between the positive x axis and this size, treated as a vector of (w, h)
    /// - Returns: A number containing the angle in radians
    /// - Example:
    /// ```
    /// new HSSize(1, 1).angle() // 0.7853981633974483 (pi/4)
    /// ```
    @objc func angle() -> Double

    /// Checks if this size is equal to another size
    /// - Parameter other: An HSSize to compare against
    /// - Returns: `true` if both sizes have the same width and height, otherwise `false`
    /// - Example:
    /// ```
    /// new HSSize(10, 20).equals(new HSSize(10, 20)) // true
    /// ```
    @objc func equals(_ other: HSSize) -> Bool

    /// Truncates the width and height of this size towards negative infinity
    /// - Returns: A new HSSize with the w and h values floored to the nearest integer
    /// - Example:
    /// ```
    /// new HSSize(10.9, 20.1).floor() // new HSSize(10, 20)
    /// ```
    @objc func floor() -> HSSize

    /// Scales this size
    /// - Parameter factor: {number | HSSize | HSPoint} A number to scale both dimensions uniformly, or an HSSize/HSPoint to scale the width and height independently
    /// - Returns: A new HSSize scaled by the given factor, or an unchanged copy of this size if `factor` is not a number, HSSize or HSPoint
    /// - Example:
    /// ```
    /// new HSSize(10, 20).scale(2) // new HSSize(20, 40)
    /// ```
    @objc func scale(_ factor: JSValue) -> HSSize

    /// Returns a plain object containing this size's dimensions, for JSON serialisation
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with `w` and `h` properties
    /// - Example:
    /// ```js
    /// JSON.stringify(new HSSize(100, 50)) // '{"w":100,"h":50}'
    /// ```
    @objc func toJSON() -> [String: Any]
}

@objc public class HSSize: NSObject, HSSizeAPI {
    @objc public var typeName = "HSSize"

    @objc public func toString() -> String {
        return "<\(typeName): \(w)x\(h)>"
    }

    public nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc public func toJSON() -> [String: Any] {
        ["w": w, "h": h]
    }

    public var size: CGSize

    public var w: Double {
        get { Double(size.width) }
        set { size.width = CGFloat(newValue) }
    }

    public var h: Double {
        get { Double(size.height) }
        set { size.height = CGFloat(newValue) }
    }

    public required init(w: Double, h: Double) {
        size = CGSize(width: w, height: h)
    }

    @objc public func angle() -> Double {
        atan2(h, w)
    }

    @objc public func equals(_ other: HSSize) -> Bool {
        w == other.w && h == other.h
    }

    @objc public func floor() -> HSSize {
        HSSize(w: Foundation.floor(w), h: Foundation.floor(h))
    }

    @objc public func scale(_ factor: JSValue) -> HSSize {
        guard let (sx, sy) = factor.toGeometryScaleFactors() else {
            AKError("HSSize: scale() requires a number, HSSize or HSPoint")
            return HSSize(w: w, h: h)
        }
        return HSSize(w: w * sx, h: h * sy)
    }
}

// ---------------------------------------------------------------
// MARK: - Conversion Helpers (Bridge Layer)
// ---------------------------------------------------------------

// --- CGSize <-> HSSize ---
extension CGSize: JSConvertible {
    public typealias BridgeType = HSSize

    public init(from bridge: HSSize) {
        self.init(width: bridge.w, height: bridge.h)
    }

    public func toBridge() -> HSSize {
        HSSize(w: Double(width), h: Double(height))
    }
}
