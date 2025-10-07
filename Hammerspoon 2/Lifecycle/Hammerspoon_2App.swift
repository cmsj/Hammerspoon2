//
//  Hammerspoon_2App.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 23/09/2025.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AKTrace("applicationDidFinishLaunching")
        let engine = JSEngine.shared
        try? engine.createContext()
    }
}

@main
struct Hammerspoon_2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Window("Console", id: "console") {
            ConsoleView()
        }
    }
}
