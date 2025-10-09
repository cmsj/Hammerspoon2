//
//  SettingsConfigView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI
import Sparkle

enum ConfigFilePickerValues: String, CaseIterable, Identifiable {
    case url, select
    var id: Self { self }
}

struct SettingsConfigView: View {
    @State private var settingsManager = SettingsManager.shared
    @State private var configFilePicker: ConfigFilePickerValues = .url
    @State private var icon = NSImage(size: .init(width: 12, height: 12))

    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 12

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Grid {
                    GridRow {
                        Text("Run at startup:")
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $configFilePicker) {
                            HStack {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: iconSize)
                                Text(settingsManager.configLocation.path(percentEncoded: false))
                            }
                            .tag(ConfigFilePickerValues.url)
                            Divider()
                            Text("Select new location")
                                .tag(ConfigFilePickerValues.select)
                        }
                        .labelsHidden()
                        .onChange(of: configFilePicker, initial: true) {
                            if configFilePicker == .select {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.canCreateDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.showsHiddenFiles = true
                                panel.directoryURL = settingsManager.configLocation.deletingLastPathComponent()

                                if panel.runModal() == .OK {
                                    if let url = panel.url {
                                        settingsManager.configLocation = url
                                    }
                                }
                            }
                            configFilePicker = .url
                            icon = NSWorkspace.shared.icon(forFile: settingsManager.configLocation.path)
                            icon.size = .init(width: iconSize, height: iconSize)
                        }
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
    SettingsConfigView()
}
