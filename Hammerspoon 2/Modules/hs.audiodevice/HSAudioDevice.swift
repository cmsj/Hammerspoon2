//
//  HSAudioDevice.swift
//  Hammerspoon 2
//

import Foundation
import CoreAudio
import JavaScriptCore

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
///     var fn = function(event) { console.log("Device event:", event); };
///     dev.addWatcher(fn);
///     // later…
///     dev.removeWatcher(fn);
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
    /// no controllable output volume. Setting `null` is a no-op.
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
    /// or `null` if balance control is not available.
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.balance = 0.5
    /// ```
    @objc var balance: NSNumber? { get set }

    // MARK: Input volume & mute

    /// Input (microphone) volume scalar in the range `0.0`–`1.0`, or `null` if
    /// the device has no controllable input volume.
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
    @objc func currentOutputDataSource() -> NSDictionary?

    /// The current input data source as `{ id, name }`, or `null` if unavailable.
    /// - Returns: A dictionary containing the id and name of the current input data source
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// console.log(mic.currentInputDataSource())
    /// ```
    @objc func currentInputDataSource() -> NSDictionary?

    /// All available output data sources as an array of `{ id, name }` objects.
    /// - Returns: A dictionary containing the ids and names of all available output data sources
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// console.log(dev.outputDataSources())
    /// ```
    @objc func outputDataSources() -> [NSDictionary]

    /// All available input data sources as an array of `{ id, name }` objects.
    /// - Returns: A dictionary containing the ids and names of all available input data sources
    /// - Example:
    /// ```js
    /// const mic = hs.audiodevice.defaultInputDevice()
    /// console.log(mic.inputDataSources())
    /// ```
    @objc func inputDataSources() -> [NSDictionary]

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

    /// Register a listener for a per-device property-change event.
    ///
    /// The callback receives one of these event strings:
    /// - `"vmout"` — output volume changed
    /// - `"vmin"` — input volume changed
    /// - `"mout"` — output mute state changed
    /// - `"min"` — input mute state changed
    /// - `"rate"` — sample rate changed
    /// - `"dsout"` — output data source changed
    /// - `"dsin"` — input data source changed
    ///
    /// - Parameter listener: A JavaScript function that receives an event name string
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.addWatcher((event) => console.log("Event:", event))
    /// ```
    @objc func addWatcher(_ listener: JSFunction)

    /// Remove a previously registered per-device listener.
    ///
    /// - Parameter listener: The JavaScript function that was passed to ``addWatcher(_:)``
    /// - Example:
    /// ```js
    /// const dev = hs.audiodevice.defaultOutputDevice()
    /// dev.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSFunction)

    // NOTE: These are not documented because they are private API for our JavaScript code
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc(_removeWatcher) func _removeWatcher()

    /// Swift-retained storage for the JS AudioDeviceWatcherEmitter instance
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@objc class HSAudioDevice: NSObject, HSAudioDeviceAPI {
    @objc var typeName = "HSAudioDevice"

    let objectID: AudioObjectID

    init(objectID: AudioObjectID) {
        self.objectID = objectID
        super.init()
    }

    deinit {
        print("deinit of HSAudioDevice id=\(objectID)")
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

    // MARK: - Channels

    @objc var outputChannels: Int { caChannelCount(objectID, scope: kAudioDevicePropertyScopeOutput) }
    @objc var inputChannels: Int  { caChannelCount(objectID, scope: kAudioDevicePropertyScopeInput) }

    // MARK: - Output volume & mute

    @objc var volume: NSNumber? {
        get {
            let element = volumeElement(scope: kAudioDevicePropertyScopeOutput)
            guard let v = caGetFloat32(objectID, kAudioDevicePropertyVolumeScalar,
                                       kAudioDevicePropertyScopeOutput, element) else { return nil }
            return NSNumber(value: Double(v))
        }
        set {
            guard let newValue else { return }
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
            guard let newValue else { return }
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
            guard let newValue else { return }
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

    private func dataSource(scope: AudioObjectPropertyScope) -> NSDictionary? {
        guard let sourceID = caGetUInt32(objectID, kAudioDevicePropertyDataSource, scope) else { return nil }
        return ["id": sourceID, "name": caDataSourceName(objectID, sourceID: sourceID, scope: scope)]
    }

    private func dataSources(scope: AudioObjectPropertyScope) -> [NSDictionary] {
        let ids = caGetUInt32Array(objectID, kAudioDevicePropertyDataSources, scope)
        return ids.map { id in
            ["id": id, "name": caDataSourceName(objectID, sourceID: id, scope: scope)]
        }
    }

    @objc func currentOutputDataSource() -> NSDictionary? { dataSource(scope: kAudioDevicePropertyScopeOutput) }
    @objc func currentInputDataSource() -> NSDictionary? { dataSource(scope: kAudioDevicePropertyScopeInput) }
    @objc func outputDataSources() -> [NSDictionary] { dataSources(scope: kAudioDevicePropertyScopeOutput) }
    @objc func inputDataSources() -> [NSDictionary] { dataSources(scope: kAudioDevicePropertyScopeInput) }

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
    // Registrations keyed by event name: each value holds the CoreAudio address and
    // the heap-allocated ObjC block (stored to guarantee pointer equality on removal).
    private var deviceRegistrations: [String: (address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = unsafe [:]
    // Strong self-reference to keep the device alive while any watcher is active.
    private var selfRetain: HSAudioDevice? = nil

    @objc func addWatcher(_ listener: JSFunction) {
        if _watcherEmitter == nil {
            guard let ctx = JSContext.current() else { return }
            let audiodevice = ctx.objectForKeyedSubscript("hs")?.objectForKeyedSubscript("audiodevice")
            _watcherEmitter = audiodevice?.invokeMethod("_makeDeviceEmitter", withArguments: [self])
        }
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard unsafe deviceRegistrations.isEmpty else { return }
        selfRetain = self

        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyScope, String)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, "vmout"),
            (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput,  "vmin"),
            (kAudioDevicePropertyMute,         kAudioDevicePropertyScopeOutput, "mout"),
            (kAudioDevicePropertyMute,         kAudioDevicePropertyScopeInput,  "min"),
            (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, "rate"),
            (kAudioDevicePropertyDataSource,   kAudioDevicePropertyScopeOutput, "dsout"),
            (kAudioDevicePropertyDataSource,   kAudioDevicePropertyScopeInput,  "dsin"),
        ]

        for (selector, scope, eventName) in candidates {
            guard caHasProperty(objectID, selector, scope) else { continue }
            var a = caAddr(selector, scope)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                callback.call(withArguments: [eventName])
            }
            if unsafe AudioObjectAddPropertyListenerBlock(objectID, &a, .main, block) == noErr {
                unsafe deviceRegistrations[eventName] = (address: a, block: block)
            }
        }

        AKTrace(unsafe "HSAudioDevice id=\(objectID): watcher started (\(deviceRegistrations.count) listeners)")
    }

    @objc(_removeWatcher) func _removeWatcher() {
        // Clear the emitter first so the next addWatcher() creates a fresh one
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
        selfRetain = nil
        AKTrace("HSAudioDevice id=\(objectID): watcher stopped")
    }

    /// Stop all CoreAudio listeners registered on this device. Called during module shutdown.
    func stopAllRegisteredWatchers() {
        _removeWatcher()
    }
}
