//
//  HSCanvasDragHostingView.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// `NSHostingView` subclass that adds `NSDraggingDestination` support, so `HSCanvas` can
/// expose a `draggingCallback` -- SwiftUI has no drag-and-drop *destination* API of its
/// own for arbitrary file/string drops onto a window, so this drops to AppKit directly.
@MainActor
final class HSCanvasDragHostingView: NSHostingView<HSCanvasRenderView> {
    /// Called with the dropped file paths (or the dropped string, as a single-element
    /// array) when a drag operation completes over this view.
    var onDrop: (([String]) -> Void)?

    required init(rootView: HSCanvasRenderView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HSCanvasDragHostingView does not support NSCoding")
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
