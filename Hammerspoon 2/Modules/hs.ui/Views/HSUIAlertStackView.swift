//
//  HSUIAlertStackView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 20/08/2026.
//

import SwiftUI

/// Full-screen host view for all auto-positioned (stacked) alerts.
/// The VStack centers the stack vertically; transitions animate individual bubbles in and out.
struct HSUIAlertStackView: View {
    let manager: HSUIAlertStackManager

    var body: some View {
        VStack(spacing: 10) {
            ForEach(manager.alerts, id: \.alertID) { alert in
                UIAlertBubble(alert: alert)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
