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
    @Bindable private var appWindows = AppWindows.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TabView(selection: $appWindows.settingsTab) {
            Tab("Configuration", systemImage: "gearshape", value: .configuration) {
                SettingsConfigView()
            }
            Tab("Permissions", systemImage: "lock.shield", value: .permissions) {
                SettingsPermissionsView()
            }
            Tab("Console", systemImage: "line.3.horizontal", value: .console) {
                SettingsConsoleView()
            }
            Tab("Advanced", systemImage: "hammer", value: .advanced) {
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
