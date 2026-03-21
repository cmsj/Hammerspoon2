//
//  SettingsPermissionsView.swift
//  Hammerspoon 2
//
//  Created by Claude on 20/03/2026.
//

import SwiftUI

@_documentation(visibility: private)
struct PermissionRowView: View {
    let permType: PermissionsType
    let state: PermissionsState

    var body: some View {
        GridRow {
            trafficLight
                .gridColumnAlignment(.center)
            VStack(alignment: .leading, spacing: 2) {
                Text(permType.displayName)
                    .fontWeight(.medium)
                Text(permType.permissionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .gridColumnAlignment(.leading)
            actionButton
                .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .trusted:
            Button("Request") {}
                .disabled(true)
        case .unknown:
            Button("Request") {
                PermissionsManager.shared.request(permType)
            }
        case .notTrusted:
            Button("Open Settings") {
                NSWorkspace.shared.open(permType.settingsURL)
            }
        }
    }

    @ViewBuilder
    private var trafficLight: some View {
        switch state {
        case .trusted:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
        case .notTrusted:
            Image(systemName: "circle.fill")
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

@_documentation(visibility: private)
struct SettingsPermissionsView: View {
    @State private var permissionStates: [PermissionsType: PermissionsState] = [:]
    @State private var refreshTimer: Timer?
    @State private var isRefreshing = true
    @State private var remainingAllowedAutoRefreshes = 100

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(height: 12.0)
            .opacity(isRefreshing ? 1.0 : 0.0)
            .padding([.top])

        HStack {
            Spacer()
            VStack {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(PermissionsType.allCases, id: \.self) { permType in
                        PermissionRowView(
                            permType: permType,
                            state: permissionStates[permType] ?? .unknown
                        )
                    }
                }
                Spacer()
            }
            .frame(width: 700)
            .padding(.vertical)
            Spacer()
        }
        .onAppear {
            remainingAllowedAutoRefreshes = 100
            refreshPermissions()
            startObserving()
        }
        .onDisappear {
            stopObserving()
        }
    }

    private func refreshPermissions() {
        for permType in PermissionsType.allCases {
            permissionStates[permType] = PermissionsManager.shared.state(permType)
        }
    }

    private func startObserving() {
        guard refreshTimer == nil else { return }
        guard remainingAllowedAutoRefreshes > 0 else { return }

        let timer = Timer(timeInterval: 5.0, repeats: true) { [self] _ in
            Task { @MainActor in
                refreshPermissions()
                isRefreshing = false
                remainingAllowedAutoRefreshes -= 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

#Preview {
    SettingsPermissionsView()
}
