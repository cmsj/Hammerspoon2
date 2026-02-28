//
//  UICircle.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI
import Combine

/// SwiftUI view that directly observes an HSColor fill so only the circle
/// re-renders when the color changes.
private struct ReactiveCircleFill: View {
    @ObservedObject var fillColor: HSColor
    let opacity: Double
    let size: CGFloat?

    var body: some View {
        Circle()
            .fill(fillColor.color)
            .opacity(opacity)
            .frame(width: size, height: size)
    }
}

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
        let resolved = elementFrame?.resolve(containerSize: containerSize)
        let size: CGFloat? = resolved.map { min($0.width, $0.height) }

        var view: AnyView
        if let fill = fillColor {
            view = AnyView(
                ReactiveCircleFill(
                    fillColor: fill,
                    opacity: elementOpacity,
                    size: size
                )
            )
        } else if let stroke = strokeColor?.color {
            view = AnyView(
                Circle()
                    .stroke(stroke, lineWidth: strokeWidth)
                    .opacity(elementOpacity)
                    .frame(width: size, height: size)
            )
        } else {
            view = AnyView(
                Circle()
                    .opacity(elementOpacity)
                    .frame(width: size, height: size)
            )
        }

        return applyInteractions(view)
    }
}
