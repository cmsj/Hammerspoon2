//
//  UIButton.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 28/02/2026.
//

import Foundation
import SwiftUI

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
        let radius = cornerRadius

        // Use SwiftUI's Button for native press-state feedback.
        // clickCallback is wired directly to the button action rather than via
        // onTapGesture, avoiding a double-fire.
        var view: AnyView = AnyView(
            Button(action: { self.clickCallback?() }) {
                Text(label.value)
                    .font(font)
                    .foregroundColor(fg)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(
                Group {
                    if let stroke = strokeColor?.color {
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(stroke, lineWidth: strokeWidth)
                    }
                }
            )
        )

        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            view = AnyView(view.frame(width: resolved.width, height: resolved.height))
        }

        view = AnyView(view.opacity(elementOpacity))

        if let onHover = hoverCallback {
            view = AnyView(view.onHover { onHover($0) })
        }

        return view
    }
}
