//
//  HSUIElement.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

/// Delegate notified when a reactive UI value (color, string, image) changes,
/// so the canvas can be re-rendered.
protocol HSUIElementDelegate: AnyObject {
    func valueDidChange()
}

/// Protocol that all UI elements must conform to
protocol HSUIElement {
    /// Convert this element to a SwiftUI view
    func toSwiftUI(containerSize: CGSize) -> AnyView
}

/// Protocol for elements that can have their shape properties modified
protocol ShapeModifiable: HSUIElement, AnyObject {
    var fillColor: HSColor? { get set }
    var strokeColor: HSColor? { get set }
    var strokeWidth: CGFloat { get set }
    var cornerRadius: CGFloat { get set }
}

/// Protocol for elements that can have frames
protocol FrameModifiable: HSUIElement, AnyObject {
    var elementFrame: UIFrame? { get set }
}

/// Protocol for elements that can have opacity
protocol OpacityModifiable: HSUIElement, AnyObject {
    var elementOpacity: Double { get set }
}

/// Protocol for elements that can have padding
protocol PaddingModifiable: HSUIElement, AnyObject {
    var elementPadding: CGFloat { get set }
}

/// Protocol for elements that can have spacing
protocol SpacingModifiable: HSUIElement, AnyObject {
    var elementSpacing: CGFloat { get set }
}

/// Protocol for container elements
protocol UIContainer: HSUIElement, AnyObject {
    var children: [any HSUIElement] { get set }
    func addChild(_ child: any HSUIElement)
}

/// Protocol for elements that have a text label with font and color
protocol TextModifiable: HSUIElement, AnyObject {
    var font: Font { get set }
    var foregroundColor: HSColor? { get set }
}

/// Protocol for elements that support click and hover callbacks
protocol InteractiveModifiable: HSUIElement, AnyObject {
    var clickCallback: (() -> Void)? { get set }
    var hoverCallback: ((Bool) -> Void)? { get set }
}

extension InteractiveModifiable {
    /// Wraps a view with tap and hover gesture modifiers if callbacks are set
    func applyInteractions(_ view: AnyView) -> AnyView {
        var result = view
        if let onClick = clickCallback {
            result = AnyView(result.contentShape(Rectangle()).onTapGesture { onClick() })
        }
        if let onHover = hoverCallback {
            result = AnyView(result.onHover { isHovered in onHover(isHovered) })
        }
        return result
    }
}
