//
//  UICircle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UICircle: ShapeModifiable, FrameModifiable, OpacityModifiable {
    var fillColor: Color? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0  // Not used for circles but required by protocol
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        // Apply frame if specified
        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            // Use the smaller dimension for circle to keep it circular
            let size = min(resolved.width, resolved.height)

            if let fill = fillColor {
                return AnyView(
                    Circle()
                        .fill(fill)
                        .frame(width: size, height: size)
                        .opacity(elementOpacity)
                )
            } else if let stroke = strokeColor {
                return AnyView(
                    Circle()
                        .stroke(stroke, lineWidth: strokeWidth)
                        .frame(width: size, height: size)
                        .opacity(elementOpacity)
                )
            } else {
                return AnyView(
                    Circle()
                        .frame(width: size, height: size)
                        .opacity(elementOpacity)
                )
            }
        } else {
            if let fill = fillColor {
                return AnyView(
                    Circle()
                        .fill(fill)
                        .opacity(elementOpacity)
                )
            } else if let stroke = strokeColor {
                return AnyView(
                    Circle()
                        .stroke(stroke, lineWidth: strokeWidth)
                        .opacity(elementOpacity)
                )
            } else {
                return AnyView(
                    Circle()
                        .opacity(elementOpacity)
                )
            }
        }
    }
}
