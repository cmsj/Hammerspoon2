//
//  HSCanvasTextFontAcceptanceTests.swift
//  Hammerspoon 2Tests
//
//  Visual acceptance tests for text-element font control (textFont/textWeight/textDesign/
//  textItalic/textAlignment/textLineBreak) -- renders through the REAL CanvasElementDrawing
//  implementation and inspects pixels, since a string-eval test can only prove "didn't
//  throw", not "actually changed the rendered font" (same rationale as
//  HSCanvasM5VisualAcceptanceTests.swift).
//

import Testing
import SwiftUI
import AppKit
@testable import Hammerspoon_2

@Suite("hs.canvas text font acceptance tests")
struct HSCanvasTextFontAcceptanceTests {

    /// Renders a single text element and returns the rasterized `CGImage`.
    @MainActor
    private func render(_ element: [String: Any], size: CGSize = CGSize(width: 200, height: 80)) throws -> CGImage {
        let store = CanvasElementStore()
        store.elements = [element]
        let view = HSCanvasRenderView(store: store)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return try #require(renderer.cgImage)
    }

    /// Raw pixel bytes, for exact byte-identity comparisons where the actual pixel format
    /// doesn't matter -- just whether two renders produced the same bytes or not.
    private func pixelData(_ image: CGImage) throws -> Data {
        try #require(image.dataProvider?.data) as Data
    }

    /// Reads a pixel's red channel (0...1) via `NSBitmapImageRep.colorAt` rather than poking
    /// raw bytes -- text rendered through the AppKit rasterization path in `drawText` can
    /// come back as a 16-bit-per-component "extended range" `CGImage` (64 bits/pixel), not
    /// the 8-bit-per-component RGBA a naive `data[byteOffset] > threshold` read assumes;
    /// `colorAt` normalizes any of that away.
    private func redChannel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.redComponent ?? 0
    }

    /// Counts "ink" pixels (anything visibly lighter than the black background) in a
    /// rendered image -- a proxy for how much of the glyph area is filled in, which rises
    /// with font weight.
    private func inkPixelCount(_ image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if redChannel(bitmap, x: x, y: y) > 0.15 { count += 1 }
            }
        }
        return count
    }

    @Test("textWeight: bold produces measurably more ink than regular for the same string/size")
    @MainActor
    func boldHasMoreInkThanRegular() throws {
        // The frame is now a hard clip boundary (matching v1's NSString.drawInRect:, which
        // this module rasterizes through) -- wide enough that neither weight's render of
        // "Hammerspoon" at this size can clip, or a heavier (wider) weight could measure as
        // LESS ink than a narrower one simply because more of it fell outside the frame.
        let base: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 500, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1]]
        let size = CGSize(width: 500, height: 80)

        var regular = base
        regular["textWeight"] = "regular"
        let regularInk = inkPixelCount(try render(regular, size: size))

        var bold = base
        bold["textWeight"] = "black"
        let boldInk = inkPixelCount(try render(bold, size: size))

        #expect(boldInk > regularInk, "black weight should render with more ink coverage than regular")
    }

    @Test("textDesign: monospaced gives 'i' and 'm' runs equal width, unlike the default design")
    @MainActor
    func monospacedDesignEqualizesGlyphWidths() throws {
        // Wide enough that the frame (a hard clip boundary, since this rasterizes through
        // NSString.drawInRect:) can't itself pin "rightmost ink column" at the clip edge.
        func rightmostInkColumn(text: String, design: String?) throws -> Int {
            var element: [String: Any] = ["type": "text", "text": text, "frame": ["x": 0, "y": 0, "w": 300, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1]]
            if let design { element["textDesign"] = design }
            let bitmap = NSBitmapImageRep(cgImage: try render(element, size: CGSize(width: 300, height: 80)))
            var rightmost = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in stride(from: bitmap.pixelsWide - 1, through: 0, by: -1) {
                    if redChannel(bitmap, x: x, y: y) > 0.15 {
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
        let uprightData = try pixelData(try render(upright))

        var italic = base
        italic["textItalic"] = true
        let italicData = try pixelData(try render(italic))

        #expect(uprightData != italicData, "textItalic:true should render different pixels than textItalic:false")
    }

    @Test("an unresolvable textFont falls back to rendering the system font instead of blank/crashing")
    @MainActor
    func unresolvableFontFallsBackInsteadOfCrashing() throws {
        let element: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textFont": "Definitely Not An Installed Font Name"]
        #expect(inkPixelCount(try render(element)) > 0, "an unresolvable textFont should still render visible text via the system font fallback, not blank output")
    }

    @Test("textFont set alongside textWeight/textDesign renders identically to textFont alone")
    @MainActor
    func customFontIgnoresWeightAndDesign() throws {
        let base: [String: Any] = ["type": "text", "text": "Hammerspoon", "frame": ["x": 0, "y": 0, "w": 200, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textFont": "Menlo-Bold"]

        let plainData = try pixelData(try render(base))

        var withExtras = base
        withExtras["textWeight"] = "thin"
        withExtras["textDesign"] = "rounded"
        let extrasData = try pixelData(try render(withExtras))

        #expect(plainData == extrasData, "textWeight/textDesign should be ignored once textFont names a custom font")
    }

    @Test("textAlignment: right-aligned text sits further right than left-aligned text in the same frame")
    @MainActor
    func textAlignmentAffectsHorizontalPosition() throws {
        func leftmostInkColumn(alignment: String) throws -> Int {
            let element: [String: Any] = ["type": "text", "text": "Hi", "frame": ["x": 0, "y": 0, "w": 400, "h": 80], "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textAlignment": alignment]
            let bitmap = NSBitmapImageRep(cgImage: try render(element, size: CGSize(width: 400, height: 80)))
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh where redChannel(bitmap, x: x, y: y) > 0.15 {
                    return x
                }
            }
            return -1
        }

        let leftX = try leftmostInkColumn(alignment: "left")
        let rightX = try leftmostInkColumn(alignment: "right")
        let centerX = try leftmostInkColumn(alignment: "center")

        #expect(leftX >= 0 && rightX >= 0 && centerX >= 0, "should find ink for all three alignments")
        #expect(rightX > centerX && centerX > leftX, "right-aligned ink should start further right than center, which should start further right than left")
    }

    @Test("textLineBreak: wordWrap grows taller than a single-line truncation mode for overflowing text")
    @MainActor
    func textLineBreakAffectsWrapping() throws {
        func inkRowCount(lineBreak: String) throws -> Int {
            // Long enough, and narrow enough, that it cannot fit on one line at this size.
            let element: [String: Any] = ["type": "text", "text": "Hammerspoon Hammerspoon Hammerspoon", "frame": ["x": 0, "y": 0, "w": 150, "h": 200], "textSize": 24, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textLineBreak": lineBreak]
            let bitmap = NSBitmapImageRep(cgImage: try render(element, size: CGSize(width: 150, height: 200)))
            var lastInkRow = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where redChannel(bitmap, x: x, y: y) > 0.15 {
                    lastInkRow = max(lastInkRow, y)
                    break
                }
            }
            return lastInkRow
        }

        let wrappedExtent = try inkRowCount(lineBreak: "wordWrap")
        let truncatedExtent = try inkRowCount(lineBreak: "truncateTail")

        #expect(wrappedExtent > truncatedExtent, "wordWrap should spread overflowing text across multiple lines (more vertical extent) while truncateTail keeps it to one line")
    }

    @Test("a frame-less text element (defaulting to the whole canvas) still aligns correctly, using the shrunk-rasterization fast path")
    @MainActor
    func frameLessTextStillAligns() throws {
        // No "frame" key -- resolveFrame() falls back to the full container size, which is
        // exactly the "text element without its own frame uses the entire canvas" case that
        // motivated shrinking the rasterized image to the text's natural size rather than
        // always rasterizing at the full (here, deliberately huge) frame.
        func leftmostInkColumn(alignment: String) throws -> Int {
            let element: [String: Any] = ["type": "text", "text": "Hi", "textSize": 32, "textColor": ["red": 1, "green": 1, "blue": 1, "alpha": 1], "textAlignment": alignment]
            let bitmap = NSBitmapImageRep(cgImage: try render(element, size: CGSize(width: 900, height: 80)))
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh where redChannel(bitmap, x: x, y: y) > 0.15 {
                    return x
                }
            }
            return -1
        }

        let leftX = try leftmostInkColumn(alignment: "left")
        let rightX = try leftmostInkColumn(alignment: "right")
        let centerX = try leftmostInkColumn(alignment: "center")

        #expect(leftX >= 0 && rightX >= 0 && centerX >= 0, "should find ink for all three alignments")
        #expect(rightX > centerX && centerX > leftX, "alignment should still be positioned relative to the whole (frame-less) canvas width, not just the shrunk text's own natural width")
    }
}
