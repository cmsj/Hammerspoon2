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
        AKGarbage("applicationDidFinishLaunching: Creating/booting shared manager")

        AppDelegate.instance = self
        ConsoleCompletionEngine.shared.prewarm()
        let managerManager = ManagerManager.shared
        do {
            try managerManager.boot()
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL, url.pathExtension.lowercased() == "spoon2" {
                importSpoon(at: url)
            } else {
                URLEventDispatcher.shared.dispatch(url)
            }
        }
    }

    private func importSpoon(at url: URL) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        do {
            let plan = try SpoonManager.shared.planImport(from: url)

            if !confirmOverwriteIfNeeded(plan) {
                AKInfo("Import of Spoon from \(url.path) cancelled by user")
                return
            }

            try SpoonManager.shared.performImport(plan)
            AKInfo("Imported Spoon '\(plan.name)' from \(url.path)")

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Spoon Installed"
            alert.informativeText = """
                "\(plan.newMetadata.name)" by \(plan.newMetadata.author) was installed as "\(plan.name)".

                Add hs.loadSpoon("\(plan.name)") to your config to use it, then reload.
                """
            alert.runModal()
        } catch {
            AKError("Failed to import Spoon from \(url.path): \(error.localizedDescription)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Install Spoon"
            alert.informativeText = "\"\(url.lastPathComponent)\" \(error.localizedDescription)"
            alert.runModal()
        }
    }

    /// Shows a confirmation dialog if `plan` would overwrite something, comparing the
    /// currently-installed Spoon's metadata against the one being imported.
    /// - Returns: `true` if there's nothing to confirm, or the user confirmed the overwrite;
    ///   `false` if the user cancelled
    private func confirmOverwriteIfNeeded(_ plan: SpoonImportPlan) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch plan.conflict {
        case .none:
            return true
        case .existingSpoon(let existing):
            alert.messageText = "Replace Existing Spoon?"
            alert.informativeText = """
                A Spoon named "\(plan.name)" is already installed.

                Installed: "\(existing.name)" v\(existing.version) by \(existing.author)
                New:       "\(plan.newMetadata.name)" v\(plan.newMetadata.version) by \(plan.newMetadata.author)

                Replacing it cannot be undone.
                """
        case .existingUnreadable:
            alert.messageText = "Replace Existing Item?"
            alert.informativeText = """
                Something already exists at the location "\(plan.name)" would be installed to, \
                but it isn't a valid Spoon.

                Replacing it cannot be undone.
                """
        }

        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@_documentation(visibility: private)
@main
struct Hammerspoon_2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var settingsManager = SettingsManager.shared

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        MenuBarExtra("Hammerspoon 2", systemImage: "hammer", isInserted: $settingsManager.dockMenuBehaviour.showMenuItem) { // FIXME: Use the real logo here
            let managerManager = ManagerManager.shared

            Button("Reload Config") {
                try? managerManager.reload()
            }

            Divider()

            Button("Settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }

            Button("Open Console") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "console")
            }

            Divider()

            CheckForUpdatesView(updater: updaterController.updater)

            Divider()

            Button("Quit") {
                managerManager.shutdown()
            }
        }
        .onChange(of: settingsManager.dockMenuBehaviour, initial: true) {
            NSApplication.shared.setActivationPolicy(settingsManager.dockMenuBehaviour.activationPolicy)
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
        .handlesExternalEvents(matching: [])

        Settings() {
            SettingsView()
        }
        .restorationBehavior(.disabled)

        Window("Welcome to Hammerspoon 2", id: "onboarding") {
            OnboardingView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(settingsManager.hasCompletedOnboarding ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
    }
}
