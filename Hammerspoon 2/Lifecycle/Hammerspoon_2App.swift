//
//  Hammerspoon_2App.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/09/2025.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AKTrace("applicationDidFinishLaunching: Creating/booting shared manager")
        let managerManager = ManagerManager.shared
        do {
            try managerManager.boot()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

@main
struct Hammerspoon_2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Hammerspoon 2", systemImage: "hammer") { // FIXME: Use the real logo here
            let managerManager = ManagerManager.shared

            Button("Reload Config") {
                try? managerManager.boot()
            }

            Divider()

            Button("Preferences") {
                // FIXME: TODO
            }
            Button("Open Console") {
                if let url = URL(string:"hammerspoon2://openConsole") {
                    NSWorkspace.shared.open(url)
                }
            }

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
    }
}
