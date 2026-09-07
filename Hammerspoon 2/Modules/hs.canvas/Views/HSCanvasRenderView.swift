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

    /// The id of whatever currently owns enter/exit tracking under the cursor: a specific
    /// tracked element's id, `Self.canvasSentinelID` (hovering background with
    /// `canvasTrackMouseEnterExit` enabled), or `nil` if neither applies. Stored as the
    /// actual id value (not a stringified key) so `clearHover()` can emit a correctly
    /// typed `mouseExit` for it without needing to re-run `trackedElements()` after the
    /// pointer has already left the view.
    @State private var hoveredID: Any?
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
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size, canvasTransform: store.canvasTransform)
        let enterExitHit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .enterExit)
        let moveHit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .move)

        let transition = Self.resolveEnterExitTransition(
            currentTargetID: hoveredID,
            enterExitHit: enterExitHit,
            canvasTrackMouseEnterExit: store.canvasTrackMouseEnterExit
        )
        if let exitID = transition.exitID {
            onMouseEvent?("mouseExit", exitID, location.x, location.y)
        }
        hoveredID = transition.newTargetID
        if let enterID = transition.enterID {
            onMouseEvent?("mouseEnter", enterID, location.x, location.y)
        }

        if let hit = moveHit {
            onMouseEvent?("mouseMove", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseMove {
            onMouseEvent?("mouseMove", Self.canvasSentinelID, location.x, location.y)
        }
    }

    /// Pure decision logic for enter/exit transitions: given what currently owns enter/exit
    /// tracking and the latest hit-test result, determines the new target and which
    /// exit/enter callbacks (if any) should fire. Extracted out of `updateHover` so this
    /// logic -- including the `canvasTrackMouseEnterExit` whole-canvas case -- is directly
    /// unit-testable without instantiating SwiftUI hover gestures.
    static func resolveEnterExitTransition(
        currentTargetID: Any?,
        enterExitHit: CanvasElementDrawing.TrackedElement?,
        canvasTrackMouseEnterExit: Bool
    ) -> (newTargetID: Any?, exitID: Any?, enterID: Any?) {
        let newTargetID: Any? = enterExitHit?.id ?? (canvasTrackMouseEnterExit ? Self.canvasSentinelID : nil)
        guard String(describing: newTargetID) != String(describing: currentTargetID) else {
            return (currentTargetID, nil, nil)
        }
        return (newTargetID, currentTargetID, newTargetID)
    }

    private func clearHover() {
        // The pointer has left the view entirely -- fire the exit callback for whatever
        // was hovered (a tracked element or the whole-canvas sentinel), since a move
        // straight from inside a shape to outside the canvas bounds never passes through
        // updateHover()'s own transition check.
        if let previousID = hoveredID {
            onMouseEvent?("mouseExit", previousID, -1, -1)
        }
        hoveredID = nil
    }

    private func handleMouseDown(at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size, canvasTransform: store.canvasTransform)
        if let hit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .down) {
            onMouseEvent?("mouseDown", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseDown {
            onMouseEvent?("mouseDown", Self.canvasSentinelID, location.x, location.y)
        }
    }

    private func handleMouseUp(at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size, canvasTransform: store.canvasTransform)
        if let hit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: .up) {
            onMouseEvent?("mouseUp", hit.id, location.x, location.y)
        } else if store.canvasTrackMouseUp {
            onMouseEvent?("mouseUp", Self.canvasSentinelID, location.x, location.y)
        }
    }
}
