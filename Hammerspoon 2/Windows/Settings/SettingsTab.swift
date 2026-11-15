//
//  SettingsTab.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import Foundation

/// The tabs of the Settings window
@_documentation(visibility: private)
enum SettingsTab: Hashable {
    case configuration
    case permissions
    case console
    case advanced
}
