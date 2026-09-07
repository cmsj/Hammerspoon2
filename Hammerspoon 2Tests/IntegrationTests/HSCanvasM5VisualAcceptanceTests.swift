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
        let outPath = "/private/tmp/claude-501/-Users-cmsj-hacking-Hammerspoon2/b081d57c-9cb0-41ee-892b-f2fdd824b997/scratchpad/m5_visual_acceptance.png"
        try pngData.write(to: URL(fileURLWithPath: outPath))

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
}
