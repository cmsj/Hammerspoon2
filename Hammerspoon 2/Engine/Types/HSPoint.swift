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

@objc protocol HSPointJSExports: JSExport {
    var x: Double { get set }
    var y: Double { get set }
    init(x: Double, y: Double)
}

@objc class HSPoint: NSObject, HSPointJSExports {
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
