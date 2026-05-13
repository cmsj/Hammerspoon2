//
//  HSNotificationAPI.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//
import Foundation
import JavaScriptCore
@unsafe @preconcurrency import UserNotifications

// MARK: - HSNotification (per-notification JS-exposed object)

/// A notification created by `hs.notify.new()`.
///
/// Call `.send()` to deliver it to macOS Notification Center. You can hold a reference
/// to the object and call `.withdraw()` later to remove it.
///
/// Example:
/// ```js
/// const n = hs.notify.new({
///     title: "Build finished",
///     body: "Your project compiled successfully.",
///     actions: [{ identifier: "OPEN", title: "Open" }],
///     callback: (r) => { if (r.actionIdentifier === "OPEN") openProject() }
/// })
/// n.send()
/// ```
@objc protocol HSNotificationAPI: HSTypeAPI, JSExport {
    /// The unique identifier assigned to this notification.
    /// Use it to correlate with system notification APIs if needed.
    @objc var identifier: String { get }

    /// Deliver this notification immediately to Notification Center.
    /// - Returns: self, for method chaining
    @objc @discardableResult func send() -> HSNotification

    /// Remove this notification from Notification Center (if delivered) or cancel it (if pending).
    @objc func withdraw()
}

@_documentation(visibility: private)
@objc class HSNotification: NSObject, HSNotificationAPI {
    @objc var typeName = "HSNotification"

    @objc let identifier: String

    fileprivate let content: UNMutableNotificationContent
    fileprivate let callback: JSValue?

    // Injected by HSNotifyModule so send() can register the callback without importing the module.
    fileprivate var registerCallback: (@MainActor (String, JSValue) -> Void)?

    init(identifier: String,
         content: UNMutableNotificationContent,
         callback: JSValue?,
         registerCallback: (@MainActor (String, JSValue) -> Void)?) {
        self.identifier = identifier
        self.content = content
        self.callback = callback
        self.registerCallback = registerCallback
    }

    @objc @discardableResult func send() -> HSNotification {
        if let cb = callback {
            registerCallback?(identifier, cb)
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in
                    AKError("hs.notify: Failed to deliver notification \(self.identifier): \(error.localizedDescription)")
                }
            }
        }
        return self
    }

    @objc func withdraw() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
