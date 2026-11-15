//
//  NotificationCategories.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import Foundation
import UserNotifications

/// Changes the notification center's categories, which hs.notify and the app's own notifications
/// share. The center can only replace the whole set, so each change reads it, alters it and
/// writes it back; this runs those changes one at a time, so none of them drops another's.
@_documentation(visibility: private)
final class NotificationCategories {
    static let shared = NotificationCategories()

    private var lastChange: Task<Void, Never>?

    /// Changes the categories, after any earlier change has finished
    /// - Parameter change: Given the current categories, returns the ones to replace them with
    func update(_ change: @escaping (Set<UNNotificationCategory>) -> Set<UNNotificationCategory>) async {
        let previous = lastChange
        let task = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            center.setNotificationCategories(change(await center.notificationCategories()))
        }
        lastChange = task
        await task.value
    }
}
