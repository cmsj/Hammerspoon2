//
//  MockSettingsManager.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 05/11/2025.
//

import Foundation
@testable import Hammerspoon_2

/// Mock implementation of SettingsManagerProtocol for testing
class MockSettingsManager: SettingsManagerProtocol {
    var configLocation: URL = URL(fileURLWithPath: "/mock/config/init.js")
    var consoleHistoryLength: Int = 100
    var relaunchOnReload: Bool = false
    var hasCompletedOnboarding: Bool = false
    var debugLoggingEnabled: Bool = false

    var resetToDefaultsCalls: Int = 0

    func resetToDefaults() {
        resetToDefaultsCalls += 1
        configLocation = URL(fileURLWithPath: "/mock/config/init.js")
        consoleHistoryLength = 100
        relaunchOnReload = false
        debugLoggingEnabled = false
    }

    // Helper methods for testing
    func reset() {
        resetToDefaultsCalls = 0
        configLocation = URL(fileURLWithPath: "/mock/config/init.js")
        consoleHistoryLength = 100
        relaunchOnReload = false
        hasCompletedOnboarding = false
        debugLoggingEnabled = false
    }
}
