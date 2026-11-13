//
//  HSCanvasElementDrawingTests.swift
//  Hammerspoon 2Tests
//
//  Pure Swift tests for CanvasElementDrawing's geometry/hit-testing/transform helpers --
//  no JSTestHarness needed since these are plain Swift functions with no JS surface of
//  their own (JS surface correctness is covered by HSCanvasIntegrationTests instead).
//

import Testing
import CoreGraphics
import SwiftUI
import AppKit
@testable import Hammerspoon_2
import HammerspoonSDK

@Suite("hs.canvas element drawing tests")
struct HSCanvasElementDrawingTests {

    // MARK: - New element type geometry

    @Test("arc produces a path with a non-empty bounding rect")
    func arcPathIsNonEmpty() {
        let element: [String: Any] = [
            "type": "arc", "center": ["x": 50, "y": 50], "radius": 30,
            "startAngle": 0, "endAngle": 180,
        ]
        let path = CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100))
        #expect(path != nil)
        #expect(path!.boundingRect.width > 0)
    }

    @Test("ellipticalArc respects a non-square frame")
    func ellipticalArcRespectsFrame() throws {
        let element: [String: Any] = [
            "type": "ellipticalArc", "frame": ["x": 0, "y": 0, "w": 100, "h": 40],
            "startAngle": 0, "endAngle": 360,
        ]
        let path = CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100))
        let bounds = try #require(path?.boundingRect)
        #expect(bounds.width > bounds.height)
    }

    @Test("segments connects coordinates in order and honors closed")
    func segmentsPathClosed() throws {
        let element: [String: Any] = [
            "type": "segments",
            "coordinates": [["x": 0, "y": 0], ["x": 10, "y": 0], ["x": 10, "y": 10]],
            "closed": true,
        ]
        let path = CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100))
        let bounds = try #require(path?.boundingRect)
        #expect(bounds.width == 10)
        #expect(bounds.height == 10)
    }

    @Test("points produces a dot per coordinate")
    func pointsPathHasDots() throws {
        let element: [String: Any] = [
            "type": "points",
            "coordinates": [["x": 10, "y": 10], ["x": 90, "y": 90]],
        ]
        let path = CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100))
        let bounds = try #require(path?.boundingRect)
        // Bounding rect should span roughly from the first dot to the second.
        #expect(bounds.width > 70)
        #expect(bounds.height > 70)
    }

    @Test("text and image element types resolve to their frame's bounding rect")
    func textAndImageResolveToFrameBounds() {
        let frame: [String: Any] = ["x": 5, "y": 5, "w": 40, "h": 20]
        let textPath = CanvasElementDrawing.pathFor(element: ["type": "text", "text": "hi", "frame": frame], containerSize: CGSize(width: 100, height: 100))
        let imagePath = CanvasElementDrawing.pathFor(element: ["type": "image", "frame": frame], containerSize: CGSize(width: 100, height: 100))
        #expect(textPath?.boundingRect == CGRect(x: 5, y: 5, width: 40, height: 20))
        #expect(imagePath?.boundingRect == CGRect(x: 5, y: 5, width: 40, height: 20))
    }

    @Test("resetClip has no path")
    func resetClipHasNoPath() {
        let path = CanvasElementDrawing.pathFor(element: ["type": "resetClip"], containerSize: CGSize(width: 100, height: 100))
        #expect(path == nil)
    }

    // MARK: - Transforms

    @Test("rotateElement's rotation attribute rotates the path around its own center")
    func rotationAppliedAboutOwnCenter() throws {
        // A 10x10 square at origin has center (5,5); rotating 90 degrees about its own
        // center should keep the bounding rect's center the same (still a square).
        let element: [String: Any] = ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "rotation": 45]
        let path = try #require(CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100)))
        let bounds = path.boundingRect
        #expect(abs(bounds.midX - 5) < 0.01)
        #expect(abs(bounds.midY - 5) < 0.01)
    }

    @Test("explicit transformation matrix translates the path")
    func explicitTransformationTranslates() throws {
        let matrix: [String: Any] = ["m11": 1, "m12": 0, "m21": 0, "m22": 1, "tX": 20, "tY": 30]
        let element: [String: Any] = ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "transformation": matrix]
        let path = try #require(CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100)))
        #expect(path.boundingRect == CGRect(x: 20, y: 30, width: 10, height: 10))
    }

    // MARK: - Rounded rectangles

    private func roundedRectPath(_ radii: Any?) throws -> Path {
        var element: [String: Any] = ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 100, "h": 100]]
        element["roundedRectRadii"] = radii
        return try #require(CanvasElementDrawing.pathFor(element: element, containerSize: CGSize(width: 100, height: 100)))
    }

    @Test("roundedRectRadii as a number rounds every corner by that radius")
    func roundedRectRadiiNumber() throws {
        let path = try roundedRectPath(20)
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(!path.contains(CGPoint(x: 99, y: 99)))
        #expect(path.contains(CGPoint(x: 50, y: 1)))
    }

    @Test("roundedRectRadii as {xRadius, yRadius} gives elliptical corners")
    func roundedRectRadiiXY() throws {
        let path = try roundedRectPath(["xRadius": 40, "yRadius": 2])
        // Only 2pt tall, so a point 10pt down the left edge is inside...
        #expect(path.contains(CGPoint(x: 2, y: 10)))
        // ...but 40pt wide, so a point 10pt along the top edge is cut off
        #expect(!path.contains(CGPoint(x: 10, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 90, y: 99.5)))
    }

    @Test("roundedRectRadii that's missing or not a number or object leaves the corners square")
    func roundedRectRadiiSquare() throws {
        #expect(try roundedRectPath(nil).contains(CGPoint(x: 1, y: 1)))
        #expect(try roundedRectPath("20").contains(CGPoint(x: 1, y: 1)))
        #expect(try roundedRectPath(["xRadius": 20, "yRadius": 20, "typo": 1]).contains(CGPoint(x: 1, y: 1)))
        #expect(try roundedRectPath(["xRadius": "20", "yRadius": 20]).contains(CGPoint(x: 1, y: 1)))
    }

    @Test("cornerRadiiProblem accepts numbers and {xRadius, yRadius}, and reports anything else")
    func cornerRadiiProblem() {
        let valid: [Any] = [10, ["xRadius": 4, "yRadius": 8], ["xRadius": 4], NSNull()]
        for raw in valid {
            #expect(CanvasElementDrawing.cornerRadiiProblem(raw) == nil, "\(raw) was reported")
        }
        let invalid: [Any] = ["10", ["x": 4, "y": 8], ["xRadius": "4"], [4, 8]]
        for raw in invalid {
            #expect(CanvasElementDrawing.cornerRadiiProblem(raw) != nil, "\(raw) wasn't reported")
        }
    }

    // MARK: - Gradients

    @Test("gradientShading returns nil without fillGradient")
    func gradientShadingNilByDefault() {
        let shading = CanvasElementDrawing.gradientShading([:], path: Path(CGRect(x: 0, y: 0, width: 10, height: 10)), containerSize: CGSize(width: 100, height: 100))
        #expect(shading == nil)
    }

    @Test("gradientShading returns a shading for a valid linear gradient spec")
    func gradientShadingLinear() {
        let element: [String: Any] = [
            "fillGradient": "linear",
            "fillGradientColors": [["red": 1, "green": 0, "blue": 0, "alpha": 1], ["red": 0, "green": 0, "blue": 1, "alpha": 1]],
        ]
        let shading = CanvasElementDrawing.gradientShading(element, path: Path(CGRect(x: 0, y: 0, width: 10, height: 10)), containerSize: CGSize(width: 100, height: 100))
        #expect(shading != nil)
    }

    @Test("gradientShading returns nil with fewer than two colors")
    func gradientShadingNeedsTwoColors() {
        let element: [String: Any] = [
            "fillGradient": "linear",
            "fillGradientColors": [["red": 1, "green": 0, "blue": 0, "alpha": 1]],
        ]
        let shading = CanvasElementDrawing.gradientShading(element, path: Path(CGRect(x: 0, y: 0, width: 10, height: 10)), containerSize: CGSize(width: 100, height: 100))
        #expect(shading == nil)
    }

    // MARK: - Colors

    /// A color's sRGB components, for comparing against expected values
    private func rgba(_ color: Color?) -> [Double]? {
        guard let color, let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent].map(Double.init)
    }

    private func expectColor(_ raw: Any, _ expected: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = rgba(CanvasElementDrawing.parseColor(raw))
        #expect(actual != nil, "\(raw) didn't parse", sourceLocation: sourceLocation)
        guard let actual else { return }
        let close = zip(actual, expected).allSatisfy { abs($0 - $1) < 0.002 }
        #expect(close, "\(raw) parsed as \(actual), expected \(expected)", sourceLocation: sourceLocation)
    }

    @Test("parseColor reads {red, green, blue, alpha}, with missing components 0 and alpha 1")
    func parseColorRGB() {
        expectColor(["red": 1, "green": 0.5, "blue": 0.25, "alpha": 0.5], [1, 0.5, 0.25, 0.5])
        expectColor(["alpha": 1], [0, 0, 0, 1])
        expectColor([String: Any](), [0, 0, 0, 1])
    }

    @Test("parseColor reads {white, alpha}")
    func parseColorWhite() {
        expectColor(["white": 1], [1, 1, 1, 1])
        expectColor(["white": 0.5, "alpha": 0.25], [0.5, 0.5, 0.5, 0.25])
    }

    @Test("parseColor reads {hue, saturation, brightness, alpha}")
    func parseColorHSB() {
        expectColor(["hue": 0, "saturation": 1, "brightness": 1], [1, 0, 0, 1])
        expectColor(["hue": 1.0 / 3.0, "saturation": 1, "brightness": 0.5, "alpha": 0.5], [0, 0.5, 0, 0.5])
    }

    @Test("parseColor reads {hex, alpha} and hex strings in #RGB, #RRGGBB and #RRGGBBAA forms")
    func parseColorHex() {
        expectColor(["hex": "#FFF"], [1, 1, 1, 1])
        expectColor(["hex": "#FF0000", "alpha": 0.5] as [String: Any], [1, 0, 0, 0.5])
        expectColor("#00FF00", [0, 1, 0, 1])
        expectColor("0000FF", [0, 0, 1, 1])
        expectColor("#F00", [1, 0, 0, 1])
        expectColor("#FF000080", [1, 0, 0, 128.0 / 255.0])
    }

    @Test("parseColor reads {list, name} from a system color list")
    func parseColorList() throws {
        let list = try #require(NSColorList.availableColorLists.first { !$0.allKeys.isEmpty })
        let name = try #require(list.allKeys.first)
        let listName = try #require(list.name)
        #expect(CanvasElementDrawing.parseColor(["list": listName, "name": name]) != nil)
        #expect(CanvasElementDrawing.colorProblem(["list": listName, "name": name]) == nil)
    }

    @Test("parseColor reads an HSColor")
    func parseColorHSColor() {
        expectColor(HSColor.hex("#0000FF"), [0, 0, 1, 1])
    }

    @Test("parseColor picks the form like v1: list/name, then hex, then white, then hue")
    func parseColorFormPrecedence() {
        expectColor(["hex": "#00FF00", "white": 1, "red": 1] as [String: Any], [0, 1, 0, 1])
        expectColor(["white": 1, "hue": 0, "saturation": 1, "brightness": 1], [1, 1, 1, 1])
        expectColor(["hue": 0, "saturation": 1, "brightness": 1, "blue": 1], [1, 0, 0, 1])
    }

    @Test("parseColor returns nil for values that aren't a usable color")
    func parseColorInvalid() {
        let values: [Any] = ["#GGG", "#12345", "1234ＦＦ", ["hex": "nope"], ["list": "No Such List", "name": "Red"], 42]
        for raw in values {
            #expect(CanvasElementDrawing.parseColor(raw) == nil, "\(raw) parsed")
        }
    }

    @Test("colorProblem accepts every supported form")
    func colorProblemAcceptsValidColors() {
        let values: [Any] = [
            ["red": 1, "green": 0, "blue": 0, "alpha": 1], ["alpha": 1], ["white": 0.5],
            ["hue": 0.5, "saturation": 1, "brightness": 1], ["hex": "#ABC", "alpha": 0.5] as [String: Any],
            "#AABBCC", NSNull(), HSColor.hex("#AABBCC"),
        ]
        for raw in values {
            let problem = CanvasElementDrawing.colorProblem(raw)
            #expect(problem == nil, "\(raw): \(problem ?? "")")
        }
    }

    @Test("colorProblem reports colors that won't draw as intended")
    func colorProblemReportsInvalidColors() {
        let values: [Any] = [
            "#GGG", ["hex": "#12345"], ["Red": 1], ["red": "1"], ["image": "x"],
            ["list": "No Such List", "name": "Red"], ["name": "Red"], 42,
        ]
        for raw in values {
            #expect(CanvasElementDrawing.colorProblem(raw) != nil, "\(raw) wasn't reported")
        }
    }

    @Test("gradientShading accepts a mix of color forms")
    func gradientShadingMixedColorForms() {
        let element: [String: Any] = [
            "fillGradient": "linear",
            "fillGradientColors": ["#FF0000", ["white": 1], HSColor.hex("#0000FF")] as [Any],
        ]
        let shading = CanvasElementDrawing.gradientShading(element, path: Path(CGRect(x: 0, y: 0, width: 10, height: 10)), containerSize: CGSize(width: 100, height: 100))
        #expect(shading != nil)
    }

    // MARK: - Blend modes

    @Test("blendMode maps a known name and falls back to normal for unknown/nil")
    func blendModeMapping() {
        #expect(CanvasElementDrawing.blendMode(for: "multiply") == .multiply)
        #expect(CanvasElementDrawing.blendMode(for: "nonsense") == .normal)
        #expect(CanvasElementDrawing.blendMode(for: nil) == .normal)
    }

    // MARK: - Text font/weight/design

    @Test("nsFontWeight maps every named weight and falls back to nil for unknown/nil")
    func nsFontWeightMapping() {
        #expect(CanvasElementDrawing.nsFontWeight("black") == .black)
        #expect(CanvasElementDrawing.nsFontWeight("bold") == .bold)
        #expect(CanvasElementDrawing.nsFontWeight("heavy") == .heavy)
        #expect(CanvasElementDrawing.nsFontWeight("light") == .light)
        #expect(CanvasElementDrawing.nsFontWeight("medium") == .medium)
        #expect(CanvasElementDrawing.nsFontWeight("regular") == .regular)
        #expect(CanvasElementDrawing.nsFontWeight("semibold") == .semibold)
        #expect(CanvasElementDrawing.nsFontWeight("thin") == .thin)
        #expect(CanvasElementDrawing.nsFontWeight("ultraLight") == .ultraLight)
        #expect(CanvasElementDrawing.nsFontWeight("nonsense") == nil)
        #expect(CanvasElementDrawing.nsFontWeight(nil) == nil)
    }

    @Test("nsFontDesign maps every named design and falls back to nil for unknown/nil")
    func nsFontDesignMapping() {
        #expect(CanvasElementDrawing.nsFontDesign("monospaced") == .monospaced)
        #expect(CanvasElementDrawing.nsFontDesign("rounded") == .rounded)
        #expect(CanvasElementDrawing.nsFontDesign("serif") == .serif)
        #expect(CanvasElementDrawing.nsFontDesign("nonsense") == nil)
        #expect(CanvasElementDrawing.nsFontDesign(nil) == nil)
    }

    @Test("nsTextAlignment maps every named alignment and falls back to nil for unknown/nil")
    func nsTextAlignmentMapping() {
        #expect(CanvasElementDrawing.nsTextAlignment("left") == .left)
        #expect(CanvasElementDrawing.nsTextAlignment("right") == .right)
        #expect(CanvasElementDrawing.nsTextAlignment("center") == .center)
        #expect(CanvasElementDrawing.nsTextAlignment("justified") == .justified)
        #expect(CanvasElementDrawing.nsTextAlignment("natural") == .natural)
        #expect(CanvasElementDrawing.nsTextAlignment("nonsense") == nil)
        #expect(CanvasElementDrawing.nsTextAlignment(nil) == nil)
    }

    @Test("nsLineBreakMode maps every named mode and falls back to nil for unknown/nil")
    func nsLineBreakModeMapping() {
        #expect(CanvasElementDrawing.nsLineBreakMode("wordWrap") == .byWordWrapping)
        #expect(CanvasElementDrawing.nsLineBreakMode("charWrap") == .byCharWrapping)
        #expect(CanvasElementDrawing.nsLineBreakMode("clip") == .byClipping)
        #expect(CanvasElementDrawing.nsLineBreakMode("truncateHead") == .byTruncatingHead)
        #expect(CanvasElementDrawing.nsLineBreakMode("truncateMiddle") == .byTruncatingMiddle)
        #expect(CanvasElementDrawing.nsLineBreakMode("truncateTail") == .byTruncatingTail)
        #expect(CanvasElementDrawing.nsLineBreakMode("nonsense") == nil)
        #expect(CanvasElementDrawing.nsLineBreakMode(nil) == nil)
    }

    @Test("minimumTextSize measures a multi-line string taller than the same text on one line")
    func minimumTextSizeMultiLineIsTaller() {
        let element: [String: Any] = ["textSize": 24]
        let oneLine = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: element)
        let twoLines = CanvasElementDrawing.minimumTextSize(text: "Hammer\nspoon", element: element)
        #expect(twoLines.height > oneLine.height)
    }

    @Test("minimumTextSize scales with textSize")
    func minimumTextSizeScalesWithTextSize() {
        let small = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: ["textSize": 12])
        let large = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: ["textSize": 48])
        #expect(large.width > small.width)
        #expect(large.height > small.height)
    }

    @Test("minimumTextSize measures a bold weight wider than regular for the same string")
    func minimumTextSizeWeightAffectsWidth() {
        let regular = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: ["textSize": 24, "textWeight": "regular"])
        let bold = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: ["textSize": 24, "textWeight": "black"])
        #expect(bold.width > regular.width)
    }

    @Test("minimumTextSize falls back to the system font size for an unresolvable textFont")
    func minimumTextSizeFallsBackForUnresolvableFont() {
        let size = CanvasElementDrawing.minimumTextSize(text: "Hammerspoon", element: ["textSize": 24, "textFont": "Definitely Not An Installed Font Name"])
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    // MARK: - Text rasterization sizing (avoiding full-frame rasterization for short text)

    @Test("textImageSize shrinks to the text's natural size when it fits the frame's width")
    func textImageSizeShrinksWhenTextFits() {
        // A huge frame (as a frame-less text element would default to on a large canvas)
        // with a small natural size -- should rasterize at the natural size, not the frame.
        let size = CanvasElementDrawing.textImageSize(naturalSize: CGSize(width: 80, height: 20), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(size == CGSize(width: 80, height: 20))
    }

    @Test("textImageSize caps the shrunk height at the frame's own height")
    func textImageSizeCapsHeightAtFrame() {
        let size = CanvasElementDrawing.textImageSize(naturalSize: CGSize(width: 80, height: 500), frame: CGRect(x: 0, y: 0, width: 1920, height: 100))
        #expect(size == CGSize(width: 80, height: 100))
    }

    @Test("textImageSize falls back to the full frame when the text needs to wrap")
    func textImageSizeFallsBackWhenWiderThanFrame() {
        let size = CanvasElementDrawing.textImageSize(naturalSize: CGSize(width: 500, height: 20), frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        #expect(size == CGSize(width: 200, height: 80))
    }

    @Test("textImageOrigin is always top-anchored, and positions per alignment")
    func textImageOriginPositioning() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let imageSize = CGSize(width: 50, height: 20)
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .left, isRightToLeft: false) == CGPoint(x: 10, y: 20))
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .center, isRightToLeft: false) == CGPoint(x: 85, y: 20))
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .right, isRightToLeft: false) == CGPoint(x: 160, y: 20))
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .natural, isRightToLeft: false) == CGPoint(x: 10, y: 20))
    }

    @Test("textImageOrigin resolves natural/justified alignment against the frame's right edge for right-to-left text")
    func textImageOriginNaturalRTL() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let imageSize = CGSize(width: 50, height: 20)
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .natural, isRightToLeft: true) == CGPoint(x: 160, y: 20))
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .justified, isRightToLeft: true) == CGPoint(x: 160, y: 20))
        // .left/.right/.center are direction-independent -- isRightToLeft must not override them.
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .left, isRightToLeft: true) == CGPoint(x: 10, y: 20))
        #expect(CanvasElementDrawing.textImageOrigin(imageSize: imageSize, frame: frame, alignment: .right, isRightToLeft: true) == CGPoint(x: 160, y: 20))
    }

    @Test("isRightToLeftText detects RTL scripts and treats LTR/empty strings as false")
    func isRightToLeftTextDetection() {
        #expect(CanvasElementDrawing.isRightToLeftText("שלום") == true)
        #expect(CanvasElementDrawing.isRightToLeftText("مرحبا") == true)
        #expect(CanvasElementDrawing.isRightToLeftText("Hello") == false)
        #expect(CanvasElementDrawing.isRightToLeftText("") == false)
    }

    // MARK: - Image scaling/alignment

    @Test("proportionalImageSize with scaleUp:true scales a small image up to fit")
    func proportionalImageSizeScalesUp() {
        let size = CanvasElementDrawing.proportionalImageSize(CGSize(width: 10, height: 10), fitting: CGSize(width: 100, height: 50), scaleUp: true)
        #expect(size == CGSize(width: 50, height: 50))
    }

    @Test("proportionalImageSize with scaleUp:false leaves a small image at native size")
    func proportionalImageSizeShrinkOnlyLeavesSmallImageAlone() {
        let size = CanvasElementDrawing.proportionalImageSize(CGSize(width: 10, height: 10), fitting: CGSize(width: 100, height: 50), scaleUp: false)
        #expect(size == CGSize(width: 10, height: 10))
    }

    @Test("proportionalImageSize shrinks a large image regardless of scaleUp")
    func proportionalImageSizeShrinksLargeImage() {
        let fitting = CGSize(width: 100, height: 50)
        let scaleUpTrue = CanvasElementDrawing.proportionalImageSize(CGSize(width: 200, height: 200), fitting: fitting, scaleUp: true)
        let scaleUpFalse = CanvasElementDrawing.proportionalImageSize(CGSize(width: 200, height: 200), fitting: fitting, scaleUp: false)
        #expect(scaleUpTrue == CGSize(width: 50, height: 50))
        #expect(scaleUpFalse == CGSize(width: 50, height: 50))
    }

    @Test("imageDrawRect: none scaling keeps native size and defaults to centering")
    func imageDrawRectNoneScalingCentersNativeSize() {
        let rect = CanvasElementDrawing.imageDrawRect(for: ["imageScaling": "none"], imageSize: CGSize(width: 20, height: 10), frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rect == CGRect(x: 40, y: 45, width: 20, height: 10))
    }

    @Test("imageDrawRect: scaleToFit stretches to the full frame regardless of aspect ratio")
    func imageDrawRectScaleToFitFillsFrame() {
        let rect = CanvasElementDrawing.imageDrawRect(for: ["imageScaling": "scaleToFit"], imageSize: CGSize(width: 20, height: 10), frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(rect == CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test("imageDrawRect: default scaling/alignment matches v1's scaleProportionally/center")
    func imageDrawRectDefaultsMatchV1() {
        let rect = CanvasElementDrawing.imageDrawRect(for: [:], imageSize: CGSize(width: 10, height: 10), frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        // Proportionally scaled up to fit the smaller axis (height: 50), then centered.
        #expect(rect == CGRect(x: 25, y: 0, width: 50, height: 50))
    }

    @Test("imageDrawRect honors each of the 9 named alignments")
    func imageDrawRectAlignments() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let size = CGSize(width: 20, height: 20)
        func origin(_ alignment: String) -> CGPoint {
            CanvasElementDrawing.imageDrawRect(for: ["imageScaling": "none", "imageAlignment": alignment], imageSize: size, frame: frame).origin
        }
        #expect(origin("topLeft") == CGPoint(x: 0, y: 0))
        #expect(origin("topRight") == CGPoint(x: 80, y: 0))
        #expect(origin("bottomLeft") == CGPoint(x: 0, y: 80))
        #expect(origin("bottomRight") == CGPoint(x: 80, y: 80))
        #expect(origin("top") == CGPoint(x: 40, y: 0))
        #expect(origin("bottom") == CGPoint(x: 40, y: 80))
        #expect(origin("left") == CGPoint(x: 0, y: 40))
        #expect(origin("right") == CGPoint(x: 80, y: 40))
        #expect(origin("center") == CGPoint(x: 40, y: 40))
    }

    // MARK: - Mouse-tracking hit-testing

    @Test("trackedElements only includes elements with a trackMouse* flag set")
    func trackedElementsFiltersUntracked() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10]],
            ["type": "rectangle", "frame": ["x": 20, "y": 20, "w": 10, "h": 10], "trackMouseDown": true],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        #expect(tracked.count == 1)
    }

    @Test("trackedElements defaults id to the element's index when not given")
    func trackedElementsDefaultID() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10]],
            ["type": "rectangle", "frame": ["x": 20, "y": 20, "w": 10, "h": 10], "trackMouseDown": true],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        #expect((tracked.first?.id as? Int) == 1)
    }

    @Test("trackedElements uses an explicit id when given")
    func trackedElementsExplicitID() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "trackMouseDown": true, "id": "myRect"],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        #expect((tracked.first?.id as? String) == "myRect")
    }

    @Test("topmostHit picks the last-drawn (topmost) overlapping element")
    func topmostHitPrefersLastDrawn() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 50, "h": 50], "trackMouseDown": true, "id": "bottom"],
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 50, "h": 50], "trackMouseDown": true, "id": "top"],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let hit = CanvasElementDrawing.topmostHit(at: CGPoint(x: 25, y: 25), in: tracked, for: .down)
        #expect((hit?.id as? String) == "top")
    }

    @Test("topmostHit only considers elements tracking the requested kind")
    func topmostHitFiltersByKind() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 50, "h": 50], "trackMouseMove": true, "id": "moveOnly"],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let downHit = CanvasElementDrawing.topmostHit(at: CGPoint(x: 25, y: 25), in: tracked, for: .down)
        let moveHit = CanvasElementDrawing.topmostHit(at: CGPoint(x: 25, y: 25), in: tracked, for: .move)
        #expect(downHit == nil)
        #expect((moveHit?.id as? String) == "moveOnly")
    }

    @Test("trackedElements includes elements that only track the right mouse button")
    func trackedElementsIncludesRightButtonOnly() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "trackRightMouseDown": true],
            ["type": "rectangle", "frame": ["x": 20, "y": 20, "w": 10, "h": 10], "trackRightMouseUp": true],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        #expect(tracked.count == 2)
    }

    @Test("topmostHit keeps left- and right-button tracking separate")
    func topmostHitSeparatesButtons() {
        // A right-click must not reach an element that only asked for left clicks (and
        // vice versa), and the topmost element tracking the right button wins even when a
        // left-only element is drawn above it.
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 50, "h": 50], "trackRightMouseDown": true, "trackRightMouseUp": true, "id": "right"],
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 50, "h": 50], "trackMouseDown": true, "trackMouseUp": true, "id": "left"],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let point = CGPoint(x: 25, y: 25)
        #expect((CanvasElementDrawing.topmostHit(at: point, in: tracked, for: .down)?.id as? String) == "left")
        #expect((CanvasElementDrawing.topmostHit(at: point, in: tracked, for: .up)?.id as? String) == "left")
        #expect((CanvasElementDrawing.topmostHit(at: point, in: tracked, for: .rightDown)?.id as? String) == "right")
        #expect((CanvasElementDrawing.topmostHit(at: point, in: tracked, for: .rightUp)?.id as? String) == "right")
    }

    @Test("topmostHit returns nil when the point is outside every tracked path")
    func topmostHitOutsideAllPaths() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "trackMouseDown": true],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let hit = CanvasElementDrawing.topmostHit(at: CGPoint(x: 50, y: 50), in: tracked, for: .down)
        #expect(hit == nil)
    }

    @Test("trackedElements applies the canvas-wide transform to hit-test paths")
    func trackedElementsAppliesCanvasTransform() {
        // Drawing already reflects setTransformation() (applied in HSCanvasRenderView's
        // Canvas closure) -- hit-testing has to apply the same transform to each tracked
        // path, or a translated/rotated/scaled canvas fires callbacks against stale
        // (pre-transform) locations. Regression test for that mismatch.
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "trackMouseDown": true],
        ]
        let translated = CGAffineTransform(translationX: 50, y: 50)

        let untransformed = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let transformed = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100), canvasTransform: translated)

        // Without a transform, (5,5) hits the rectangle and (55,55) misses it.
        #expect(CanvasElementDrawing.topmostHit(at: CGPoint(x: 5, y: 5), in: untransformed, for: .down) != nil)
        #expect(CanvasElementDrawing.topmostHit(at: CGPoint(x: 55, y: 55), in: untransformed, for: .down) == nil)

        // With a +50/+50 canvas transform, hit-testing should follow the shape to its new
        // on-screen location: (55,55) now hits, (5,5) no longer does.
        #expect(CanvasElementDrawing.topmostHit(at: CGPoint(x: 55, y: 55), in: transformed, for: .down) != nil)
        #expect(CanvasElementDrawing.topmostHit(at: CGPoint(x: 5, y: 5), in: transformed, for: .down) == nil)
    }
}

/// Tests for `HSCanvasRenderView.resolveEnterExitTransition`, the pure decision function
/// behind `updateHover()`/`canvasMouseEvents()`'s enter/exit delivery -- extracted so this
/// logic (including the whole-canvas `canvasTrackMouseEnterExit` case) is unit-testable
/// without instantiating SwiftUI hover gestures.
@Suite("hs.canvas enter/exit transition tests")
struct HSCanvasEnterExitTransitionTests {

    private func trackedElement(id: Any) -> CanvasElementDrawing.TrackedElement {
        CanvasElementDrawing.TrackedElement(
            id: id, path: Path(),
            trackMouseDown: false, trackMouseUp: false,
            trackMouseEnterExit: true, trackMouseMove: false
        )
    }

    @Test("No hit and canvasTrackMouseEnterExit disabled: no target, nothing fires")
    func noHitNoCanvasTracking() {
        let result = HSCanvasRenderView.resolveEnterExitTransition(
            currentTargetID: nil, enterExitHit: nil, canvasTrackMouseEnterExit: false
        )
        #expect(result.newTargetID == nil)
        #expect(result.exitID == nil)
        #expect(result.enterID == nil)
    }

    @Test("No element hit but canvasTrackMouseEnterExit enabled: enters the whole-canvas sentinel")
    func backgroundHoverEntersCanvasSentinel() {
        // This is the exact case that was previously dead code: canvasTrackMouseEnterExit
        // was stored but never read, so canvasMouseEvents(_, _, true, _) never delivered
        // its promised enter/exit events for background regions.
        let result = HSCanvasRenderView.resolveEnterExitTransition(
            currentTargetID: nil, enterExitHit: nil, canvasTrackMouseEnterExit: true
        )
        #expect(result.newTargetID as? String == HSCanvasRenderView.canvasSentinelID)
        #expect(result.exitID == nil)
        #expect(result.enterID as? String == HSCanvasRenderView.canvasSentinelID)
    }

    @Test("Already at the canvas sentinel with no hit: no repeated enter")
    func repeatedBackgroundHoverDoesNotRefire() {
        let result = HSCanvasRenderView.resolveEnterExitTransition(
            currentTargetID: HSCanvasRenderView.canvasSentinelID, enterExitHit: nil, canvasTrackMouseEnterExit: true
        )
        #expect(result.exitID == nil)
        #expect(result.enterID == nil)
    }

    @Test("Moving from the canvas sentinel onto a tracked element: exits canvas, enters element")
    func movingFromBackgroundToElement() {
        let result = HSCanvasRenderView.resolveEnterExitTransition(
            currentTargetID: HSCanvasRenderView.canvasSentinelID,
            enterExitHit: trackedElement(id: "dot"),
            canvasTrackMouseEnterExit: true
        )
        #expect(result.exitID as? String == HSCanvasRenderView.canvasSentinelID)
        #expect(result.enterID as? String == "dot")
        #expect(result.newTargetID as? String == "dot")
    }

    @Test("Moving off a tracked element with no canvas tracking: exits the element, no new target")
    func movingOffElementWithoutCanvasTracking() {
        let result = HSCanvasRenderView.resolveEnterExitTransition(
            currentTargetID: "dot", enterExitHit: nil, canvasTrackMouseEnterExit: false
        )
        #expect(result.exitID as? String == "dot")
        #expect(result.enterID == nil)
        #expect(result.newTargetID == nil)
    }
}

/// Tests for `HSCanvasPressState`, which decides what each left-button press reports from
/// the presses `HSCanvasWindow` records and the `DragGesture` callbacks that follow.
@Suite("hs.canvas press state tests")
@MainActor
struct HSCanvasPressStateTests {
    @Test("A plain press reports left down then left up, once each")
    func plainPress() {
        let state = HSCanvasPressState()
        state.pressBegan(modifiers: [.shift, .option, .command])
        #expect(state.gestureChanged() == .left)
        #expect(state.gestureChanged() == nil)
        #expect(state.gestureEnded() == .left)
        #expect(state.gestureEnded() == nil)
    }

    @Test("A press with Ctrl held is a Ctrl-click")
    func controlClick() {
        let state = HSCanvasPressState()
        state.pressBegan(modifiers: [.control, .shift])
        #expect(state.gestureChanged() == .controlClick)
        #expect(state.gestureEnded() == .controlClick)
    }

    @Test("A gesture with no recorded press behind it reports nothing")
    func gestureWithoutPress() {
        // Covers a right-button press, should SwiftUI ever start delivering those to
        // DragGesture: the window only records left presses, so nothing is reported twice.
        let state = HSCanvasPressState()
        #expect(state.gestureChanged() == nil)
        state.pressBegan(modifiers: [])
        _ = state.gestureChanged()
        _ = state.gestureEnded()
        #expect(state.gestureChanged() == nil)
        #expect(state.gestureEnded() == nil)
    }

    @Test("A press whose gesture was cancelled doesn't leak into the next press")
    func cancelledPressIsAbandoned() {
        let state = HSCanvasPressState()
        state.pressBegan(modifiers: .control)
        #expect(state.gestureChanged() == .controlClick)
        // No gestureEnded(): SwiftUI cancelled the gesture.
        state.pressBegan(modifiers: [])
        #expect(state.gestureChanged() == .left)
        #expect(state.gestureEnded() == .left)
    }
}
