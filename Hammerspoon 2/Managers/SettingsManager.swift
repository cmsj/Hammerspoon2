//
//  SettingsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import SwiftUI

enum DockMenubarType: String, CaseIterable, Identifiable {
    var id: Self { self }

    case none
    case dock
    case menuBar
    case both

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .dock:
            return "Dock only"
        case .menuBar:
            return "Menu bar only"
        case .both:
            return "Dock and Menu bar"
        }
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .none, .menuBar:
            return .accessory
        default:
            return .regular
        }
    }

    var showMenuItem: Bool {
        switch self {
        case .menuBar, .both:
            return true
        default:
            return false
        }
    }
}

protocol SettingsManagerDelegate: AnyObject {
    func settingsDidChange()
}

@_documentation(visibility: private)
@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    @ObservationIgnored
    private var delegates = HSWeakObjectSet<any SettingsManagerDelegate>()

    enum Keys: String, CaseIterable {
        case configLocation
        case consoleHistoryLength
        case relaunchOnReload
        case dockMenuBehaviour

        var id: String { "\(self)" }

        var defaultValue: Any {
            switch(self) {
            case .configLocation:
                return URL(filePath: NSString("~/.config/Hammerspoon2/init.js").expandingTildeInPath)
            case .consoleHistoryLength:
                return 100
            case .relaunchOnReload:
                return false
            case .dockMenuBehaviour:
                return DockMenubarType.both.rawValue
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
    var dockMenuBehaviour: DockMenubarType {
        didSet { UserDefaults.standard.set(dockMenuBehaviour.rawValue, forKey: Keys.dockMenuBehaviour.rawValue)}
    }

    @ObservationIgnored
    private var defaultsObserver: (any NSObjectProtocol)?

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.configLocation.rawValue: Keys.configLocation.defaultValue,
            Keys.consoleHistoryLength.rawValue: Keys.consoleHistoryLength.defaultValue,
            Keys.relaunchOnReload.rawValue: Keys.relaunchOnReload.defaultValue,
            Keys.dockMenuBehaviour.rawValue: Keys.dockMenuBehaviour.defaultValue
        ])
        configLocation = UserDefaults.standard.url(forKey: Keys.configLocation.rawValue)
            ?? (Keys.configLocation.defaultValue as! URL)
        consoleHistoryLength = UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        relaunchOnReload = UserDefaults.standard.bool(forKey: Keys.relaunchOnReload.rawValue)

        let dockMenuBehaviourString = UserDefaults.standard.string(forKey: Keys.dockMenuBehaviour.rawValue) ?? Keys.dockMenuBehaviour.defaultValue as! String
        dockMenuBehaviour = DockMenubarType(rawValue: dockMenuBehaviourString) ?? Keys.dockMenuBehaviour.defaultValue as! DockMenubarType

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

        let newDockMenuBehaviour = UserDefaults.standard.string(forKey: Keys.dockMenuBehaviour.rawValue)
        if let newDockMenuBehaviour, newDockMenuBehaviour != dockMenuBehaviour.rawValue {
            if let behaviour = DockMenubarType(rawValue: newDockMenuBehaviour) {
                dockMenuBehaviour = behaviour
            }
        }
    }
}

// MARK: - SettingsManagerProtocol Conformance
extension SettingsManager: SettingsManagerProtocol {
    func resetToDefaults() {
        configLocation = Keys.configLocation.defaultValue as! URL
        consoleHistoryLength = Keys.consoleHistoryLength.defaultValue as! Int
        relaunchOnReload = Keys.relaunchOnReload.defaultValue as! Bool

        let dockMenuType = DockMenubarType(rawValue: Keys.dockMenuBehaviour.defaultValue as! String)!
        dockMenuBehaviour = dockMenuType
    }
}
