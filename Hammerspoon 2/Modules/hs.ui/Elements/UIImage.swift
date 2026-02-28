//
//  UIImage.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 26/02/2026.
//

import Foundation
import SwiftUI

/// A UI element that displays an image
class UIImage: HSUIElement, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var hsImage: HSImage?
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var resizable: Bool = false
    var aspectRatio: ContentMode = .fit
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    init(hsImage: HSImage?) {
        self.hsImage = hsImage
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        guard let nsImage = hsImage?.image else {
            return AnyView(Color.clear)
        }

        var imageView: AnyView

        if resizable {
            imageView = AnyView(
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: aspectRatio)
            )
        } else {
            imageView = AnyView(Image(nsImage: nsImage))
        }

        if let frame = elementFrame {
            let resolved = frame.resolve(containerSize: containerSize)
            imageView = AnyView(
                imageView.frame(width: resolved.width, height: resolved.height)
            )
        }

        if elementOpacity != 1.0 {
            imageView = AnyView(imageView.opacity(elementOpacity))
        }

        return applyInteractions(imageView)
    }
}
