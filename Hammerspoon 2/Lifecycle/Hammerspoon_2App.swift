//
//  Hammerspoon_2App.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/09/2025.
//

import SwiftUI
import Sparkle

@_documentation(visibility: private)
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var instance: AppDelegate! = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        AKTrace("applicationDidFinishLaunching: Creating/booting shared manager")

        AppDelegate.instance = self
        ConsoleCompletionEngine.shared.prewarm()
        let managerManager = ManagerManager.shared
        do {
            try managerManager.boot()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

@_documentation(visibility: private)
@main
struct Hammerspoon_2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        MenuBarExtra("Hammerspoon 2", systemImage: "hammer") { // FIXME: Use the real logo here
            let managerManager = ManagerManager.shared

            Button("Reload Config") {
                try? managerManager.boot()
            }

            Divider()

            Button("Settings") {
                openSettings()
            }

            Button("Open Console") {
                if let url = URL(string:"hammerspoon2://openConsole") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            CheckForUpdatesView(updater: updaterController.updater)

            Divider()

            Button("Quit") {
                managerManager.shutdown()
            }
        }
        Window("Content", id: "content") {
            ContentView()
        }

        Window("Console", id: "console") {
            ConsoleView()
        }
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: ["openConsole", "closeConsole"])
        .commands {
            // About
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About Hammerspoon 2") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About Hammerspoon 2", id: "about") {
            AboutView()
                .containerBackground(.thickMaterial, for: .window)
                .windowResizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings() {
            SettingsView()
        }
    }
}
