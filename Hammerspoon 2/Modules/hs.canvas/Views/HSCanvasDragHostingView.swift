//
//  HSCanvasDragHostingView.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// `NSHostingView` subclass that adds `NSDraggingDestination` support, so `HSCanvas` can
/// expose a `draggingCallback` -- SwiftUI has no drag-and-drop *destination* API of its
/// own for arbitrary file/string drops onto a window, so this drops to AppKit directly.
///
/// It also handles the right mouse button, which the root view's `DragGesture` never
/// fires for, and owns the root view's `pressState`, which `HSCanvas.show()` also hands to
/// the `HSCanvasWindow` so it can feed it each left mouse-down.
@MainActor
final class HSCanvasDragHostingView: NSHostingView<HSCanvasRenderView> {
    /// Called with the dropped file paths (or the dropped string, as a single-element
    /// array) when a drag operation completes over this view.
    var onDrop: (([String]) -> Void)?

    let pressState = HSCanvasPressState()

    required init(rootView: HSCanvasRenderView) {
        var rootView = rootView
        rootView.pressState = pressState
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HSCanvasDragHostingView does not support NSCoding")
    }

    // `isFlipped` is true for NSHostingView, so converted locations are already in the
    // root view's top-left-origin coordinate space.
    override func rightMouseDown(with event: NSEvent) {
        rootView.handleRightMouseDown(at: convert(event.locationInWindow, from: nil), size: bounds.size)
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        rootView.handleRightMouseUp(at: convert(event.locationInWindow, from: nil), size: bounds.size)
        super.rightMouseUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDrop != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onDrop else { return false }

        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            onDrop(urls.map { $0.path })
            return true
        }
        if let string = sender.draggingPasteboard.string(forType: .string) {
            onDrop([string])
            return true
        }
        return false
    }
}
