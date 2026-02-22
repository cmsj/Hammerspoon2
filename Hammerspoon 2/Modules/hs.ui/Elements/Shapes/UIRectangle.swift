//
//  UIRectangle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

class UIRectangle: ShapeModifiable, FrameModifiable, OpacityModifiable {
    var fillColor: Color? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 0.0
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        // Apply frame if specified
        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)

            if let fill = fillColor {
                return AnyView(
                    Rectangle()
                        .fill(fill)
                        .frame(width: resolved.width, height: resolved.height)
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            } else if let stroke = strokeColor {
                return AnyView(
                    Rectangle()
                        .stroke(stroke, lineWidth: strokeWidth)
                        .frame(width: resolved.width, height: resolved.height)
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            } else {
                return AnyView(
                    Rectangle()
                        .frame(width: resolved.width, height: resolved.height)
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            }
        } else {
            if let fill = fillColor {
                return AnyView(
                    Rectangle()
                        .fill(fill)
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            } else if let stroke = strokeColor {
                return AnyView(
                    Rectangle()
                        .stroke(stroke, lineWidth: strokeWidth)
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            } else {
                return AnyView(
                    Rectangle()
                        .cornerRadius(cornerRadius)
                        .opacity(elementOpacity)
                )
            }
        }
    }
}
