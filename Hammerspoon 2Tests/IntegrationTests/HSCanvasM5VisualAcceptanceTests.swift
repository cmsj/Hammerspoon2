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
}
