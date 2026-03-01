//
//  UIText.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

/// SwiftUI view that directly observes an HSString so only the text element
/// re-renders when the value changes — not the entire canvas.
private struct ReactiveText: View {
    var content: HSString
    let font: Font
    let foreground: Color
    let opacity: Double
    let width: CGFloat?
    let height: CGFloat?

    var body: some View {
        Text(content.value)
            .font(font)
            .foregroundColor(foreground)
            .opacity(opacity)
            .frame(width: width, height: height)
    }
}

class UIText: FrameModifiable, OpacityModifiable, InteractiveModifiable, TextModifiable {
    var content: HSString
    var font: Font = .body
    var foregroundColor: HSColor? = nil
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    init(content: HSString) {
        self.content = content
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        let fg = foregroundColor?.color ?? Color.primary
        let resolved = elementFrame?.resolve(containerSize: containerSize)

        let view = AnyView(
            ReactiveText(
                content: content,
                font: font,
                foreground: fg,
                opacity: elementOpacity,
                width: resolved?.width,
                height: resolved?.height
            )
        )

        return applyInteractions(view)
    }
}
