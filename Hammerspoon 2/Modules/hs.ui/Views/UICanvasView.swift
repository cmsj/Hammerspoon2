//
//  UICanvasView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI

/// SwiftUI view that renders an HSUIElement tree.
/// Reactive values (HSColor, HSString, HSImage) are observed directly by each element's
/// SwiftUI view, so only the specific element re-renders when a value changes — the rest
/// of the canvas (including any .onHover modifiers) is left untouched.
struct UICanvasView: View {
    let element: any HSUIElement
    let backgroundColor: Color
    let containerSize: CGSize

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            element.toSwiftUI(containerSize: containerSize)
        }
    }
}
