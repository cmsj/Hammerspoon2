//
//  CanvasAnimation.swift
//  Hammerspoon 2
//

import AppKit
import QuartzCore
import SwiftUI

// How `hs.canvas.animate()` works:
//
// While its closure runs, the module holds a `CanvasAnimationGroup` as the current animation.
// Every canvas setter still updates the model straight away (so getters return the new value),
// but an element setter also records a `CanvasAnimationTrack` (from, to, start time, duration,
// curve) in the canvas's `CanvasElementStore`, keyed by the element's stable identity and the
// attribute name. Window frame and alpha changes are handed to `NSAnimationContext` instead.
//
// `HSCanvasRenderView` draws `CanvasElementStore.presentationElements(at:containerSize:)`: the
// model with every track's interpolated value substituted in. That's a pure function of the
// time, so dropped frames and refresh rates don't matter. A `TimelineView` drives it, paused
// when there are no tracks. The group's own timer removes its tracks and resolves the promise
// when its duration has elapsed, whether or not the canvas is on screen.

/// A cubic bezier timing curve, as used by both `UnitCurve` (element tracks) and
/// `CAMediaTimingFunction` (window frame/alpha), from the same control points, so the two ease
/// identically.
struct CanvasAnimationCurve: Equatable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    static let linear = CanvasAnimationCurve(x1: 0, y1: 0, x2: 1, y2: 1)
    static let easeIn = CanvasAnimationCurve(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeOut = CanvasAnimationCurve(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = CanvasAnimationCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    static let named: [String: CanvasAnimationCurve] = [
        "linear": .linear, "easeIn": .easeIn, "easeOut": .easeOut, "easeInOut": .easeInOut,
    ]

    /// The eased progress for linear progress `t` (0-1)
    func progress(_ t: Double) -> Double {
        if self == .linear { return t }
        return UnitCurve.bezier(startControlPoint: UnitPoint(x: x1, y: y1),
                                endControlPoint: UnitPoint(x: x2, y: y2)).value(at: t)
    }

    var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }

    /// Parses an `animate()` `curve` option: a name, or `[x1, y1, x2, y2]`.
    /// - Returns: the curve, or a description of what's wrong with `raw`
    static func parse(_ raw: Any?) -> Result<CanvasAnimationCurve, CanvasAnimationOptionError> {
        guard let raw, !(raw is NSNull) else { return .success(.easeInOut) }
        if let name = raw as? String {
            guard let curve = named[name] else {
                return .failure(.init("unknown curve \"\(name)\" (use \(named.keys.sorted().joined(separator: ", ")), or [x1, y1, x2, y2])"))
            }
            return .success(curve)
        }
        if let points = raw as? [Any] {
            let numbers = points.compactMap(CanvasAnimatable.plainNumber)
            guard points.count == 4, numbers.count == 4, numbers.allSatisfy(\.isFinite) else {
                return .failure(.init("a bezier curve must be four numbers, [x1, y1, x2, y2]"))
            }
            guard (0...1).contains(numbers[0]), (0...1).contains(numbers[2]) else {
                return .failure(.init("a bezier curve's x1 and x2 must be between 0 and 1"))
            }
            return .success(CanvasAnimationCurve(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]))
        }
        return .failure(.init("curve must be a name or [x1, y1, x2, y2], not \(raw)"))
    }
}

struct CanvasAnimationOptionError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// An attribute value in a form that can be interpolated, parsed once when a track is created
/// rather than on every frame.
indirect enum CanvasAnimatable: Equatable {
    case number(Double)
    /// A percentage of the canvas size (`"50%"` is 50)
    case percent(Double)
    /// sRGB components, each 0-1
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case dict([String: CanvasAnimatable])
    case array([CanvasAnimatable])

    /// Which canvas dimension a percentage is resolved against
    enum Axis {
        case width, height, minimum
    }

    /// The element attributes that animate. Anything else (`type`, `action`, `text`, `image`,
    /// booleans, ...) changes immediately, even inside `animate()`.
    static let animatableKeys: Set<String> = [
        "frame", "center", "radius", "rotation", "rotationPoint", "transformation", "strokeWidth",
        "startAngle", "endAngle", "imageAlpha", "canvasAlpha", "textSize", "fillGradientAngle",
        "fillGradientCenter", "fillGradientColors", "roundedRectRadii", "coordinates",
        "fillColor", "strokeColor", "textColor",
    ]

    private static let colorKeys: Set<String> = ["fillColor", "strokeColor", "textColor"]

    private static let identityMatrix: [String: Any] = ["m11": 1, "m12": 0, "m21": 0, "m22": 1, "tX": 0, "tY": 0]

    /// What the renderer uses for an attribute that isn't set, so animating from an unset
    /// attribute starts from what was actually drawn. Attributes whose default depends on the
    /// element's own geometry (`rotationPoint`, `fillGradientCenter`) or has no meaningful
    /// interpolation (colors) aren't listed, and snap to their new value instead.
    private static let defaults: [String: Any] = [
        "frame": ["x": 0, "y": 0, "w": "100%", "h": "100%"],
        "center": ["x": "50%", "y": "50%"],
        "radius": "50%",
        "rotation": 0,
        "strokeWidth": 1,
        "startAngle": 0,
        "endAngle": 360,
        "imageAlpha": 1,
        "canvasAlpha": 1,
        "textSize": 27,
        "fillGradientAngle": 0,
        "roundedRectRadii": 0,
        "transformation": identityMatrix,
    ]

    /// Defaults for the keys of object-valued attributes, so `{x: 10}` can animate to
    /// `{x: 50, y: 20}`: both are filled out to the same set of keys first.
    private static let subkeyDefaults: [String: [String: Any]] = [
        "frame": ["x": 0, "y": 0, "w": "100%", "h": "100%"],
        "center": ["x": "50%", "y": "50%"],
        "transformation": identityMatrix,
        "roundedRectRadii": ["xRadius": 0, "yRadius": 0],
    ]

    /// Parses an attribute's value, or its default if `raw` is `nil`. Returns `nil` if the
    /// attribute doesn't animate or the value can't be interpolated.
    static func make(_ raw: Any?, key: String) -> CanvasAnimatable? {
        guard animatableKeys.contains(key), var raw = raw ?? defaults[key], !(raw is NSNull) else { return nil }
        if key == "roundedRectRadii", let radius = plainNumber(raw) {
            // A number means circular corners, so it can animate to or from {xRadius, yRadius}
            raw = ["xRadius": radius, "yRadius": radius]
        }
        if colorKeys.contains(key) {
            return color(raw)
        }
        if key == "fillGradientColors" {
            guard let list = raw as? [Any] else { return nil }
            let colors = list.compactMap(color)
            return colors.count == list.count ? .array(colors) : nil
        }
        if var dict = raw as? [String: Any] {
            if key == "frame" {
                // UIFrame accepts width/height as aliases for w/h
                if let width = dict.removeValue(forKey: "width"), dict["w"] == nil { dict["w"] = width }
                if let height = dict.removeValue(forKey: "height"), dict["h"] == nil { dict["h"] = height }
            }
            for (subkey, value) in subkeyDefaults[key] ?? [:] where dict[subkey] == nil {
                dict[subkey] = value
            }
            return structural(dict)
        }
        return structural(raw)
    }

    /// A number, percentage string, or an object or array of them
    private static func structural(_ raw: Any) -> CanvasAnimatable? {
        if let number = plainNumber(raw) { return .number(number) }
        if let string = raw as? String { return percent(string) }
        if let dict = raw as? [String: Any] {
            var result: [String: CanvasAnimatable] = [:]
            for (key, value) in dict {
                guard let parsed = structural(value) else { return nil }
                result[key] = parsed
            }
            return .dict(result)
        }
        if let list = raw as? [Any] {
            let items = list.compactMap(structural)
            return items.count == list.count ? .array(items) : nil
        }
        return nil
    }

    /// `raw` as a number, unless it's a boolean (which JavaScriptCore also bridges as NSNumber)
    static func plainNumber(_ raw: Any) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    /// A percentage string as `UIDimension.parse` reads it: `"fill"` or `"N%"`
    private static func percent(_ string: String) -> CanvasAnimatable? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed == "fill" { return .percent(100) }
        guard trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) else { return nil }
        return .percent(value)
    }

    private static func color(_ raw: Any) -> CanvasAnimatable? {
        guard let parsed = CanvasElementDrawing.parseColor(raw),
              let srgb = NSColor(parsed).usingColorSpace(.sRGB) else { return nil }
        return .color(red: srgb.redComponent, green: srgb.greenComponent,
                      blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    /// Whether `self` can be interpolated to `other`: the same shape, where a number and a
    /// percentage count as the same shape.
    func isCompatible(with other: CanvasAnimatable) -> Bool {
        switch (self, other) {
        case (.number, .number), (.number, .percent), (.percent, .number), (.percent, .percent), (.color, .color):
            return true
        case let (.dict(a), .dict(b)):
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in
                b[key].map(value.isCompatible) ?? false
            }
        case let (.array(a), .array(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.isCompatible(with: $1) }
        default:
            return false
        }
    }

    /// The value `progress` of the way from `from` to `to` (0 is `from`, 1 is `to`; eased
    /// progress can overshoot either). A number interpolated with a percentage is resolved to
    /// points against `containerSize`. Returns `to` if the two aren't compatible.
    static func interpolate(_ from: CanvasAnimatable, _ to: CanvasAnimatable, progress: Double,
                            axis: Axis, containerSize: CGSize) -> CanvasAnimatable {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }

        switch (from, to) {
        case let (.number(a), .number(b)):
            return .number(lerp(a, b))
        case let (.percent(a), .percent(b)):
            return .percent(lerp(a, b))
        case (.number, .percent), (.percent, .number):
            return .number(lerp(from.points(axis: axis, containerSize: containerSize),
                                to.points(axis: axis, containerSize: containerSize)))
        case let (.color(r1, g1, b1, a1), .color(r2, g2, b2, a2)):
            let clamp = { (value: Double) in min(max(value, 0), 1) }
            return .color(red: clamp(lerp(r1, r2)), green: clamp(lerp(g1, g2)),
                          blue: clamp(lerp(b1, b2)), alpha: clamp(lerp(a1, a2)))
        case let (.dict(a), .dict(b)) where Set(a.keys) == Set(b.keys):
            var result: [String: CanvasAnimatable] = [:]
            for (key, value) in a {
                // swiftlint:disable:next force_unwrapping
                result[key] = interpolate(value, b[key]!, progress: progress,
                                          axis: Self.axis(forSubkey: key) ?? axis, containerSize: containerSize)
            }
            return .dict(result)
        case let (.array(a), .array(b)) where a.count == b.count:
            return .array(zip(a, b).map {
                interpolate($0, $1, progress: progress, axis: axis, containerSize: containerSize)
            })
        default:
            return to
        }
    }

    /// The axis a percentage in an object's `key` is resolved against, as the renderer does
    /// for frames, points and segment control points, or `nil` to use the parent's.
    private static func axis(forSubkey key: String) -> Axis? {
        switch key {
        case "x", "w", "c1x", "c2x": return .width
        case "y", "h", "c1y", "c2y": return .height
        default: return nil
        }
    }

    /// A number or percentage in points
    private func points(axis: Axis, containerSize: CGSize) -> Double {
        switch self {
        case .number(let value):
            return value
        case .percent(let value):
            let length: CGFloat
            switch axis {
            case .width: length = containerSize.width
            case .height: length = containerSize.height
            case .minimum: length = min(containerSize.width, containerSize.height)
            }
            return Double(length) * value / 100
        default:
            return 0
        }
    }

    /// The value in the form the renderer reads, as a JS caller would have written it
    var rawValue: Any {
        switch self {
        case .number(let value):
            return value
        case .percent(let value):
            return "\(value)%"
        case let .color(red, green, blue, alpha):
            return ["red": red, "green": green, "blue": blue, "alpha": alpha]
        case .dict(let dict):
            return dict.mapValues(\.rawValue)
        case .array(let list):
            return list.map(\.rawValue)
        }
    }

    /// A transform as a `transformation`-style matrix, for animating the canvas-wide transform
    static func matrix(_ transform: CGAffineTransform) -> CanvasAnimatable {
        .dict(["m11": .number(transform.a), "m12": .number(transform.b), "m21": .number(transform.c),
               "m22": .number(transform.d), "tX": .number(transform.tx), "tY": .number(transform.ty)])
    }
}

/// One attribute animating from one value to another. A top-level percentage (`radius`) is
/// resolved against the smaller canvas dimension, as the renderer does.
struct CanvasAnimationTrack {
    let key: String
    let from: CanvasAnimatable
    let to: CanvasAnimatable
    let group: CanvasAnimationGroup

    /// The interpolated value at `date`: `from` before the group starts, `to` once it's done
    func value(at date: Date, containerSize: CGSize) -> CanvasAnimatable {
        let elapsed = date.timeIntervalSince(group.startDate)
        let t = group.duration > 0 ? min(max(elapsed / group.duration, 0), 1) : 1
        return CanvasAnimatable.interpolate(from, to, progress: group.curve.progress(t),
                                            axis: .minimum, containerSize: containerSize)
    }
}

/// One `hs.canvas.animate()` call: its timing, the stores it added tracks to, and its promise.
///
/// The promise resolves when the duration has elapsed: `true` if every change it made ran to
/// completion, `false` if any was interrupted (by another change to the same attribute, its
/// element or attribute being removed, or its canvas being destroyed).
final class CanvasAnimationGroup {
    let startDate: Date
    let duration: TimeInterval
    let curve: CanvasAnimationCurve

    private(set) var wasInterrupted = false
    /// Whether anything animates: a track was added, or a window frame/alpha animation began
    private(set) var hasWork = false
    private var stores: [WeakCanvasStore] = []
    private var holder: JSPromiseHolder?
    private var timer: Task<Void, Never>?
    private var onFinish: ((CanvasAnimationGroup) -> Void)?

    private struct WeakCanvasStore {
        weak var store: CanvasElementStore?
    }

    init(startDate: Date = .now, duration: TimeInterval, curve: CanvasAnimationCurve) {
        self.startDate = startDate
        self.duration = duration
        self.curve = curve
    }

    /// Records that `store` holds tracks of this group, so they're removed when it finishes
    func register(_ store: CanvasElementStore) {
        hasWork = true
        if !stores.contains(where: { $0.store === store }) {
            stores.append(WeakCanvasStore(store: store))
        }
    }

    /// Records a window frame or alpha animation, which `NSAnimationContext` runs itself
    func noteWindowAnimation() {
        hasWork = true
    }

    func markInterrupted() {
        wasInterrupted = true
    }

    /// Starts the timer that ends the group after its duration, resolving `holder` then.
    /// A group with nothing to animate ends straight away.
    func start(holder: JSPromiseHolder?, onFinish: @escaping (CanvasAnimationGroup) -> Void) {
        self.holder = holder
        self.onFinish = onFinish
        guard hasWork else {
            finish()
            return
        }
        let delay = max(0, duration - Date.now.timeIntervalSince(startDate))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Ends the group now: settles its tracks and resolves its promise
    func finish() {
        timer?.cancel()
        timer = nil
        for entry in stores {
            entry.store?.finishTracks(of: self)
        }
        stores = []
        let holder = self.holder
        let onFinish = self.onFinish
        self.holder = nil
        self.onFinish = nil
        onFinish?(self)
        holder?.resolveWith(!wasInterrupted)
    }

    /// Abandons the group without calling into JS, for module shutdown
    func cancel() {
        timer?.cancel()
        timer = nil
        for entry in stores {
            entry.store?.finishTracks(of: self)
        }
        stores = []
        holder = nil
        onFinish = nil
    }
}
