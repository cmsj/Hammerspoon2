//
//  LoginItemManager.swift
//  Hammerspoon 2
//
//  Created by Claude on 27/11/2026.
//

import Foundation
import ServiceManagement

/// The parts of `SMAppService` that `LoginItemManager` uses, so tests can substitute a fake
/// instead of changing the real login items of the machine running them.
@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

extension SMAppService: LoginItemService {
    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Whether the app launches when the user logs in.
///
/// This uses `SMAppService.mainApp` (macOS 13+), which registers the app bundle itself as a login
/// item; no helper app or LaunchAgent plist is needed. The registration lives in the system, not in
/// our preferences: the user can turn it off in System Settings → General → Login Items &
/// Extensions at any time, so `status` is re-read from the system rather than cached in
/// `UserDefaults`, and "Reset all settings" leaves it alone.
@_documentation(visibility: private)
@Observable
@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()

    @ObservationIgnored
    private let service: any LoginItemService

    /// The registration state, as of the last `refresh()` or change made through this manager.
    private(set) var status: SMAppService.Status

    /// The error from the most recent failed attempt to change the registration, for display.
    private(set) var lastError: String?

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
        self.status = service.status
    }

    /// Whether the app is registered and allowed to launch at login. Setting it registers or
    /// unregisters the app.
    var isEnabled: Bool {
        get { status == .enabled }
        set { setEnabled(newValue) }
    }

    /// Whether the app is registered but the user has disallowed it in System Settings, so it
    /// won't launch at login until they allow it there.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Re-read the registration state from the system, e.g. after the user may have changed it in
    /// System Settings.
    func refresh() {
        let newStatus = service.status
        if newStatus != status {
            status = newStatus
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            switch (enabled, service.status) {
            case (true, .requiresApproval):
                // We're already registered, but the user has disallowed us, which only they can
                // undo, in System Settings.
                service.openSystemSettingsLoginItems()
            case (true, _):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            case (false, _):
                break
            }
        } catch {
            AKError("Unable to \(enabled ? "enable" : "disable") launching at login: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettingsLoginItems() {
        service.openSystemSettingsLoginItems()
    }
}
