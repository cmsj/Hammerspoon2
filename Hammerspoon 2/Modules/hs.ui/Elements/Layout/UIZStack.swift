//
//  UIZStack.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIZStack: UIContainer, PaddingModifiable {
    var children: [any HSUIElement] = []
    var elementPadding: CGFloat = 0

    func addChild(_ child: any HSUIElement) {
        children.append(child)
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        AnyView(
            ZStack {
                ForEach(0..<children.count, id: \.self) { index in
                    self.children[index].toSwiftUI(containerSize: containerSize)
                }
            }
            .padding(elementPadding)
        )
    }
}
