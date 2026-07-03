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
/// const n = hs.notify.create({
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
/// | `userInfo` | object | The `userInfo` object originally passed to `create()`, if any |
/// | `notificationId` | string | The notification's unique identifier |
///
/// ## Options for `create()`
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
/// | `trigger` | object | — | When to deliver the notification (see below). Omit for immediate delivery. |
/// | `actions` | array | — | Action buttons (see below) |
/// | `callback` | function | — | Invoked when the user interacts with the notification |
///
/// ## Triggers
///
/// Pass a `trigger` object in `create()`'s options to schedule the notification instead of delivering it
/// **Time interval** — deliver after a fixed delay in seconds (minimum 60 s):
/// ```js
/// trigger: { type: "timeInterval", interval: 300 }
/// ```
///
/// **Calendar** — deliver at a specific date/time. Provide either a JS `Date` object or individual
/// date-component keys; any omitted component matches every value:
/// ```js
/// // At a specific moment
/// trigger: { type: "calendar", date: new Date("2026-06-01T09:00:00") }
///
/// // At 09:00 on the next day that matches (e.g. next Monday, weekday 2)
/// trigger: { type: "calendar", weekday: 2, hour: 9, minute: 0 }
/// ```
/// Supported component keys: `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday`.
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
    ///   - callback: {(response: Record<string, any>) => void} Optional function called when the user taps the notification. Receives a response object (see module docs for shape).
    /// - Example:
    /// ```js
    /// hs.notify.show("Build complete", "Your project compiled successfully.")
    /// ```
    @objc(show:::) func show(_ title: String, _ body: String, _ callback: JSFunction)

    // MARK: Rich API

    /// Create a richly configured notification without sending it yet.
    ///
    /// - Parameter options: A JavaScript object — see module documentation for supported keys.
    /// - Returns: An `HSNotification` object. Call `.send()` on it to deliver the notification.
    /// - Example:
    /// ```js
    /// const n = hs.notify.create({ title: "Hello", body: "World" })
    /// n.send()
    /// ```
    @objc func create(_ options: [String: Any]) -> HSNotification?

    // MARK: Management

    /// Remove all delivered Hammerspoon notifications from Notification Center.
    /// - Example:
    /// ```js
    /// hs.notify.removeAllDelivered()
    /// ```
    @objc func removeAllDelivered()

    /// Cancel all pending (not yet delivered) Hammerspoon notifications.
    /// - Example:
    /// ```js
    /// hs.notify.removeAllPending()
    /// ```
    @objc func removeAllPending()
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSNotifyModule: NSObject, HSModuleAPI, HSNotifyModuleAPI {
    var name = "hs.notify"
    let engineID: UUID

    private var callbacks: [String: JSCallback] = [:]

    // Private userInfo key used to carry the category ID through to didReceive for pruning.
    fileprivate static let categoryIdKey = "_hs.notify.categoryId"

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        UNUserNotificationCenter.current().delegate = self
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for key in callbacks.keys {
            callbacks[key]?.detach(from: self)
        }
        callbacks.removeAll()
        UNUserNotificationCenter.current().delegate = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
        shutdown()
    }

    // MARK: - Internal callback registration

    func storeCallback(identifier: String, callback: JSFunction) {
        callbacks[identifier] = JSCallback(value: callback, owner: self)
    }

    // MARK: - HSNotifyModuleAPI

    @objc(show:::) func show(_ title: String, _ body: String, _ callback: JSFunction) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let id = UUID().uuidString
        if callback.isObject {
            callbacks[id] = JSCallback(value: callback, owner: self)
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

    @objc func create(_ options: [String: Any]) -> HSNotification? {
        guard let title = options["title"] as? String, !title.isEmpty else {
            AKError("hs.notify.create(): 'title' is required and must be a non-empty string")
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = title

        if let subtitle = options["subtitle"] as? String         { content.subtitle = subtitle }
        if let body = options["body"] as? String                 { content.body = body }
        if let threadId = options["threadIdentifier"] as? String { content.threadIdentifier = threadId }
        if let badge = options["badge"] as? NSNumber             { content.badge = badge }

        if let rawUserInfo = options["userInfo"] as? [AnyHashable: Any] {
            content.userInfo = rawUserInfo
        }

        // Sound: omitted → default, true → default, false → silent, string → named file
        let soundVal = options["sound"]
        if let soundName = soundVal as? String {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else if let soundBool = soundVal as? Bool {
            content.sound = soundBool ? .default : nil
        } else {
            content.sound = .default
        }

        if #available(macOS 12.0, *) {
            if let level = options["interruptionLevel"] as? String {
                switch level {
                case "passive":       content.interruptionLevel = .passive
                case "timeSensitive": content.interruptionLevel = .timeSensitive
                default:              content.interruptionLevel = .active
                }
            }
        }

        // Parse the optional trigger.
        let trigger = Self.buildTrigger(from: options["trigger"] as? [AnyHashable: Any])

        // Build action buttons into a UNNotificationCategory.
        // The category is NOT registered here — HSNotification.send() registers it atomically
        // with the notification request to eliminate the race between registration and delivery.
        let actionsNS = options["actions"] as? NSArray
        let actionsRaw = actionsNS?.compactMap { $0 as? [AnyHashable: Any] } ?? []
        var pendingCategory: UNNotificationCategory?
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
                pendingCategory = UNNotificationCategory(
                    identifier: categoryId, actions: actions,
                    intentIdentifiers: [], options: []
                )
                // Piggyback the category ID in userInfo so didReceive can prune it after use.
                var userInfo = content.userInfo
                userInfo[HSNotifyModule.categoryIdKey] = categoryId
                content.userInfo = userInfo
            }
        }

        // Extract the callback via forProperty so the JSValue function is preserved
        // (toDictionary() silently drops function values).
        let callback = options["callback"] as? JSFunction

        let id = UUID().uuidString
        let notification = HSNotification(
            identifier: id,
            content: content,
            callback: callback,
            registerCallback: { @MainActor [weak self] notifId, cb in
                self?.storeCallback(identifier: notifId, callback: cb)
            }
        )
        notification.trigger = trigger
        notification.pendingCategory = pendingCategory
        return notification
    }

    // MARK: - Trigger builder

    private static func buildTrigger(from dict: [AnyHashable: Any]?) -> UNNotificationTrigger? {
        guard let dict, let type = dict["type"] as? String else { return nil }
        switch type {
        case "timeInterval":
            guard let interval = dict["interval"] as? TimeInterval, interval > 0 else {
                AKError("hs.notify: trigger.type 'timeInterval' requires 'interval' > 0")
                return nil
            }
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        case "calendar":
            var components = DateComponents()
            if let date = (dict["date"] as? NSDate).map({ $0 as Date }) {
                let cal = Calendar.current
                components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            } else {
                if let v = dict["year"]    as? Int { components.year    = v }
                if let v = dict["month"]   as? Int { components.month   = v }
                if let v = dict["day"]     as? Int { components.day     = v }
                if let v = dict["hour"]    as? Int { components.hour    = v }
                if let v = dict["minute"]  as? Int { components.minute  = v }
                if let v = dict["second"]  as? Int { components.second  = v }
                if let v = dict["weekday"] as? Int { components.weekday = v }
            }
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        default:
            AKError("hs.notify: unknown trigger type '\(type)' — expected 'timeInterval' or 'calendar'")
            return nil
        }
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
            let rawUserInfo = response.notification.request.content.userInfo
            let userText = (response as? UNTextInputNotificationResponse)?.userText

            // Strip the internal category key before exposing userInfo to JS.
            let categoryId = rawUserInfo[HSNotifyModule.categoryIdKey] as? String
            var userInfo = rawUserInfo
            userInfo.removeValue(forKey: HSNotifyModule.categoryIdKey)

            if let cb = callbacks.removeValue(forKey: notifId) {
                var responseObj: [AnyHashable: Any] = [
                    "actionIdentifier": actionId,
                    "userInfo":         userInfo,
                    "notificationId":   notifId,
                ]
                if let text = userText { responseObj["userText"] = text }
                _ = cb.call(withArguments: [responseObj])
                cb.detach(from: self)
            }

            // Prune the per-notification category now that it has served its purpose.
            if let categoryId {
                UNUserNotificationCenter.current().getNotificationCategories { existing in
                    let pruned = existing.filter { $0.identifier != categoryId }
                    UNUserNotificationCenter.current().setNotificationCategories(pruned)
                }
            }
        }
        completionHandler()
    }
}
