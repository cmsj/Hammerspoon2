//
//  UICanvasView.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import SwiftUI
import Combine

/// Drives re-renders of UICanvasView when reactive colors change.
/// HSUIWindow owns one; it is passed to UICanvasView and registered as a delegate on HSColor objects.
class CanvasRenderState: ObservableObject {
    @Published var version: Int = 0
}

/// SwiftUI view that renders an HSUIElement tree.
/// Observing CanvasRenderState ensures the body is re-evaluated whenever any
/// signal used by this canvas changes its value.
struct UICanvasView: View {
    let element: any HSUIElement
    let backgroundColor: Color
    let containerSize: CGSize
    @ObservedObject var renderState: CanvasRenderState

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            element.toSwiftUI(containerSize: containerSize)
        }
    }
}
