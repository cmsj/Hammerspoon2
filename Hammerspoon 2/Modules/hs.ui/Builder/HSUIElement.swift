//
//  HSUIElement.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import SwiftUI

/// Protocol that all UI elements must conform to
protocol HSUIElement {
    /// Convert this element to a SwiftUI view
    func toSwiftUI(containerSize: CGSize) -> AnyView
}

/// Protocol for elements that can have their shape properties modified
protocol ShapeModifiable: HSUIElement, AnyObject {
    var fillColor: Color? { get set }
    var strokeColor: Color? { get set }
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
