//
//  UICanvasView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI

/// SwiftUI view that renders an HSUIElement tree
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
