//
//  HSCanvasMouseButtonTests.swift
//  Hammerspoon 2Tests
//

import AppKit
import SwiftUI
import Testing
@testable import Hammerspoon_2

/// End-to-end checks that left clicks, right clicks and Ctrl-clicks reach `mouseCallback`
/// as the right messages, by sending real `NSEvent`s through an `HSCanvasWindow`.
///
/// Two things about real event delivery make this worth testing end to end: SwiftUI hands
/// events to gestures from inside `NSWindow.sendEvent(_:)`, before the hit view's
/// `mouseDown` runs, and `DragGesture` doesn't fire at all for a real right-button press
/// (button number 1). Synthesised events have to match real ones on both counts -- a
/// right-button `NSEvent` built with `mouseEvent(with:...)` alone carries button number 0
/// and gets treated as a left press, which hid exactly this bug.
@Suite("hs.canvas mouse button delivery tests", .serialized)
@MainActor
struct HSCanvasMouseButtonTests {
    private final class Recorder {
        var messages: [String] = []
        var locations: [CGPoint] = []
    }

    private func makeWindow(recorder: Recorder) -> HSCanvasWindow {
        let store = CanvasElementStore()
        store.elements = [
            ["type": "rectangle", "action": "fill", "frame": ["x": 0, "y": 0, "w": 100, "h": 100],
             "trackMouseDown": true, "trackMouseUp": true,
             "trackRightMouseDown": true, "trackRightMouseUp": true, "id": "both"],
        ]
        let view = HSCanvasRenderView(store: store) { message, _, x, y in
            recorder.messages.append(message)
            recorder.locations.append(CGPoint(x: x, y: y))
        }
        let window = HSCanvasWindow(
            contentRect: NSRect(x: 200, y: 200, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = HSCanvasDragHostingView(rootView: view)
        window.orderFrontRegardless()
        return window
    }

    /// Bottom-left-origin window coordinates, as AppKit uses: (30, 70) in a 100x100
    /// window is (30, 30) in the canvas's top-left-origin coordinates.
    private let location = NSPoint(x: 30, y: 70)

    private func click(_ window: HSCanvasWindow, down: NSEvent.EventType, up: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) async throws {
        for type in [down, up] {
            var event = try #require(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            if type == .rightMouseDown || type == .rightMouseUp {
                // Match a real right click, which carries button number 1.
                let cgEvent = try #require(event.cgEvent)
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: 1)
                event = try #require(NSEvent(cgEvent: cgEvent))
            }
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("Left, right and Ctrl-clicks are each reported as the correct button")
    func buttonsAreDistinguished() async throws {
        let recorder = Recorder()
        let window = makeWindow(recorder: recorder)
        defer { window.close() }
        // Let SwiftUI lay out and install its gestures before sending events.
        try await Task.sleep(for: .milliseconds(300))

        // Interleaved so each press has to set the button itself: a Ctrl-click straight
        // after a right click would pass even if it only inherited stale state.
        try await click(window, down: .rightMouseDown, up: .rightMouseUp)
        try await click(window, down: .leftMouseDown, up: .leftMouseUp)
        try await click(window, down: .leftMouseDown, up: .leftMouseUp, modifiers: .control)
        try await click(window, down: .leftMouseDown, up: .leftMouseUp)

        #expect(recorder.messages == [
            "rightMouseDown", "rightMouseUp",
            "mouseDown", "mouseUp",
            "rightMouseDown", "rightMouseUp",
            "mouseDown", "mouseUp",
        ])
        // Right clicks are delivered from AppKit rather than SwiftUI, so check they report
        // the same (flipped, top-left-origin) coordinates as every other event.
        #expect(recorder.locations.allSatisfy { $0 == CGPoint(x: 30, y: 30) })
    }
}
