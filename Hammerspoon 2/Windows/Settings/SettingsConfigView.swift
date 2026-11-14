//
//  SettingsConfigView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI

@_documentation(visibility: private)
enum ConfigFilePickerValues: String, CaseIterable, Identifiable {
    case url, select
    var id: Self { self }
}

@_documentation(visibility: private)
struct SettingsConfigView: View {
    @State private var settingsManager = SettingsManager.shared
    @State private var configFilePicker: ConfigFilePickerValues = .url
    @State private var icon = NSImage(size: .init(width: 12, height: 12))

    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 12

    fileprivate func handleConfigFilePickerChange() {
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

    private var neitherHint: String {
        switch settingsManager.reopenAction {
        case .showConsole:
            return "To open the Console, launch Hammerspoon 2 again (e.g. from Finder or Spotlight)."
        case .callback:
            return "Launching Hammerspoon 2 again (e.g. from Finder or Spotlight) calls hs.onRelaunch, or opens the Console if your config hasn't set it."
        case .doNothing:
            return "Launching Hammerspoon 2 again is set to do nothing (see Advanced), so you'll need hs.openConsole() or the hs2 command line tool to open the Console."
        }
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Grid {
                    GridRow {
                        Text("Configuration:")
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
                        .gridColumnAlignment(.leading)
                        .onChange(of: configFilePicker, initial: true) {
                            handleConfigFilePickerChange()
                        }
                    }
                    GridRow {
                        Text("Show in:")
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $settingsManager.dockMenuBehaviour) {
                            ForEach(DockMenubarType.allCases) { someType in
                                Text("\(someType.displayName)")
                            }
                        }
                        .labelsHidden()
                    }
                    if settingsManager.dockMenuBehaviour == .neither {
                        GridRow {
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                            Text(neitherHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                                .frame(maxWidth: 400, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
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
