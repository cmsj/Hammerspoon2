//
//  AppWindows.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import SwiftUI

/// Opens the app's SwiftUI windows from code that isn't a SwiftUI view, such as notification responses.
@_documentation(visibility: private)
final class AppWindows {
    static let shared = AppWindows()

    // The Settings scene can only be opened with SwiftUI's OpenSettingsAction, which lives in
    // the environment, so the App hands it to us once its scenes exist.
    private var openSettingsAction: OpenSettingsAction?
    private var settingsRequestedEarly = false

    /// Called by the App, so `showSettings()` can open the Settings window
    /// - Parameter openSettings: The App's `openSettings` environment action
    func register(openSettings: OpenSettingsAction) {
        openSettingsAction = openSettings
        if settingsRequestedEarly {
            settingsRequestedEarly = false
            openSettings()
        }
    }

    func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let openSettingsAction else {
            // e.g. the app was launched by the response to a notification
            settingsRequestedEarly = true
            return
        }
        openSettingsAction()
    }

    func showConsole() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let url = URL(string: "hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }
}
