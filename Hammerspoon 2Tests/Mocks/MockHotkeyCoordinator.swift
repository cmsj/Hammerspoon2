//
//  MockHotkeyCoordinator.swift
//  Hammerspoon 2Tests
//

import Foundation
@testable import Hammerspoon_2

@MainActor
final class MockHotkeyCoordinator: HotkeyCoordinator {
    private(set) var enabledHotkeys: [HSHotkey] = []
    private(set) var disabledHotkeys: [HSHotkey] = []

    func hotkeyDidEnable(_ hotkey: HSHotkey) -> Bool {
        enabledHotkeys.append(hotkey)
        return true
    }

    func hotkeyDidDisable(_ hotkey: HSHotkey) {
        enabledHotkeys.removeAll { $0 === hotkey }
        disabledHotkeys.append(hotkey)
    }
}
