//
//  View.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 26/12/2025.
//

import SwiftUI

extension View {
    @ViewBuilder func optionalGlassEffect() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular)
        } else {
            self
        }
    }
}
