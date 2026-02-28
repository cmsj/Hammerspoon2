//
//  UIHStack.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIHStack: UIContainer, PaddingModifiable, SpacingModifiable {
    var children: [any HSUIElement] = []
    var elementPadding: CGFloat = 0
    var elementSpacing: CGFloat = 8  // Default SwiftUI spacing

    func addChild(_ child: any HSUIElement) {
        children.append(child)
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        AnyView(
            HStack(spacing: elementSpacing) {
                ForEach(0..<children.count, id: \.self) { index in
                    self.children[index].toSwiftUI(containerSize: containerSize)
                }
            }
            .padding(elementPadding)
        )
    }
}
