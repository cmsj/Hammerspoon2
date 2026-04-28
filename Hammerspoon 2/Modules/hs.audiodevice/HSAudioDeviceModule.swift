//
//  HSAudioDeviceModule.swift
//  Hammerspoon 2
//

import Foundation
import CoreAudio
import JavaScriptCore

// MARK: - JavaScript API

/// Module for discovering and controlling audio devices.
///
/// ## Finding devices
///
/// ```javascript
/// const all = hs.audiodevice.all();
/// const out = hs.audiodevice.defaultOutputDevice();
/// const mic = hs.audiodevice.defaultInputDevice();
/// ```
///
/// ## Selecting a device
///
/// ```javascript
/// const usb = hs.audiodevice.findDeviceByName("USB Audio CODEC");
/// if (usb) usb.setDefaultOutputDevice();
/// ```
///
/// ## Watching for system-level changes
///
/// ```javascript
/// hs.audiodevice.setWatcherCallback(function(event) {
///     if (event === "dOut") console.log("Default output changed");
///     if (event === "dev+") console.log("A device was added");
/// });
/// hs.audiodevice.startWatcher();
/// ```
@objc protocol HSAudioDeviceModuleAPI: JSExport {
    /// All audio devices attached to the system.
    /// - Returns: An array of HSAudioDevice objects
    @objc func all() -> [HSAudioDevice]

    /// All audio devices that have at least one output stream.
    /// - Returns: An array of HSAudioDevice objects
    @objc func allOutputDevices() -> [HSAudioDevice]

    /// All audio devices that have at least one input stream.
    /// - Returns: An array of HSAudioDevice objects
    @objc func allInputDevices() -> [HSAudioDevice]

    /// The current system default output device.
    /// - Returns: An HSAudioDevice, or null if none is set
    @objc func defaultOutputDevice() -> HSAudioDevice?

    /// The current system default input device.
    /// - Returns: An HSAudioDevice, or null if none is set
    @objc func defaultInputDevice() -> HSAudioDevice?

    /// The current system alert sound device.
    /// - Returns: An HSAudioDevice, or null if none is set
    @objc func defaultEffectDevice() -> HSAudioDevice?

    /// Find the first audio device whose name matches the given string.
    /// - Parameter name: The device name to search for
    /// - Returns: An HSAudioDevice if found, null otherwise
    @objc func findDeviceByName(_ name: String) -> HSAudioDevice?

    /// Find the audio device with the given unique identifier.
    /// - Parameter uid: The device UID to search for
    /// - Returns: An HSAudioDevice if found, null otherwise
    @objc func findDeviceByUID(_ uid: String) -> HSAudioDevice?

    /// Set the callback invoked when the system audio configuration changes.
    ///
    /// The callback receives one of these event strings:
    /// - `"dOut"` — the default output device changed
    /// - `"dIn"` — the default input device changed
    /// - `"dSErr"` — the default alert sound device changed
    /// - `"dev+"` — an audio device was added
    /// - `"dev-"` — an audio device was removed
    ///
    /// - Parameter callback: A JavaScript function that receives an event name string
    @objc func setWatcherCallback(_ callback: JSValue)

    /// Start the system-level audio hardware watcher.
    @objc func startWatcher()

    /// Stop the system-level audio hardware watcher.
    @objc func stopWatcher()

    /// Whether the system-level watcher is currently running.
    /// - Returns: `true` if the watcher is active
    @objc func watcherIsActive() -> Bool
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@objc class HSAudioDeviceModule: NSObject, HSModuleAPI, HSAudioDeviceModuleAPI {
    var name = "hs.audiodevice"

    // MARK: - Module lifecycle

    override required init() { super.init() }

    func shutdown() {
        stopWatcher()
        HSAudioDeviceManager.shared.stopAllWatchers()
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Device enumeration

    @objc func all() -> [HSAudioDevice] {
        allDeviceIDs().map { HSAudioDeviceManager.shared.device(for: $0) }
    }

    @objc func allOutputDevices() -> [HSAudioDevice] { all().filter { $0.isOutput } }
    @objc func allInputDevices() -> [HSAudioDevice]  { all().filter { $0.isInput } }

    @objc func defaultOutputDevice() -> HSAudioDevice? {
        deviceForProperty(kAudioHardwarePropertyDefaultOutputDevice)
    }

    @objc func defaultInputDevice() -> HSAudioDevice? {
        deviceForProperty(kAudioHardwarePropertyDefaultInputDevice)
    }

    @objc func defaultEffectDevice() -> HSAudioDevice? {
        deviceForProperty(kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    @objc func findDeviceByName(_ name: String) -> HSAudioDevice? {
        all().first { $0.name == name }
    }

    @objc func findDeviceByUID(_ uid: String) -> HSAudioDevice? {
        all().first { $0.uid == uid }
    }

    // MARK: - System-level watcher

    private var watcherCallback: JSValue? = nil
    private var previousDeviceIDs: Set<AudioObjectID> = []
    // Watcher registrations: each block has a [weak self] capture, so removing the
    // listener + clearing the array is sufficient cleanup — no raw pointer needed.
    private var watcherRegistrations: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = unsafe []

    @objc func setWatcherCallback(_ callback: JSValue) {
        watcherCallback = callback
    }

    @objc func startWatcher() {
        guard unsafe watcherRegistrations.isEmpty else { return }
        previousDeviceIDs = Set(allDeviceIDs())
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)

        for addr in systemPropertyAddresses() {
            var a = addr
            let block: AudioObjectPropertyListenerBlock = { [weak self] numAddresses, addresses in
                guard let self else { return }
                let addrs = unsafe Array(UnsafeBufferPointer(start: addresses, count: Int(numAddresses)))
                self.handleSystemPropertyChange(addresses: addrs)
            }
            if unsafe AudioObjectAddPropertyListenerBlock(sysObjID, &a, .main, block) == noErr {
                unsafe watcherRegistrations.append((address: a, block: block))
            }
        }

        AKTrace("\(name): system watcher started")
    }

    @objc func stopWatcher() {
        guard unsafe !watcherRegistrations.isEmpty else { return }
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        for unsafe var registration in unsafe watcherRegistrations {
            unsafe AudioObjectRemovePropertyListenerBlock(sysObjID, &registration.address, .main, registration.block)
        }
        unsafe watcherRegistrations.removeAll()
        AKTrace("\(name): system watcher stopped")
    }

    @objc func watcherIsActive() -> Bool { unsafe !watcherRegistrations.isEmpty }

    /// Called on the main thread from the watcher block.
    private func handleSystemPropertyChange(addresses: [AudioObjectPropertyAddress]) {
        guard let callback = watcherCallback, callback.isObject else { return }
        for address in addresses {
            switch address.mSelector {
            case kAudioHardwarePropertyDefaultOutputDevice:
                callback.call(withArguments: ["dOut"])
            case kAudioHardwarePropertyDefaultInputDevice:
                callback.call(withArguments: ["dIn"])
            case kAudioHardwarePropertyDefaultSystemOutputDevice:
                callback.call(withArguments: ["dSErr"])
            case kAudioHardwarePropertyDevices:
                let current = Set(allDeviceIDs())
                for _ in current.subtracting(previousDeviceIDs) { callback.call(withArguments: ["dev+"]) }
                for _ in previousDeviceIDs.subtracting(current) { callback.call(withArguments: ["dev-"]) }
                previousDeviceIDs = current
            default:
                break
            }
        }
    }

    // MARK: - Private helpers

    private func allDeviceIDs() -> [AudioObjectID] {
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        var a = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard unsafe AudioObjectGetPropertyDataSize(sysObjID, &a, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard unsafe AudioObjectGetPropertyData(sysObjID, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { $0 != kAudioObjectUnknown }
    }

    private func deviceForProperty(_ selector: AudioObjectPropertySelector) -> HSAudioDevice? {
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        var a = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceID: AudioObjectID = 0
        guard unsafe AudioObjectGetPropertyData(sysObjID, &a, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        return HSAudioDeviceManager.shared.device(for: deviceID)
    }

    private func systemPropertyAddresses() -> [AudioObjectPropertyAddress] {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            kAudioHardwarePropertyDevices,
        ]
        return selectors.map {
            AudioObjectPropertyAddress(
                mSelector: $0,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }
    }
}
