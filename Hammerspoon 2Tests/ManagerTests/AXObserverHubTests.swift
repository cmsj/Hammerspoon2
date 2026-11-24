//
//  AXObserverHubTests.swift
//  Hammerspoon 2Tests
//

import Testing
import AppKit
import AXSwift
@testable import Hammerspoon_2

/// Tests for the process-wide AX observer hub that modules share.
///
/// Real AX callbacks don't reach the test runner (see HSAXWatcherRoutingTests), so delivery is
/// simulated with `deliver(element:notification:pid:)`, while registration goes through the real
/// AX API against the test app. Assertions are scoped to the test app's PID, since the hub is
/// shared with every other suite running at the same time.
@Suite("AXObserverHub tests", .serialized,
       .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"),
       .testApp)
@MainActor
struct AXObserverHubTests {
    private let hub = AXObserverHub.shared
    private let windowCreated = UIElement.AXNotification(rawValue: kAXWindowCreatedNotification as String)
    private let focusedWindowChanged = UIElement.AXNotification(rawValue: kAXFocusedWindowChangedNotification as String)

    /// The test app's PID and application element
    private func testApp() -> (pid: pid_t, element: UIElement)? {
        guard let pid = TestAppControl.pid else { return nil }
        TestAppControl.showCurrentTest()
        return (pid, UIElement(AXUIElementCreateApplication(pid)))
    }

    @Test("clients sharing a registration each receive its notifications, and the observer lasts until the last one lets go")
    func testSharedRegistration() throws {
        let (pid, app) = try #require(testApp())
        var aCount = 0
        var bCount = 0
        let a = hub.makeClient { _, _, _ in aCount += 1 }
        let b = hub.makeClient { _, _, _ in bCount += 1 }
        defer {
            a.invalidate()
            b.invalidate()
        }

        try a.add(windowCreated, element: app, pid: pid)
        try b.add(windowCreated, element: app, pid: pid)
        #expect(hub.hasObserver(for: pid))

        hub.deliver(element: app, notification: windowCreated, pid: pid)
        #expect(aCount == 1)
        #expect(bCount == 1)

        a.remove(windowCreated, element: app)
        #expect(!a.isRegistered(windowCreated, element: app))
        #expect(b.isRegistered(windowCreated, element: app))
        #expect(hub.hasObserver(for: pid))

        hub.deliver(element: app, notification: windowCreated, pid: pid)
        #expect(aCount == 1)
        #expect(bCount == 2)

        b.remove(windowCreated, element: app)
        #expect(!hub.hasObserver(for: pid))
    }

    @Test("a client only receives the notification types it registered for, in its own process")
    func testDeliveryIsScopedByNotificationAndProcess() throws {
        let (pid, app) = try #require(testApp())
        var received: [String] = []
        let client = hub.makeClient { _, notification, _ in received.append(notification.rawValue) }
        defer { client.invalidate() }

        try client.add(windowCreated, element: app, pid: pid)

        hub.deliver(element: app, notification: focusedWindowChanged, pid: pid)
        hub.deliver(element: app, notification: windowCreated, pid: pid + 100_000)
        #expect(received.isEmpty)

        hub.deliver(element: app, notification: windowCreated, pid: pid)
        #expect(received == [windowCreated.rawValue])
    }

    @Test("adding the same registration twice is not an error, and is removed once")
    func testRepeatedAddIsIdempotent() throws {
        let (pid, app) = try #require(testApp())
        let client = hub.makeClient { _, _, _ in }
        defer { client.invalidate() }

        try client.add(windowCreated, element: app, pid: pid)
        try client.add(windowCreated, element: app, pid: pid)
        #expect(client.registrationCount == 1)

        client.remove(windowCreated, element: app)
        #expect(client.registrationCount == 0)
        #expect(!hub.hasObserver(for: pid))
    }

    @Test("removeAll(pid:) and invalidate() drop a client's registrations")
    func testBulkRemoval() throws {
        let (pid, app) = try #require(testApp())
        let client = hub.makeClient { _, _, _ in }

        try client.add(windowCreated, element: app, pid: pid)
        try client.add(focusedWindowChanged, element: app, pid: pid)
        #expect(client.registrationCount == 2)

        client.removeAll(pid: pid + 100_000)
        #expect(client.registrationCount == 2)

        client.removeAll(pid: pid)
        #expect(client.registrationCount == 0)
        #expect(!hub.hasObserver(for: pid))

        try client.add(windowCreated, element: app, pid: pid)
        client.invalidate()
        #expect(client.registrationCount == 0)
        #expect(!hub.hasObserver(for: pid))
    }

    @Test("releasing a client removes its registrations")
    func testReleasedClientUnregisters() throws {
        let (pid, app) = try #require(testApp())
        var client: AXObserverHub.Client? = hub.makeClient { _, _, _ in }
        try client?.add(windowCreated, element: app, pid: pid)
        #expect(hub.hasObserver(for: pid))

        client = nil
        #expect(!hub.hasObserver(for: pid))
    }

    @Test("forgetProcess() drops every registration for a process that has quit")
    func testForgetProcess() throws {
        let (pid, app) = try #require(testApp())
        var count = 0
        let client = hub.makeClient { _, _, _ in count += 1 }
        defer { client.invalidate() }

        try client.add(windowCreated, element: app, pid: pid)
        hub.forgetProcess(pid)
        #expect(!hub.hasObserver(for: pid))
        #expect(client.registrationCount == 0)

        hub.deliver(element: app, notification: windowCreated, pid: pid)
        #expect(count == 0)
    }

    @Test("a registration that AX refuses throws, and leaves no observer behind")
    func testFailedRegistrationLeavesNothing() {
        // No process has this PID, so AX can't register anything for it
        let pid: pid_t = 999_999
        let client = hub.makeClient { _, _, _ in }
        defer { client.invalidate() }

        #expect(throws: AXError.self) {
            try client.add(windowCreated, element: UIElement(AXUIElementCreateApplication(pid)), pid: pid)
        }
        #expect(client.registrationCount == 0)
        #expect(!hub.hasObserver(for: pid))
    }
}
