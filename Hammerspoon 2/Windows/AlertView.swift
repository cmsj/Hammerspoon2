//
//  AlertView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 10/11/2025.
//

import SwiftUI

struct AlertView: View {
    let message: HSAlert

    @State private var viewOpacity = 0.0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(message.message)
                    .font(message.swiftUIFont)
                    .multilineTextAlignment(.center)
                    .padding(.all, message.swiftUIPadding)
                    .optionalGlassEffect()
                Spacer()
            }
            Spacer()
        }
        .opacity(viewOpacity)
        .task {
            withAnimation(.linear(duration: 0.2)) {
                viewOpacity = 1.0
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Double(message.expire) - 0.2))
            withAnimation(.linear(duration: 0.2)) {
                viewOpacity = 0.0
            }
        }
    }
}

#Preview("Alert") {
    let alertObject = HSAlert(message: "TESTING")
    AlertView(message: alertObject)
}
