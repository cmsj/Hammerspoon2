//
//  AppWindows.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import SwiftUI

/// Opens the app's SwiftUI windows from code that isn't a SwiftUI view, such as notification responses.
@_documentation(visibility: private)
@Observable
final class AppWindows {
    static let shared = AppWindows()

    /// The tab the Settings window shows
    var settingsTab: SettingsTab = .configuration

    // The Settings scene can only be opened with SwiftUI's OpenSettingsAction, which lives in
    // the environment, so the App hands it to us once its scenes exist.
    @ObservationIgnored private var openSettingsAction: OpenSettingsAction?
    @ObservationIgnored private var settingsRequestedEarly = false
    @ObservationIgnored private var openWindowAction: OpenWindowAction?

    /// The Console's window while it's open, set by ConsoleView
    @ObservationIgnored weak var consoleWindow: NSWindow? {
        didSet {
            if consoleRaisePending, consoleWindow != nil {
                raiseConsole()
            }
        }
    }
    /// Set when the Console was asked for before its window existed, so it's raised once it does
    @ObservationIgnored private var consoleRaisePending = false

    /// Called by the App, so `showSettings(_:)` and `showConsole()` can open their windows
    /// - Parameters:
    ///   - openSettings: The App's `openSettings` environment action
    ///   - openWindow: The App's `openWindow` environment action
    func register(openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        openSettingsAction = openSettings
        openWindowAction = openWindow
        if settingsRequestedEarly {
            settingsRequestedEarly = false
            openSettings()
        }
    }

    /// Opens the Settings window, or brings it forward if it's already open
    /// - Parameter tab: The tab to show
    func showSettings(_ tab: SettingsTab) {
        settingsTab = tab
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let openSettingsAction else {
            // e.g. the app was launched by the response to a notification
            settingsRequestedEarly = true
            return
        }
        openSettingsAction()
    }

    /// Opens the Console window, or brings it forward if it's already open, in front of other apps' windows
    func showConsole() {
        guard let openWindowAction else {
            // e.g. the app was launched by the response to a notification, before the scenes exist
            consoleRaisePending = true
            if let url = URL(string: "hammerspoon2://openConsole") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        openWindowAction(id: "console")
        // A newly created window attaches itself to consoleWindow a moment later, which raises it.
        // An existing one is raised on the next run loop pass, after SwiftUI has ordered it in.
        consoleRaisePending = true
        DispatchQueue.main.async { [self] in
            if consoleWindow?.isVisible == true {
                raiseConsole()
            }
        }
    }

    /// Makes the Console window key and Hammerspoon the frontmost app.
    ///
    /// `NSApplication.activate` can't be relied on for this: since macOS 14 activation is
    /// cooperative, and the request is refused unless the active app yields, which leaves the
    /// Console behind whatever the user was using (e.g. when it's opened from the status item
    /// menu or a hotkey). So this uses the same non-cooperative call as hs.application's
    /// setFrontmost(), bringing forward only the Console, not every Hammerspoon window.
    func raiseConsole() {
        guard let window = consoleWindow else {
            consoleRaisePending = true
            return
        }
        consoleRaisePending = false
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        _ = NSRunningApplication.current.setFrontmost(allWindows: false)
    }
}
