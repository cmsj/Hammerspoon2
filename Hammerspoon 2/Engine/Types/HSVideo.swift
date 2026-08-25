//
//  HSVideo.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 02/08/2026.
//

import Foundation
import JavaScriptCore
import AVFoundation

// ---------------------------------------------------------------
// MARK: - Bridge Class (JavaScript Interface)
// ---------------------------------------------------------------

/// Bridge type for working with video playback in JavaScript
///
/// HSVideo wraps an `AVQueuePlayer` and can be embedded in an `hs.ui.window` via `.video()`,
/// or driven entirely from JavaScript with `play()`, `pause()`, `seek()`, `loop()`, and `volume`.
///
/// ## Loading Video
///
/// Each entry may be a local file path (`~` is expanded) or a remote URL string. Multiple
/// entries are queued and play back to back, in order.
///
/// ```javascript
/// // A single local file
/// const clip = HSVideo.fromURLs(["~/Movies/clip.mp4"])
///
/// // A playlist mixing a local file and a remote stream
/// const playlist = HSVideo.fromURLs(["~/Movies/intro.mp4", "https://example.com/video.mp4"])
/// ```
///
/// ## Playback Control
///
/// ```javascript
/// const clip = HSVideo.fromURLs(["~/Movies/clip.mp4"])
/// clip.volume = 0.5
/// clip.loop(true)
/// clip.play()
/// // ... later ...
/// clip.seek(30)
/// clip.pause()
/// ```
///
/// ## Looping
///
/// Gapless looping (via `AVPlayerLooper`) is only supported when the playlist contains a
/// single URL. Calling `loop(true)` on a multi-URL playlist has no effect (the playlist just
/// plays through once) and logs a warning.
@objc protocol HSVideoAPI: HSTypeAPI, JSExport {
    /// Load a playlist of videos to play back to back, in order
    /// - Parameter urls: {string[]} Each entry is a local file path (`~` is expanded) or a remote URL string
    /// - Returns: An HSVideo object, or null if the list is empty or an entry couldn't be resolved
    /// - Example:
    /// ```js
    /// const clip = HSVideo.fromURLs(["~/Movies/clip.mp4"])
    /// const playlist = HSVideo.fromURLs(["~/Movies/intro.mp4", "https://example.com/video.mp4"])
    /// ```
    @objc static func fromURLs(_ urls: [String]) -> HSVideo?

    /// Start (or resume) playback
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// clip.play()
    /// ```
    @objc @discardableResult func play() -> HSVideo

    /// Pause playback
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// clip.pause()
    /// ```
    @objc @discardableResult func pause() -> HSVideo

    /// Seek to a specific position
    /// - Parameter seconds: The position to seek to, in seconds
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// clip.seek(30)
    /// ```
    @objc @discardableResult func seek(_ seconds: Double) -> HSVideo

    /// Enable or disable gapless looping
    ///
    /// Only supported when this HSVideo was created from a single-URL playlist. Enabling
    /// loop on a multi-URL playlist has no effect and logs a warning.
    ///
    /// - Parameter enabled: Pass `true` to loop playback indefinitely
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// HSVideo.fromURLs(["~/Movies/clip.mp4"]).loop(true).play()
    /// ```
    @objc @discardableResult func loop(_ enabled: Bool) -> HSVideo

    /// The playback volume, from 0.0 (silent) to 1.0 (full volume)
    /// - Example:
    /// ```js
    /// clip.volume = 0.5
    /// console.log(clip.volume)
    /// ```
    @objc var volume: Double { get set }
}

@objc class HSVideo: NSObject, HSVideoAPI {
    @objc var typeName = "HSVideo"

    @objc func toString() -> String {
        return "<\(typeName): \(items.count) item\(items.count == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    let player: AVQueuePlayer
    private let items: [AVPlayerItem]
    private var looper: AVPlayerLooper?

    init(player: AVQueuePlayer, items: [AVPlayerItem]) {
        self.player = player
        self.items = items
        super.init()
    }

    // MARK: - Factory Methods

    @objc static func fromURLs(_ urls: [String]) -> HSVideo? {
        guard !urls.isEmpty else {
            AKError("HSVideo: fromURLs requires at least one URL")
            return nil
        }

        var resolvedURLs: [URL] = []
        for entry in urls {
            guard let url = resolveURL(entry) else { return nil }
            resolvedURLs.append(url)
        }

        let items = resolvedURLs.map { AVPlayerItem(url: $0) }
        return HSVideo(player: AVQueuePlayer(items: items), items: items)
    }

    private static func resolveURL(_ entry: String) -> URL? {
        if let url = URL(string: entry), url.scheme != nil {
            return url
        }

        let expandedPath = NSString(string: entry).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            AKError("HSVideo: File does not exist: \(entry)")
            return nil
        }
        return URL(fileURLWithPath: expandedPath)
    }

    // MARK: - Playback Control

    @objc func play() -> HSVideo {
        player.play()
        return self
    }

    @objc func pause() -> HSVideo {
        player.pause()
        return self
    }

    @objc func seek(_ seconds: Double) -> HSVideo {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        return self
    }

    @objc func loop(_ enabled: Bool) -> HSVideo {
        guard enabled else {
            // Nothing to tear down: looper is only ever non-nil for a single-URL
            // playlist, so skip the queue reset for multi-URL playlists (where it
            // would discard every item but the first) and when loop was never enabled.
            guard looper != nil else { return self }
            looper?.disableLooping()
            looper = nil

            // Clear out anything that AVPlayerLooper added to the queue
            player.removeAllItems()
            if let item = items.first {
                player.insert(item, after: nil)
            }
            return self
        }

        guard items.count == 1, let templateItem = items.first else {
            AKWarning("HSVideo: loop() is only supported for a single-URL playlist")
            return self
        }

        guard looper == nil else {
            AKWarning("HSVideo: loop() already enabled")
            return self
        }

        looper = AVPlayerLooper(player: player, templateItem: templateItem)
        return self
    }

    @objc var volume: Double {
        get { Double(player.volume) }
        set { player.volume = Float(newValue) }
    }
}
