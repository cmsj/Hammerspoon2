//
//  LoginItemManagerTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 27/11/2026.
//

import Testing
import Foundation
import ServiceManagement
@testable import Hammerspoon_2

/// Stands in for `SMAppService.mainApp`, so the tests don't change the real login items.
@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    var registerError: (any Error)?
    /// What `register()` changes `status` to, e.g. `.requiresApproval` when the system wants the
    /// user to allow the app.
    var statusAfterRegister: SMAppService.Status = .enabled
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSettingsCount += 1
    }
}

private struct FakeError: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
struct LoginItemManagerTests {
    @Test("Reads the initial state from the service")
    func initialState() {
        #expect(LoginItemManager(service: FakeLoginItemService(status: .enabled)).isEnabled)
        #expect(!LoginItemManager(service: FakeLoginItemService(status: .notRegistered)).isEnabled)
        #expect(!LoginItemManager(service: FakeLoginItemService(status: .notFound)).isEnabled)

        let disallowed = LoginItemManager(service: FakeLoginItemService(status: .requiresApproval))
        #expect(!disallowed.isEnabled)
        #expect(disallowed.requiresApproval)
    }

    @Test("Enabling registers the app")
    func enableRegisters() {
        let service = FakeLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)

        manager.isEnabled = true

        #expect(service.registerCount == 1)
        #expect(manager.isEnabled)
        #expect(manager.lastError == nil)
    }

    @Test("Disabling unregisters the app")
    func disableUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        let manager = LoginItemManager(service: service)

        manager.isEnabled = false

        #expect(service.unregisterCount == 1)
        #expect(!manager.isEnabled)
    }

    @Test("Disabling when not registered does nothing")
    func disableWhenNotRegistered() {
        let service = FakeLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)

        manager.isEnabled = false

        #expect(service.unregisterCount == 0)
        #expect(manager.lastError == nil)
    }

    @Test("Registration that needs the user's approval is reported, not shown as enabled")
    func registerRequiringApproval() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = LoginItemManager(service: service)

        manager.isEnabled = true

        #expect(!manager.isEnabled)
        #expect(manager.requiresApproval)
    }

    @Test("Enabling a disallowed app opens System Settings instead of registering")
    func enableWhenDisallowed() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)

        manager.isEnabled = true

        #expect(service.registerCount == 0)
        #expect(service.openSettingsCount == 1)
    }

    @Test("A failed registration is surfaced and leaves the app disabled")
    func registerFailure() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = FakeError()
        let manager = LoginItemManager(service: service)

        manager.isEnabled = true

        #expect(!manager.isEnabled)
        #expect(manager.lastError == "Operation not permitted")
    }

    @Test("refresh() picks up changes made in System Settings")
    func refreshPicksUpExternalChanges() {
        let service = FakeLoginItemService(status: .enabled)
        let manager = LoginItemManager(service: service)

        service.status = .requiresApproval
        manager.refresh()

        #expect(!manager.isEnabled)
        #expect(manager.requiresApproval)
    }
}
