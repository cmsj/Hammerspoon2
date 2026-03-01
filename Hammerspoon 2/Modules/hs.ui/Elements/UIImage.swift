//
//  UIImage.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 26/02/2026.
//

import Foundation
import SwiftUI

/// SwiftUI view that directly observes an HSImage so only the image element
/// re-renders when the image changes.
private struct ReactiveImageView: View {
    var hsImage: HSImage
    let isResizable: Bool
    let aspectRatio: ContentMode
    let opacity: Double
    let width: CGFloat?
    let height: CGFloat?

    var body: some View {
        Group {
            if isResizable {
                Image(nsImage: hsImage.image)
                    .resizable()
                    .aspectRatio(contentMode: aspectRatio)
            } else {
                Image(nsImage: hsImage.image)
            }
        }
        .frame(width: width, height: height)
        .opacity(opacity)
    }
}

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
        guard let img = hsImage else {
            return AnyView(Color.clear)
        }

        let resolved = elementFrame?.resolve(containerSize: containerSize)

        let view = AnyView(
            ReactiveImageView(
                hsImage: img,
                isResizable: resizable,
                aspectRatio: aspectRatio,
                opacity: elementOpacity,
                width: resolved?.width,
                height: resolved?.height
            )
        )

        return applyInteractions(view)
    }
}
