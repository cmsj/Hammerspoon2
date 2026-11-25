//
//  CanvasElementStore.swift
//  Hammerspoon 2
//

import Foundation
import Observation
import CoreGraphics

/// Observable holder for a canvas's element list, and the animations running on it.
///
/// Mutating `elements` (via `appendElements`, `setElementAttribute`, etc.) triggers
/// `HSCanvasRenderView`'s `Canvas` to redraw automatically -- the same `@Observable`
/// pattern used by `HSString`/`HSColor`/`HSImage` for hs.ui's reactive types.
///
/// `elements` is the model: what JS set, and what the getters return. What's drawn is
/// `presentationElements(at:containerSize:)`, which is the model with any running
/// `hs.canvas.animate()` tracks interpolated in.
@Observable
final class CanvasElementStore {
    /// The element list. Prefer the mutating methods below, which keep each element's
    /// identity (and so its animations) as elements are added and removed. Assigning the
    /// whole list directly gives every element a new identity if the count changes.
    var elements: [[String: Any]] = [] {
        didSet {
            if elementIDs.count != elements.count {
                cancelAllElementTracks()
                elementIDs = elements.map { _ in UUID() }
            }
        }
    }

    /// A stable identity for each element, parallel to `elements`, so an animation follows
    /// its element when others are inserted or removed before it
    private(set) var elementIDs: [UUID] = []

    /// Running animation tracks, by element identity and then attribute name
    private(set) var tracks: [UUID: [String: CanvasAnimationTrack]] = [:]

    /// The running animation of the canvas-wide transform, if any
    private(set) var transformTrack: CanvasAnimationTrack?

    // Whole-canvas mouse tracking flags (`canvasMouseEvents()`), for regions not covered
    // by any individual tracked element. Live-read by HSCanvasRenderView's gesture
    // handlers on each event, so changes after `show()` take effect immediately.
    var canvasTrackMouseDown = false
    var canvasTrackMouseUp = false
    var canvasTrackRightMouseDown = false
    var canvasTrackRightMouseUp = false
    var canvasTrackMouseEnterExit = false
    var canvasTrackMouseMove = false

    /// Whole-canvas 2D affine transform set via `setTransformation()`/`clearTransformation()`.
    private(set) var canvasTransform: CGAffineTransform?

    /// Whether any animation is running, which keeps `HSCanvasRenderView`'s timeline ticking
    var isAnimating: Bool { !tracks.isEmpty || transformTrack != nil }

    // MARK: - Structural changes

    func append(_ newElements: [[String: Any]]) {
        elementIDs.append(contentsOf: newElements.map { _ in UUID() })
        elements.append(contentsOf: newElements)
    }

    func insert(_ element: [String: Any], at index: Int) {
        elementIDs.insert(UUID(), at: index)
        elements.insert(element, at: index)
    }

    func remove(at index: Int) {
        cancelTracks(of: elementIDs[index])
        elementIDs.remove(at: index)
        elements.remove(at: index)
    }

    /// Replaces the whole list, giving every element a new identity
    func replaceAll(_ newElements: [[String: Any]]) {
        cancelAllElementTracks()
        elementIDs = newElements.map { _ in UUID() }
        elements = newElements
    }

    /// Replaces the element at `index` with `element`, keeping its identity, so inside
    /// `animate()` every animatable attribute that differs animates to its new value.
    /// Unchanged attributes are left alone, so a running animation of one keeps going.
    func assign(_ element: [String: Any], at index: Int, animation: CanvasAnimationGroup?, containerSize: CGSize) {
        let current = elements[index]
        let keys = Set(current.keys).union(element.keys)
        for key in keys where !Self.isSameValue(current[key], element[key]) {
            setAttribute(at: index, key: key, value: element[key], animation: animation, containerSize: containerSize)
        }
    }

    /// Whether two attribute values are equal, comparing them as the Foundation objects
    /// JavaScriptCore bridges them to. Booleans only equal booleans, although `NSNumber`
    /// would otherwise call `true` and `1` equal.
    static func isSameValue(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a as [String: Any], b as [String: Any]):
            return a.count == b.count && a.allSatisfy { key, value in b[key].map { isSameValue(value, $0) } ?? false }
        case let (a as [Any], b as [Any]):
            return a.count == b.count && zip(a, b).allSatisfy { isSameValue($0, $1) }
        case let (a?, b?):
            if isBoolean(a) != isBoolean(b) { return false }
            return (a as AnyObject).isEqual(b as AnyObject)
        default:
            return false
        }
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Clears the elements, transform and every animation, for `HSCanvas.destroy()`
    func removeAll() {
        replaceAll([])
        setCanvasTransform(nil, animation: nil)
    }

    // MARK: - Attribute changes

    /// Sets (or, for `nil`, removes) an attribute of the element at `index`. With an
    /// `animation`, an animatable attribute animates from its current displayed value to the
    /// new one. Either way, a running animation of that attribute is replaced.
    func setAttribute(at index: Int, key: String, value: Any?, animation: CanvasAnimationGroup?, containerSize: CGSize) {
        let id = elementIDs[index]
        if let animation, let to = CanvasAnimatable.make(value, key: key) {
            // Start from what's on screen, so retargeting a running animation doesn't jump
            let from = tracks[id]?[key]?.value(at: animation.startDate, containerSize: containerSize)
                ?? CanvasAnimatable.make(elements[index][key], key: key)
            if let start = from, start != to, start.isCompatible(with: to) {
                cancelTrack(of: id, key: key)
                tracks[id, default: [:]][key] = CanvasAnimationTrack(key: key, from: start, to: to, group: animation)
                animation.register(self)
                storeModelValue(value, at: index, key: key)
                return
            }
        }
        cancelTrack(of: id, key: key)
        storeModelValue(value, at: index, key: key)
    }

    private func storeModelValue(_ value: Any?, at index: Int, key: String) {
        if let value {
            elements[index][key] = value
        } else {
            elements[index].removeValue(forKey: key)
        }
    }

    /// Sets the canvas-wide transform, animating it with an `animation`
    func setCanvasTransform(_ transform: CGAffineTransform?, animation: CanvasAnimationGroup?) {
        let previous = transformTrack
        if let previous {
            previous.group.markInterrupted()
            transformTrack = nil
        }
        if let animation {
            let from = previous?.value(at: animation.startDate, containerSize: .zero)
                ?? CanvasAnimatable.matrix(canvasTransform ?? .identity)
            let to = CanvasAnimatable.matrix(transform ?? .identity)
            if from != to {
                transformTrack = CanvasAnimationTrack(key: "transformation", from: from, to: to, group: animation)
                animation.register(self)
            }
        }
        canvasTransform = transform
    }

    // MARK: - Presentation

    /// The elements as they should be drawn at `date`: the model, with each running track's
    /// interpolated value in place of its attribute
    func presentationElements(at date: Date, containerSize: CGSize) -> [[String: Any]] {
        guard !tracks.isEmpty else { return elements }
        var result = elements
        for (index, id) in elementIDs.enumerated() {
            guard let elementTracks = tracks[id] else { continue }
            for (key, track) in elementTracks {
                result[index][key] = track.value(at: date, containerSize: containerSize).rawValue
            }
        }
        return result
    }

    /// The canvas-wide transform as it should be drawn at `date`
    func presentationTransform(at date: Date) -> CGAffineTransform? {
        guard let transformTrack else { return canvasTransform }
        let value = transformTrack.value(at: date, containerSize: .zero)
        guard let matrix = value.rawValue as? [String: Any] else { return canvasTransform }
        return CanvasElementDrawing.transformMatrix(matrix)
    }

    // MARK: - Ending tracks

    /// Removes `group`'s tracks once it has run its course, leaving the model values drawn
    func finishTracks(of group: CanvasAnimationGroup) {
        for (id, elementTracks) in tracks {
            let remaining = elementTracks.filter { $0.value.group !== group }
            if remaining.count != elementTracks.count {
                tracks[id] = remaining.isEmpty ? nil : remaining
            }
        }
        if transformTrack?.group === group {
            transformTrack = nil
        }
    }

    private func cancelTrack(of id: UUID, key: String) {
        guard let track = tracks[id]?[key] else { return }
        track.group.markInterrupted()
        tracks[id]?[key] = nil
        if tracks[id]?.isEmpty == true {
            tracks[id] = nil
        }
    }

    private func cancelTracks(of id: UUID) {
        guard let elementTracks = tracks.removeValue(forKey: id) else { return }
        elementTracks.values.forEach { $0.group.markInterrupted() }
    }

    private func cancelAllElementTracks() {
        guard !tracks.isEmpty else { return }
        tracks.values.flatMap(\.values).forEach { $0.group.markInterrupted() }
        tracks = [:]
    }
}
