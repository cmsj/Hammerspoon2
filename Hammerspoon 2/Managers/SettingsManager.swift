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
final class SettingsManager {
    static let shared = SettingsManager()

    enum Keys: String, CaseIterable {
        case configLocation
        case consoleHistoryLength

        var id: String { "\(self)" }

        var defaultValue: Any {
            switch(self) {
            case .configLocation:
                return URL(filePath: NSString("~/.config/Hammerspoon2/init.js").expandingTildeInPath)
            case .consoleHistoryLength:
                return 100
            }
        }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.configLocation.rawValue: Keys.configLocation.defaultValue
        ])
    }
}

// MARK: - SettingsManagerProtocol Conformance
extension SettingsManager: SettingsManagerProtocol {
    // All required methods are already implemented in the class
    @ObservationIgnored
    var configLocation: URL {
        get {
            access(keyPath: \.configLocation)
            return UserDefaults.standard.url(forKey: Keys.configLocation.rawValue)!
        }
        set {
            withMutation(keyPath: \.configLocation) {
                UserDefaults.standard.set(newValue, forKey: Keys.configLocation.rawValue)
            }
        }
    }

    @ObservationIgnored
    var consoleHistoryLength: Int {
        get {
            access(keyPath: \.consoleHistoryLength)
            return UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        }
        set {
            withMutation(keyPath: \.consoleHistoryLength) {
                UserDefaults.standard.set(newValue, forKey: Keys.consoleHistoryLength.rawValue)
            }
        }
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.configLocation.rawValue)
        UserDefaults.standard.removeObject(forKey: Keys.consoleHistoryLength.rawValue)
    }
}
