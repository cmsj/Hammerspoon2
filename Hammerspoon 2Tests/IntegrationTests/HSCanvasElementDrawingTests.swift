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
@testable import Hammerspoon_2

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

    // MARK: - Blend modes

    @Test("blendMode maps a known name and falls back to normal for unknown/nil")
    func blendModeMapping() {
        #expect(CanvasElementDrawing.blendMode(for: "multiply") == .multiply)
        #expect(CanvasElementDrawing.blendMode(for: "nonsense") == .normal)
        #expect(CanvasElementDrawing.blendMode(for: nil) == .normal)
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

    @Test("topmostHit returns nil when the point is outside every tracked path")
    func topmostHitOutsideAllPaths() {
        let elements: [[String: Any]] = [
            ["type": "rectangle", "frame": ["x": 0, "y": 0, "w": 10, "h": 10], "trackMouseDown": true],
        ]
        let tracked = CanvasElementDrawing.trackedElements(elements: elements, containerSize: CGSize(width: 100, height: 100))
        let hit = CanvasElementDrawing.topmostHit(at: CGPoint(x: 50, y: 50), in: tracked, for: .down)
        #expect(hit == nil)
    }
}
