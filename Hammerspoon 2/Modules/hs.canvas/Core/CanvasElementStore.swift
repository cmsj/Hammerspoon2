//
//  CanvasElementStore.swift
//  Hammerspoon 2
//

import Foundation
import Observation
import CoreGraphics

/// Observable holder for a canvas's element list.
///
/// Mutating `elements` (via `appendElements`, `setElementAttribute`, etc.) triggers
/// `HSCanvasRenderView`'s `Canvas` to redraw automatically -- the same `@Observable`
/// pattern used by `HSString`/`HSColor`/`HSImage` for hs.ui's reactive types.
@Observable
final class CanvasElementStore {
    var elements: [[String: Any]] = []

    // Whole-canvas mouse tracking flags (`canvasMouseEvents()`), for regions not covered
    // by any individual tracked element. Live-read by HSCanvasRenderView's gesture
    // handlers on each event, so changes after `show()` take effect immediately.
    var canvasTrackMouseDown = false
    var canvasTrackMouseUp = false
    var canvasTrackMouseEnterExit = false
    var canvasTrackMouseMove = false

    /// Whole-canvas 2D affine transform set via `setTransformation()`/`clearTransformation()`.
    var canvasTransform: CGAffineTransform?
}
