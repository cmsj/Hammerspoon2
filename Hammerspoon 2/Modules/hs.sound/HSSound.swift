//
//  HSSound.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

/// An object representing an audio sound that can be played, paused, and stopped.
/// Create instances using `hs.sound.fromFile()` or `hs.sound.named()`.
@objc protocol HSSoundAPI: HSTypeAPI, JSExport {
    /// A unique identifier for this sound object.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// console.log(s.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The name of this sound. System sounds loaded by name return their name; file-based sounds return `null`.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// console.log(s.name)  // "Basso"
    /// ```
    @objc var name: String? { get }

    /// The total duration of the sound in seconds.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// console.log(s.duration + " seconds")
    /// ```
    @objc var duration: Double { get }

    /// The current playback position in seconds. Assign a value to seek to that position.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.currentTime = 0.1
    /// s.play()
    /// ```
    @objc var currentTime: Double { get set }

    /// The playback volume, from `0.0` (silent) to `1.0` (full volume).
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.volume = 0.5
    /// s.play()
    /// ```
    @objc var volume: Double { get set }

    /// Whether the sound loops when it reaches the end. Defaults to `false`.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.loops = true
    /// s.play()
    /// ```
    @objc var loops: Bool { get set }

    /// Whether the sound is currently playing.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.play()
    /// console.log(s.isPlaying)  // true
    /// ```
    @objc var isPlaying: Bool { get }

    /// Starts playback from the current position.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// hs.sound.named("Basso").play()
    /// ```
    @objc @discardableResult func play() -> HSSound

    /// Pauses playback, preserving the current position.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.play()
    /// s.pause()
    /// ```
    @objc @discardableResult func pause() -> HSSound

    /// Resumes playback from a paused position.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.play()
    /// s.pause()
    /// s.resume()
    /// ```
    @objc @discardableResult func resume() -> HSSound

    /// Stops playback. The playback position is not reset.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// const s = hs.sound.named("Basso")
    /// s.play()
    /// s.stop()
    /// ```
    @objc @discardableResult func stop() -> HSSound

    /// Sets a function to be called when playback finishes.
    /// The callback receives two arguments: the sound object and a boolean — `true` if the
    /// sound completed naturally, `false` if it was stopped before finishing.
    /// - Parameter callback: {(sound: HSSound, didFinish: boolean) => void} A function called when playback ends.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// hs.sound.named("Basso")
    ///     .setCallback((sound, didFinish) => {
    ///         console.log("Finished: " + didFinish)
    ///     })
    ///     .play()
    /// ```
    @objc func setCallback(_ callback: JSValue) -> HSSound

    /// Removes the completion callback previously set with `setCallback()`.
    /// - Returns: This sound object, for chaining.
    /// - Example:
    /// ```js
    /// s.removeCallback()
    /// ```
    @objc func removeCallback() -> HSSound

    /// Stops playback and releases all resources held by this sound.
    /// After calling `destroy()` the sound object should not be used.
    /// - Example:
    /// ```js
    /// s.destroy()
    /// ```
    @objc func destroy()
}

@_documentation(visibility: private)
@MainActor
@objc class HSSound: NSObject, HSSoundAPI {
    @objc var typeName = "HSSound"
    @objc let identifier = UUID().uuidString

    private let sound: NSSound
    private let _name: String?
    private var _callback: JSCallback?
    private var _isDestroyed = false

    init(sound: NSSound, name: String? = nil) {
        self.sound = sound
        // Capture the name at init time; NSSound.name on a copy is unreliable
        // under concurrent access to the shared named-sound cache.
        self._name = name ?? sound.name.map { String($0) }
        super.init()
        sound.delegate = self
    }

    isolated deinit {
        _teardown()
        AKDebug("deinit of HSSound(\(identifier))")
    }

    private func _teardown() {
        guard !_isDestroyed else { return }
        _isDestroyed = true
        _ = sound.stop()
        sound.delegate = nil
        _callback?.detach(from: self)
        _callback = nil
    }

    // MARK: - HSSoundAPI

    @objc var name: String? { _name }

    @objc var duration: Double { sound.duration }

    @objc var currentTime: Double {
        get { sound.currentTime }
        set { sound.currentTime = newValue }
    }

    @objc var volume: Double {
        get { Double(sound.volume) }
        set { sound.volume = Float(newValue) }
    }

    @objc var loops: Bool {
        get { sound.loops }
        set { sound.loops = newValue }
    }

    @objc var isPlaying: Bool { sound.isPlaying }

    @objc @discardableResult func play() -> HSSound {
        if !sound.play() {
            AKWarning("hs.sound: play() failed for sound \(identifier)")
        }
        return self
    }

    @objc @discardableResult func pause() -> HSSound {
        if !sound.pause() {
            AKWarning("hs.sound: pause() failed for sound \(identifier)")
        }
        return self
    }

    @objc @discardableResult func resume() -> HSSound {
        if !sound.resume() {
            AKWarning("hs.sound: resume() failed for sound \(identifier)")
        }
        return self
    }

    @objc @discardableResult func stop() -> HSSound {
        if !sound.stop() {
            AKWarning("hs.sound: stop() failed for sound \(identifier)")
        }
        return self
    }

    @objc func setCallback(_ callback: JSValue) -> HSSound {
        _callback?.detach(from: self)
        _callback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func removeCallback() -> HSSound {
        _callback?.detach(from: self)
        _callback = nil
        return self
    }

    @objc func destroy() {
        _teardown()
    }
}

// MARK: - NSSoundDelegate

extension HSSound: NSSoundDelegate {
    // NSSound guarantees delivery on the main thread; assumeIsolated asserts this.
    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        MainActor.assumeIsolated {
            _ = _callback?.value?.call(withArguments: [self, flag])
        }
    }
}
