//
//  HSGeometryJSValue.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 27/08/2026.
//

import Foundation
import JavaScriptCore
import CoreGraphics

// ---------------------------------------------------------------
// MARK: - JSValue Convenience Extensions for Geometry Methods
// ---------------------------------------------------------------
//
// Several hs.geometry-style methods (angleTo, distance, vector, move, scale)
// accept more than one concrete type from JavaScript (e.g. an HSPoint or an
// HSRect's center; a plain number or an HSSize). These helpers centralize
// that flexible resolution so each type's methods stay simple.

extension JSValue {
    /// Resolves this JSValue to a center point, accepting either an HSPoint (its x/y) or an HSRect (the midpoint of its bounds)
    func toGeometryCenter() -> CGPoint? {
        if let point = toObjectOf(HSPoint.self) as? HSPoint {
            return CGPoint(from: point)
        } else if let rect = toObjectOf(HSRect.self) as? HSRect {
            let r = CGRect(from: rect)
            return CGPoint(x: r.midX, y: r.midY)
        }
        return nil
    }

    /// Resolves this JSValue to an (dx, dy) offset, accepting either an HSPoint (its x/y) or an HSSize (its w/h)
    func toGeometryOffset() -> (dx: Double, dy: Double)? {
        if let point = toObjectOf(HSPoint.self) as? HSPoint {
            return (point.x, point.y)
        } else if let size = toObjectOf(HSSize.self) as? HSSize {
            return (size.w, size.h)
        }
        return nil
    }

    /// Resolves this JSValue to an (sx, sy) scale factor pair, accepting a number (uniform scale), an HSSize (independent w/h scale), or an HSPoint (independent x/y scale)
    func toGeometryScaleFactors() -> (sx: Double, sy: Double)? {
        if isNumber {
            let factor = toDouble()
            return (factor, factor)
        } else if let size = toObjectOf(HSSize.self) as? HSSize {
            return (size.w, size.h)
        } else if let point = toObjectOf(HSPoint.self) as? HSPoint {
            return (point.x, point.y)
        }
        return nil
    }
}
