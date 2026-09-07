//
//  HSCanvasRoundedCornersAcceptanceTests.swift
//  Hammerspoon 2Tests
//
//  Acceptance test for the hs.canvas plan (~/.claude/plans/melodic-discovering-garden.md):
//  reproduces RoundedCorners.spoon's exact element sequence (build rectangle -> clip
//  circle with reversePath -> fill -> resetClip) through the REAL CanvasElementDrawing
//  implementation (not the JS bridge -- JSTestHarness's string-eval assertions can't
//  verify rendered pixels), and rasterizes it to PNG for visual confirmation. This is
//  the concrete gap the user hit trying to port RoundedCorners to hs.ui, so it's the
//  concrete proof hs.canvas closes it.
//

import Testing
import SwiftUI
import AppKit
@testable import Hammerspoon_2

@Suite("hs.canvas RoundedCorners acceptance test")
struct HSCanvasRoundedCornersAcceptanceTests {

    @Test("RoundedCorners.spoon's element sequence renders a punched quarter-circle corner")
    @MainActor
    func roundedCornersRenders() throws {
        let radius: CGFloat = 40
        // Mirrors RoundedCorners.spoon's cornerData for the top-left screen corner:
        // { frame={x=screenFrame.x, y=screenFrame.y}, center={x=radius, y=radius} }
        let elements: [[String: Any]] = [
            ["action": "build", "type": "rectangle"],
            [
                "action": "clip", "type": "circle",
                "center": ["x": radius, "y": radius], "radius": radius,
                "reversePath": true,
            ],
            [
                "action": "fill", "type": "rectangle",
                "frame": ["x": 0, "y": 0, "w": radius, "h": radius],
                "fillColor": ["alpha": 1],
            ],
            ["type": "resetClip"],
        ]

        let view = HSCanvasRenderView(store: {
            let store = CanvasElementStore()
            store.elements = elements
            return store
        }())
        .frame(width: radius, height: radius)
        .background(Color.green.opacity(0.5)) // so the punched-out hole is visible in the PNG

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        let cgImage = try #require(renderer.cgImage, "ImageRenderer produced no CGImage")
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let pngData = try #require(bitmapRep.representation(using: .png, properties: [:]))

        let outPath = "/private/tmp/claude-501/-Users-cmsj-hacking-Hammerspoon2/b081d57c-9cb0-41ee-892b-f2fdd824b997/scratchpad/roundedcorners_acceptance.png"
        try pngData.write(to: URL(fileURLWithPath: outPath))

        // Programmatic check mirroring the visual one: sample the pixel at the exact
        // circle center (should be punched out -> background color, i.e. NOT opaque
        // black) vs. a pixel in the far corner (should remain opaque black fill).
        guard let dataProvider = cgImage.dataProvider, let data = dataProvider.data else {
            Issue.record("Could not read rendered pixel data")
            return
        }
        let pixelData = data as Data
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        func pixel(atX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return (pixelData[offset], pixelData[offset + 1], pixelData[offset + 2], pixelData[offset + 3])
        }

        // The circle is centered at (radius, radius) -- the box's far corner from the
        // origin -- matching RoundedCorners' cornerData for the top-left screen corner.
        // So the actual screen-corner sliver near the box's origin (0,0) is OUTSIDE the
        // circle and should stay solid black fill (the visible corner mask), while the
        // area near the circle's center is INSIDE it and should be punched out (clipped
        // away), revealing the background -- that punched quarter-disk is what makes the
        // corner look rounded.
        let scale = Int(renderer.scale)
        let nearOrigin = pixel(atX: 2 * scale, y: 2 * scale)
        let nearCircleCenter = pixel(atX: Int(radius) * scale - 2, y: Int(radius) * scale - 2)

        let nearOriginIsBlack = nearOrigin.r < 20 && nearOrigin.g < 20 && nearOrigin.b < 20 && nearOrigin.a > 200
        let nearCircleCenterIsBlack = nearCircleCenter.r < 20 && nearCircleCenter.g < 20 && nearCircleCenter.b < 20 && nearCircleCenter.a > 200

        #expect(nearOriginIsBlack, "The corner sliver outside the circle should remain solid opaque black fill")
        #expect(!nearCircleCenterIsBlack, "The area near the circle center should be punched out (not opaque black) -- the RoundedCorners cutout")
    }
}
