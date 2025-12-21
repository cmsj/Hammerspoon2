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
}

@objc class HSPoint: NSObject, HSPointAPI {
    @objc var typeName = "HSPoint"
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

// Optional: detect and auto-unbox from JSValue
extension JSValue {
    func toCGPoint() -> CGPoint? {
        guard let bridge = toObjectOf(HSPoint.self) as? HSPoint else { return nil }
        return CGPoint(from: bridge)
    }
}
