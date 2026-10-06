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
/// SwiftUI hands events to gestures from inside `NSWindow.sendEvent(_:)`, before the
/// hit view's `mouseDown`/`rightMouseDown` run, so the button is only knowable if it's
/// captured in the window. These tests go through that real path rather than calling the
/// hit-testing helpers directly.
@Suite("hs.canvas mouse button delivery tests", .serialized)
@MainActor
struct HSCanvasMouseButtonTests {
    private final class Recorder {
        var messages: [String] = []
    }

    private func makeWindow(recorder: Recorder) -> HSCanvasWindow {
        let store = CanvasElementStore()
        store.elements = [
            ["type": "rectangle", "action": "fill", "frame": ["x": 0, "y": 0, "w": 100, "h": 100],
             "trackMouseDown": true, "trackMouseUp": true,
             "trackRightMouseDown": true, "trackRightMouseUp": true, "id": "both"],
        ]
        let view = HSCanvasRenderView(store: store) { message, _, _, _ in
            recorder.messages.append(message)
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

    private func click(_ window: HSCanvasWindow, down: NSEvent.EventType, up: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) async throws {
        for type in [down, up] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 50, y: 50), modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
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
    }
}
