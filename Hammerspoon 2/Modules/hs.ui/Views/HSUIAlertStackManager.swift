//
//  HSUIAlertStackManager.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 20/08/2026.
//

import Foundation
import Observation
import SwiftUI

/// Tracks active auto-positioned alerts and animates their appearance in a stacked layout.
@Observable
final class HSUIAlertStackManager {
    var alerts: [HSUIAlert] = []

    var isEmpty: Bool { alerts.isEmpty }

    func add(_ alert: HSUIAlert) {
        guard !alerts.contains(where: { $0 === alert }) else { return }
        withAnimation(.linear(duration: 0.2)) {
            alerts.append(alert)
        }
    }

    func remove(_ alert: HSUIAlert) {
        withAnimation(.linear(duration: 0.2)) {
            alerts.removeAll { $0 === alert }
        }
    }
}
