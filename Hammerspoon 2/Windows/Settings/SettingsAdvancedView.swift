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

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self._automaticallyChecksForUpdates = State(initialValue: updaterController.updater.automaticallyChecksForUpdates)
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
                            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                                updaterController.updater.automaticallyChecksForUpdates = newValue
                            }
                    }
                    GridRow {
                        Text("Relaunch app on config reload:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Relaunch app on config reload", isOn: Bindable(settingsManager).relaunchOnReload)
                            .labelsHidden()
                    }
                    GridRow {
                        Divider()
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Console history length:")
                            .gridColumnAlignment(.trailing)
                        TextField("Length", value: $settingsManager.consoleHistoryLength, formatter: NumberFormatter())
                            .labelsHidden()
                            .frame(width: 120)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    GridRow {
                        Text("Enable garbage collection logging:")
                            .gridColumnAlignment(.trailing)
                        Toggle("Enable garbage collection logging", isOn: Bindable(settingsManager).garbageLoggingEnabled)
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
