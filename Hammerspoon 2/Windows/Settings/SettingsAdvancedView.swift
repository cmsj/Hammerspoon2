//
//  SettingsAdvancedView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI
import Sparkle

@_documentation(visibility: private)
struct SettingsAdvancedView: View {
    @State private var settingsManager = SettingsManager.shared
    @State private var automaticallyChecksForUpdates: Bool = false
    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 12

    init() {
        self._automaticallyChecksForUpdates = State(initialValue: AppUpdater.updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Grid {
                    GridRow {
                        Text("Automatically check for updates:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                            .labelsHidden()
                            .gridColumnAlignment(.leading)
                            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                                AppUpdater.updater.automaticallyChecksForUpdates = newValue
                            }
                    }
                    GridRow {
                        Text("Relaunch app on config reload:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Relaunch app on config reload", isOn: Bindable(settingsManager).relaunchOnReload)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("When launched while running:")
                            .gridColumnAlignment(.trailing)
                        Picker("When launched while running", selection: Bindable(settingsManager).reopenAction) {
                            ForEach(ReopenAction.allCases) { action in
                                Text(action.displayName)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    GridRow {
                        Text("Install Spoons when opened:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Install Spoons when opened", isOn: Bindable(settingsManager).importSpoonsOnOpen)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Offer to report crashes on GitHub:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Offer to report crashes on GitHub", isOn: Bindable(settingsManager).offerCrashReports)
                            .labelsHidden()
                    }

                    GridRow {
                        Spacer()
                    }
                    GridRow {
                        Divider()
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Button("Reset all settings") {
                            settingsManager.resetToDefaults()
                        }
                        .gridCellColumns(2)
                    }
                }
                Spacer()
            }
            .frame(width: 700)
            .padding(.vertical)
            Spacer()
        }
    }
}

#Preview {
    SettingsAdvancedView()
}
