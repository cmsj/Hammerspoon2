//
//  Font.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/11/2025.
//

import Foundation
import JavaScriptCore
import SwiftUI

/// This is a JavaScript object used to represent macOS fonts. It includes a variety of static methods that can instantiate the various font sizes commonly used with UI elements, and also includes static methods for instantiating the system font at various sizes/weights, or any custom font available on the system.
@objc protocol HSFontAPI: HSTypeAPI, JSExport {
    /// Body text style
    /// - Returns: An HSFont object
    @objc static func body() -> HSFont

    /// Callout text style
    /// - Returns: An HSFont object
    @objc static func callout() -> HSFont

    /// Caption text style
    /// - Returns: An HSFont object
    @objc static func caption() -> HSFont

    /// Caption2 text style
    /// - Returns: An HSFont object
    @objc static func caption2() -> HSFont

    /// Footnote text style
    /// - Returns: An HSFont object
    @objc static func footnote() -> HSFont

    /// Headline text style
    /// - Returns: An HSFont object
    @objc static func headline() -> HSFont

    /// Large Title text style
    /// - Returns: An HSFont object
    @objc static func largeTitle() -> HSFont

    /// Sub-headline text style
    /// - Returns: An HSFont object
    @objc static func subheadline() -> HSFont

    /// Title text style
    /// - Returns: An HSFont object
    @objc static func title() -> HSFont

    /// Title2 text style
    /// - Returns: An HSFont object
    @objc static func title2() -> HSFont

    /// Title3 text style
    /// - Returns: An HSFont object
    @objc static func title3() -> HSFont

    /// The system font in a custom size
    /// - Parameter size: The font size in points
    /// - Returns: An HSFont object
    @objc static func system(_ size: Double) -> HSFont
    
    /// The system font in a custom size with a choice of weights
    /// - Parameters:
    ///   - size: The font size in points
    ///   - weight: The font weight as a string (e.g. "ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black")
    /// - Returns: An HSFont object
    @objc static func system(_ size: Double, weight: String) -> HSFont

    /// A font present on the system at a given size
    /// - Parameters:
    ///   - name: A string containing the name of the font to instantiate
    ///   - size: The font size in points
    /// - Returns: An HSFont object
    @objc static func custom(_ name: String, size: Double) -> HSFont
}

@objc class HSFont: NSObject, HSFontAPI {
    @objc var typeName = "HSFont"
    var font: Font

    private init(font: Font) {
        self.font = font
        super.init()
    }

    // MARK: - Text Styles

    @objc static func body() -> HSFont {
        HSFont(font: .body)
    }

    @objc static func callout() -> HSFont {
        HSFont(font: .callout)
    }

    @objc static func caption() -> HSFont {
        HSFont(font: .caption)
    }

    @objc static func caption2() -> HSFont {
        HSFont(font: .caption2)
    }

    @objc static func footnote() -> HSFont {
        HSFont(font: .footnote)
    }

    @objc static func headline() -> HSFont {
        HSFont(font: .headline)
    }

    @objc static func largeTitle() -> HSFont {
        HSFont(font: .largeTitle)
    }

    @objc static func subheadline() -> HSFont {
        HSFont(font: .subheadline)
    }

    @objc static func title() -> HSFont {
        HSFont(font: .title)
    }

    @objc static func title2() -> HSFont {
        HSFont(font: .title2)
    }

    @objc static func title3() -> HSFont {
        HSFont(font: .title3)
    }

    // MARK: - System Fonts

    @objc static func system(_ size: Double) -> HSFont {
        HSFont(font: .system(size: size))
    }

    @objc static func system(_ size: Double, weight: String) -> HSFont {
        let fontWeight: Font.Weight
        switch weight.lowercased() {
        case "ultralight":
            fontWeight = .ultraLight
        case "thin":
            fontWeight = .thin
        case "light":
            fontWeight = .light
        case "regular":
            fontWeight = .regular
        case "medium":
            fontWeight = .medium
        case "semibold":
            fontWeight = .semibold
        case "bold":
            fontWeight = .bold
        case "heavy":
            fontWeight = .heavy
        case "black":
            fontWeight = .black
        default:
            AKError("Unknown font weight: \(weight), using regular")
            fontWeight = .regular
        }
        return HSFont(font: .system(size: size, weight: fontWeight))
    }

    // MARK: - Custom Fonts

    @objc static func custom(_ name: String, size: Double) -> HSFont {
        HSFont(font: .custom(name, size: size))
    }
}
