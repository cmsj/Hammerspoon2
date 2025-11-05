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

@objc protocol HSRectJSExports: JSExport {
    var x: Double { get set }
    var y: Double { get set }
    var w: Double { get set }
    var h: Double { get set }
    var origin: HSPoint { get set }
    var size: HSSize { get set }

    init(x: Double, y: Double, w: Double, h: Double)
}

@objc class HSRect: NSObject, HSRectJSExports {
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

// Optional: detect and auto-unbox from JSValue
extension JSValue {
    func toCGRect() -> CGRect? {
        guard let bridge = toObjectOf(HSRect.self) as? HSRect else { return nil }
        return CGRect(from: bridge)
    }
}
