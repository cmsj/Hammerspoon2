//
//  UICircle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UICircle: ShapeModifiable, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var fillColor: HSColor? = nil
    var strokeColor: HSColor? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0  // Not used for circles but required by protocol
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        var view: AnyView
        if let fill = fillColor?.color {
            view = AnyView(Circle().fill(fill))
        } else if let stroke = strokeColor?.color {
            view = AnyView(Circle().stroke(stroke, lineWidth: strokeWidth))
        } else {
            view = AnyView(Circle())
        }

        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            let size = min(resolved.width, resolved.height)
            view = AnyView(view.frame(width: size, height: size))
        }

        view = AnyView(view.opacity(elementOpacity))

        return applyInteractions(view)
    }
}
