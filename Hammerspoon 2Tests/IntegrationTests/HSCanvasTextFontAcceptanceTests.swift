//
//  HSCanvasTextFontAcceptanceTests.swift
//  Hammerspoon 2Tests
//
//  Visual acceptance tests for text-element font control (textFont/textWeight/textDesign/
//  textItalic) -- renders through the REAL CanvasElementDrawing implementation and inspects
//  pixels, since a string-eval test can only prove "didn't throw", not "actually changed
//  the rendered font" (same rationale as HSCanvasM5VisualAcceptanceTests.swift).
//

import Testing
import SwiftUI
import AppKit
@testable import Hammerspoon_2

@Suite("hs.canvas text font acceptance tests")
struct HSCanvasTextFontAcceptanceTests {

    /// Renders a single text element and returns its rasterized pixel buffer plus the
    /// geometry needed to read pixels back out of it.
    @MainActor
    private func render(_ element: [String: Any], size: CGSize = CGSize(width: 200, height: 80)) throws -> (data: Data, bytesPerPixel: Int, bytesPerRow: Int, scale: Int) {
        let store = CanvasElementStore()
        store.elements = [element]
        let view = HSCanvasRenderView(store: store)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let cgImage = try #require(renderer.cgImage)
        let data = try #require(cgImage.dataProvider?.data) as Data
        return (data, cgImage.bitsPerPixel / 8, cgImage.bytesPerRow, Int(renderer.scale))
    }

    /// Counts "ink" pixels (anything visibly lighter than the black background) in a
    /// rendered buffer -- a proxy for how much of the glyph area is filled in, which rises
    /// with font weight.
    private func inkPixelCount(_ buffer: (data: Data, bytesPerPixel: Int, bytesPerRow: Int, scale: Int), width: Int, height: Int) -> Int {
        var count = 0
        for y in 0..<(height * buffer.scale) {
            for x in 0..<(width * buffer.scale) {
                let offset = y * buffer.bytesPerRow + x * buffer.bytesPerPixel
                if buffer.data[offset] > 40 { count += 1 }
            }
        }
        return count
    }

    @Test("textWeight: bold produces measurably more ink than regular for the same string/size")
    @MainActor
    func boldHasMoreInkThanRegular() throws {
        let base: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1]]

        var regular = base
        regular["textWeight"] = "regular"
        let regularBuffer = try render(regular)
        let regularInk = inkPixelCount(regularBuffer, width: 200, height: 80)

        var bold = base
        bold["textWeight"] = "black"
        let boldBuffer = try render(bold)
        let boldInk = inkPixelCount(boldBuffer, width: 200, height: 80)

        #expect(boldInk > regularInk, "black weight should render with more ink coverage than regular")
    }

    @Test("textDesign: monospaced gives 'i' and 'm' runs equal width, unlike the default design")
    @MainActor
    func monospacedDesignEqualizesGlyphWidths() throws {
        func rightmostInkColumn(text: String, design: String?) throws -> Int {
            var element: [String: Any] = ["type": "text", "text": text, "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1]]
            if let design { element["textDesign"] = design }
            let buffer = try render(element)
            var rightmost = 0
            for y in 0..<(80 * buffer.scale) {
                for x in stride(from: 200 * buffer.scale - 1, through: 0, by: -1) {
                    let offset = y * buffer.bytesPerRow + x * buffer.bytesPerPixel
                    if buffer.data[offset] > 40 {
                        rightmost = max(rightmost, x)
                        break
                    }
                }
            }
            return rightmost
        }

        let defaultIWidth = try rightmostInkColumn(text: "iiiiii", design: nil)
        let defaultMWidth = try rightmostInkColumn(text: "mmmmmm", design: nil)
        #expect(defaultMWidth > defaultIWidth, "sanity check: the default design should NOT give 'i' and 'm' the same width")

        let monoIWidth = try rightmostInkColumn(text: "iiiiii", design: "monospaced")
        let monoMWidth = try rightmostInkColumn(text: "mmmmmm", design: "monospaced")
        #expect(abs(monoIWidth - monoMWidth) < abs(defaultMWidth - defaultIWidth), "monospaced design should equalize 'i' and 'm' run widths relative to the default design")
    }

    @Test("textItalic slants the glyphs, changing the rendered pixels")
    @MainActor
    func italicChangesRenderedPixels() throws {
        let base: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1]]

        var upright = base
        upright["textItalic"] = false
        let uprightBuffer = try render(upright)

        var italic = base
        italic["textItalic"] = true
        let italicBuffer = try render(italic)

        #expect(uprightBuffer.data != italicBuffer.data, "textItalic:true should render different pixels than textItalic:false")
    }

    @Test("an unresolvable textFont falls back to rendering the system font instead of blank/crashing")
    @MainActor
    func unresolvableFontFallsBackInsteadOfCrashing() throws {
        let element: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textFont": "Definitely Not An Installed Font Name"]
        let buffer = try render(element)
        #expect(inkPixelCount(buffer, width: 200, height: 80) > 0, "an unresolvable textFont should still render visible text via SwiftUI's fallback, not blank output")
    }

    @Test("textFont set alongside textWeight/textDesign renders identically to textFont alone")
    @MainActor
    func customFontIgnoresWeightAndDesign() throws {
        let base: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textFont": "Menlo-Bold"]

        let plainBuffer = try render(base)

        var withExtras = base
        withExtras["textWeight"] = "thin"
        withExtras["textDesign"] = "rounded"
        let extrasBuffer = try render(withExtras)

        #expect(plainBuffer.data == extrasBuffer.data, "textWeight/textDesign should be ignored once textFont names a custom font")
    }
}
