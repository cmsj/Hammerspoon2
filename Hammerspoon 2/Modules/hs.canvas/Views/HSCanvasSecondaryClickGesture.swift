//
//  HSCanvasSecondaryClickGesture.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// SwiftUI gesture that reports right mouse button presses and releases.
///
/// `DragGesture` only ever sees the primary (left) button, so `HSCanvasRenderView`
/// attaches this alongside it to deliver `rightMouseDown`/`rightMouseUp`. The two never
/// compete for the same events, so no gesture-priority coordination is needed.
struct HSCanvasSecondaryClickGesture: NSGestureRecognizerRepresentable {
    enum Phase {
        case down, up
    }

    var action: (_ phase: Phase, _ location: CGPoint) -> Void

    func makeNSGestureRecognizer(context: Context) -> SecondaryButtonRecognizer {
        SecondaryButtonRecognizer()
    }

    func handleNSGestureRecognizerAction(_ recognizer: SecondaryButtonRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            action(.down, location)
        case .ended:
            action(.up, location)
        default:
            break
        }
    }

    /// Recognizes a single right-button press: `.began` on mouse-down, `.ended` on
    /// mouse-up. Primary-button events fail it immediately, so it never holds left
    /// clicks in `.possible` while `DragGesture` is handling them.
    final class SecondaryButtonRecognizer: NSGestureRecognizer {
        override func rightMouseDown(with event: NSEvent) {
            state = .began
        }

        override func rightMouseUp(with event: NSEvent) {
            state = .ended
        }

        override func mouseDown(with event: NSEvent) {
            state = .failed
        }
    }
}
