//
//  UIRectangle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

/// SwiftUI view that directly observes an HSColor fill so only the rectangle
/// re-renders when the color changes — hover state and other modifiers are preserved.
private struct ReactiveRectangleFill: View {
    @ObservedObject var fillColor: HSColor
    let cornerRadius: CGFloat
    let opacity: Double
    let width: CGFloat?
    let height: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillColor.color)
            .opacity(opacity)
            .frame(width: width, height: height)
    }
}

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
        let resolved = elementFrame?.resolve(containerSize: containerSize)
        let w = resolved?.width
        let h = resolved?.height

        var view: AnyView
        if let fill = fillColor {
            view = AnyView(
                ReactiveRectangleFill(
                    fillColor: fill,
                    cornerRadius: cornerRadius,
                    opacity: elementOpacity,
                    width: w,
                    height: h
                )
            )
        } else if let stroke = strokeColor?.color {
            view = AnyView(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: strokeWidth)
                    .opacity(elementOpacity)
                    .frame(width: w, height: h)
            )
        } else {
            view = AnyView(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .opacity(elementOpacity)
                    .frame(width: w, height: h)
            )
        }

        return applyInteractions(view)
    }
}
