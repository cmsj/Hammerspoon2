//
//  CanvasElementDrawing.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import CoreText
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

            // `action` and `compositeRule` apply uniformly to every element type, including
            // text/image/canvas -- resolving both up front (rather than inside the
            // shape-only switch below, as originally written) is what makes `action: "skip"`
            // actually hide a text/image/canvas element, and what stops those types from
            // silently inheriting whatever blendMode a previous shape element left behind.
            let actionString = (element["action"] as? String) ?? "strokeAndFill"
            if actionString == "skip" {
                pendingPath = nil
                continue
            }
            working.blendMode = blendMode(for: element["compositeRule"] as? String)

            if typeString == CanvasElementType.text.rawValue {
                drawText(element, into: working, containerSize: size)
                pendingPath = nil
                continue
            }

            if typeString == CanvasElementType.image.rawValue {
                drawImage(element, into: working, containerSize: size)
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

            let eoFill = (element["windingRule"] as? String) == "evenOdd"

            switch actionString {
            case "build":
                pendingPath = combinedPath

            case "clip":
                working.clip(to: combinedPath, style: FillStyle(eoFill: eoFill))
                pendingPath = nil

            default:
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

    /// Renders text by rasterizing it with AppKit (`NSAttributedString.draw(in:withAttributes:)`)
    /// into an offscreen image, then drawing that image into the `GraphicsContext` -- rather
    /// than resolving a SwiftUI `Text` and drawing it directly.
    ///
    /// This exists because `textAlignment`/`textLineBreak` need `NSParagraphStyle`, and
    /// SwiftUI has no path to that: `Text.multilineTextAlignment`/`.truncationMode` are
    /// declared only as `View` extensions (they work by setting an environment value), and
    /// `GraphicsContext.draw` only accepts a concrete `Text`, not `some View` -- there's no
    /// way to get an environment value onto a bare `Text` before resolving it. Rasterizing
    /// through AppKit sidesteps that entirely and gets full v1 parity (including `justified`
    /// alignment and `clip`/`charWrap` line-break modes, which have no SwiftUI equivalent at
    /// all) for less code than approximating it.
    static func drawText(_ element: [String: Any], into context: GraphicsContext, containerSize: CGSize) {
        guard let string = element["text"] as? String else { return }
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        guard rect.width > 0, rect.height > 0 else { return }

        let font = resolvedNSFont(for: element)
        let color = NSColor(parseColor(element["textColor"]) ?? .black)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment(element["textAlignment"]) ?? .natural
        paragraphStyle.lineBreakMode = nsLineBreakMode(element["textLineBreak"]) ?? .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        // Rasterizing at the full frame size is wasteful when the text doesn't need it -- a
        // text element with no `frame` of its own defaults to the entire canvas, so a single
        // short status line would otherwise repaint a giant, mostly-empty offscreen bitmap on
        // every redraw. If the text already fits on one line (or one physical line per
        // explicit `\n`) within the frame's width, none of NSAttributedString's
        // wrapping/truncation layout actually gets exercised, so it's safe to rasterize just
        // the text's own natural size and position that within the frame ourselves instead --
        // see `textImageSize`/`textImageOrigin`. Text that needs to wrap still uses the full
        // frame, unchanged: shrinking that case safely needs real line-layout measurement,
        // not just this fits-on-one-line check.
        let naturalSize = (string as NSString).size(withAttributes: [.font: font])
        let imageSize = textImageSize(naturalSize: naturalSize, frame: rect)

        // `flipped: true` matches every other element's y-down frame convention (see the
        // module-level coordinate systems doc) -- text draws top-down starting at the rect's
        // visual top, not AppKit's unflipped bottom-left origin.
        let image = NSImage(size: imageSize, flipped: true) { imageRect in
            (string as NSString).draw(in: imageRect, withAttributes: attributes)
            return true
        }

        var textContext = context
        let transform = elementTransform(element: element, pivotRect: rect, containerSize: containerSize)
        if !transform.isIdentity {
            textContext.concatenate(transform)
        }
        let origin = textImageOrigin(imageSize: imageSize, frame: rect, alignment: paragraphStyle.alignment, isRightToLeft: isRightToLeftText(string))
        textContext.draw(Image(nsImage: image), in: CGRect(origin: origin, size: imageSize))
    }

    /// Whether `string` lays out right-to-left, per CoreText's own bidi/shaping resolution --
    /// the same engine `NSAttributedString`'s drawing uses on macOS, so this stays consistent
    /// with how `.natural`/`.justified` alignment actually resolves when text lays out for
    /// real, rather than reimplementing the Unicode bidi algorithm ourselves.
    static func isRightToLeftText(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string))
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let firstRun = runs.first else { return false }
        return CTRunGetStatus(firstRun).contains(.rightToLeft)
    }

    /// The size to rasterize a text element's offscreen image at: the text's own natural size
    /// (rounded up, height capped at the frame's height) if it fits within the frame's width
    /// without needing to wrap, or the full frame size otherwise -- the safe fallback, since
    /// correctly shrinking a WRAPPED render needs real line-layout measurement, not just this
    /// fits-on-one-line check.
    static func textImageSize(naturalSize: CGSize, frame: CGRect) -> CGSize {
        guard naturalSize.width > 0, naturalSize.height > 0, naturalSize.width <= frame.width else {
            return frame.size
        }
        return CGSize(width: ceil(naturalSize.width), height: min(ceil(naturalSize.height), frame.height))
    }

    /// Where to place a (possibly shrunk) text image within its frame, so the result is
    /// pixel-identical to having drawn the full-size text directly into `frame`: always
    /// top-anchored vertically (`NSAttributedString` always lays lines out top-down,
    /// regardless of alignment or spare height), horizontally positioned per `alignment`.
    /// Nesting a narrower alignment inside a wider one produces the same absolute position
    /// as aligning directly against the full width, for `center`/`right`/`left` (`center`:
    /// (frame.midX - imageSize.width/2) equals centering the image itself, which already
    /// centers its own content; `right`/`left`: edges stay flush either way).
    ///
    /// `natural`/`justified` need `isRightToLeft` to resolve correctly: "natural" means
    /// flush with the text's own *leading* edge, which is the frame's right edge for RTL
    /// content, not always the left -- and for a single physical line (the only case this
    /// function is used for), `justified` behaves the same as the paragraph's leading edge,
    /// since justification only stretches non-final lines. `isRightToLeft` is `@autoclosure`
    /// so callers don't pay for computing it (a real text-shaping pass, not free) except in
    /// that branch.
    static func textImageOrigin(imageSize: CGSize, frame: CGRect, alignment: NSTextAlignment, isRightToLeft: @autoclosure () -> Bool) -> CGPoint {
        let x: CGFloat
        switch alignment {
        case .right:
            x = frame.maxX - imageSize.width
        case .center:
            x = frame.midX - imageSize.width / 2
        case .left:
            x = frame.minX
        default: // .natural, .justified
            x = isRightToLeft() ? frame.maxX - imageSize.width : frame.minX
        }
        return CGPoint(x: x, y: frame.minY)
    }

    static func drawImage(_ element: [String: Any], into context: GraphicsContext, containerSize: CGSize) {
        guard let hsImage = element["image"] as? HSImage else { return }
        let rect = resolveFrame(element["frame"], containerSize: containerSize)
            ?? CGRect(origin: .zero, size: containerSize)
        let alpha = (element["imageAlpha"] as? NSNumber)?.doubleValue ?? 1.0

        var imageContext = context
        imageContext.opacity = CGFloat(alpha)
        let transform = elementTransform(element: element, pivotRect: rect, containerSize: containerSize)
        if !transform.isIdentity {
            imageContext.concatenate(transform)
        }
        // Matches v1's explicit `[NSBezierPath clipRect:cellFrame]` -- without it, "none"
        // scaling of an image larger than the frame would overflow it instead of being cropped.
        imageContext.clip(to: Path(rect))
        let drawRect = imageDrawRect(for: element, imageSize: hsImage.image.size, frame: rect)
        imageContext.draw(Image(nsImage: hsImage.image), in: drawRect)
    }

    /// Computes the sub-rect an image should actually be drawn into within its element
    /// `frame`, honoring v1's `imageScaling` (default `"scaleProportionally"`) and
    /// `imageAlignment` (default `"center"`) keys -- mirrors v1's
    /// `realRectFor:inFrame:withScaling:withAlignment:`. v1 branched on view-flippedness for
    /// vertical alignment; that's not needed here since this module's element frames are
    /// already uniformly y-down, so "top" always means the smaller `y`.
    static func imageDrawRect(for element: [String: Any], imageSize: CGSize, frame: CGRect) -> CGRect {
        let scaling = (element["imageScaling"] as? String) ?? "scaleProportionally"
        let targetSize: CGSize
        switch scaling {
        case "none": targetSize = imageSize
        case "scaleToFit": targetSize = frame.size
        case "shrinkToFit": targetSize = proportionalImageSize(imageSize, fitting: frame.size, scaleUp: false)
        default: targetSize = proportionalImageSize(imageSize, fitting: frame.size, scaleUp: true) // "scaleProportionally"
        }

        let alignment = (element["imageAlignment"] as? String) ?? "center"
        let x: CGFloat
        switch alignment {
        case "left", "topLeft", "bottomLeft": x = frame.minX
        case "right", "topRight", "bottomRight": x = frame.maxX - targetSize.width
        default: x = frame.midX - targetSize.width / 2 // "center", "top", "bottom"
        }
        let y: CGFloat
        switch alignment {
        case "top", "topLeft", "topRight": y = frame.minY
        case "bottom", "bottomLeft", "bottomRight": y = frame.maxY - targetSize.height
        default: y = frame.midY - targetSize.height / 2 // "center", "left", "right"
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: targetSize)
    }

    /// Scales `imageSize` to fit inside `frameSize` preserving aspect ratio, matching v1's
    /// `scaleProportionally()` C function. `scaleUp: false` only ever shrinks (v1's
    /// `shrinkToFit`); `scaleUp: true` scales in either direction to exactly fit one axis
    /// (v1's `scaleProportionally`, the default scaling mode).
    static func proportionalImageSize(_ imageSize: CGSize, fitting frameSize: CGSize, scaleUp: Bool) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let ratio = min(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
        guard ratio < 1.0 || scaleUp else { return imageSize }
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
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
        // Rotation/transformation pivots about the embed box's own center -- resolve the
        // pivot rect AFTER the translateBy above, in the same local (0,0)-origin space the
        // nested render() call below uses, so it doesn't have to be reasoned about relative
        // to any already-applied translation.
        let localPivotRect = CGRect(origin: .zero, size: rect.size)
        let transform = elementTransform(element: element, pivotRect: localPivotRect, containerSize: containerSize)
        if !transform.isIdentity {
            nestedContext.concatenate(transform)
        }
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

    // MARK: - Text measurement

    static func nsFontWeight(_ raw: Any?) -> NSFont.Weight? {
        guard let weight = raw as? String else { return nil }
        switch weight {
        case "black": return .black
        case "bold": return .bold
        case "heavy": return .heavy
        case "light": return .light
        case "medium": return .medium
        case "regular": return .regular
        case "semibold": return .semibold
        case "thin": return .thin
        case "ultraLight": return .ultraLight
        default: return nil
        }
    }

    static func nsFontDesign(_ raw: Any?) -> NSFontDescriptor.SystemDesign? {
        guard let design = raw as? String else { return nil }
        switch design {
        case "monospaced": return .monospaced
        case "rounded": return .rounded
        case "serif": return .serif
        default: return nil
        }
    }

    static func nsTextAlignment(_ raw: Any?) -> NSTextAlignment? {
        guard let alignment = raw as? String else { return nil }
        switch alignment {
        case "left": return .left
        case "right": return .right
        case "center": return .center
        case "justified": return .justified
        case "natural": return .natural
        default: return nil
        }
    }

    static func nsLineBreakMode(_ raw: Any?) -> NSLineBreakMode? {
        guard let wrap = raw as? String else { return nil }
        switch wrap {
        case "wordWrap": return .byWordWrapping
        case "charWrap": return .byCharWrapping
        case "clip": return .byClipping
        case "truncateHead": return .byTruncatingHead
        case "truncateMiddle": return .byTruncatingMiddle
        case "truncateTail": return .byTruncatingTail
        default: return nil
        }
    }

    /// Builds the `NSFont` a text element's `textFont`/`textSize`/`textWeight`/`textDesign`/
    /// `textItalic` keys resolve to. Used both to actually render the text (`drawText`) and
    /// to measure it (`minimumTextSize`), so an unresolvable `textFont` name only needs to be
    /// warned about in one place.
    static func resolvedNSFont(for element: [String: Any]) -> NSFont {
        let size = (element["textSize"] as? NSNumber)?.doubleValue ?? 27.0
        var font: NSFont
        if let fontName = element["textFont"] as? String {
            if let named = NSFont(name: fontName, size: size) {
                font = named
            } else {
                AKWarning("hs.canvas: textFont \"\(fontName)\" is not an installed font name, falling back to the system font")
                font = .systemFont(ofSize: size)
            }
        } else {
            let weight = nsFontWeight(element["textWeight"]) ?? .regular
            font = .systemFont(ofSize: size, weight: weight)
            if let design = nsFontDesign(element["textDesign"]), let descriptor = font.fontDescriptor.withDesign(design) {
                font = NSFont(descriptor: descriptor, size: size) ?? font
            }
        }
        if (element["textItalic"] as? NSNumber)?.boolValue ?? false {
            let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            font = NSFont(descriptor: italicDescriptor, size: size) ?? font
        }
        return font
    }

    /// Measures the minimum size needed to fully render `text` using an element's font
    /// attributes, mirroring v1's `hs.canvas:minimumTextSize()` (which used
    /// `NSString.sizeWithAttributes()` under the hood). Multi-line strings (separated by
    /// `\n`) are measured correctly for free -- `size(withAttributes:)` sizes each explicit
    /// line and returns the tallest/widest combination, it isn't a fixed single-line size.
    static func minimumTextSize(text: String, element: [String: Any]) -> CGSize {
        let font = resolvedNSFont(for: element)
        return (text as NSString).size(withAttributes: [.font: font])
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
    /// to an already-built element `Path`. Returns `path` unchanged if neither attribute
    /// is set. Thin wrapper around `elementTransform(element:pivotRect:containerSize:)` --
    /// see that function for the shared logic used by every element type, not just
    /// Path-based shapes.
    static func applyElementTransform(_ path: Path, element: [String: Any], containerSize: CGSize) -> Path {
        let transform = elementTransform(element: element, pivotRect: path.boundingRect, containerSize: containerSize)
        return transform.isIdentity ? path : path.applying(transform)
    }

    /// Computes the `CGAffineTransform` implied by an element's `transformation` matrix or
    /// `rotation` angle (`transformation` takes precedence if both are present), using
    /// `pivotRect`'s center as the default rotation pivot when no explicit `rotationPoint`
    /// is given. Returns `.identity` if neither attribute is set.
    ///
    /// Shared by `applyElementTransform` (applied to a `Path`, for shape elements) and
    /// `drawText`/`drawImage`/`drawNestedCanvas` (applied directly to a `GraphicsContext`
    /// via `concatenate`, since text/image/nested-canvas content isn't drawn via a `Path`
    /// and so has nothing for `applyElementTransform` to apply a transform to).
    static func elementTransform(element: [String: Any], pivotRect: CGRect, containerSize: CGSize) -> CGAffineTransform {
        if let matrixDict = element["transformation"] as? [String: Any] {
            return transformMatrix(matrixDict)
        }
        guard let angle = (element["rotation"] as? NSNumber)?.doubleValue else { return .identity }

        let pivot: CGPoint
        if let pointDict = element["rotationPoint"] as? [String: Any] {
            pivot = resolvePoint(pointDict, keyX: "x", keyY: "y", containerSize: containerSize)
        } else {
            pivot = CGPoint(x: pivotRect.midX, y: pivotRect.midY)
        }
        let radians = angle * .pi / 180
        return CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: radians)
            .translatedBy(x: -pivot.x, y: -pivot.y)
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
    /// - Parameter canvasTransform: The whole-canvas transform set via `setTransformation()`,
    ///   if any. Drawing already reflects this (via `GraphicsContext.concatenate` in
    ///   `HSCanvasRenderView`'s `Canvas` closure) -- hit-testing has to apply the same
    ///   transform to each tracked path, or pointer locations get compared against
    ///   geometry that no longer matches what's on screen.
    static func trackedElements(elements: [[String: Any]], containerSize: CGSize, canvasTransform: CGAffineTransform? = nil) -> [TrackedElement] {
        var result: [TrackedElement] = []
        for (index, element) in elements.enumerated() {
            let trackDown = (element["trackMouseDown"] as? Bool) ?? false
            let trackUp = (element["trackMouseUp"] as? Bool) ?? false
            let trackEnterExit = (element["trackMouseEnterExit"] as? Bool) ?? false
            let trackMove = (element["trackMouseMove"] as? Bool) ?? false
            guard trackDown || trackUp || trackEnterExit || trackMove else { continue }
            guard var path = pathFor(element: element, containerSize: containerSize) else { continue }
            if let canvasTransform {
                path = path.applying(canvasTransform)
            }
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
