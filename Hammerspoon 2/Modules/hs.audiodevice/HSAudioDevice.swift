//
//  HSAudioDevice.swift
//  Hammerspoon 2
//

import Foundation
import CoreAudio
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - CoreAudio Helpers

/// Construct an ``AudioObjectPropertyAddress`` concisely.
private func caAddr(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

private func caHasProperty(_ objectID: AudioObjectID,
                            _ selector: AudioObjectPropertySelector,
                            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                            _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
    var a = caAddr(selector, scope, element)
    return unsafe AudioObjectHasProperty(objectID, &a)
}

private func caIsPropertySettable(_ objectID: AudioObjectID,
                                   _ selector: AudioObjectPropertySelector,
                                   _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                   _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
    var a = caAddr(selector, scope, element)
    var settable: DarwinBoolean = false
    guard unsafe AudioObjectIsPropertySettable(objectID, &a, &settable) == noErr else { return false }
    return settable.boolValue
}

private func caGetUInt32(_ objectID: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
    var a = caAddr(selector, scope, element)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

private func caGetFloat32(_ objectID: AudioObjectID,
                           _ selector: AudioObjectPropertySelector,
                           _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Float32? {
    var a = caAddr(selector, scope, element)
    var size = UInt32(MemoryLayout<Float32>.size)
    var value: Float32 = 0
    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

private func caGetFloat64(_ objectID: AudioObjectID,
                           _ selector: AudioObjectPropertySelector,
                           _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Float64? {
    var a = caAddr(selector, scope, element)
    var size = UInt32(MemoryLayout<Float64>.size)
    var value: Float64 = 0
    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

private func caGetString(_ objectID: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
    var a = caAddr(selector, scope)
    var size = unsafe UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var unmanaged: Unmanaged<CFString>? = nil

    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &unmanaged) == noErr else { return nil }
    guard unsafe unmanaged != nil else { return nil }

    return unsafe unmanaged!.takeRetainedValue() as String
}

@discardableResult
private func caSetUInt32(_ objectID: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                          value: UInt32) -> Bool {
    var a = caAddr(selector, scope, element)
    var v = value
    return unsafe AudioObjectSetPropertyData(objectID, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
}

@discardableResult
private func caSetFloat32(_ objectID: AudioObjectID,
                           _ selector: AudioObjectPropertySelector,
                           _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                           value: Float32) -> Bool {
    var a = caAddr(selector, scope, element)
    var v = value
    return unsafe AudioObjectSetPropertyData(objectID, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
}

@discardableResult
private func caSetFloat64(_ objectID: AudioObjectID,
                           _ selector: AudioObjectPropertySelector,
                           _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                           value: Float64) -> Bool {
    var a = caAddr(selector, scope, element)
    var v = value
    return unsafe AudioObjectSetPropertyData(objectID, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &v) == noErr
}

private func caGetUInt32Array(_ objectID: AudioObjectID,
                               _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [UInt32] {
    var a = caAddr(selector, scope)
    var size: UInt32 = 0
    guard unsafe AudioObjectGetPropertyDataSize(objectID, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<UInt32>.size
    var values = [UInt32](repeating: 0, count: count)
    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &values) == noErr else { return [] }
    return values
}

/// Count the total channels in an `AudioBufferList` for the given scope.
private func caChannelCount(_ objectID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var a = caAddr(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard unsafe AudioObjectGetPropertyDataSize(objectID, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { unsafe data.deallocate() }
    guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, data) == noErr else { return 0 }
    // Use a typed pointer so Swift's struct layout determines the correct offset of mBuffers.
    // (AudioBuffer contains a pointer so it has 8-byte alignment, meaning there are 4 bytes
    // of padding after mNumberBuffers — manual offset arithmetic would get this wrong.)
    let ablPtr = unsafe data.assumingMemoryBound(to: AudioBufferList.self)
    let numBuffers = Int(unsafe ablPtr.pointee.mNumberBuffers)
    return unsafe withUnsafePointer(to: &ablPtr.pointee.mBuffers) { firstBuffer in
        unsafe UnsafeBufferPointer(start: firstBuffer, count: numBuffers).reduce(0) {
            unsafe $0 + Int($1.mNumberChannels)
        }
    }
}

/// Get the name for a data source ID using an `AudioValueTranslation`.
private func caDataSourceName(_ objectID: AudioObjectID,
                               sourceID: UInt32,
                               scope: AudioObjectPropertyScope) -> String {
    var inputID = sourceID
    var outputName: CFString? = nil
    withUnsafeMutablePointer(to: &inputID) { inputPtr in
        withUnsafeMutablePointer(to: &outputName) { outputPtr in
            var translation = unsafe AudioValueTranslation(
                mInputData: UnsafeMutableRawPointer(inputPtr),
                mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                mOutputData: UnsafeMutableRawPointer(outputPtr),
                mOutputDataSize: UInt32(MemoryLayout<CFString?>.size)
            )
            var a = caAddr(kAudioDevicePropertyDataSourceNameForIDCFString, scope)
            var tSize = unsafe UInt32(MemoryLayout<AudioValueTranslation>.size)
            unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &tSize, &translation)
        }
    }
    return outputName as String? ?? "Unknown (\(sourceID))"
}

// MARK: - JavaScript API

/// An audio device attached to the system.
///
/// Obtain instances via ``hs.audiodevice`` module methods — do not instantiate directly.
///
/// ## Getting and setting volume
///
/// ```javascript
/// const dev = hs.audiodevice.defaultOutputDevice();
/// if (dev) {
///     console.log(dev.volume);    // 0.0 – 1.0, or null
///     dev.volume = 0.5;
/// }
/// ```
///
/// ## Watching for changes
///
/// ```javascript
/// const dev = hs.audiodevice.defaultOutputDevice();
/// if (dev) {
///     var fn = function(volume) { console.log("Output volume changed to " + volume); };
///     dev.on('vmout', fn);
///     // later…
///     dev.off('vmout', fn);
/// }
/// ```
@objc protocol HSAudioDeviceAPI: HSTypeAPI, JSExport {

    // MARK: Identity

    /// The CoreAudio object ID of this device.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.id)
    /// ```
    @objc var id: Int { get }

    /// The human-readable name of this device (e.g. `"Built-in Output"`).
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.name)
    /// ```
    @objc var name: String { get }

    /// The persistent unique identifier for this device.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.uid)
    /// ```
    @objc var uid: String { get }

    // MARK: Capabilities

    /// Whether this device has output streams (can play audio).
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.isOutput)
    /// ```
    @objc var isOutput: Bool { get }

    /// Whether this device has input streams (can record audio).
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultInputDevice()
    /// console.log(dev.isInput)
    /// ```
    @objc var isInput: Bool { get }

    /// The transport mechanism: `"built-in"`, `"usb"`, `"bluetooth"`, `"bluetooth-le"`,
    /// `"hdmi"`, `"display-port"`, `"firewire"`, `"airplay"`, `"avb"`,
    /// `"thunderbolt"`, `"virtual"`, `"aggregate"`, `"pci"`, or `"unknown"`.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.transportType)
    /// ```
    @objc var transportType: String { get }

    // MARK: Activity

    /// Whether any process (not just Hammerspoon) is currently using this device for input
    /// or output - e.g. a call or dictation app has opened the microphone, or music is playing.
    /// Listen for the `"inUse"` event to be told when this changes.
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// if (mic.isInUse) console.log("Something is using the microphone")
    /// ```
    @objc var isInUse: Bool { get }

    /// Whether a jack (e.g. headphones) is connected to this device. Always `false` if the device
    /// does not support jack sensing. Output jack state is reported for devices with output,
    /// otherwise input jack state. Listen for the `"jack"` event to be told when this changes.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// if (dev.jackConnected) console.log("Headphones are plugged in")
    /// ```
    @objc var jackConnected: Bool { get }

    // MARK: Channels

    /// Number of output channels, or 0 if the device has no output.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.outputChannels)
    /// ```
    @objc var outputChannels: Int { get }

    /// Number of input channels, or 0 if the device has no input.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultInputDevice()
    /// console.log(dev.inputChannels)
    /// ```
    @objc var inputChannels: Int { get }

    // MARK: Output volume & mute

    /// Output volume scalar in the range `0.0`–`1.0`, or `null` if the device has
    /// no controllable output volume. Setting `null` is a no-op, and setting a value outside
    /// `0.0`–`1.0` logs an error and leaves the volume unchanged (Hammerspoon v1 used `0`–`100`).
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.volume = 0.5
    /// ```
    @objc var volume: NSNumber? { get set }

    /// Whether output is muted. Always `false` if the device has no mutable output.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.muted = true
    /// ```
    @objc var muted: Bool { get set }

    /// Output stereo balance in the range `0.0` (full left)–`1.0` (full right),
    /// or `null` if balance control is not available. Setting a value outside `0.0`–`1.0`
    /// logs an error and leaves the balance unchanged.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.balance = 0.5
    /// ```
    @objc var balance: NSNumber? { get set }

    // MARK: Input volume & mute

    /// Input (microphone) volume scalar in the range `0.0`–`1.0`, or `null` if
    /// the device has no controllable input volume. Setting a value outside `0.0`–`1.0` logs
    /// an error and leaves the volume unchanged (Hammerspoon v1 used `0`–`100`).
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// mic.inputVolume = 0.8
    /// ```
    @objc var inputVolume: NSNumber? { get set }

    /// Whether input is muted. Always `false` if the device has no mutable input.
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// mic.inputMuted = true
    /// ```
    @objc var inputMuted: Bool { get set }

    // MARK: Sample rate

    /// The current nominal sample rate in Hz (e.g. `44100`), or `null` if unknown.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.sampleRate)
    /// ```
    @objc var sampleRate: NSNumber? { get set }

    /// All sample rates (in Hz) that this device supports.
    /// For devices that support a range, both the minimum and maximum are included.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.availableSampleRates)
    /// ```
    @objc var availableSampleRates: [NSNumber] { get }

    // MARK: Data sources

    /// The current output data source as `{ id, name }`, or `null` if unavailable.
    /// - Returns: A dictionary containing the id and name of the current output data source
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.currentOutputDataSource())
    /// ```
    @objc func currentOutputDataSource() -> [String: Any]?

    /// The current input data source as `{ id, name }`, or `null` if unavailable.
    /// - Returns: A dictionary containing the id and name of the current input data source
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// console.log(mic.currentInputDataSource())
    /// ```
    @objc func currentInputDataSource() -> [String: Any]?

    /// All available output data sources as an array of `{ id, name }` objects.
    /// - Returns: A dictionary containing the ids and names of all available output data sources
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.outputDataSources())
    /// ```
    @objc func outputDataSources() -> [[String: Any]]

    /// All available input data sources as an array of `{ id, name }` objects.
    /// - Returns: A dictionary containing the ids and names of all available input data sources
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// console.log(mic.inputDataSources())
    /// ```
    @objc func inputDataSources() -> [[String: Any]]

    /// Select an output data source by its numeric ID.
    /// - Parameter sourceID: The `id` value from ``outputDataSources()``
    /// - Returns: `true` on success
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// const sources = dev.outputDataSources()
    /// dev.setCurrentOutputDataSource(sources[0].id)
    /// ```
    @objc func setCurrentOutputDataSource(_ sourceID: Int) -> Bool

    /// Select an input data source by its numeric ID.
    /// - Parameter sourceID: The `id` value from ``inputDataSources()``
    /// - Returns: `true` on success
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// const sources = mic.inputDataSources()
    /// mic.setCurrentInputDataSource(sources[0].id)
    /// ```
    @objc func setCurrentInputDataSource(_ sourceID: Int) -> Bool

    // MARK: Default device control

    /// Make this device the system default output device.
    /// - Returns: `true` on success
    /// - Example:
    /// ```js
    /// const usb = hs.audiodevice.findDeviceByName("USB Audio CODEC")
    /// usb.setDefaultOutputDevice()
    /// ```
    @objc func setDefaultOutputDevice() -> Bool

    /// Make this device the system default input device.
    /// - Returns: `true` on success
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.findDeviceByName("External Mic")
    /// mic.setDefaultInputDevice()
    /// ```
    @objc func setDefaultInputDevice() -> Bool

    /// Make this device the system alert sound (effect) device.
    /// - Returns: `true` on success
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.setDefaultEffectDevice()
    /// ```
    @objc func setDefaultEffectDevice() -> Bool

    // MARK: Per-device watcher

    /// Register a listener for a named per-device property-change event.
    ///
    /// Available events:
    /// - `"vmout"` — output volume changed. The listener receives the new ``volume``.
    /// - `"vmin"` — input volume changed. The listener receives the new ``inputVolume``.
    /// - `"mout"` — output mute state changed. The listener receives the new ``muted`` value.
    /// - `"min"` — input mute state changed. The listener receives the new ``inputMuted`` value.
    /// - `"rate"` — sample rate changed. The listener receives the new ``sampleRate``.
    /// - `"dsout"` — output data source changed. The listener receives the new
    ///   ``currentOutputDataSource()``.
    /// - `"dsin"` — input data source changed. The listener receives the new
    ///   ``currentInputDataSource()``.
    /// - `"balance"` — output stereo balance changed. The listener receives the new ``balance``.
    /// - `"inUse"` — the device started or stopped being used by any process. The listener
    ///   receives the new ``isInUse`` value.
    /// - `"jack"` — a jack (e.g. headphones) was connected or disconnected. The listener
    ///   receives the new ``jackConnected`` value.
    /// - `"config"` — the device's configuration changed (e.g. its streams or channel layout);
    ///   any properties you have cached for it may be stale. The listener receives nothing.
    ///
    /// The value is read when the listener is called, and is `null` if the device can't
    /// report it. `"inUse"` and `"jack"` always pass a boolean, `false` if the device can't
    /// report it, as ``isInUse`` and ``jackConnected`` do.
    ///
    /// - Parameters:
    ///   - event: {"vmout" | "vmin" | "mout" | "min" | "rate" | "dsout" | "dsin" | "balance" | "inUse" | "jack" | "config"} The event to listen for
    ///   - listener: {(value?: number | boolean | {id: number, name: string} | null) => void} Called when the event occurs, with the new value of the property that changed (see above); for `"config"` it is passed nothing
    /// - Throws: true
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// try {
    ///     dev.on('vmout', (volume) => console.log("Output volume is now " + volume))
    ///
    ///     // Be told whenever any app opens or releases the microphone
    ///     const mic = hs.audiodevice.defaultInputDevice()
    ///     mic.on('inUse', (inUse) => console.log("Microphone is " + (inUse ? "in use" : "idle")))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func on(_ event: String, _ listener: JSFunction)

    /// Remove a previously registered per-device event listener.
    /// - Parameters:
    ///   - event: {"vmout" | "vmin" | "mout" | "min" | "rate" | "dsout" | "dsin" | "balance" | "inUse" | "jack" | "config"} The event the listener was registered for
    ///   - listener: The function originally passed to `on`
    /// - Example:
    /// ```js
    /// dev.off('vmout', myListener)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Register a listener that fires at most once for a per-device event.
    /// - Parameters:
    ///   - event: {"vmout" | "vmin" | "mout" | "min" | "rate" | "dsout" | "dsin" | "balance" | "inUse" | "jack" | "config"} The event to listen for
    ///   - listener: {(value?: number | boolean | {id: number, name: string} | null) => void} Called once, then automatically removed. Passed the new value, as for `on()`
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     dev.once('vmout', () => console.log("Volume changed once"))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func once(_ event: String, _ listener: JSFunction)

    // NOTE: These are not documented because they are private API for our JavaScript code
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc(_removeWatcher) func _removeWatcher()

    /// Swift-retained storage for the JS watcher emitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSAudioDevicePropertyEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    /// Returns a plain object describing this device, for JSON serialisation
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with the device's `id`, `name`, `uid`, `isInput`, `isOutput`, `transportType`, `isInUse`, `jackConnected`, `inputChannels`, `outputChannels`, `volume`, `muted`, `balance`, `inputVolume`, `inputMuted` and `sampleRate`. Values the device doesn't support are `null`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.audiodevice.defaultOutputDevice(), null, 2))
    /// ```
    @objc func toJSON() -> [String: Any]
}

// MARK: - Implementation

/// Per-device property-change events emitted by an HSAudioDevice's watcher
nonisolated enum HSAudioDevicePropertyEvent: String, HSEventName {
    case outputVolume = "vmout"
    case inputVolume = "vmin"
    case outputMute = "mout"
    case inputMute = "min"
    case sampleRate = "rate"
    case outputDataSource = "dsout"
    case inputDataSource = "dsin"
    case balance = "balance"
    case inUse = "inUse"
    case jack = "jack"
    case configuration = "config"
}

@safe @_documentation(visibility: private)
@objc class HSAudioDevice: NSObject, HSAudioDeviceAPI {
    @objc var typeName = "HSAudioDevice"

    @objc func toString() -> String {
        return "<\(typeName): '\(name)'>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func toJSON() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "uid": uid,
            "isInput": isInput,
            "isOutput": isOutput,
            "transportType": transportType,
            "isInUse": isInUse,
            "jackConnected": jackConnected,
            "inputChannels": inputChannels,
            "outputChannels": outputChannels,
            "volume": volume.orNSNull,
            "muted": muted,
            "balance": balance.orNSNull,
            "inputVolume": inputVolume.orNSNull,
            "inputMuted": inputMuted,
            "sampleRate": sampleRate.orNSNull,
        ]
    }

    let objectID: AudioObjectID
    /// Set by the module each time it hands this device to JS. Device objects are cached across
    /// engines, so this is whichever engine's module most recently vended it.
    weak var tracker: HSObjectTracker<HSAudioDevice>?

    init(objectID: AudioObjectID) {
        self.objectID = objectID
        super.init()
    }

    isolated deinit {
        AKGarbage("deinit of HSAudioDevice id=\(objectID)")
    }

    // MARK: - Private helpers

    /// The preferred element for volume/mute control in a given scope.
    /// Returns element 0 (master) if available, otherwise element 1 (left channel).
    private func volumeElement(scope: AudioObjectPropertyScope) -> AudioObjectPropertyElement {
        if caHasProperty(objectID, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) {
            return kAudioObjectPropertyElementMain
        }
        return 1
    }

    // MARK: - Identity

    @objc var id: Int { Int(objectID) }

    @objc var name: String {
        caGetString(objectID, kAudioObjectPropertyName) ?? "Unknown"
    }

    @objc var uid: String {
        caGetString(objectID, kAudioDevicePropertyDeviceUID) ?? ""
    }

    // MARK: - Capabilities

    @objc var isOutput: Bool { outputChannels > 0 }
    @objc var isInput: Bool { inputChannels > 0 }

    @objc var transportType: String {
        guard let raw = caGetUInt32(objectID, kAudioDevicePropertyTransportType) else { return "unknown" }
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn:      return "built-in"
        case kAudioDeviceTransportTypeUSB:          return "usb"
        case kAudioDeviceTransportTypeBluetooth:    return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:  return "bluetooth-le"
        case kAudioDeviceTransportTypeHDMI:         return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort:  return "display-port"
        case kAudioDeviceTransportTypeFireWire:     return "firewire"
        case kAudioDeviceTransportTypeAirPlay:      return "airplay"
        case kAudioDeviceTransportTypeAVB:          return "avb"
        case kAudioDeviceTransportTypeThunderbolt:  return "thunderbolt"
        case kAudioDeviceTransportTypeVirtual:      return "virtual"
        case kAudioDeviceTransportTypeAggregate:    return "aggregate"
        case kAudioDeviceTransportTypePCI:          return "pci"
        default:                                    return "unknown"
        }
    }

    // MARK: - Activity

    @objc var isInUse: Bool {
        (caGetUInt32(objectID, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    /// The scope jack sensing is reported for: output if the device has any, otherwise input.
    private var jackScope: AudioObjectPropertyScope {
        isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }

    @objc var jackConnected: Bool {
        (caGetUInt32(objectID, kAudioDevicePropertyJackIsConnected, jackScope) ?? 0) != 0
    }

    // MARK: - Channels

    @objc var outputChannels: Int { caChannelCount(objectID, scope: kAudioDevicePropertyScopeOutput) }
    @objc var inputChannels: Int  { caChannelCount(objectID, scope: kAudioDevicePropertyScopeInput) }

    // MARK: - Output volume & mute

    /// Whether `value` is in the `0.0`–`1.0` range CoreAudio's volume and balance scalars use,
    /// logging an error if not. Out-of-range values are refused rather than clamped: a v1
    /// script setting `volume = 50` meant half volume, and clamping it would mean full volume.
    private func isUnitScalar(_ value: NSNumber, _ property: String) -> Bool {
        let scalar = value.doubleValue
        guard scalar >= 0 && scalar <= 1 else {
            // Only a value v1's 0-100 scale could have meant gets the conversion hint
            let hint = property != "balance" && scalar.isFinite && scalar > 1 && scalar <= 100
                ? " (Hammerspoon v1 used 0-100, so use \(scalar / 100) for \(scalar)%)" : ""
            AKError("hs.audiodevice: \(property) must be between 0.0 and 1.0, not \(scalar)\(hint). Leaving it unchanged.")
            return false
        }
        return true
    }

    @objc var volume: NSNumber? {
        get {
            let element = volumeElement(scope: kAudioDevicePropertyScopeOutput)
            guard let v = caGetFloat32(objectID, kAudioDevicePropertyVolumeScalar,
                                       kAudioDevicePropertyScopeOutput, element) else { return nil }
            return NSNumber(value: Double(v))
        }
        set {
            guard let newValue, isUnitScalar(newValue, "volume") else { return }
            let element = volumeElement(scope: kAudioDevicePropertyScopeOutput)
            caSetFloat32(objectID, kAudioDevicePropertyVolumeScalar,
                         kAudioDevicePropertyScopeOutput, element,
                         value: Float32(newValue.doubleValue))
        }
    }

    @objc var muted: Bool {
        get { caGetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) == 1 }
        set { caSetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, value: newValue ? 1 : 0) }
    }

    @objc var balance: NSNumber? {
        get {
            guard let v = caGetFloat32(objectID, kAudioDevicePropertyStereoPan,
                                       kAudioDevicePropertyScopeOutput) else { return nil }
            return NSNumber(value: Double(v))
        }
        set {
            guard let newValue, isUnitScalar(newValue, "balance") else { return }
            caSetFloat32(objectID, kAudioDevicePropertyStereoPan, kAudioDevicePropertyScopeOutput,
                         value: Float32(newValue.doubleValue))
        }
    }

    // MARK: - Input volume & mute

    @objc var inputVolume: NSNumber? {
        get {
            let element = volumeElement(scope: kAudioDevicePropertyScopeInput)
            guard let v = caGetFloat32(objectID, kAudioDevicePropertyVolumeScalar,
                                       kAudioDevicePropertyScopeInput, element) else { return nil }
            return NSNumber(value: Double(v))
        }
        set {
            guard let newValue, isUnitScalar(newValue, "inputVolume") else { return }
            let element = volumeElement(scope: kAudioDevicePropertyScopeInput)
            caSetFloat32(objectID, kAudioDevicePropertyVolumeScalar,
                         kAudioDevicePropertyScopeInput, element,
                         value: Float32(newValue.doubleValue))
        }
    }

    @objc var inputMuted: Bool {
        get { caGetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput) == 1 }
        set { caSetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, value: newValue ? 1 : 0) }
    }

    // MARK: - Sample rate

    @objc var sampleRate: NSNumber? {
        get {
            guard let v = caGetFloat64(objectID, kAudioDevicePropertyNominalSampleRate) else { return nil }
            return NSNumber(value: v)
        }
        set {
            guard let newValue else { return }
            caSetFloat64(objectID, kAudioDevicePropertyNominalSampleRate, value: newValue.doubleValue)
        }
    }

    @objc var availableSampleRates: [NSNumber] {
        var a = caAddr(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard unsafe AudioObjectGetPropertyDataSize(objectID, &a, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard unsafe AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, &ranges) == noErr else { return [] }

        // Collect unique rates; for ranges (min != max), include both endpoints.
        var rates = Set<Double>()
        for range in ranges {
            rates.insert(range.mMinimum)
            if range.mMaximum != range.mMinimum { rates.insert(range.mMaximum) }
        }
        return rates.sorted().map { NSNumber(value: $0) }
    }

    // MARK: - Data sources

    private func dataSource(scope: AudioObjectPropertyScope) -> [String: Any]? {
        guard let sourceID = caGetUInt32(objectID, kAudioDevicePropertyDataSource, scope) else { return nil }
        return ["id": sourceID, "name": caDataSourceName(objectID, sourceID: sourceID, scope: scope)]
    }

    private func dataSources(scope: AudioObjectPropertyScope) -> [[String: Any]] {
        let ids = caGetUInt32Array(objectID, kAudioDevicePropertyDataSources, scope)
        return ids.map { id in
            ["id": id, "name": caDataSourceName(objectID, sourceID: id, scope: scope)]
        }
    }

    @objc func currentOutputDataSource() -> [String: Any]? { dataSource(scope: kAudioDevicePropertyScopeOutput) }
    @objc func currentInputDataSource() -> [String: Any]? { dataSource(scope: kAudioDevicePropertyScopeInput) }
    @objc func outputDataSources() -> [[String: Any]] { dataSources(scope: kAudioDevicePropertyScopeOutput) }
    @objc func inputDataSources() -> [[String: Any]] { dataSources(scope: kAudioDevicePropertyScopeInput) }

    @objc func setCurrentOutputDataSource(_ sourceID: Int) -> Bool {
        caSetUInt32(objectID, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput,
                    value: UInt32(sourceID))
    }

    @objc func setCurrentInputDataSource(_ sourceID: Int) -> Bool {
        caSetUInt32(objectID, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeInput,
                    value: UInt32(sourceID))
    }

    // MARK: - Default device control

    @objc func setDefaultOutputDevice() -> Bool {
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        var a = caAddr(kAudioHardwarePropertyDefaultOutputDevice)
        var devID = objectID
        return unsafe AudioObjectSetPropertyData(sysObjID, &a, 0, nil,
                                                 UInt32(MemoryLayout<AudioObjectID>.size), &devID) == noErr
    }

    @objc func setDefaultInputDevice() -> Bool {
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        var a = caAddr(kAudioHardwarePropertyDefaultInputDevice)
        var devID = objectID
        return unsafe AudioObjectSetPropertyData(sysObjID, &a, 0, nil,
                                                 UInt32(MemoryLayout<AudioObjectID>.size), &devID) == noErr
    }

    @objc func setDefaultEffectDevice() -> Bool {
        let sysObjID = AudioObjectID(kAudioObjectSystemObject)
        var a = caAddr(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var devID = objectID
        return unsafe AudioObjectSetPropertyData(sysObjID, &a, 0, nil,
                                                 UInt32(MemoryLayout<AudioObjectID>.size), &devID) == noErr
    }

    // MARK: - Per-device watcher

    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSAudioDevicePropertyEvent.allNames }
    // Registrations keyed by event name: each value holds the CoreAudio address and
    // the heap-allocated ObjC block (stored to guarantee pointer equality on removal).
    //
    // A watching device is active: it stays alive until the watcher is removed, even if the
    // user dropped their reference to it.
    private var deviceRegistrations: [String: (address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = unsafe [:] {
        didSet {
            unsafe tracker?.setActive(self, !deviceRegistrations.isEmpty)
        }
    }
    private var watcherCallback: JSCallback?
    // Not an event name: ends the watch when the device goes away (see _addWatcher)
    private static let deviceIsAliveRegistration = "_deviceIsAlive"

    /// Lazily creates this device's JS watcher emitter (via the module's `_makeDeviceEmitter`
    /// factory) if one doesn't already exist. Returns nil (having already set `ctx.exception`)
    /// on failure, so on()/once() never return without registering - same as HSCamera's.
    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let emitterFactory = ctx.objectForKeyedSubscript("hs")?
                    .objectForKeyedSubscript("audiodevice")?
                    .objectForKeyedSubscript("_makeDeviceEmitter"),
                  emitterFactory.isFunction else {
                ctx.exception = JSValue(
                    newErrorFromMessage: "hs.audiodevice device: device watcher emitter factory is unavailable",
                    in: ctx
                )
                return nil
            }
            let emitter = ctx.callCapturingException { emitterFactory.call(withArguments: [self]) }
            guard ctx.exception == nil, let emitter, emitter.isObject else {
                if ctx.exception == nil {
                    ctx.exception = JSValue(
                        newErrorFromMessage: "hs.audiodevice device: failed to create device watcher emitter",
                        in: ctx
                    )
                }
                return nil
            }
            _watcherEmitter = emitter
        }
        return _watcherEmitter
    }

    @objc func on(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        // callCapturingException, not plain invokeMethod: a throw from inside the emitter's
        // on() (e.g. the native watcher failing to start) must reach this call's own JS
        // caller - see callCapturingException's doc comment for why invokeMethod alone can't.
        _ = ctx.callCapturingException { emitter.invokeMethod("on", withArguments: [event, listener]) }
    }

    @objc func off(_ event: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("off", withArguments: [event, listener])
    }

    @objc func once(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        _ = ctx.callCapturingException { emitter.invokeMethod("once", withArguments: [event, listener]) }
    }

    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool {
        guard unsafe deviceRegistrations.isEmpty else {
            AKWarning("HSAudioDevice id=\(objectID): Already watching. Refusing to create a second.")
            return false
        }
        watcherCallback = JSCallback(value: listener, owner: self)

        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyScope, HSAudioDevicePropertyEvent)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, .outputVolume),
            (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput,  .inputVolume),
            (kAudioDevicePropertyMute,         kAudioDevicePropertyScopeOutput, .outputMute),
            (kAudioDevicePropertyMute,         kAudioDevicePropertyScopeInput,  .inputMute),
            (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, .sampleRate),
            (kAudioDevicePropertyDataSource,   kAudioDevicePropertyScopeOutput, .outputDataSource),
            (kAudioDevicePropertyDataSource,   kAudioDevicePropertyScopeInput,  .inputDataSource),
            (kAudioDevicePropertyStereoPan,    kAudioDevicePropertyScopeOutput, .balance),
            (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal, .inUse),
            (kAudioDevicePropertyJackIsConnected, jackScope,                    .jack),
            (kAudioDevicePropertyDeviceHasChanged, kAudioObjectPropertyScopeGlobal, .configuration),
        ]

        for (selector, scope, event) in candidates {
            let eventName = event.rawValue
            guard caHasProperty(objectID, selector, scope) else { continue }
            var a = caAddr(selector, scope)
            // Delivered on .main (see AudioObjectAddPropertyListenerBlock below)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    _ = self.watcherCallback?.call(withArguments: [eventName] + self.eventArguments(event))
                }
            }
            if unsafe AudioObjectAddPropertyListenerBlock(objectID, &a, .main, block) == noErr {
                unsafe deviceRegistrations[eventName] = (address: a, block: block)
            }
        }

        guard unsafe !deviceRegistrations.isEmpty else {
            AKError("HSAudioDevice id=\(objectID): Failed to register any property listeners")
            watcherCallback?.detach(from: self)
            watcherCallback = nil
            return false
        }

        // End the watch when the device goes away (unplugged, or an aggregate device removed):
        // its listeners can never fire again, and it would otherwise stay active until reload.
        // Removed on the next tick, rather than from inside CoreAudio's own listener call.
        var aliveAddress = caAddr(kAudioDevicePropertyDeviceIsAlive)
        let aliveBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, caGetUInt32(self.objectID, kAudioDevicePropertyDeviceIsAlive) != 1 else { return }
                AKDebug("HSAudioDevice id=\(self.objectID): device went away, stopping its watcher")
                DispatchQueue.main.async { self._removeWatcher() }
            }
        }
        if unsafe AudioObjectAddPropertyListenerBlock(objectID, &aliveAddress, .main, aliveBlock) == noErr {
            unsafe deviceRegistrations[Self.deviceIsAliveRegistration] = (address: aliveAddress, block: aliveBlock)
        }
        AKDebug(unsafe "HSAudioDevice id=\(objectID): watcher started (\(deviceRegistrations.count) listeners)")
        return true
    }

    /// Extra arguments passed to listeners after the event name: the new value, for the events
    /// that report one. Read when the event is delivered, not when CoreAudio queued it. A value
    /// the device can't report arrives as `null`.
    private func eventArguments(_ event: HSAudioDevicePropertyEvent) -> [Any] {
        let value: Any?
        switch event {
        case .outputVolume: value = volume
        case .inputVolume: value = inputVolume
        // Read directly rather than through muted/inputMuted, which report a failed read as false
        case .outputMute: value = caGetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput).map { $0 == 1 }
        case .inputMute: value = caGetUInt32(objectID, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput).map { $0 == 1 }
        case .sampleRate: value = sampleRate
        case .outputDataSource: value = currentOutputDataSource()
        case .inputDataSource: value = currentInputDataSource()
        case .balance: value = balance
        case .inUse: value = isInUse
        case .jack: value = jackConnected
        case .configuration: return []
        }
        return [value ?? NSNull()]
    }

    @objc(_removeWatcher) func _removeWatcher() {
        // Clear the emitter first so the next on()/once() creates a fresh one
        // in the caller's JSVirtualMachine. Leaving a stale emitter here causes
        // cross-VM JSValue passing when subsequent harnesses reuse this device.
        _watcherEmitter = nil
        guard unsafe !deviceRegistrations.isEmpty else { return }
        for eventName in unsafe Array(deviceRegistrations.keys) {
            guard unsafe deviceRegistrations[eventName] != nil else { continue }
            var registration = unsafe deviceRegistrations[eventName]!
            unsafe AudioObjectRemovePropertyListenerBlock(objectID, &registration.address, .main, registration.block)
        }
        unsafe deviceRegistrations.removeAll()
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("HSAudioDevice id=\(objectID): watcher stopped")
    }

    /// Stop all CoreAudio listeners registered on this device. Called during module shutdown.
    func stopAllRegisteredWatchers() {
        _removeWatcher()
    }
}

extension HSAudioDevice: HSTrackedObject {
    /// Stops watching the device, at module shutdown
    func destroy() {
        _removeWatcher()
    }
}
