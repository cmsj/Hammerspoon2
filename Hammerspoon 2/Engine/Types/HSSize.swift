//
//  HSSize.swift
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

/// This is a JavaScript object used to represent the size of a rectangle, as used in various places throughout Hammerspoon's API, particularly where dealing with portions of a display. Behind the scenes it is a wrapper for the CGSize type in Swift/ObjectiveC.
@objc protocol HSSizeAPI: JSExport {
    /// The width of the rectangle
    var w: Double { get set }

    /// The height of the rectangle
    var h: Double { get set }
    
    /// Create a new HSSize object
    /// - Parameters:
    ///   - w: The width of the rectangle
    ///   - h: The height of the rectangle
    init(w: Double, h: Double)
}

@objc class HSSize: NSObject, HSSizeAPI {
    @objc var typeName = "HSSize"
    var size: CGSize

    var w: Double {
        get { Double(size.width) }
        set { size.width = CGFloat(newValue) }
    }

    var h: Double {
        get { Double(size.height) }
        set { size.height = CGFloat(newValue) }
    }

    required init(w: Double, h: Double) {
        size = CGSize(width: w, height: h)
    }
}

// ---------------------------------------------------------------
// MARK: - Conversion Helpers (Bridge Layer)
// ---------------------------------------------------------------

// --- CGSize <-> HSSize ---
extension CGSize: JSConvertible {
    typealias BridgeType = HSSize

    init(from bridge: HSSize) {
        self.init(width: bridge.w, height: bridge.h)
    }

    func toBridge() -> HSSize {
        HSSize(w: Double(width), h: Double(height))
    }
}

// Optional: detect and auto-unbox from JSValue
extension JSValue {
    func toCGSize() -> CGSize? {
        guard let bridge = toObjectOf(HSSize.self) as? HSSize else { return nil }
        return CGSize(from: bridge)
    }
}
