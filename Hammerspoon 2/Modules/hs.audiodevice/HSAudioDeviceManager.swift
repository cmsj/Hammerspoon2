//
//  HSAudioDeviceManager.swift
//  Hammerspoon 2
//

import Foundation
import CoreAudio

/// A manager that caches weak references to ``HSAudioDevice`` instances.
///
/// Devices with active watchers retain themselves, so they remain alive even
/// when JavaScript has dropped its reference. Devices without watchers are
/// eligible for garbage collection once JS no longer holds them.
class HSAudioDeviceManager {
    static let shared = HSAudioDeviceManager()
    private var cache: [AudioObjectID: WeakRef<HSAudioDevice>] = [:]

    private init() {}

    /// Return the existing ``HSAudioDevice`` for the given `AudioObjectID`, or
    /// create and cache a new one.
    func device(for objectID: AudioObjectID) -> HSAudioDevice {
        if let ref = cache[objectID], let existing = ref.value {
            return existing
        }
        let device = HSAudioDevice(objectID: objectID)
        cache[objectID] = WeakRef(device)
        return device
    }

    /// Return an existing ``HSAudioDevice`` if it is alive in the cache, without creating a new one.
    func cachedDevice(for objectID: AudioObjectID) -> HSAudioDevice? {
        cache[objectID]?.value
    }

    /// Remove cache entries whose underlying objects have been deallocated.
    func prune() {
        cache = cache.filter { $0.value.value != nil }
    }

    /// Stop all active per-device watchers. Called during module shutdown.
    func stopAllWatchers() {
        for ref in cache.values {
            ref.value?.stopWatcher()
        }
        prune()
    }
}

private class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
