//
//  SettingsView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI

@_documentation(visibility: private)
struct SettingsView: View {
    @State private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TabView {
            Tab("Configuration", systemImage: "gearshape") {
                SettingsConfigView()
            }
            Tab("Advanced", systemImage: "hammer") {
                SettingsAdvancedView()
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
