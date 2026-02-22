//
//  UIText.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIText: FrameModifiable, OpacityModifiable {
    var content: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0

    init(content: String) {
        self.content = content
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        let textView = Text(content)
            .font(font)
            .foregroundColor(foregroundColor)
            .opacity(elementOpacity)

        // Apply frame if specified
        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            return AnyView(
                textView
                    .frame(width: resolved.width, height: resolved.height)
            )
        } else {
            return AnyView(textView)
        }
    }
}
