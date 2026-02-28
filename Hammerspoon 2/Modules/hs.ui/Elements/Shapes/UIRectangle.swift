//
//  UIRectangle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIRectangle: ShapeModifiable, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var fillColor: HSColor? = nil
    var strokeColor: HSColor? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        var view: AnyView
        if let fill = fillColor?.color {
            view = AnyView(Rectangle().fill(fill))
        } else if let stroke = strokeColor?.color {
            view = AnyView(Rectangle().stroke(stroke, lineWidth: strokeWidth))
        } else {
            view = AnyView(Rectangle())
        }

        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            view = AnyView(view.frame(width: resolved.width, height: resolved.height))
        }

        view = AnyView(view.cornerRadius(cornerRadius).opacity(elementOpacity))

        return applyInteractions(view)
    }
}
