//
//  SettingsAdvancedView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import SwiftUI
import Sparkle

struct SettingsAdvancedView: View {
    @State private var settingsManager = SettingsManager.shared
    @State private var hiddenTrigger: Bool = false // FIXME: This is an ugly hack to make the Sparkle binding below update the UI correctly.

    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 12

    private let updaterController: SPUStandardUpdaterController
    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding (
            get: { self.updaterController.updater.automaticallyChecksForUpdates },
            set: {
                self.updaterController.updater.automaticallyChecksForUpdates = $0
                hiddenTrigger = $0
            }
        )
    }

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        hiddenTrigger = updaterController.updater.automaticallyChecksForUpdates
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Grid {
                    GridRow {
                        Text("Automatically check for updates: \(hiddenTrigger ? "" : "")")
                            .gridColumnAlignment(.trailing)
                        Toggle(isOn: automaticallyChecksForUpdates) {
                            Text("")
                        }
                        .labelsHidden()
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
