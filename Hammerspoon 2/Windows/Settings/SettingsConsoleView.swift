//
//  SettingsConsoleView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 29/09/2026.
//

import SwiftUI

@_documentation(visibility: private)
struct SettingsConsoleView: View {
    @State private var settingsManager = SettingsManager.shared
    @AppStorage("minimumLogLevel") var minimumLogLevel: HammerspoonLogType = .Debug

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Grid {
                    GridRow {
                        Text("History length:")
                            .gridColumnAlignment(.trailing)
                        TextField("Length", value: $settingsManager.consoleHistoryLength, formatter: NumberFormatter())
                            .labelsHidden()
                            .frame(width: 120)
                            .fixedSize(horizontal: true, vertical: true)
                            .gridColumnAlignment(.leading)
                    }
                    GridRow {
                        Text("Minimum log level:")
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $minimumLogLevel) {
                            ForEach(HammerspoonLogType.allCases.filter { $0 != .Autocomplete }){ item in
                                Text(item.asString)
                            }
                        }
                        .labelsHidden()
                        .gridColumnAlignment(.leading)
                    }
                    GridRow() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Enable garbage collection logging:")
                            Text("Requires Console log level “Garbage”.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .gridColumnAlignment(.trailing)
                        Toggle("Enable garbage collection logging", isOn: $settingsManager.garbageLoggingEnabled)
                            .labelsHidden()
                            .gridColumnAlignment(.leading)
                    }

                    GridRow {
                        Divider()
                            .gridCellColumns(2)
                    }

                    GridRow() {
                        Text("Keep console window on top:")
                            .gridColumnAlignment(.trailing)
                        Toggle("", isOn: $settingsManager.consoleAlwaysOnTop)
                            .labelsHidden()
                            .gridColumnAlignment(.leading)
                    }
                    GridRow() {
                        Text("Console window opacity:")
                            .gridColumnAlignment(.trailing)
                        HStack {
                            Slider(value: $settingsManager.consoleAlpha, in: 0.2...1.0) { Text("") }
                                .labelsHidden()
                                .frame(width: 160)
                            Text(settingsManager.consoleAlpha, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
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
    SettingsConsoleView()
}
