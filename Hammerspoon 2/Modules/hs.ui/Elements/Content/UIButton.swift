//
//  UIButton.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 28/02/2026.
//

import Foundation
import SwiftUI

/// SwiftUI view that directly observes an HSString label so only the button
/// re-renders when the label changes.
private struct ReactiveButton: View {
    var label: HSString
    let font: Font
    let foreground: Color
    let fill: Color
    let strokeColor: Color?
    let strokeWidth: CGFloat
    let cornerRadius: CGFloat
    let opacity: Double
    let width: CGFloat?
    let height: CGFloat?
    let action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            Text(label.value)
                .font(font)
                .foregroundColor(foreground)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
        .overlay(
            Group {
                if let stroke = strokeColor {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(stroke, lineWidth: strokeWidth)
                }
            }
        )
        .opacity(opacity)
        .frame(width: width, height: height)
    }
}

class UIButton: ShapeModifiable, FrameModifiable, OpacityModifiable, InteractiveModifiable, TextModifiable {
    var label: HSString
    var font: Font = .body
    var foregroundColor: HSColor? = nil
    var fillColor: HSColor? = nil
    var strokeColor: HSColor? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 8.0
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    init(label: HSString) {
        self.label = label
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        let fg = foregroundColor?.color ?? Color.primary
        let fill = fillColor?.color ?? Color.clear
        let stroke = strokeColor?.color
        let resolved = elementFrame?.resolve(containerSize: containerSize)

        var view = AnyView(
            ReactiveButton(
                label: label,
                font: font,
                foreground: fg,
                fill: fill,
                strokeColor: stroke,
                strokeWidth: strokeWidth,
                cornerRadius: cornerRadius,
                opacity: elementOpacity,
                width: resolved?.width,
                height: resolved?.height,
                action: clickCallback
            )
        )

        if let onHover = hoverCallback {
            view = AnyView(view.onHover { onHover($0) })
        }

        return view
    }
}
