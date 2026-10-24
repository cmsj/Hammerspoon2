//
//  HSColor.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import JavaScriptCore
import SwiftUI
import Observation

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
    /// - Parameter hex: Hex string (e.g. "#FF0000", "FF0000", "#F00", or "#FF000080" with alpha)
    /// - Returns: An HSColor object
    @objc static func hex(_ hex: String) -> HSColor

    /// Create a color from a named system color
    /// - Parameter name: Name of the system color (e.g. "red", "blue", "systemBlue")
    /// - Returns: An HSColor object
    @objc static func named(_ name: String) -> HSColor

    /// Update this color's value.
    ///
    /// If this color is bound to a UI element, the canvas re-renders automatically.
    /// - Parameter value: {string | HSColor} A hex color string (e.g. "#FF0000") or another HSColor object
    /// - Example:
    /// ```js
    /// const reactive = HSColor.hex("#4A90E2")
    /// reactive.set("#E24A4A")
    /// reactive.set(HSColor.named("red"))
    /// ```
    @objc func set(_ value: JSValue)

    /// Returns a plain object containing this color's sRGB components, for JSON serialisation
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with `red`, `green`, `blue` and `alpha` properties, each between 0.0 and 1.0, matching the arguments of `HSColor.rgb()`
    /// - Example:
    /// ```js
    /// JSON.stringify(HSColor.rgb(1, 0, 0, 0.5)) // '{"red":1,"green":0,"blue":0,"alpha":0.5}'
    /// ```
    @objc func toJSON() -> [String: Any]
}

@Observable
@objc class HSColor: NSObject, HSColorAPI {
    @objc var typeName = "HSColor"

    @objc func toString() -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(ns.redComponent * 255)
        let g = Int(ns.greenComponent * 255)
        let b = Int(ns.blueComponent * 255)
        return unsafe "<\(typeName): #\(String(format: "%02X%02X%02X", r, g, b))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func toJSON() -> [String: Any] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return [
            "red": Double(ns.redComponent),
            "green": Double(ns.greenComponent),
            "blue": Double(ns.blueComponent),
            "alpha": Double(ns.alphaComponent),
        ]
    }

    var color: Color

    /// The colour for AppKit APIs
    var nsColor: NSColor { NSColor(color) }

    init(color: Color) {
        self.color = color
        super.init()
    }

    // MARK: - Factory Methods

    @objc static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> HSColor {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a).toBridge()
    }

    @objc static func hex(_ hex: String) -> HSColor {
        guard let color = parseHex(hex) else {
            AKError("hs.ui: Invalid hex color: \(hex), using black")
            return Color.black.toBridge()
        }
        return color.toBridge()
    }

    /// Parses a `#RGB`, `#RRGGBB` or `#RRGGBBAA` hex string (the `#` is optional), or returns
    /// `nil` if it isn't one
    static func parseHex(_ hex: String) -> Color? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }
        // ASCII only: Character.isHexDigit also accepts fullwidth digits, which Scanner stops at
        guard hexSanitized.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if hexSanitized.count == 3 {
            hexSanitized = String(hexSanitized.flatMap { [$0, $0] })
        }

        var rgb: UInt64 = 0
        guard unsafe Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        default:
            return nil
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
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

    // MARK: - Reactive Mutation

    @objc func set(_ value: JSValue) {
        if let newColor = HSColor.fromJSValue(value) {
            color = newColor.color
        }
    }

    // MARK: - Helper Methods

    /// The AppKit colour for an HSColor or a valid hex string, or nil for anything else. Unlike
    /// `fromJSValue`, an invalid hex string is rejected rather than turned into black.
    static func nsColor(from value: JSValue) -> NSColor? {
        if value.isString {
            return value.toString().flatMap(parseHex).map { NSColor($0) }
        }
        return (value.toObjectOf(HSColor.self) as? HSColor)?.nsColor
    }

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
