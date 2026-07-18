//
//  HSSoundModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

// MARK: - API

/// Play audio from files on disk or from the system's built-in sound library.
@objc protocol HSSoundModuleAPI: JSExport {
    /// Loads an audio file from the given path and returns a sound object.
    /// Returns `null` if the file cannot be loaded.
    /// - Parameter path: The absolute path to an audio file (AIFF, WAV, MP3, CAF, etc.).
    /// - Returns: An `HSSound` object, or `null` on failure.
    /// - Example:
    /// ```js
    /// const s = hs.sound.fromFile("/Users/me/sounds/alert.aiff")
    /// if (s) s.play()
    /// ```
    @objc func fromFile(_ path: String) -> HSSound?

    /// Creates a sound object for a built-in system sound by name.
    /// Returns `null` if no sound with that name can be found.
    /// Use `hs.sound.systemSounds()` to discover available names.
    /// - Parameter name: The name of a system sound, e.g. `"Basso"` or `"Glass"`.
    /// - Returns: An `HSSound` object, or `null` on failure.
    /// - Example:
    /// ```js
    /// hs.sound.named("Basso").play()
    /// ```
    @objc func named(_ name: String) -> HSSound?

    /// Returns a sorted array of all available system sound names.
    /// These names can be passed directly to `hs.sound.named()`.
    /// Scans `/System/Library/Sounds`, `/Library/Sounds`, and `~/Library/Sounds`.
    /// - Returns: A sorted array of sound name strings.
    /// - Example:
    /// ```js
    /// console.log(hs.sound.systemSounds())
    /// // ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", ...]
    /// ```
    @objc func systemSounds() -> [String]
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSoundModule: NSObject, HSModuleAPI, HSSoundModuleAPI {
    var name = "hs.sound"
    let engineID: UUID
    private var sounds = HSWeakObjectSet<HSSound>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for sound in sounds.allObjects {
            sound.destroy()
        }
        sounds.removeAllObjects()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - HSSoundModuleAPI

    @objc func fromFile(_ path: String) -> HSSound? {
        guard let nsSound = NSSound(contentsOfFile: path, byReference: false) else {
            AKError("hs.sound.fromFile(): Failed to load audio from '\(path)'")
            return nil
        }
        let sound = HSSound(sound: nsSound)
        sounds.add(sound)
        return sound
    }

    @objc func named(_ name: String) -> HSSound? {
        guard let nsSound = NSSound(named: NSSound.Name(name)) else {
            AKError("hs.sound.named(): No system sound named '\(name)'")
            return nil
        }
        // NSSound(named:) returns a shared instance; copy it so each caller
        // gets independent volume, position, and delegate state.
        guard let nssoundCopy = nsSound.copy() as? NSSound else {
            AKError("hs.sound.named(): Unable to prepare sound")
            return nil
        }
        let sound = HSSound(sound: nssoundCopy, name: name)
        sounds.add(sound)
        return sound
    }

    @objc func systemSounds() -> [String] {
        let searchPaths: [String] = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds")
        ]
        let audioExtensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
        var names: Set<String> = []
        let fm = FileManager.default

        for dir in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for filename in contents {
                let fileURL = URL(fileURLWithPath: filename)
                guard audioExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                names.insert(fileURL.deletingPathExtension().lastPathComponent)
            }
        }

        return names.sorted()
    }
}
