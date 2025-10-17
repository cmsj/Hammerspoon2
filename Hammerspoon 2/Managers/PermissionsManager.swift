//
//  PermissionsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import Foundation
@preconcurrency import ApplicationServices.HIServices.AXUIElement

enum PermissionsState: Int {
    case notTrusted = 0
    case trusted
    case unknown
}

enum PermissionsType: Int {
    case accessibility = 0
}

@MainActor
class PermissionsManager {
    static let shared = PermissionsManager()

    func check(_ permType: PermissionsType) -> PermissionsState {
        switch permType {
        case .accessibility:
            return AXIsProcessTrusted() ? .trusted : .notTrusted
        }
    }

    func request(_ permType: PermissionsType) {
        switch permType {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
}
