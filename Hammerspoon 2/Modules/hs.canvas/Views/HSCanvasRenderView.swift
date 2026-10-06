//
//  HSCanvasRenderView.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// SwiftUI `Canvas` that replays the element list on every redraw, plus mouse-tracking
/// delivery for `mouseCallback`/`canvasMouseEvents`.
///
/// Deliberately not named `HSCanvasView` -- `Modules/hs.ui/Views/UICanvasView.swift`
/// already uses that name for hs.ui's unrelated root view, and reusing it here
/// would conflate two different "canvas" concepts in the codebase.
///
/// Mouse delivery is SwiftUI-native (`.onContinuousHover`/`DragGesture`, plus
/// `HSCanvasSecondaryClickGesture` for the right button, which `DragGesture` never
/// sees; Ctrl-clicks arrive via `DragGesture` and are re-routed as right clicks) rather than a separate `NSTrackingArea`-based overlay: per-element hit-testing walks a cached
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
    /// Which button the in-progress `DragGesture` press is being reported as, or `nil` when
    /// no press is active. Fixed at mouse-down so a Ctrl-click still ends as `rightMouseUp`
    /// if Ctrl is released before the button.
    @State private var activePress: PressButton?

    enum PressButton {
        case primary, secondary
    }

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
                        guard activePress == nil else { return }
                        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                        let button = Self.pressButton(forModifiers: modifiers)
                        activePress = button
                        switch button {
                        case .primary:
                            handleMouseDown(at: value.location, size: geometry.size)
                        case .secondary:
                            handleRightMouseDown(at: value.location, size: geometry.size)
                        }
                    }
                    .onEnded { value in
                        let button = activePress ?? .primary
                        activePress = nil
                        switch button {
                        case .primary:
                            handleMouseUp(at: value.location, size: geometry.size)
                        case .secondary:
                            handleRightMouseUp(at: value.location, size: geometry.size)
                        }
                    }
            )
            .gesture(
                HSCanvasSecondaryClickGesture { phase, location in
                    switch phase {
                    case .down:
                        handleRightMouseDown(at: location, size: geometry.size)
                    case .up:
                        handleRightMouseUp(at: location, size: geometry.size)
                    }
                }
            )
        }
    }

    /// Maps the modifiers held at a primary-button mouse-down to the button it's reported
    /// as: Ctrl-click is the standard macOS secondary click, so it's delivered as
    /// `rightMouseDown`/`rightMouseUp` rather than `mouseDown`/`mouseUp`.
    static func pressButton(forModifiers modifiers: NSEvent.ModifierFlags) -> PressButton {
        modifiers.contains(.control) ? .secondary : .primary
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
        deliverButtonEvent("mouseDown", kind: .down, canvasTracks: store.canvasTrackMouseDown, at: location, size: size)
    }

    private func handleMouseUp(at location: CGPoint, size: CGSize) {
        deliverButtonEvent("mouseUp", kind: .up, canvasTracks: store.canvasTrackMouseUp, at: location, size: size)
    }

    private func handleRightMouseDown(at location: CGPoint, size: CGSize) {
        deliverButtonEvent("rightMouseDown", kind: .rightDown, canvasTracks: store.canvasTrackRightMouseDown, at: location, size: size)
    }

    private func handleRightMouseUp(at location: CGPoint, size: CGSize) {
        deliverButtonEvent("rightMouseUp", kind: .rightUp, canvasTracks: store.canvasTrackRightMouseUp, at: location, size: size)
    }

    /// Delivers a button event to the topmost element tracking `kind`, falling back to the
    /// whole-canvas sentinel when `canvasTracks` is enabled and no element was hit.
    private func deliverButtonEvent(_ message: String, kind: CanvasElementDrawing.MouseTrackingKind, canvasTracks: Bool, at location: CGPoint, size: CGSize) {
        let tracked = CanvasElementDrawing.trackedElements(elements: store.elements, containerSize: size, canvasTransform: store.canvasTransform)
        if let hit = CanvasElementDrawing.topmostHit(at: location, in: tracked, for: kind) {
            onMouseEvent?(message, hit.id, location.x, location.y)
        } else if canvasTracks {
            onMouseEvent?(message, Self.canvasSentinelID, location.x, location.y)
        }
    }
}
