//
//  CanvasElementDrawing.swift
//  Hammerspoon 2
//

import Foundation
import SwiftUI

/// Translates v1-style canvas element dictionaries into SwiftUI `GraphicsContext` drawing
/// calls. Kept as a set of pure functions (no state) so both `HSCanvasRenderView`'s live
/// render pass, `HSCanvas.elementBounds(_:)`'s one-off geometry query, and mouse-tracking
/// hit-testing can all share it.
enum CanvasElementDrawing {

    /// Maximum nesting depth for `canvas`-type elements (a canvas embedding another canvas,
    /// which embeds another, etc.) -- guards against a self-referencing or cyclic embed
    /// hanging the render pass.
    static let maxNestingDepth = 8

    /// Replays the full element list into a `GraphicsContext`, honoring the v1
    /// clip/build/resetClip/skip action pipeline.
    ///
    /// `GraphicsContext` is a value type, which is what makes this loop match v1's
    /// documented semantics without a manual save/restore stack: `clip` intersect-
    /// accumulates against the *current* context (like `CGContextClip`), while
    /// `resetClip` jumps back to the *pristine* (fully unclipped) snapshot taken at
    /// the top of the loop -- it is not a stack pop. `build` does not draw at all;
    /// it appends its shape to a pending compound path that keeps growing until a
    /// non-build action (fill/stroke/clip) consumes it. This combination is what
    /// lets a `build` rectangle + a `clip` circle with `reversePath: true` punch a
    /// hole in the rectangle under the nonZero winding rule -- see
    /// `Hammerspoon 2Tests/IntegrationTests/HSCanvasRoundedCornersAcceptanceTests.swift`.
    static func render(elements: [[String: Any]], into context: GraphicsContext, size: CGSize, depth: Int = 0) {
        guard depth < maxNestingDepth else {
            AKWarning("hs.canvas: nested canvas recursion exceeded \(maxNestingDepth) levels, stopping")
            return
        }

        let pristine = context
        var working = context
        var pendingPath: Path?

        for element in elements {
            guard let typeString = element["type"] as? String else { continue }

            if typeString == CanvasElementType.resetClip.rawValue {
                working = pristine
                pendingPath = nil
                continue
            }

            if typeString == CanvasElementType.text.rawValue {
                drawText(element, into: &working, containerSize: size)
                pendingPath = nil
                continue
            }

            if typeString == CanvasElementType.image.rawValue {
                drawImage(element, into: &working, containerSize: size)
                pendingPath = nil
                continue
            }

            if typeString == CanvasElementType.canvas.rawValue {
                drawNestedCanvas(element, into: working, containerSize: size, depth: depth)
                pendingPath = nil
                continue
            }

            guard let shapePath = pathFor(element: element, containerSize: size) else { continue }

            var combinedPath = pendingPath ?? Path()
            combinedPath.addPath(shapePath)

            let actionString = (element["action"] as? String) ?? "strokeAndFill"
            let eoFill = (element["windingRule"] as? String) == "evenOdd"

            switch actionString {
            case "skip":
                pendingPath = nil

            case "build":
                pendingPath = combinedPath

            case "clip":
                working.clip(to: combinedPath, style: FillStyle(eoFill: eoFill))
                pendingPath = nil

            default:
                // compositeRule maps to blendMode; reset to .normal every element so a
                // non-default mode set by a previous element never leaks into this one.
                working.blendMode = blendMode(for: element["compositeRule"] as? String)

                if actionString == "fill" || actionString == "strokeAndFill" {
                    if let shading = gradientShading(element, path: combinedPath, containerSize: size) {
                        working.fill(combinedPath, with: shading, style: FillStyle(eoFill: eoFill))
                    } else if let fillColor = parseColor(element["fillColor"]) {
                        working.fill(combinedPath, with: .color(fillColor), style: FillStyle(eoFill: eoFill))
                    }
                }
                if actionString == "stroke" || actionString == "strokeAndFill",
                   let strokeColor = parseColor(element["strokeColor"]) {
                    let width = (element["strokeWidth"] as? NSNumber)?.doubleValue ?? 1.0
                    working.stroke(combinedPath, with: .color(strokeColor), lineWidth: CGFloat(width))
                }
                pendingPath = nil
            }
        }
    }

    /// Resolves a single element's geometry into a `Path`, with no fill/stroke applied.
    /// `text`/`image`/`canvas` return their bounding-frame rectangle (they have no natural
    /// vector shape) so `elementBounds(_:)` and mouse-tracking hit-testing still work for
    /// them. Returns `nil` only for `resetClip`, which has no geometry at all.
    static func pathFor(element: [String: Any], containerSize: CGSize) -> Path? {
        guard let typeString = element["type"] as? String,
              let type = CanvasElementType(rawValue: typeString) else { return nil }

        let rawPath: Path?
        switch type {
        case .rectangle:
            let rect = resolveFrame(element["frame"], containerSize: containerSize)
                ?? CGRect(origin: .zero, size: containerSize)
            if let radius = element["roundedRectRadii"] as? NSNumber {
                rawPath = Path(roundedRect: rect, cornerRadius: CGFloat(radius.doubleValue))
            } else {
                rawPath = Path(rect)
            }

        case .circle:
            let (center, radius) = resolveCenterRadius(element, containerSize: containerSize)
            // reversePath:true -> clockwise:true is what punches a hole when this circle's
            // path is appended (via `build`) to a rectangle's path and clipped under nonZero
            // winding -- empirically confirmed in the M0 spike, not just reasoned about.
            let reversed = (element["reversePath"] as? Bool) ?? false
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: reversed)
            rawPath = path

        case .oval:
            let rect = resolveFrame(element["frame"], containerSize: containerSize)
                ?? CGRect(origin: .zero, size: containerSize)
            rawPath = Path(ellipseIn: rect)

        case .arc:
            rawPath = arcPath(element, containerSize: containerSize)

        case .ellipticalArc:
            rawPath = ellipticalArcPath(element, containerSize: containerSize)

        case .segments:
            rawPath = segmentsPath(element, containerSize: containerSize)

        case .points:
            rawPath = pointsPath(element, containerSize: containerSize)

        case .text, .image, .canvas:
            rawPath = resolveFrame(element["frame"], containerSize: containerSize)
                .map { Path($0) } ?? Path(CGRect(origin: .zero, size: containerSize))

        case .resetClip:
            rawPath = nil
        }

        guard let path = rawPath else { return nil }
        return applyElementTransform(path, element: element, containerSize: containerSize)
    }

    static func arcPath(_ element: [String: Any], containerSize: CGSize) -> Path {
        let (center, radius) = resolveCenterRadius(element, containerSize: containerSize)
        let startAngle = (element["startAngle"] as? NSNumber)?.doubleValue ?? 0
        let endAngle = (element["endAngle"] as? NSNumber)?.doubleValue ?? 360
        let clockwise = (element["arcClockwise"] as? Bool) ?? false
        let includeRadii = (element["arcRadii"] as? Bool) ?? false

        var path = Path()
        if includeRadii {
            path.move(to: center)
            path.addLine(to: pointOnCircle(center: center, radius: radius, degrees: startAngle))
            path.addArc(center: center, radius: radius, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: clockwise)
            path.addLine(to: center)
        } else {
            path.addArc(center: center, radius: radius, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: clockwise)
        }
        return path
    }

    static func ellipticalArcPath(_ element: [String: Any], containerSize: CGSize) -> Path {
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        let startAngle = (element["startAngle"] as? NSNumber)?.doubleValue ?? 0
        let endAngle = (element["endAngle"] as? NSNumber)?.doubleValue ?? 360
        let clockwise = (element["arcClockwise"] as? Bool) ?? false

        var unitPath = Path()
        unitPath.addArc(center: .zero, radius: 1, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: clockwise)

        // Scale a unit circle to the frame's radii, then translate to its center --
        // CGAffineTransform composition applies the first transform, then the second.
        let transform = CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2)
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return unitPath.applying(transform)
    }

    static func segmentsPath(_ element: [String: Any], containerSize: CGSize) -> Path {
        guard let coordinates = element["coordinates"] as? [[String: Any]], !coordinates.isEmpty else { return Path() }

        var path = Path()
        for (index, point) in coordinates.enumerated() {
            let target = resolvePoint(point, keyX: "x", keyY: "y", containerSize: containerSize)
            if index == 0 {
                path.move(to: target)
            } else if point["c1x"] != nil && point["c1y"] != nil && point["c2x"] != nil && point["c2y"] != nil {
                let control1 = resolvePoint(point, keyX: "c1x", keyY: "c1y", containerSize: containerSize)
                let control2 = resolvePoint(point, keyX: "c2x", keyY: "c2y", containerSize: containerSize)
                path.addCurve(to: target, control1: control1, control2: control2)
            } else {
                path.addLine(to: target)
            }
        }
        if (element["closed"] as? Bool) ?? false {
            path.closeSubpath()
        }
        return path
    }

    static func pointsPath(_ element: [String: Any], containerSize: CGSize) -> Path {
        guard let coordinates = element["coordinates"] as? [[String: Any]] else { return Path() }
        let dotRadius: CGFloat = 2.0

        var path = Path()
        for point in coordinates {
            let center = resolvePoint(point, keyX: "x", keyY: "y", containerSize: containerSize)
            path.addEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }
        return path
    }

    static func resolvePoint(_ dict: [String: Any], keyX: String, keyY: String, containerSize: CGSize) -> CGPoint {
        let x = dict[keyX].map { UIDimension.parse($0).resolve(containerSize: containerSize.width) } ?? 0
        let y = dict[keyY].map { UIDimension.parse($0).resolve(containerSize: containerSize.height) } ?? 0
        return CGPoint(x: x, y: y)
    }

    static func pointOnCircle(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    static func drawText(_ element: [String: Any], into context: inout GraphicsContext, containerSize: CGSize) {
        guard let string = element["text"] as? String else { return }
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        let size = (element["textSize"] as? NSNumber)?.doubleValue ?? 27.0
        let color = parseColor(element["textColor"]) ?? .black
        let resolved = Text(string).font(.system(size: CGFloat(size))).foregroundColor(color)
        context.draw(resolved, in: rect)
    }

    static func drawImage(_ element: [String: Any], into context: inout GraphicsContext, containerSize: CGSize) {
        guard let hsImage = element["image"] as? HSImage else { return }
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        let alpha = (element["imageAlpha"] as? NSNumber)?.doubleValue ?? 1.0

        var imageContext = context
        imageContext.opacity = CGFloat(alpha)
        imageContext.draw(Image(nsImage: hsImage.image), in: rect)
    }

    /// Recursively renders another `HSCanvas`'s elements as a nested element. Takes a
    /// LOCAL copy of `context` (translated/faded) rather than mutating the caller's --
    /// `GraphicsContext`'s drawing calls composite onto a shared underlying surface
    /// regardless of which copy issues them, but its state (transform/opacity/clip) is
    /// per-copy, so this leaves the outer element loop's `working` context untouched.
    static func drawNestedCanvas(_ element: [String: Any], into context: GraphicsContext, containerSize: CGSize, depth: Int) {
        guard let nested = element["canvas"] as? HSCanvas else { return }
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        let alpha = (element["canvasAlpha"] as? NSNumber)?.doubleValue ?? 1.0

        var nestedContext = context
        nestedContext.opacity = CGFloat(alpha)
        nestedContext.translateBy(x: rect.minX, y: rect.minY)
        render(elements: nested.elementsForNestedRendering, into: nestedContext, size: rect.size, depth: depth + 1)
    }

    /// Resolves a `frame` dictionary (`{x, y, w, h}`, numbers or percentage strings) against
    /// a container size. Reuses `UIFrame`/`UIDimension` from hs.ui rather than a new
    /// abstraction, since they already generically parse numbers and `"50%"` strings.
    static func resolveFrame(_ raw: Any?, containerSize: CGSize) -> CGRect? {
        guard let dict = raw as? [String: Any], let uiFrame = UIFrame.from(dict: dict) else { return nil }
        return uiFrame.resolve(containerSize: containerSize)
    }

    /// Resolves a `center`+`radius` pair (used by `circle`/`arc`), each independently
    /// numeric or a percentage string. Kept local rather than folded into `UIFrame`/
    /// `UIDimension` since it's a different shape (point + scalar, not a rect).
    static func resolveCenterRadius(_ element: [String: Any], containerSize: CGSize) -> (CGPoint, CGFloat) {
        var cx = containerSize.width / 2
        var cy = containerSize.height / 2
        if let centerDict = element["center"] as? [String: Any] {
            if let x = centerDict["x"] { cx = UIDimension.parse(x).resolve(containerSize: containerSize.width) }
            if let y = centerDict["y"] { cy = UIDimension.parse(y).resolve(containerSize: containerSize.height) }
        }
        var radius = min(containerSize.width, containerSize.height) / 2
        if let r = element["radius"] {
            radius = UIDimension.parse(r).resolve(containerSize: min(containerSize.width, containerSize.height))
        }
        return (CGPoint(x: cx, y: cy), radius)
    }

    /// Parses a v1-style color dictionary (`{red, green, blue, alpha}`, each 0.0-1.0,
    /// missing components default to 0 except alpha which defaults to 1 -- matching
    /// RoundedCorners.spoon's `fillColor={alpha=1}` meaning opaque black).
    static func parseColor(_ raw: Any?) -> Color? {
        guard let dict = raw as? [String: Any] else { return nil }
        let r = (dict["red"] as? NSNumber)?.doubleValue ?? 0
        let g = (dict["green"] as? NSNumber)?.doubleValue ?? 0
        let b = (dict["blue"] as? NSNumber)?.doubleValue ?? 0
        let a = (dict["alpha"] as? NSNumber)?.doubleValue ?? 1
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // MARK: - Gradients

    /// Builds a `GraphicsContext.Shading` from `fillGradient`/`fillGradientColors`/
    /// `fillGradientAngle`/`fillGradientCenter`, or `nil` if the element doesn't specify
    /// a gradient (in which case the caller falls back to a plain `fillColor`).
    static func gradientShading(_ element: [String: Any], path: Path, containerSize: CGSize) -> GraphicsContext.Shading? {
        guard let kind = element["fillGradient"] as? String, kind == "linear" || kind == "radial" else { return nil }
        guard let colorDicts = element["fillGradientColors"] as? [[String: Any]] else { return nil }
        let colors = colorDicts.compactMap { parseColor($0) }
        guard colors.count >= 2 else { return nil }
        let gradient = Gradient(colors: colors)
        let bounds = path.boundingRect

        if kind == "radial" {
            var center = CGPoint(x: bounds.midX, y: bounds.midY)
            if let centerDict = element["fillGradientCenter"] as? [String: Any] {
                if let x = centerDict["x"] { center.x = UIDimension.parse(x).resolve(containerSize: containerSize.width) }
                if let y = centerDict["y"] { center.y = UIDimension.parse(y).resolve(containerSize: containerSize.height) }
            }
            let radius = max(bounds.width, bounds.height) / 2
            return .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        }

        // linear
        let angle = (element["fillGradientAngle"] as? NSNumber)?.doubleValue ?? 0
        let radians = angle * .pi / 180
        let halfDiagonal = sqrt(pow(bounds.width / 2, 2) + pow(bounds.height / 2, 2))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let start = CGPoint(x: center.x - cos(radians) * halfDiagonal, y: center.y - sin(radians) * halfDiagonal)
        let end = CGPoint(x: center.x + cos(radians) * halfDiagonal, y: center.y + sin(radians) * halfDiagonal)
        return .linearGradient(gradient, startPoint: start, endPoint: end)
    }

    // MARK: - Composite / blend modes

    static let blendModeValues: [String: GraphicsContext.BlendMode] = [
        "normal": .normal, "sourceOver": .normal, "multiply": .multiply, "screen": .screen,
        "overlay": .overlay, "darken": .darken, "lighten": .lighten, "colorDodge": .colorDodge,
        "colorBurn": .colorBurn, "softLight": .softLight, "hardLight": .hardLight,
        "difference": .difference, "exclusion": .exclusion, "hue": .hue, "saturation": .saturation,
        "color": .color, "luminosity": .luminosity, "clear": .clear, "copy": .copy,
        "sourceIn": .sourceIn, "sourceOut": .sourceOut, "sourceAtop": .sourceAtop,
        "destinationOver": .destinationOver, "destinationIn": .destinationIn, "destinationOut": .destinationOut,
        "destinationAtop": .destinationAtop, "xor": .xor, "plusDarker": .plusDarker, "plusLighter": .plusLighter,
    ]

    static func blendMode(for ruleName: String?) -> GraphicsContext.BlendMode {
        guard let ruleName else { return .normal }
        return blendModeValues[ruleName] ?? .normal
    }

    // MARK: - Element-level transforms (rotateElement / per-element transformation)

    /// Applies either an explicit `transformation` matrix or a simple `rotation` angle
    /// to an already-built element `Path`. `transformation` takes precedence if both are
    /// present. Returns `path` unchanged if neither attribute is set.
    static func applyElementTransform(_ path: Path, element: [String: Any], containerSize: CGSize) -> Path {
        if let matrixDict = element["transformation"] as? [String: Any] {
            return path.applying(transformMatrix(matrixDict))
        }
        if let angle = (element["rotation"] as? NSNumber)?.doubleValue {
            return rotatedPath(path, degrees: angle, element: element, containerSize: containerSize)
        }
        return path
    }

    /// Parses a v1-style 2D affine matrix (`{m11, m12, m21, m22, tX, tY}`).
    static func transformMatrix(_ dict: [String: Any]) -> CGAffineTransform {
        let a = (dict["m11"] as? NSNumber)?.doubleValue ?? 1
        let b = (dict["m12"] as? NSNumber)?.doubleValue ?? 0
        let c = (dict["m21"] as? NSNumber)?.doubleValue ?? 0
        let d = (dict["m22"] as? NSNumber)?.doubleValue ?? 1
        let tx = (dict["tX"] as? NSNumber)?.doubleValue ?? 0
        let ty = (dict["tY"] as? NSNumber)?.doubleValue ?? 0
        return CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(tx), ty: CGFloat(ty))
    }

    static func rotatedPath(_ path: Path, degrees: Double, element: [String: Any], containerSize: CGSize) -> Path {
        let pivot: CGPoint
        if let pointDict = element["rotationPoint"] as? [String: Any] {
            pivot = resolvePoint(pointDict, keyX: "x", keyY: "y", containerSize: containerSize)
        } else {
            let bounds = path.boundingRect
            pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        let radians = degrees * .pi / 180
        let transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: radians)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        return path.applying(transform)
    }

    // MARK: - Mouse-tracking hit-testing

    /// A single element eligible for mouse-tracking hit-testing (has at least one
    /// `trackMouse*` flag set to `true`).
    struct TrackedElement {
        let id: Any
        let path: Path
        let trackMouseDown: Bool
        let trackMouseUp: Bool
        let trackMouseEnterExit: Bool
        let trackMouseMove: Bool

        func tracks(_ kind: MouseTrackingKind) -> Bool {
            switch kind {
            case .down: return trackMouseDown
            case .up: return trackMouseUp
            case .enterExit: return trackMouseEnterExit
            case .move: return trackMouseMove
            }
        }
    }

    enum MouseTrackingKind {
        case down, up, enterExit, move
    }

    /// Builds the list of elements with tracking enabled, each resolved to a current
    /// `Path` for hit-testing. An element's `id` defaults to its index if not given,
    /// matching v1. Kept as a pure function (no SwiftUI/gesture dependency) so it's
    /// directly unit-testable.
    static func trackedElements(elements: [[String: Any]], containerSize: CGSize) -> [TrackedElement] {
        var result: [TrackedElement] = []
        for (index, element) in elements.enumerated() {
            let trackDown = (element["trackMouseDown"] as? Bool) ?? false
            let trackUp = (element["trackMouseUp"] as? Bool) ?? false
            let trackEnterExit = (element["trackMouseEnterExit"] as? Bool) ?? false
            let trackMove = (element["trackMouseMove"] as? Bool) ?? false
            guard trackDown || trackUp || trackEnterExit || trackMove else { continue }
            guard let path = pathFor(element: element, containerSize: containerSize) else { continue }
            let id = element["id"] ?? index
            result.append(TrackedElement(
                id: id, path: path,
                trackMouseDown: trackDown, trackMouseUp: trackUp,
                trackMouseEnterExit: trackEnterExit, trackMouseMove: trackMove
            ))
        }
        return result
    }

    /// Finds the topmost (last-drawn) tracked element whose path contains `point` and
    /// which opts into the given tracking kind -- v1's "topmost element wins" model.
    static func topmostHit(at point: CGPoint, in tracked: [TrackedElement], for kind: MouseTrackingKind) -> TrackedElement? {
        for element in tracked.reversed() where element.tracks(kind) {
            if element.path.contains(point) { return element }
        }
        return nil
    }
}
