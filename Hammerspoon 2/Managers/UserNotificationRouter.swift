//
//  UserNotificationRouter.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import Foundation
import UserNotifications

/// The app's single `UNUserNotificationCenter` delegate. It handles the app's own notifications
/// (see `ConfigProblemNotifier`) and passes everything else to hs.notify, if it's loaded.
///
/// The delegate has to outlive any one JS context, because the app's own notifications are
/// typically posted when the config failed to load, and so hs.notify never was.
@_documentation(visibility: private)
final class UserNotificationRouter: NSObject {
    static let shared = UserNotificationRouter()

    /// The loaded hs.notify module, which handles responses to the notifications it posted
    weak var notifyModule: UNUserNotificationCenterDelegate?

    // When the user clicks a notification, macOS brings the app forward by opening it, which
    // reopens it if it was already running, just after the response is delivered.
    private static let reopenGracePeriod: Duration = .seconds(1)
    private var lastResponseTime: ContinuousClock.Instant?

    /// Whether a notification response was just delivered, so a reopen now was caused by it,
    /// rather than by the user launching the app again
    var isHandlingResponse: Bool {
        guard let lastResponseTime else { return false }
        return ContinuousClock.now - lastResponseTime < Self.reopenGracePeriod
    }

    /// Makes this the notification center's delegate. This must happen before the app finishes
    /// launching, so a response that launched the app is delivered to it.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }
}

// Isolated to the main actor, because Apple calls didReceive on the main thread
extension UserNotificationRouter: @MainActor UNUserNotificationCenterDelegate {
    // Show banner/sound/badge even while Hammerspoon is the frontmost app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        lastResponseTime = .now
        if ConfigProblemNotifier.shared.handle(response) {
            completionHandler()
            return
        }
        // nil if hs.notify isn't loaded, in which case nobody is waiting for the response
        if notifyModule?.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler) == nil {
            completionHandler()
        }
    }
}
