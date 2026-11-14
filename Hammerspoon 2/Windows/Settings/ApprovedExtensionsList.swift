//
//  ApprovedExtensionsList.swift
//  Hammerspoon 2
//

import SwiftUI

/// The extensions the user has allowed to load, each with a button to remove its approval.
@_documentation(visibility: private)
struct ApprovedExtensionsList: View {
    let approvals: [ExtensionApproval]
    let revoke: (String) -> Void

    var body: some View {
        if approvals.isEmpty {
            Text("None. You're asked the first time your config loads each extension.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading) {
                List(approvals) { approval in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(approval.name)
                            Text("\(approval.signerName ?? "Not signed by an identified developer"), allowed \(approval.date, format: .dateTime.day().month().year())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove approval for \(approval.name)", systemImage: "minus.circle") {
                            revoke(approval.name)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove approval. You'll be asked again the next time your config loads it.")
                    }
                }
                .listStyle(.bordered)
                .frame(height: 90)

                Text("An extension whose approval you remove keeps running until your config reloads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ApprovedExtensionsList(
        approvals: [
            ExtensionApproval(name: "com.example.foo", cdHash: "abc", signerName: "Developer ID Application: Example Ltd (ABCDE12345)", date: .now),
            ExtensionApproval(name: "hs2.testextension", cdHash: "def", signerName: nil, date: .now),
        ],
        revoke: { _ in }
    )
    .frame(width: 450)
    .padding()
}
