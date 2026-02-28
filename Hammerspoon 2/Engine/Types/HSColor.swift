//
//  HSColor.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import SwiftUI

// ---------------------------------------------------------------
// MARK: - Bridge Class (JavaScript Interface)
// ---------------------------------------------------------------

/// Bridge type for working with colors in JavaScript
@objc protocol HSColorAPI: HSTypeAPI, JSExport {
    /// Create a color from RGB values
    /// - Parameters:
    ///   - r: Red component (0.0-1.0)
    ///   - g: Green component (0.0-1.0)
    ///   - b: Blue component (0.0-1.0)
    ///   - a: Alpha component (0.0-1.0)
    /// - Returns: An HSColor object
    @objc static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> HSColor

    /// Create a color from a hex string
    /// - Parameter hex: Hex string (e.g. "#FF0000" or "FF0000")
    /// - Returns: An HSColor object
    @objc static func hex(_ hex: String) -> HSColor

    /// Create a color from a named system color
    /// - Parameter name: Name of the system color (e.g. "red", "blue", "systemBlue")
    /// - Returns: An HSColor object
    @objc static func named(_ name: String) -> HSColor

    /// Update this color's value
    /// - Parameter value: New color as a hex string (e.g. "#FF0000") or another HSColor object
    @objc func set(_ value: JSValue)
}

@objc class HSColor: NSObject, HSColorAPI {
    @objc var typeName = "HSColor"
    weak var delegate: (any HSUIElementDelegate)?

    var color: Color {
        didSet { delegate?.valueDidChange() }
    }

    init(color: Color) {
        self.color = color
        super.init()
    }

    // MARK: - Factory Methods

    @objc static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> HSColor {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a).toBridge()
    }

    @objc static func hex(_ hex: String) -> HSColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard unsafe Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            AKError("hs.ui: Invalid hex color: \(hex), using black")
            return Color.black.toBridge()
        }

        let length = hexSanitized.count
        let r, g, b, a: Double

        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            AKError("hs.ui: Invalid hex color length: \(hex), using black")
            return Color.black.toBridge()
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a).toBridge()
    }

    @objc static func named(_ name: String) -> HSColor {
        let color: Color

        switch name.lowercased() {
        case "black": color = .black
        case "white": color = .white
        case "red": color = .red
        case "green": color = .green
        case "blue": color = .blue
        case "yellow": color = .yellow
        case "orange": color = .orange
        case "purple": color = .purple
        case "pink": color = .pink
        case "gray", "grey": color = .gray
        case "clear": color = .clear
        default:
            AKError("hs.ui: Unknown color name: \(name), using black")
            color = .black
        }

        return color.toBridge()
    }

    // MARK: - Mutation

    @objc func set(_ value: JSValue) {
        if let newColor = HSColor.fromJSValue(value) {
            color = newColor.color
        }
    }

    // MARK: - Helper Methods

    /// Create an HSColor from a JSValue (supports hex strings or HSColor objects)
    static func fromJSValue(_ value: JSValue) -> HSColor? {
        if value.isString, let hexString = value.toString() {
            return HSColor.hex(hexString)
        } else if let color = value.toObjectOf(HSColor.self) as? HSColor {
            return color
        }
        return nil
    }
}

// ---------------------------------------------------------------
// MARK: - JSConvertible Extension (Bridge Layer)
// ---------------------------------------------------------------

extension Color: JSConvertible {
    typealias BridgeType = HSColor

    init(from bridge: HSColor) {
        self = bridge.color
    }

    func toBridge() -> HSColor {
        HSColor(color: self)
    }
}

// ---------------------------------------------------------------
// MARK: - JSValue Convenience Extension
// ---------------------------------------------------------------

extension JSValue {
    /// Convert a JSValue to a SwiftUI Color
    /// Supports:
    /// - HSColor objects
    /// - Hex strings (e.g. "#FF0000" or "FF0000")
    func toColor() -> Color? {
        if let bridge = HSColor.fromJSValue(self) {
            return Color(from: bridge)
        }
        return nil
    }
}
