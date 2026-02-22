//
//  UIDialogView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI

/// SwiftUI view for displaying dialogs with buttons
struct UIDialogView: View {
    let dialog: HSUIDialog
    let onButtonPress: (Int) -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Message
            Text(dialog.message)
                .font(.headline)
                .multilineTextAlignment(.center)

            // Informative text
            if let informativeText = dialog.informativeText {
                Text(informativeText)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }

            // Buttons
            HStack(spacing: 10) {
                ForEach(0..<dialog.buttons.count, id: \.self) { index in
                    Button(dialog.buttons[index]) {
                        onButtonPress(index)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
