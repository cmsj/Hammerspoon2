//
//  UICircle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UICircle: ShapeModifiable, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var fillColor: Color? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0  // Not used for circles but required by protocol
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        // Build the base shape with color
        var view: AnyView
        if let fill = fillColor {
            view = AnyView(Circle().fill(fill))
        } else if let stroke = strokeColor {
            view = AnyView(Circle().stroke(stroke, lineWidth: strokeWidth))
        } else {
            view = AnyView(Circle())
        }

        // Apply frame if specified, using the smaller dimension to keep it circular
        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            let size = min(resolved.width, resolved.height)
            view = AnyView(view.frame(width: size, height: size))
        }

        view = AnyView(view.opacity(elementOpacity))

        return applyInteractions(view)
    }
}
