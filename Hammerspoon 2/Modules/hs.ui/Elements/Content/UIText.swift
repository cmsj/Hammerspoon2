//
//  UIText.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIText: FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var content: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    init(content: String) {
        self.content = content
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        var view: AnyView = AnyView(
            Text(content)
                .font(font)
                .foregroundColor(foregroundColor)
                .opacity(elementOpacity)
        )

        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            view = AnyView(view.frame(width: resolved.width, height: resolved.height))
        }

        return applyInteractions(view)
    }
}
