//
//  UIAlertView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI

/// Full-screen host view for an explicitly-positioned (standalone) alert.
/// Positions the bubble at the coordinates stored in `alert.position`,
/// falling back to center when no position is set.
struct UIAlertView: View {
    let alert: HSUIAlert

    @State private var viewOpacity = 0.0

    var body: some View {
        GeometryReader { geometry in
            UIAlertBubble(alert: alert)
                .position(
                    x: alert.position?.x ?? geometry.size.width / 2,
                    y: alert.position?.y ?? geometry.size.height / 2
                )
        }
        .opacity(viewOpacity)
        .task {
            withAnimation(.linear(duration: 0.2)) {
                viewOpacity = 1.0
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(alert.duration - 0.2))
            withAnimation(.linear(duration: 0.2)) {
                viewOpacity = 0.0
            }
        }
    }
}

/// The visual pill shared by both UIAlertView and HSUIAlertStackView.
struct UIAlertBubble: View {
    let alert: HSUIAlert

    var body: some View {
        Text(alert.message)
            .font(alert.font)
            .multilineTextAlignment(.center)
            .padding(alert.padding ?? 20)
            .optionalGlassEffect()
    }
}
