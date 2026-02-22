//
//  UIAlertView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI

/// SwiftUI view for displaying alerts
struct UIAlertView: View {
    let alert: HSUIAlert

    @State private var viewOpacity = 0.0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(alert.message)
                    .font(alert.font)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .optionalGlassEffect()
                Spacer()
            }
            Spacer()
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
