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
/// var fn = function(event) {
///     if (event === "dOut") console.log("Default output changed");
///     if (event === "dev+") console.log("A device was added");
/// };
/// hs.audiodevice.addWatcher(fn);
/// // later…
/// hs.audiodevice.removeWatcher(fn);
/// ```
@objc protocol HSAudioDeviceModuleAPI: JSExport {
    /// All audio devices attached to the system.
    /// - Returns: An array of HSAudioDevice objects
    /// - Example:
    /// ```js
    /// const devs = hs.audiodevice.all()
    /// devs.forEach(d => console.log(d.name))
    /// ```
    @objc func all() -> [HSAudioDevice]

    /// All audio devices that have at least one output stream.
    /// - Returns: An array of HSAudioDevice objects
    /// - Example:
    /// ```js
    /// const outputs = hs.audiodevice.allOutputDevices()
    /// ```
    @objc func allOutputDevices() -> [HSAudioDevice]

    /// All audio devices that have at least one input stream.
    /// - Returns: An array of HSAudioDevice objects
    /// - Example:
    /// ```js
    /// const inputs = hs.audiodevice.allInputDevices()
    /// ```
    @objc func allInputDevices() -> [HSAudioDevice]

    /// The current system default output device.
    /// - Returns: An HSAudioDevice, or null if none is set
    /// - Example:
    /// ```js
    /// const out = hs.audiodevice.defaultOutputDevice()
    /// console.log(out && out.name)
    /// ```
    @objc func defaultOutputDevice() -> HSAudioDevice?

    /// The current system default input device.
    /// - Returns: An HSAudioDevice, or null if none is set
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// ```
    @objc func defaultInputDevice() -> HSAudioDevice?

    /// The current system alert sound device.
    /// - Returns: An HSAudioDevice, or null if none is set
    /// - Example:
    /// ```js
    /// const effect = hs.audiodevice.defaultEffectDevice()
    /// ```
    @objc func defaultEffectDevice() -> HSAudioDevice?

    /// Find the first audio device whose name matches the given string.
    /// - Parameter name: The device name to search for
    /// - Returns: An HSAudioDevice if found, null otherwise
    /// - Example:
    /// ```js
    /// const usb = hs.audiodevice.findDeviceByName("USB Audio CODEC")
    /// ```
    @objc func findDeviceByName(_ name: String) -> HSAudioDevice?

    /// Find the audio device with the given unique identifier.
    /// - Parameter uid: The device UID to search for
    /// - Returns: An HSAudioDevice if found, null otherwise
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.findDeviceByUID("BuiltInSpeakerDevice")
    /// ```
    @objc func findDeviceByUID(_ uid: String) -> HSAudioDevice?

    /// Register a listener for all system-level audio configuration events.
    ///
    /// The listener receives one of the following event name strings:
    /// - `"dOut"` — the default output device changed
    /// - `"dIn"` — the default input device changed
    /// - `"dSErr"` — the default alert sound device changed
    /// - `"dev+"` — an audio device was added
    /// - `"dev-"` — an audio device was removed
    ///
    /// - Parameter listener: A JavaScript function that receives the event name string
    /// - Example:
    /// ```js
    /// hs.audiodevice.addWatcher((event) => {
    ///     if (event === "dOut") console.log("Default output changed")
    /// })
    /// ```
    @objc func addWatcher(_ listener: JSValue)

    /// Remove a previously registered system-level listener.
    ///
    /// - Parameter listener: The JavaScript function that was passed to ``addWatcher(_:)``
    /// - Example:
    /// ```js
    /// hs.audiodevice.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSValue)

    // NOTE: These are not documented because they are private API for our JavaScript code
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSValue)
    /// SKIP_DOCS
    @objc(_removeWatcher) func _removeWatcher()

    /// Swift-retained storage for the JS AudioDeviceModuleWatcherEmitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSValue? { get set }
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSAudioDeviceModule: NSObject, HSModuleAPI, HSAudioDeviceModuleAPI {
    var name = "hs.audiodevice"
    let engineID: UUID

    // MARK: - Module lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        HSAudioDeviceManager.shared.stopAllWatchers()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - Device enumeration

    @objc func all() -> [HSAudioDevice] {
        HSAudioDeviceManager.shared.prune()
        return allDeviceIDs().map { HSAudioDeviceManager.shared.device(for: $0) }
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

    @objc var _watcherEmitter: JSValue? = nil
    private var moduleCallback: JSValue? = nil
    private var moduleRegistrations: [String: (address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = unsafe [:]
    private var previousDeviceIDs: Set<AudioObjectID> = []

    @objc func addWatcher(_ listener: JSValue) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSValue) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSValue) {
        guard unsafe moduleRegistrations.isEmpty else { return }
        moduleCallback = callback
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)

        let propertyEvents: [(String, AudioObjectPropertySelector)] = [
            ("dOut",  kAudioHardwarePropertyDefaultOutputDevice),
            ("dIn",   kAudioHardwarePropertyDefaultInputDevice),
            ("dSErr", kAudioHardwarePropertyDefaultSystemOutputDevice),
        ]
        for (eventName, selector) in propertyEvents {
            var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.moduleCallback?.call(withArguments: [eventName])
            }
            if unsafe AudioObjectAddPropertyListenerBlock(sysObjID, &a, .main, block) == noErr {
                unsafe moduleRegistrations[eventName] = (address: a, block: block)
            }
        }

        previousDeviceIDs = Set(allDeviceIDs())
        var devAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let current = Set(self.allDeviceIDs())
            for _ in current.subtracting(self.previousDeviceIDs) { self.moduleCallback?.call(withArguments: ["dev+"]) }
            for _ in self.previousDeviceIDs.subtracting(current) { self.moduleCallback?.call(withArguments: ["dev-"]) }
            self.previousDeviceIDs = current
        }
        if unsafe AudioObjectAddPropertyListenerBlock(sysObjID, &devAddr, .main, devBlock) == noErr {
            unsafe moduleRegistrations["__devices"] = (address: devAddr, block: devBlock)
        }
    }

    @objc(_removeWatcher) func _removeWatcher() {
        guard unsafe !moduleRegistrations.isEmpty else { return }
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        for key in unsafe Array(moduleRegistrations.keys) {
            guard unsafe moduleRegistrations[key] != nil else { continue }
            var reg = unsafe moduleRegistrations[key]!
            unsafe AudioObjectRemovePropertyListenerBlock(sysObjID, &reg.address, .main, reg.block)
        }
        unsafe moduleRegistrations.removeAll()
        moduleCallback = nil
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

}
