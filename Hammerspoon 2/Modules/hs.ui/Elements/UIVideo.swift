//
//  UIVideo.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 02/08/2026.
//

import Foundation
import SwiftUI
import AVKit

/// SwiftUI view that hosts an HSVideo's player. Playback is driven entirely by
/// HSVideo's play()/pause()/seek()/volume — this view just renders the player.
private struct ReactiveVideoPlayer: View {
    let hsVideo: HSVideo
    let opacity: Double
    let width: CGFloat?
    let height: CGFloat?

    var body: some View {
        VideoPlayer(player: hsVideo.player)
            .frame(width: width, height: height)
            .opacity(opacity)
    }
}

/// A UI element that plays video via an HSVideo object
class UIVideo: HSUIElement, FrameModifiable, OpacityModifiable, InteractiveModifiable {
    var hsVideo: HSVideo?
    var elementFrame: UIFrame? = nil
    var elementOpacity: Double = 1.0
    var clickCallback: (() -> Void)? = nil
    var hoverCallback: ((Bool) -> Void)? = nil

    init(hsVideo: HSVideo?) {
        self.hsVideo = hsVideo
    }

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        guard let video = hsVideo else {
            return AnyView(Color.clear)
        }

        let resolved = elementFrame?.resolve(containerSize: containerSize)

        let view = AnyView(
            ReactiveVideoPlayer(
                hsVideo: video,
                opacity: elementOpacity,
                width: resolved?.width,
                height: resolved?.height
            )
        )

        return applyInteractions(view)
    }
}
