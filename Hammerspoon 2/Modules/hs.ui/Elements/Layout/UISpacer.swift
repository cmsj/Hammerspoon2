//
//  UISpacer.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 21/02/2026.
//

import Foundation
import SwiftUI

class UISpacer: HSUIElement {
    var minLength: CGFloat?

    init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        if let minLength = minLength {
            return AnyView(Spacer(minLength: minLength))
        } else {
            return AnyView(Spacer())
        }
    }
}
