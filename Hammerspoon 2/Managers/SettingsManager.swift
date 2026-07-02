//
//  SettingsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import SwiftUI

@_documentation(visibility: private)
@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    enum Keys: String, CaseIterable {
        case configLocation
        case consoleHistoryLength
        case relaunchOnReload

        var id: String { "\(self)" }

        var defaultValue: Any {
            switch(self) {
            case .configLocation:
                return URL(filePath: NSString("~/.config/Hammerspoon2/init.js").expandingTildeInPath)
            case .consoleHistoryLength:
                return 100
            case .relaunchOnReload:
                return false
            }
        }
    }

    var configLocation: URL {
        didSet { UserDefaults.standard.set(configLocation, forKey: Keys.configLocation.rawValue) }
    }
    var consoleHistoryLength: Int {
        didSet { UserDefaults.standard.set(consoleHistoryLength, forKey: Keys.consoleHistoryLength.rawValue) }
    }
    var relaunchOnReload: Bool {
        didSet { UserDefaults.standard.set(relaunchOnReload, forKey: Keys.relaunchOnReload.rawValue) }
    }

    @ObservationIgnored
    private var defaultsObserver: (any NSObjectProtocol)?

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.configLocation.rawValue: Keys.configLocation.defaultValue,
            Keys.consoleHistoryLength.rawValue: Keys.consoleHistoryLength.defaultValue,
            Keys.relaunchOnReload.rawValue: Keys.relaunchOnReload.defaultValue
        ])
        configLocation = UserDefaults.standard.url(forKey: Keys.configLocation.rawValue)
            ?? (Keys.configLocation.defaultValue as! URL)
        consoleHistoryLength = UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        relaunchOnReload = UserDefaults.standard.bool(forKey: Keys.relaunchOnReload.rawValue)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromUserDefaults() }
        }
    }

    isolated deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func syncFromUserDefaults() {
        let newConfigLocation = UserDefaults.standard.url(forKey: Keys.configLocation.rawValue)
            ?? (Keys.configLocation.defaultValue as! URL)
        if newConfigLocation != configLocation { configLocation = newConfigLocation }

        let newConsoleHistoryLength = UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        if newConsoleHistoryLength != consoleHistoryLength { consoleHistoryLength = newConsoleHistoryLength }

        let newRelaunchOnReload = UserDefaults.standard.bool(forKey: Keys.relaunchOnReload.rawValue)
        if newRelaunchOnReload != relaunchOnReload { relaunchOnReload = newRelaunchOnReload }
    }
}

// MARK: - SettingsManagerProtocol Conformance
extension SettingsManager: SettingsManagerProtocol {
    func resetToDefaults() {
        configLocation = Keys.configLocation.defaultValue as! URL
        consoleHistoryLength = Keys.consoleHistoryLength.defaultValue as! Int
        relaunchOnReload = Keys.relaunchOnReload.defaultValue as! Bool
    }
}
