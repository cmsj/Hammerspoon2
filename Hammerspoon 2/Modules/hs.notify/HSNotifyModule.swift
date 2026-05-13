//
//  HSNotifyModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/05/2026.
//

import Foundation
import JavaScriptCore
@unsafe @preconcurrency import UserNotifications



// MARK: - Module API protocol

/// Module for creating and displaying macOS system notifications.
///
/// macOS notifications require user permission before they will appear. Request it once
/// (typically at startup) via `hs.permissions.requestNotifications()` and it will be
/// remembered across sessions:
///
/// ```js
/// hs.permissions.requestNotifications().then(granted => {
///     if (granted) hs.notify.show("Hammerspoon", "Notifications are enabled!")
/// })
/// ```
///
/// ## Quick notification
///
/// ```js
/// // Fire and forget
/// hs.notify.show("Build complete", "Your project compiled successfully.")
///
/// // With a callback invoked when the user interacts
/// hs.notify.show("Build complete", "Click to view the log.", (response) => {
///     console.log("User tapped:", response.actionIdentifier)
/// })
/// ```
///
/// ## Rich notification
///
/// ```js
/// const n = hs.notify.new({
///     title:    "New message",
///     subtitle: "From Alice",
///     body:     "Are you free tonight?",
///     sound:    true,
///     threadIdentifier: "messages-alice",
///     actions: [
///         { identifier: "REPLY", title: "Reply", textInput: true,
///           textInputButtonTitle: "Send", textInputPlaceholder: "Type a reply…" },
///         { identifier: "DISMISS", title: "Dismiss", destructive: true }
///     ],
///     callback: (response) => {
///         if (response.actionIdentifier === "REPLY") {
///             console.log("Reply text:", response.userText)
///         }
///     }
/// })
/// n.send()
/// // Later, if needed:
/// n.withdraw()
/// ```
///
/// ## Callback response object
///
/// The `callback` function receives a single object with these properties:
///
/// | Property | Type | Description |
/// |----------|------|-------------|
/// | `actionIdentifier` | string | `"DEFAULT"` when the user tapped the notification body; `"DISMISS"` when dismissed (if `.customDismissAction` is set); otherwise the action's `identifier` string |
/// | `userText` | string? | Text entered in a `textInput` action; only present when applicable |
/// | `userInfo` | object | The `userInfo` object originally passed to `new()`, if any |
/// | `notificationId` | string | The notification's unique identifier |
///
/// ## Options for `new()`
///
/// | Key | Type | Default | Description |
/// |-----|------|---------|-------------|
/// | `title` | string | *(required)* | The bold heading line |
/// | `subtitle` | string | — | A second line shown beneath the title |
/// | `body` | string | — | The main message body |
/// | `sound` | boolean \| string | `true` | `true` = default sound, `false` = no sound, string = named `.aiff` file |
/// | `badge` | number | — | Value to show on the app icon badge |
/// | `threadIdentifier` | string | — | Groups related notifications visually in Notification Center |
/// | `userInfo` | object | `{}` | Arbitrary payload passed back to the callback |
/// | `interruptionLevel` | string | `"active"` | `"passive"`, `"active"`, or `"timeSensitive"` — controls Focus/DND behaviour (macOS 12+) |
/// | `actions` | array | — | Action buttons (see below) |
/// | `callback` | function | — | Invoked when the user interacts with the notification |
///
/// ## Action objects
///
/// | Key | Type | Default | Description |
/// |-----|------|---------|-------------|
/// | `identifier` | string | *(required)* | Unique identifier passed to the callback |
/// | `title` | string | *(required)* | Button label |
/// | `destructive` | boolean | `false` | Renders the title in a destructive (red) style |
/// | `foreground` | boolean | `false` | Brings Hammerspoon to the foreground when tapped |
/// | `textInput` | boolean | `false` | Converts this action to an inline text-reply button |
/// | `textInputButtonTitle` | string | `"Send"` | Label on the reply send button (requires `textInput: true`) |
/// | `textInputPlaceholder` | string | `""` | Placeholder shown in the text field (requires `textInput: true`) |
@objc protocol HSNotifyModuleAPI: JSExport {

    // MARK: Simple API

    /// Display a notification immediately.
    ///
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body text
    ///   - callback: Optional function called when the user taps the notification.
    ///     Receives a response object (see module docs for shape).
    @objc(show:::) func show(_ title: String, _ body: String, _ callback: JSValue)

    // MARK: Rich API

    /// Create a richly configured notification without sending it yet.
    ///
    /// - Parameter options: A JavaScript object — see module documentation for supported keys.
    /// - Returns: An `HSNotification` object. Call `.send()` on it to deliver the notification.
    @objc func new(_ options: JSValue) -> HSNotification?

    // MARK: Management

    /// Remove all delivered Hammerspoon notifications from Notification Center.
    @objc func removeAllDelivered()

    /// Cancel all pending (not yet delivered) Hammerspoon notifications.
    @objc func removeAllPending()
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSNotifyModule: NSObject, HSModuleAPI, HSNotifyModuleAPI {
    var name = "hs.notify"

    private var callbacks: [String: JSValue] = [:]

    override required init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func shutdown() {
        callbacks.removeAll()
    }

    isolated deinit {
        print("Deinit of \(name)")
        shutdown()
    }

    // MARK: - Internal callback registration

    func storeCallback(identifier: String, callback: JSValue) {
        callbacks[identifier] = callback
    }

    // MARK: - HSNotifyModuleAPI

    @objc(show:::) func show(_ title: String, _ body: String, _ callback: JSValue) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let id = UUID().uuidString
        if callback.isObject {
            callbacks[id] = callback
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in
                    AKError("hs.notify.show(): Failed to deliver notification: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func new(_ options: JSValue) -> HSNotification? {
        guard options.isObject, let dict = options.toDictionary() else {
            AKError("hs.notify.new(): Expected a JavaScript object with options")
            return nil
        }

        guard let title = dict["title"] as? String, !title.isEmpty else {
            AKError("hs.notify.new(): 'title' is required and must be a non-empty string")
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = title

        if let subtitle = dict["subtitle"] as? String         { content.subtitle = subtitle }
        if let body = dict["body"] as? String                 { content.body = body }
        if let threadId = dict["threadIdentifier"] as? String { content.threadIdentifier = threadId }
        if let badge = dict["badge"] as? NSNumber             { content.badge = badge }

        if let rawUserInfo = dict["userInfo"] as? [AnyHashable: Any] {
            content.userInfo = rawUserInfo
        }

        // Sound: omitted → default, true → default, false → silent, string → named file
        let soundVal = dict["sound"]
        if let soundName = soundVal as? String {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else if let soundBool = soundVal as? Bool {
            content.sound = soundBool ? .default : nil
        } else {
            content.sound = .default
        }

        if #available(macOS 12.0, *) {
            if let level = dict["interruptionLevel"] as? String {
                switch level {
                case "passive":       content.interruptionLevel = .passive
                case "timeSensitive": content.interruptionLevel = .timeSensitive
                default:              content.interruptionLevel = .active
                }
            }
        }

        // Build action buttons and register a per-notification category.
        let actionsNS = dict["actions"] as? NSArray
        let actionsRaw = actionsNS?.compactMap { $0 as? [AnyHashable: Any] } ?? []
        if !actionsRaw.isEmpty {
            var actions: [UNNotificationAction] = []
            for actionDict in actionsRaw {
                guard let actionId    = actionDict["identifier"] as? String,
                      let actionTitle = actionDict["title"] as? String else { continue }

                var opts: UNNotificationActionOptions = []
                if (actionDict["destructive"] as? Bool) == true { opts.insert(.destructive) }
                if (actionDict["foreground"]  as? Bool) == true { opts.insert(.foreground) }

                if (actionDict["textInput"] as? Bool) == true {
                    let btnTitle    = actionDict["textInputButtonTitle"] as? String ?? "Send"
                    let placeholder = actionDict["textInputPlaceholder"] as? String ?? ""
                    actions.append(UNTextInputNotificationAction(
                        identifier: actionId, title: actionTitle, options: opts,
                        textInputButtonTitle: btnTitle, textInputPlaceholder: placeholder
                    ))
                } else {
                    actions.append(UNNotificationAction(identifier: actionId, title: actionTitle, options: opts))
                }
            }

            if !actions.isEmpty {
                let categoryId = "hs.notify.\(UUID().uuidString)"
                content.categoryIdentifier = categoryId
                let category = UNNotificationCategory(
                    identifier: categoryId, actions: actions,
                    intentIdentifiers: [], options: []
                )
                UNUserNotificationCenter.current().getNotificationCategories { existing in
                    var updated = existing
                    updated.insert(category)
                    UNUserNotificationCenter.current().setNotificationCategories(updated)
                }
            }
        }

        // Extract the callback via forProperty so the JSValue function is preserved
        // (toDictionary() silently drops function values).
        let callbackVal = options.forProperty("callback")
        let callback: JSValue? = (callbackVal?.isObject == true) ? callbackVal : nil

        let id = UUID().uuidString
        return HSNotification(
            identifier: id,
            content: content,
            callback: callback,
            registerCallback: { @MainActor [weak self] notifId, cb in
                self?.storeCallback(identifier: notifId, callback: cb)
            }
        )
    }

    @objc func removeAllDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    @objc func removeAllPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension HSNotifyModule: UNUserNotificationCenterDelegate {

    // Show banner/sound/badge even while Hammerspoon is the frontmost app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    // Dispatch user interactions to the registered JS callback.
    // Apple guarantees this is called on the main thread, so assumeIsolated is safe.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Apple guarantees this is called on the main thread.
        MainActor.assumeIsolated {
            let notifId = response.notification.request.identifier
            let actionId: String
            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier: actionId = "DEFAULT"
            case UNNotificationDismissActionIdentifier: actionId = "DISMISS"
            default: actionId = response.actionIdentifier
            }
            let userInfo = response.notification.request.content.userInfo
            let userText = (response as? UNTextInputNotificationResponse)?.userText

            if let cb = callbacks[notifId] {
                var responseObj: [AnyHashable: Any] = [
                    "actionIdentifier": actionId,
                    "userInfo":         userInfo,
                    "notificationId":   notifId,
                ]
                if let text = userText { responseObj["userText"] = text }
                cb.call(withArguments: [responseObj])
            }
        }
        completionHandler()
    }
}
