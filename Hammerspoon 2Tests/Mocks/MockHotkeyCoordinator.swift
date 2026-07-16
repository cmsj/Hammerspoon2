//
//  MockHotkeyCoordinator.swift
//  Hammerspoon 2Tests
//

import Foundation
@testable import Hammerspoon_2

typealias MockHotkeyCoordinator = MockEventTapHotkeyCoordinator

@MainActor
final class MockEventTapHotkeyCoordinator: EventTapHotkeyCoordinator {
    private(set) var enabledHotkeys: [HSEventTapHotkey] = []
    private(set) var disabledHotkeys: [HSEventTapHotkey] = []

    func tapHotkeyDidEnable(_ hotkey: HSEventTapHotkey) -> Bool {
        enabledHotkeys.append(hotkey)
        return true
    }

    func tapHotkeyDidDisable(_ hotkey: HSEventTapHotkey) {
        enabledHotkeys.removeAll { $0 === hotkey }
        disabledHotkeys.append(hotkey)
    }
}
