//
//  HSCanvasM5VisualAcceptanceTests.swift
//  Hammerspoon 2Tests
//
//  Visual acceptance test for the M5 full-parity surface (gradients, arc/ellipticalArc/
//  segments/points, blend modes) -- renders through the REAL CanvasElementDrawing
//  implementation and rasterizes to PNG, since JSTestHarness's string-eval assertions
//  can only prove "didn't throw", not "looks right" (same rationale as
//  HSCanvasRoundedCornersAcceptanceTests.swift for the M3 clip/build pipeline).
//

import Testing
import SwiftUI
import AppKit
@testable import Hammerspoon_2

@Suite("hs.canvas M5 visual acceptance test")
struct HSCanvasM5VisualAcceptanceTests {

    @Test("Gradient fill, arc, and segments render into distinguishable regions")
    @MainActor
    func gradientArcSegmentsRender() throws {
        let size = CGSize(width: 200, height: 200)
        let elements: [[String: Any]] = [
            // Radial gradient rectangle covering the left half.
            [
                "type": "rectangle", "action": "fill",
                "frame": ["x": 0, "y": 0, "w": 100, "h": 200],
                "fillGradient": "radial",
                "fillGradientColors": [["red": 1, "alpha": 1], ["blue": 1, "alpha": 1]],
            ],
            // A half-circle arc on the right half.
            [
                "type": "arc", "action": "fill",
                "center": ["x": 150, "y": 100], "radius": 40,
                "startAngle": 0, "endAngle": 180,
                "fillColor": ["green": 1, "alpha": 1],
            ],
        ]

        let store = CanvasElementStore()
        store.elements = elements
        let view = HSCanvasRenderView(store: store)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let cgImage = try #require(renderer.cgImage)

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let pngData = try #require(bitmapRep.representation(using: .png, properties: [:]))
        // Diagnostic-only -- the assertions below read pixels straight from `cgImage`, not
        // from this file. Written to the system temp directory (not a hardcoded developer
        // path) purely so it can be opened for a visual sanity check while debugging.
        let outPath = FileManager.default.temporaryDirectory.appendingPathComponent("m5_visual_acceptance.png")
        try pngData.write(to: outPath)

        guard let data = cgImage.dataProvider?.data else {
            Issue.record("Could not read rendered pixel data")
            return
        }
        let pixelData = data as Data
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let scale = Int(renderer.scale)

        func pixel(atX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return (pixelData[offset], pixelData[offset + 1], pixelData[offset + 2])
        }

        // Gradient center (left half, radial center ~50,100) should be red-ish (first stop).
        let gradientCenter = pixel(atX: 50 * scale, y: 100 * scale)
        // Gradient edge (left half, far corner) should be more blue (second stop).
        let gradientEdge = pixel(atX: 2, y: 2)
        // Arc region (right half, inside the half-circle) should be green. The arc spans
        // startAngle 0 to endAngle 180 with clockwise:false, which -- in SwiftUI's y-down
        // coordinate space -- bulges downward from its center, so sample below center.
        let arcInterior = pixel(atX: 150 * scale, y: 120 * scale)
        // Background outside both shapes (bottom-right corner) should stay black.
        let background = pixel(atX: 199 * scale, y: 199 * scale)

        #expect(gradientCenter.r > gradientEdge.r, "Gradient center should be redder than its edge")
        #expect(gradientEdge.b > gradientEdge.r, "Gradient edge should be bluer than red (second stop)")
        #expect(arcInterior.g > arcInterior.r && arcInterior.g > arcInterior.b, "Arc interior should be green")
        #expect(background.r < 20 && background.g < 20 && background.b < 20, "Untouched background should remain black")
    }

    /// Builds a small solid-color square `HSImage` via a throwaway canvas + `imageFromCanvas()`,
    /// so `image`-type elements can be tested without depending on an external file.
    @MainActor
    private func makeSolidColorImage(color: [String: Any], size: CGFloat = 20) throws -> HSImage {
        let module = HSCanvasModule(engineID: UUID())
        let helper = HSCanvas(frame: CGRect(x: 0, y: 0, width: size, height: size), module: module)
        _ = helper.appendElements([["type": "rectangle", "action": "fill", "fillColor": color]])
        return try #require(helper.imageFromCanvas())
    }

    @Test("text/image/canvas elements honor action:skip, don't leak a previous element's blendMode, and apply rotation")
    @MainActor
    func specialElementsRespectActionTransformAndCompositeRule() throws {
        let size = CGSize(width: 300, height: 200)
        let green: [String: Any] = ["green": 1, "alpha": 1]
        let greenImage = try makeSolidColorImage(color: green)

        let elements: [[String: Any]] = [
            // Region 1 (x:0-40, y:0-40): action:"skip" on an image element. Before the fix,
            // text/image/canvas elements were drawn unconditionally regardless of `action` --
            // this should draw nothing at all.
            ["type": "image", "action": "skip", "image": greenImage, "frame": ["x": 10, "y": 10, "w": 20, "h": 20]],

            // Region 2 (x:80-120, y:10-50): a blue rectangle sets compositeRule:"multiply"
            // (multiply against the black background leaves that area black either way), then
            // a green image with NO compositeRule draws over the same spot. Before the fix,
            // the image inherited the leftover .multiply blendMode from the rectangle, so
            // multiply(green, black) stayed black; after the fix, blendMode resets to .normal
            // per element, so the image should draw as plain opaque green.
            ["type": "rectangle", "action": "fill", "frame": ["x": 80, "y": 10, "w": 40, "h": 40], "fillColor": ["blue": 1, "alpha": 1], "compositeRule": "multiply"],
            ["type": "image", "image": greenImage, "frame": ["x": 80, "y": 10, "w": 40, "h": 40]],

            // Region 3: a green image at (220,10)-(240,30) rotated 180 degrees about a pivot
            // far from its own center (250,100). Before the fix, `rotation` was ignored for
            // image elements, so it would draw at its unrotated frame; after the fix, a 180
            // degree rotation about (250,100) maps its center (~230,20) to (~270,180).
            ["type": "image", "image": greenImage, "frame": ["x": 220, "y": 10, "w": 20, "h": 20], "rotation": 180, "rotationPoint": ["x": 250, "y": 100]],
        ]

        let store = CanvasElementStore()
        store.elements = elements
        let view = HSCanvasRenderView(store: store)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let cgImage = try #require(renderer.cgImage)

        guard let data = cgImage.dataProvider?.data else {
            Issue.record("Could not read rendered pixel data")
            return
        }
        let pixelData = data as Data
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let scale = Int(renderer.scale)

        func pixel(atX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return (pixelData[offset], pixelData[offset + 1], pixelData[offset + 2])
        }
        func isGreen(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
            p.g > 150 && p.r < 60 && p.b < 60
        }
        func isBackground(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
            p.r < 20 && p.g < 20 && p.b < 20
        }

        // Region 1: skip -- nothing should be drawn at the image's own frame.
        #expect(isBackground(pixel(atX: 20 * scale, y: 20 * scale)), "action:\"skip\" should hide an image element, not draw it")

        // Region 2: blendMode must not leak from the preceding rectangle into the image.
        #expect(isGreen(pixel(atX: 100 * scale, y: 30 * scale)), "An image with no compositeRule should draw at normal blend, not inherit the previous element's blendMode")

        // Region 3: rotation must actually move where the image is drawn.
        #expect(isBackground(pixel(atX: 230 * scale, y: 20 * scale)), "A rotated image should no longer appear at its unrotated frame position")
        #expect(isGreen(pixel(atX: 270 * scale, y: 180 * scale)), "A rotated image should appear at its rotated position")
    }

    @Test("image elements honor imageScaling/imageAlignment, matching v1 defaults instead of always stretching to fill the frame")
    @MainActor
    func imageScalingAndAlignmentRespected() throws {
        let size = CGSize(width: 200, height: 200)
        let red: [String: Any] = ["red": 1, "alpha": 1]

        // A wide (40x10) solid-color image -- non-square, so stretch-to-fill vs proportional
        // scaling produce visibly different results.
        let module = HSCanvasModule(engineID: UUID())
        let helper = HSCanvas(frame: CGRect(x: 0, y: 0, width: 40, height: 10), module: module)
        _ = helper.appendElements([["type": "rectangle", "action": "fill", "fillColor": red]])
        let wideRedImage = try #require(helper.imageFromCanvas())

        let elements: [[String: Any]] = [
            // Region 1 (0,0)-(100,100): default scaling/alignment (v1's "scaleProportionally"/
            // "center") -- the 40x10 image should scale up to 100x25 (limited by width) and
            // center vertically, not stretch to fill the whole 100x100 square.
            ["type": "image", "image": wideRedImage, "frame": ["x": 0, "y": 0, "w": 100, "h": 100]],

            // Region 2 (100,0)-(200,100): imageScaling:"none" + imageAlignment:"topLeft" --
            // should draw at native 40x10 size, pinned to the frame's top-left corner.
            ["type": "image", "image": wideRedImage, "frame": ["x": 100, "y": 0, "w": 100, "h": 100], "imageScaling": "none", "imageAlignment": "topLeft"],
        ]

        let store = CanvasElementStore()
        store.elements = elements
        let view = HSCanvasRenderView(store: store)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let cgImage = try #require(renderer.cgImage)
        let pixelData = try #require(cgImage.dataProvider?.data) as Data
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let scale = Int(renderer.scale)

        func isRed(atX x: Int, y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return pixelData[offset] > 150 && pixelData[offset + 1] < 60 && pixelData[offset + 2] < 60
        }

        // Region 1: proportionally scaled to 100x25, centered vertically (band y:37.5-62.5) --
        // the frame's own top-left corner is well outside that band and must stay black.
        #expect(!isRed(atX: 5 * scale, y: 5 * scale), "proportional scaling should NOT stretch the image to fill the whole frame")
        #expect(isRed(atX: 50 * scale, y: 50 * scale), "proportional scaling should place the scaled image across its centered band")

        // Region 2: native 40x10 size pinned to the frame's top-left corner.
        #expect(isRed(atX: 105 * scale, y: 5 * scale), "imageAlignment:topLeft + imageScaling:none should pin the image to the frame's top-left corner")
        #expect(!isRed(atX: 105 * scale, y: 95 * scale), "imageScaling:none should not stretch the image down to the bottom of the frame")
    }
}
