//
//  UIRectangle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIRectangle: ShapeModifiable, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var fillColor: Color? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        // Build the base shape with color
        var view: AnyView
        if let fill = fillColor {
            view = AnyView(Rectangle().fill(fill))
        } else if let stroke = strokeColor {
            view = AnyView(Rectangle().stroke(stroke, lineWidth: strokeWidth))
        } else {
            view = AnyView(Rectangle())
        }

        // Apply frame if specified
        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            view = AnyView(view.frame(width: resolved.width, height: resolved.height))
        }

        view = AnyView(view.cornerRadius(cornerRadius).opacity(elementOpacity))

        return applyInteractions(view)
    }
}
