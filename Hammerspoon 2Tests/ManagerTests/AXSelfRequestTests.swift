//
//  AXSelfRequestTests.swift
//  Hammerspoon 2Tests
//

import Testing
import AppKit
import AXSwift
@testable import Hammerspoon_2

/// Tests for Accessibility requests Hammerspoon makes to its own process: the guard that keeps
/// them on the main thread, and the hub's AppKit-made notifications for its own windows.
///
/// Requests to Hammerspoon's own process are answered in-process, so none of this needs
/// Accessibility permission.
@MainActor
struct AXSelfRequestTests {
    /// A titled window on screen, and its AX element
    private static func makeWindow(title: String) throws -> (NSWindow, UIElement) {
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 240, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.orderFrontRegardless()
        let app = UIElement(AXUIElementCreateApplication(getpid()))
        let windows: [UIElement] = try #require(try app.arrayAttribute(.windows))
        let element = try #require(windows.first { Int(WindowEnumerator.windowID(of: $0)) == window.windowNumber })
        return (window, element)
    }

    /// Polls `condition` on the main actor, letting the main queue run in between
    private static func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Suite("Accessibility requests to Hammerspoon's own process")
    @MainActor
    struct GuardTests {
        @Test("only requests to Hammerspoon's own process made off the main thread are refused")
        func testRefusal() async {
            let own = AXSelfRequestGuard.ownProcessID
            #expect(AXSelfRequestGuard.refusal(forProcessID: own) == nil)
            let offMain = await Task.detached {
                (AXSelfRequestGuard.refusal(forProcessID: own), AXSelfRequestGuard.refusal(forProcessID: own + 100_000))
            }.value
            #expect(offMain.0 == .cannotComplete)
            #expect(offMain.1 == nil)
        }

        @Test("the guard is installed into AXSwift at launch")
        func testInstalled() {
            #expect(UIElement.requestGate != nil)
        }

        // Without the guard, the background request is answered by running the window's
        // NSAccessibility code on the background thread
        @Test("AXSwift refuses a request to one of Hammerspoon's own windows off the main thread, but answers it on the main thread")
        func testAXSwiftRequests() async throws {
            let (window, element) = try makeWindow(title: "Self-request guard test")
            defer { window.orderOut(nil) }

            #expect(try element.attribute(.title) == "Self-request guard test")

            nonisolated(unsafe) let unsafeElement = element
            let offMain = await Task.detached { () -> AXError? in
                do throws(AXError) {
                    let _: String? = try unsafeElement.attribute(.title)
                    return nil
                } catch {
                    return error
                }
            }.value
            #expect(offMain == .cannotComplete)
        }
    }

    @Suite("AXObserverHub notifications for Hammerspoon's own windows", .serialized)
    @MainActor
    struct OwnWindowNotificationTests {
        private let hub = AXObserverHub.shared
        private let own = AXSelfRequestGuard.ownProcessID
        private let appElement = UIElement(AXUIElementCreateApplication(getpid()))

        private func notification(_ name: String) -> UIElement.AXNotification {
            UIElement.AXNotification(rawValue: name)
        }

        @Test("only the window notifications, on the application or a window, can be registered for")
        func testUnsupportedRegistrations() throws {
            let client = hub.makeClient { _, _, _ in }
            defer { client.invalidate() }
            #expect(throws: AXError.notificationUnsupported) {
                try client.add(notification(kAXValueChangedNotification), element: appElement, pid: own)
            }
            #expect(!hub.hasObserver(for: own))

            try client.add(notification(kAXWindowCreatedNotification), element: appElement, pid: own)
            #expect(hub.hasObserver(for: own))
            client.invalidate()
            #expect(!hub.hasObserver(for: own))
        }

        @Test("a window's appearance, moves, retitling and disappearance are posted, after the change")
        func testWindowLifecycle() async throws {
            var received: [(name: String, element: UIElement)] = []
            let client = hub.makeClient { element, notification, pid in
                guard pid == AXSelfRequestGuard.ownProcessID else { return }
                received.append((notification.rawValue, element))
            }
            defer { client.invalidate() }
            for name in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXTitleChangedNotification] {
                try client.add(notification(name), element: appElement, pid: own)
            }

            let (window, element) = try AXSelfRequestTests.makeWindow(title: "Own window notifications")
            defer { window.orderOut(nil) }
            // An ordered-out window's element no longer says which window it is, so match elements
            func saw(_ name: String) -> Bool { received.contains { $0.name == name && $0.element == element } }

            #expect(await AXSelfRequestTests.waitUntil { saw(kAXWindowCreatedNotification) })

            // Posted asynchronously, so not while AppKit is still moving it
            window.setFrameOrigin(NSPoint(x: 200, y: 200))
            #expect(!saw(kAXWindowMovedNotification))
            #expect(await AXSelfRequestTests.waitUntil { saw(kAXWindowMovedNotification) })

            window.title = "Retitled"
            #expect(await AXSelfRequestTests.waitUntil { saw(kAXTitleChangedNotification) })

            window.orderOut(nil)
            #expect(await AXSelfRequestTests.waitUntil { saw(kAXUIElementDestroyedNotification) })

            // Ordered back in, it's a new window as far as AX is concerned
            received.removeAll()
            window.orderFrontRegardless()
            #expect(await AXSelfRequestTests.waitUntil {
                received.contains { $0.name == kAXWindowCreatedNotification && Int(WindowEnumerator.windowID(of: $0.element)) == window.windowNumber }
            })
            let reshown = try #require(received.first { $0.name == kAXWindowCreatedNotification }?.element)

            window.close()
            #expect(await AXSelfRequestTests.waitUntil {
                received.contains { $0.name == kAXUIElementDestroyedNotification && $0.element == reshown }
            })
        }
    }
}
