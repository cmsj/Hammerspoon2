//
//  ManagerManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import AppKit

class ManagerManager {
    static let shared = ManagerManager()

    let engine = JSEngine.shared
    let settings = SettingsManager.shared

    func boot() throws {
        try engine.resetContext()

        if !FileManager.default.fileExists(atPath: settings.configLocation.path) {
            AKError("No config file found at: \(settings.configLocation.path)")
            return
        }
        try engine.evalFromURL(settings.configLocation)
    }

    func shutdown() {
        NSApp.terminate(self)
    }
}
