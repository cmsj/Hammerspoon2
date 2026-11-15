//
//  ConfigProblemNotifier.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import Foundation
import UserNotifications

nonisolated extension ConfigProblem {
    /// Where the notification's action takes the user to fix the problem
    enum Remedy: String, CaseIterable {
        case openSettings
        case openConsole

        /// The notification category whose action applies this remedy
        var categoryIdentifier: String { "hs2.configProblem.\(rawValue)" }

        var actionTitle: String {
            switch self {
            case .openSettings: return "Open Settings"
            case .openConsole: return "Open Console"
            }
        }
    }

    var title: String {
        switch self {
        case .missingDirectory: return "Config folder not found"
        case .missingFile: return "Config file not found"
        case .unreadableFile: return "Couldn't read your config file"
        case .scriptError: return "Your config has an error"
        }
    }

    var body: String {
        switch self {
        case .missingDirectory(let directory):
            return "\(directory.path(percentEncoded: false)) doesn't exist, so your config wasn't loaded. Open Settings to choose where your config lives."
        case .missingFile(let file):
            return "\(file.path(percentEncoded: false)) doesn't exist, so your config wasn't loaded. Open Settings to choose your config file."
        case .unreadableFile(_, let reason):
            return "\(reason) Your config wasn't loaded. Open Settings to choose your config file."
        case .scriptError(let message):
            return "\(message)\nYour config may only be partly loaded. Open the Console to see the full error."
        }
    }

    var remedy: Remedy {
        switch self {
        case .missingDirectory, .missingFile, .unreadableFile: return .openSettings
        case .scriptError: return .openConsole
        }
    }
}

/// Tells the user about config problems with a macOS notification, whose action opens the
/// Settings window (for a missing or unreadable config) or the Console (for an error in it).
/// Responses to these notifications are routed here by `UserNotificationRouter`.
@_documentation(visibility: private)
final class ConfigProblemNotifier: ConfigProblemNotifierProtocol {
    static let shared = ConfigProblemNotifier()

    /// There's only ever one config problem notification, so a new one replaces the last
    static let notificationIdentifier = "hs2.configProblem"

    // Bumped by every notify() and withdraw(), so a notification still waiting on authorization
    // isn't delivered after a later one, or after the config has since been reloaded.
    private var generation = 0

    func notify(_ problem: ConfigProblem) {
        generation += 1
        let postedGeneration = generation

        let content = UNMutableNotificationContent()
        content.title = problem.title
        content.body = problem.body
        content.categoryIdentifier = problem.remedy.categoryIdentifier
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)

        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    AKWarning("Notifications aren't allowed, so couldn't show the config problem: \(problem.title)")
                    return
                }
                await registerCategories()
                guard postedGeneration == generation else { return }
                try await center.add(request)
            } catch {
                AKError("Failed to show the config problem notification: \(error.localizedDescription)")
            }
        }
    }

    func withdraw() {
        generation += 1
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    /// Applies the remedy for a response to one of our notifications
    /// - Parameter response: The user's response to a notification
    /// - Returns: `true` if the notification was one of ours, `false` if it belongs to someone else
    func handle(_ response: UNNotificationResponse) -> Bool {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        guard let remedy = ConfigProblem.Remedy.allCases.first(where: { $0.categoryIdentifier == categoryIdentifier }) else {
            return false
        }
        if response.actionIdentifier != UNNotificationDismissActionIdentifier {
            switch remedy {
            case .openSettings: AppWindows.shared.showSettings(.configuration)
            case .openConsole: AppWindows.shared.showConsole()
            }
        }
        return true
    }

    /// Adds our categories to the notification center's, keeping the ones hs.notify registered
    private func registerCategories() async {
        let ours = ConfigProblem.Remedy.allCases.map { remedy in
            UNNotificationCategory(
                identifier: remedy.categoryIdentifier,
                actions: [UNNotificationAction(identifier: remedy.rawValue, title: remedy.actionTitle)],
                intentIdentifiers: []
            )
        }
        let ourIdentifiers = Set(ours.map(\.identifier))
        await NotificationCategories.shared.update { existing in
            existing.filter { !ourIdentifiers.contains($0.identifier) }.union(ours)
        }
    }
}
