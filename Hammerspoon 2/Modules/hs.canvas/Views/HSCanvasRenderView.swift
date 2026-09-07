//
//  HSCanvasRenderView.swift
//  Hammerspoon 2
//

import SwiftUI

/// SwiftUI `Canvas` that replays the element list on every redraw, plus mouse-tracking
/// delivery for `mouseCallback`/`canvasMouseEvents`.
///
/// Deliberately not named `HSCanvasView` -- `Modules/hs.ui/Views/UICanvasView.swift`
/// already uses that name for hs.ui's unrelated root view, and reusing it here
/// would conflate two different "canvas" concepts in the codebase.
///
/// Mouse delivery is SwiftUI-native (`.onContinuousHover`/`DragGesture`) rather than a
/// separate `NSTrackingArea`-based overlay: per-element hit-testing walks a cached
/// `Path` list (`CanvasElementDrawing.trackedElements`/`topmostHit`, built fresh from
/// the current element list on each event) in reverse z-order, exactly mirroring v1's
/// single-`mouseCallback`-with-topmost-element-wins model.
struct HSCanvasRenderView: View {
    var store: CanvasElementStore
    var onMouseEvent: ((_ message: String, _ id: Any, _ x: Double, _ y: Double) -> Void)? = nil

    /// Sentinel id passed to `onMouseEvent` for whole-canvas tracking (`canvasMouseEvents`)
    /// when no individual element was hit.
    static let canvasSentinelID = "_canvas"

    @State private var hoveredKey: String?
    @State private var isPressed = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var working = context
                if let transform = store.canvasTransform {
                    working.concatenate(transform)
                }
                CanvasElementDrawing.render(elements: store.elements, into: working, size: size)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                handleHover(phase, size: geometry.size)
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !isPressed else { return }
                        isPressed = true
                        handleMouseDown(at: value.location, size: geometry.size)
                    }
                    .onEnded { value in
                        isPressed = false
                        handleMouseUp(at: value.location, size: geometry.size)
                    }
            )
        }
    }

    private func handleHover(_ phase: HoverPhase, size: CGSize) {
        switch phase {
        case .active(let location):
            updateHover(at: location, size: size)
        case .ended:
            clearHover()
        @unknown default:
            clearHover()
        }
    }

    private func updateHover(at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size)
        let enterExitHit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .enterExit)
        let moveHit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .move)
        let newKey = (enterExitHit ?? moveHit).map { String(describing: $0.id) }

        if newKey != hoveredKey {
            if let previousKey = hoveredKey,
               let previous = tracked.first(where: { String(describing: $0.id) == previousKey }),
               previous.trackMouseEnterExit {
                onMouseEvent?("mouseExit", previous.id, location.x, location.y)
            }
            hoveredKey = newKey
            if let hit = enterExitHit {
                onMouseEvent?("mouseEnter", hit.id, location.x, location.y)
            }
        }

        if let hit = moveHit {
            onMouseEvent?("mouseMove", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseMove {
            onMouseEvent?("mouseMove", Self.canvasSentinelID, location.x, location.y)
        }
    }

    private func clearHover() {
        hoveredKey = nil
    }

    private func handleMouseDown(at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size)
        if let hit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .down) {
            onMouseEvent?("mouseDown", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseDown {
            onMouseEvent?("mouseDown", Self.canvasSentinelID, location.x, location.y)
        }
    }

    private func handleMouseUp(at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size)
        if let hit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .up) {
            onMouseEvent?("mouseUp", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseUp {
            onMouseEvent?("mouseUp", Self.canvasSentinelID, location.x, location.y)
        }
    }
}
