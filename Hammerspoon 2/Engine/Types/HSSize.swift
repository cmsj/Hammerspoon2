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

@objc protocol HSSizeJSExports: JSExport {
    var w: Double { get set }
    var h: Double { get set }
    init(w: Double, h: Double)
}

@objc class HSSize: NSObject, HSSizeJSExports {
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
