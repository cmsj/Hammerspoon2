//
//  Hammerspoon_2App.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/09/2025.
//

import SwiftUI
import Sparkle
@_spi(HammerspoonHost) import HammerspoonSDK

@_documentation(visibility: private)
class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var instance: AppDelegate! = nil

    private let openFileQueue = OpenFileQueue { url in
        if JSEngine.shared.moduleRoot?.callOnOpenFile(url.path) != true {
            AKWarning("Opened \(url.path), but hs.onOpenFile isn't set, so ignoring it")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AKGarbage("applicationDidFinishLaunching: Creating/booting shared manager")

        AppDelegate.instance = self
        ConsoleCompletionEngine.shared.prewarm()
        // Before the config loads, so a config that crashes the app can still be reported.
        CrashReportManager.shared.offerToReportNewCrashes()
        let managerManager = ManagerManager.shared
        do {
            try managerManager.boot()
        } catch {
            fatalError(error.localizedDescription)
        }

        openFileQueue.markReady()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AKGarbage("applicationWillTerminate: Shutting down shared manager")
        ManagerManager.shared.prepareForTermination()
    }

    /// Called when the app is launched again while already running (Finder, Spotlight, `open -a`)
    /// or its Dock icon is clicked. This is how users get back to the console when we're hidden
    /// from both the Dock and the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        switch SettingsManager.shared.reopenAction {
        case .showConsole:
            showConsole()
        case .callback:
            // With no callback to call (e.g. the config failed to load), fall back to the
            // Console, so there's always a way back in when we're in neither Dock nor menu bar
            if JSEngine.shared.moduleRoot?.callOnRelaunch() != true {
                AKWarning("Relaunched, but hs.onRelaunch isn't set, so showing the Console instead")
                showConsole()
            }
        case .doNothing:
            break
        }
        // We've handled it ourselves, so SwiftUI shouldn't reopen a window of its choosing
        return false
    }

    /// Called each time the Dock icon's menu opens. The items it returns appear above the Dock's own.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        (JSEngine.shared.moduleRoot?.modules["dockicon"] as? HSDockIconModule)?.makeDockMenu()
    }

    private func showConsole() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let url = URL(string: "hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch OpenedURLRoute(for: url, importSpoonsOnOpen: SettingsManager.shared.importSpoonsOnOpen) {
            case .importSpoon:
                importSpoon(at: url)
            case .openFile:
                openFileQueue.open(url)
            case .urlEvent:
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

                Add hs.spoons.load("\(plan.name)") to your config to use it, then reload.
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
struct Hammerspoon2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var settingsManager = SettingsManager.shared

    init() {
        // Everything logged through the SDK's AK* functions, by the app or an extension, goes
        // to the Console
        HSSDK.logHandler = { level, message in
            HammerspoonLog.shared.log(level, message)
        }
        HSSDK.engineContextProvider = { JSEngine.shared.context }

        // Start the updater at launch, not on first use of the menu
        _ = AppUpdater.controller
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $settingsManager.dockMenuBehaviour.showMenuItem) {
            let managerManager = ManagerManager.shared

            Button("Reload Config") {
                try? managerManager.reload()
            }

            Button("Show Config") {
                NSWorkspace.shared.open(SettingsManager.shared.configLocation.deletingLastPathComponent())
            }

            Divider()

            Button("Settings...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }

            Button("Console...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "console")
            }

            Button("API Documentation") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                JSEngine.shared.eval("hs.docs.show()")
            }

            Divider()

            CheckForUpdatesView(updater: AppUpdater.updater)

            Divider()

            Button("Quit") {
                managerManager.shutdown()
            }
        } label: {
            Label {Text("Hammerspoon 2") } icon: {
                // FIXME: This is an ugly hack because a regular Image() here, backed by our SVG, renders vastly too large
                let image: NSImage = {
                    let ratio = $0.size.height / $0.size.width
                    $0.size.height = 18
                    $0.size.width = 18 / ratio
                    return $0
                }(NSImage(named: "MenubarIcon")!)

                Image(nsImage: image)
            }
        }
        .onChange(of: settingsManager.dockMenuBehaviour, initial: true) {
            // Info.plist declares LSUIElement, so we start as .accessory and promote ourselves here.
            // Without it, LaunchServices resets an .accessory app to .regular (showing a Dock icon)
            // whenever it opens the app, e.g. for a hammerspoon2:// URL or `open -a` (#316)
            NSApplication.shared.setActivationPolicy(settingsManager.dockMenuBehaviour.activationPolicy)
        }

        Window("Console", id: "console") {
            ConsoleView()
        }
        .restorationBehavior(.disabled)
        .windowLevel(settingsManager.consoleAlwaysOnTop ? .floating : .normal)
        .handlesExternalEvents(matching: ["openConsole", "closeConsole"])
        .commands {
            // About
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About Hammerspoon 2") {
                    openWindow(id: "about")
                }

                CheckForUpdatesView(updater: AppUpdater.updater)
            }

            CommandMenu("Debug") {
                Button("Reload Config") {
                    try? ManagerManager.shared.reload()
                }

                Button("Open Console") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "console")
                }
                Button("Open Documentation") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    JSEngine.shared.eval("hs.docs.show()")
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

        Settings {
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
