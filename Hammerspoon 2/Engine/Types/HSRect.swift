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
}

@objc class HSRect: NSObject, HSRectAPI {
    @objc var typeName = "HSRect"
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
