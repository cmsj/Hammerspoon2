//
//  HSNotifyIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Chris Jones on 13/05/2026.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Suite 1: hs.notify API structure

/// Tests that all expected functions and properties exist on hs.notify.
/// No notifications are displayed — we have no way to verify display in a test runner,
/// and the runner will not have notification permission.
@Suite("hs.notify API structure tests")
struct HSNotifyStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSNotifyModule.self, as: "notify")
        return harness
    }

    @Test("show is a function")
    func testShowIsFunction() {
        makeHarness().expectTrue("typeof hs.notify.show === 'function'")
    }

    @Test("create is a function")
    func testCreateIsFunction() {
        makeHarness().expectTrue("typeof hs.notify.create === 'function'")
    }

    @Test("removeAllDelivered is a function")
    func testRemoveAllDeliveredIsFunction() {
        makeHarness().expectTrue("typeof hs.notify.removeAllDelivered === 'function'")
    }

    @Test("removeAllPending is a function")
    func testRemoveAllPendingIsFunction() {
        makeHarness().expectTrue("typeof hs.notify.removeAllPending === 'function'")
    }

    @Test("new() returns null when called without a title")
    func testCreateWithoutTitleReturnsNull() {
        let harness = makeHarness()
        harness.expectTrue(
            "(function() { var n = hs.notify.create({}); return n === null || n === undefined; })()"
        )
        #expect(!harness.hasException)
    }

    @Test("new() throws when passed a non-object")
    func testCreateWithNonObjectReturnsNull() {
        let harness = makeHarness()
        harness.eval("hs.notify.create('oops')")
        #expect(harness.hasException)
    }

    @Test("new() returns an object when given a valid title")
    func testCreateReturnsObject() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.notify.create({ title: 'Test' }) === 'object'")
    }

    @Test("HSNotification has an identifier string")
    func testNotificationHasIdentifier() {
        let harness = makeHarness()
        harness.expectTrue(
            "typeof hs.notify.create({ title: 'Test' }).identifier === 'string'"
        )
    }

    @Test("HSNotification.identifier is a non-empty string")
    func testNotificationIdentifierIsNonEmpty() {
        let harness = makeHarness()
        harness.expectTrue(
            "hs.notify.create({ title: 'Test' }).identifier.length > 0"
        )
    }

    @Test("two notifications have different identifiers")
    func testNotificationsHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.notify.create({ title: 'A' });
                var b = hs.notify.create({ title: 'B' });
                return a.identifier !== b.identifier;
            })()
        """)
    }

    @Test("HSNotification.send is a function")
    func testNotificationSendIsFunction() {
        let harness = makeHarness()
        harness.expectTrue(
            "typeof hs.notify.create({ title: 'Test' }).send === 'function'"
        )
    }

    @Test("HSNotification.withdraw is a function")
    func testNotificationWithdrawIsFunction() {
        let harness = makeHarness()
        harness.expectTrue(
            "typeof hs.notify.create({ title: 'Test' }).withdraw === 'function'"
        )
    }

    @Test("HSNotification.send() returns the notification itself (for chaining)")
    func testSendReturnsSelf() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var n = hs.notify.create({ title: 'Chain test' });
                return n.send() === n;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("withdraw() can be called without throwing")
    func testWithdrawDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("""
            var _nwn = hs.notify.create({ title: 'Withdraw test' });
            _nwn.send();
            _nwn.withdraw();
        """)
        #expect(!harness.hasException)
    }

    @Test("removeAllDelivered() does not throw")
    func testRemoveAllDeliveredDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.notify.removeAllDelivered()")
        #expect(!harness.hasException)
    }

    @Test("removeAllPending() does not throw")
    func testRemoveAllPendingDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.notify.removeAllPending()")
        #expect(!harness.hasException)
    }

    @Test("new() accepts all documented options without throwing")
    func testCreateAcceptsAllOptions() {
        let harness = makeHarness()
        harness.eval("""
            hs.notify.create({
                title:           'Full options test',
                subtitle:        'Subtitle',
                body:            'Body text',
                sound:           true,
                badge:           1,
                threadIdentifier: 'thread-1',
                userInfo:        { key: 'value' },
                interruptionLevel: 'active',
                actions: [
                    { identifier: 'OK',     title: 'OK' },
                    { identifier: 'CANCEL', title: 'Cancel', destructive: true },
                    { identifier: 'REPLY',  title: 'Reply',  textInput: true,
                      textInputButtonTitle: 'Send', textInputPlaceholder: 'Type...' }
                ],
                callback: function(r) {}
            })
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 2: hs.permissions notification methods

@Suite("hs.permissions notification API tests")
struct HSNotifyPermissionsTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPermissionsModule.self, as: "permissions")
        return harness
    }

    @Test("checkNotifications is a function")
    func testCheckNotificationsIsFunction() {
        makeHarness().expectTrue("typeof hs.permissions.checkNotifications === 'function'")
    }

    @Test("requestNotifications is a function")
    func testRequestNotificationsIsFunction() {
        makeHarness().expectTrue("typeof hs.permissions.requestNotifications === 'function'")
    }

    @Test("checkNotifications returns a boolean")
    func testCheckNotificationsReturnsBool() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.permissions.checkNotifications() === 'boolean'")
    }
}
