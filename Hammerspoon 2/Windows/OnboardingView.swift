//
//  OnboardingView.swift
//  Hammerspoon 2
//
//  Created by Claude on 25/08/2026.
//

import SwiftUI
import UniformTypeIdentifiers

private let docsURL = URL(string: "https://cmsj.github.io/Hammerspoon2")!

@_documentation(visibility: private)
struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var configDirectory: URL
    @State private var isChoosingDirectory = false
    @State private var errorMessage: String?

    init() {
        _configDirectory = State(initialValue: SettingsManager.shared.configLocation.deletingLastPathComponent())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Hammerspoon 2")
                .font(.title)
                .fontWeight(.bold)

            Text("Hammerspoon 2 automates macOS using JavaScript. Your automations live in a config file, which is loaded on startup and whenever you reload it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Config location")
                    .font(.headline)

                HStack {
                    Text(configDirectory.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Button("Choose…") {
                        isChoosingDirectory = true
                    }
                }
            }

            Link("Open the API documentation", destination: docsURL)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Get Started") {
                    getStarted()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                configDirectory = url
            }
        }
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func getStarted() {
        errorMessage = nil
        do {
            try ManagerManager.shared.completeOnboarding(configDirectory: configDirectory)
            dismissWindow(id: "onboarding")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OnboardingView()
}
