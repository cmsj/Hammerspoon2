//
//  SettingsView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI

struct SettingsView: View {
    @State private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TabView {
            SettingsConfigView()
                .tabItem {
                    Label("Configuration", systemImage: "gearshape")
                }
            SettingsAdvancedView()
                .tabItem {
                    Label("Advanced", systemImage: "hammer")
                }
        }
        .frame(width: 750, height: 400)
        .onKeyPress { action in
            if action.key == "w" && action.modifiers == [.command] {
                dismiss()
                return .handled
            }
            return .ignored
        }
    }
}

#Preview {
    SettingsView()
}
