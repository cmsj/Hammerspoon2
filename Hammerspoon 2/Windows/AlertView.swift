//
//  AlertView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 10/11/2025.
//

import SwiftUI

@MainActor
@Observable
final class AlertViewModel: WindowAccessorDelegate {
    weak var window: NSWindow? = nil
}

struct AlertView: View {
    @Environment(\.dismissWindow) var dismissWindow

    @State var viewModel = AlertViewModel()
    let message: HSAlertObject

    var body: some View {
        ZStack {
            NSWindowAccessor(delegate: viewModel)
                .frame(width: 0, height: 0)
            Text(message.message)
                .onChange(of: viewModel.window) { _, _ in
                    // Hide the traffic light buttons if we now have a valid NSWindow
                    guard let window = viewModel.window else { return }
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                }
                .task {
                    try? await Task.sleep(for: .seconds(message.expire))
                    dismissWindow()
                }
        }
    }
}

struct HSAlertObject: Decodable, Encodable, Hashable {
    let message: String
    let expire: Int

    init(message: String, expire: Int = 5) {
        self.message = message
        self.expire = expire
    }
}

#Preview("Alert") {
    AlertView(message: HSAlertObject(message: "TESTING"))
}
