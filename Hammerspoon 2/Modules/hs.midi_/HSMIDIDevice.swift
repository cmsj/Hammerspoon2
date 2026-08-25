//
//  HSMIDIDevice.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreMIDI

/// Collects every `MIDIUniversalMessage` `MIDIEventListForEachEvent` parses out of an event
/// list. `MIDIEventVisitor` is a plain C function pointer (no captures allowed), so this
/// must be a file-scope function — state is threaded through the opaque `context` pointer
/// instead, which the caller points at a local `[MIDIUniversalMessage]` for the duration of
/// the (synchronous) `MIDIEventListForEachEvent` call.
nonisolated private func hsMIDIEventVisitor(_ context: UnsafeMutableRawPointer?, _ timeStamp: MIDITimeStamp, _ message: MIDIUniversalMessage) {
    guard let context = unsafe context else { return }
    let collected = unsafe context.assumingMemoryBound(to: [MIDIUniversalMessage].self)
    unsafe collected.pointee.append(message)
}

// MIDIReceiveBlock runs on an internal high-priority thread CoreMIDI owns, not the main
// thread, so this must be built by a file-scope `nonisolated` function (mirroring
// HSSerialPort's `hsSerialPortReadHandler`): a closure literal written directly inside an
// `@MainActor` method would wrongly infer @MainActor isolation under this project's
// default-actor-isolation setting and trip a runtime isolation check when CoreMIDI calls it
// off-main. A closure returned from a `nonisolated` function correctly infers nonisolated.
nonisolated private func hsMIDIMakeReceiveHandler(deviceRef: Unmanaged<HSMIDIDevice>) -> (UnsafePointer<MIDIEventList>, UnsafeMutableRawPointer?) -> Void {
    return { evtlist, _ in
        let device = unsafe deviceRef.takeUnretainedValue()

        var collected: [MIDIUniversalMessage] = []
        withUnsafeMutablePointer(to: &collected) { collectedPtr in
            unsafe MIDIEventListForEachEvent(evtlist, hsMIDIEventVisitor, UnsafeMutableRawPointer(collectedPtr))
        }

        Task { @MainActor in
            device.handleIncomingMessages(collected)
        }
    }
}

// MARK: - Protocol

/// A MIDI device or virtual source, created via `hs.midi.deviceNamed()` or
/// `hs.midi.virtualSourceNamed()`.
@objc protocol HSMIDIDeviceAPI: HSTypeAPI, JSExport {
    /// A unique identifier for this device object.
    /// - Example:
    /// ```js
    /// const kb = hs.midi.deviceNamed(hs.midi.devices()[0])
    /// console.log(kb.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The device's raw name.
    /// - Example:
    /// ```js
    /// console.log(kb.name)
    /// ```
    @objc var name: String { get }

    /// The device's user-facing display name. Falls back to `name` if unavailable.
    /// - Example:
    /// ```js
    /// console.log(kb.displayName)
    /// ```
    @objc var displayName: String { get }

    /// The device's manufacturer name, or an empty string if unavailable.
    /// - Example:
    /// ```js
    /// console.log(kb.manufacturer)
    /// ```
    @objc var manufacturer: String { get }

    /// The device's model name, or an empty string if unavailable.
    /// - Example:
    /// ```js
    /// console.log(kb.model)
    /// ```
    @objc var model: String { get }

    /// Whether the device is currently online (connected).
    /// - Example:
    /// ```js
    /// console.log(kb.isOnline)
    /// ```
    @objc var isOnline: Bool { get }

    /// Whether this is a virtual source (created via `hs.midi.virtualSourceNamed()`)
    /// rather than a physical device.
    /// - Example:
    /// ```js
    /// console.log(kb.isVirtual)
    /// ```
    @objc var isVirtual: Bool { get }

    /// Sets or removes the callback fired when a MIDI message is received.
    ///
    /// The callback receives five arguments: this device object, the device's name,
    /// the command type as a string (e.g. `"noteOn"`, `"controlChange"`,
    /// `"systemExclusive"` — see `hs.midi.commandTypes` for the full set), a
    /// human-readable description, and a metadata table of command-specific fields.
    ///
    /// Note: most MIDI keyboards send `noteOn` when a key is pressed and `noteOff`
    /// when released, but some send `noteOn` with `velocity` 0 instead of `noteOff`.
    /// - Parameter fn: {((device: HSMIDIDevice, deviceName: string, commandType: string, description: string, metadata: object) => void) | null} The function to call on each received message, or `null` to remove it
    /// - Returns: This device object, for chaining
    /// - Example:
    /// ```js
    /// kb.setCallback((device, deviceName, commandType, description, metadata) => {
    ///     if (commandType === "noteOn") console.log("Note " + metadata.note + " velocity " + metadata.velocity)
    /// })
    /// ```
    @objc func setCallback(_ fn: JSValue?) -> HSMIDIDevice

    /// Sends a MIDI command to the device.
    ///
    /// Supported `commandType` values and their `metadata` fields:
    /// - `noteOn`, `noteOff`: `note` (0-127), `velocity` (0-127), `channel` (0-15)
    /// - `polyphonicKeyPressure`: `note` (0-127), `pressure` (0-127), `channel` (0-15)
    /// - `controlChange`: `controllerNumber` (0-127), `controllerValue` (0-127), `channel` (0-15)
    /// - `programChange`: `programNumber` (0-127), `channel` (0-15)
    /// - `channelPressure`: `pressure` (0-127), `channel` (0-15)
    /// - `pitchWheelChange`: `pitchChange` (0-16383, center `8192`), `channel` (0-15)
    /// - Parameter commandType: The command type string
    /// - Parameter metadata: {object} A table of command-specific fields
    /// - Returns: `true` if the command was sent, `false` if the device has no
    ///   destination (e.g. a virtual source) or `commandType`/`metadata` was invalid
    /// - Example:
    /// ```js
    /// kb.sendCommand("noteOn", { note: 60, velocity: 100, channel: 0 })
    /// ```
    @objc func sendCommand(_ commandType: String, _ metadata: [String: Any]) -> Bool

    /// Sends a System Exclusive command to the device.
    /// - Parameter command: A hex string (whitespace ignored), e.g. `"F0 7E 7F 06 01 F7"`
    /// - Example:
    /// ```js
    /// kb.sendSysex("F0 7E 7F 06 01 F7")
    /// ```
    @objc func sendSysex(_ command: String)

    /// Sends a MIDI Identity Request. The device's reply, if any, arrives via the
    /// callback set with `setCallback()` as a `systemExclusive` message.
    /// - Example:
    /// ```js
    /// kb.identityRequest()
    /// ```
    @objc func identityRequest()

    /// Stops receiving from and releases all resources held by this device object.
    /// Called automatically when Hammerspoon reloads.
    /// - Example:
    /// ```js
    /// kb.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSMIDIDevice: NSObject, HSMIDIDeviceAPI {
    @objc var typeName = "HSMIDIDevice"

    @objc func toString() -> String {
        return "<\(typeName): \(name)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    @objc let identifier = UUID().uuidString

    private weak var module: HSMIDIModule?
    private let infoObject: MIDIObjectRef
    let sourceEndpoint: MIDIEndpointRef?
    let destinationEndpoint: MIDIEndpointRef?
    @objc let isVirtual: Bool

    private var inputPort = MIDIPortRef()
    // Retains self while `inputPort` is connected — CoreMIDI's C callback only has a raw
    // pointer to us, which ARC knows nothing about, so nothing else keeps us alive for it.
    private var selfRef: Unmanaged<HSMIDIDevice>?
    private var sysexAccumulator: [UInt8]?
    private var _callback: JSCallback?
    private var isDestroyed = false

    init(module: HSMIDIModule, infoObject: MIDIObjectRef, sourceEndpoint: MIDIEndpointRef?, destinationEndpoint: MIDIEndpointRef?, isVirtual: Bool) {
        self.module = module
        self.infoObject = infoObject
        self.sourceEndpoint = sourceEndpoint
        self.destinationEndpoint = destinationEndpoint
        self.isVirtual = isVirtual
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSMIDIDevice(\(identifier))")
    }

    // MARK: - HSMIDIDeviceAPI

    @objc var name: String { midiStringProperty(infoObject, kMIDIPropertyName) }

    @objc var displayName: String {
        let display = midiStringProperty(infoObject, kMIDIPropertyDisplayName)
        return display.isEmpty ? name : display
    }

    @objc var manufacturer: String { midiStringProperty(infoObject, kMIDIPropertyManufacturer) }

    @objc var model: String { midiStringProperty(infoObject, kMIDIPropertyModel) }

    @objc var isOnline: Bool { !midiIsOffline(infoObject) }

    @objc func setCallback(_ fn: JSValue?) -> HSMIDIDevice {
        _callback?.detach(from: self)
        _callback = nil
        guard let fn else {
            disconnectInput()
            return self
        }
        _callback = JSCallback(value: fn, owner: self)
        connectInputIfNeeded()
        return self
    }

    @objc func sendCommand(_ commandType: String, _ metadata: [String: Any]) -> Bool {
        guard let destination = destinationEndpoint, let port = module?.ensureOutputPort() else {
            AKWarning("hs.midi: sendCommand() failed for '\(name)' — no destination endpoint")
            return false
        }
        guard let word = encodeMIDICommand(type: commandType, metadata: metadata) else {
            AKWarning("hs.midi: sendCommand() failed for '\(name)' — invalid commandType '\(commandType)' or metadata")
            return false
        }
        return sendMIDIPackets([[word]], via: port, to: destination)
    }

    @objc func sendSysex(_ command: String) {
        guard let destination = destinationEndpoint, let port = module?.ensureOutputPort() else {
            AKWarning("hs.midi: sendSysex() failed for '\(name)' — no destination endpoint")
            return
        }
        guard let bytes = hexStringToBytes(command) else {
            AKWarning("hs.midi: sendSysex() failed for '\(name)' — malformed hex string")
            return
        }
        _ = sendMIDIPackets(encodeSysexWords(stripSysexFraming(bytes)), via: port, to: destination)
    }

    @objc func identityRequest() {
        guard let destination = destinationEndpoint, let port = module?.ensureOutputPort() else {
            AKWarning("hs.midi: identityRequest() failed for '\(name)' — no destination endpoint")
            return
        }
        let identityRequestPayload: [UInt8] = [0x7E, 0x7F, 0x06, 0x01] // Universal Non-Realtime Identity Request, F0/F7 framing implicit in UMP
        _ = sendMIDIPackets(encodeSysexWords(identityRequestPayload), via: port, to: destination)
    }

    @objc func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        disconnectInput()
        _callback?.detach(from: self)
        _callback = nil
        module?.removeChild(self)
    }

    // MARK: - Input port lifecycle

    private func connectInputIfNeeded() {
        guard inputPort == 0, let source = sourceEndpoint, let module else { return }
        let client = module.midiClient
        guard client != 0 else { return }

        unsafe selfRef = unsafe Unmanaged.passRetained(self)

        let status = unsafe MIDIInputPortCreateWithProtocol(client, "Hammerspoon 2 Input" as CFString, ._1_0, &inputPort, hsMIDIMakeReceiveHandler(deviceRef: selfRef!))
        guard status == noErr else {
            AKError("hs.midi: Failed to create input port for '\(name)' (error \(status))")
            unsafe selfRef?.release()
            unsafe selfRef = nil
            inputPort = MIDIPortRef()
            return
        }

        let connectStatus = MIDIPortConnectSource(inputPort, source, nil)
        guard connectStatus == noErr else {
            AKError("hs.midi: Failed to connect input port to '\(name)' (error \(connectStatus))")
            return
        }
        AKTrace("hs.midi: Connected input for '\(name)'")
    }

    private func disconnectInput() {
        guard inputPort != 0 else { return }
        if let source = sourceEndpoint {
            _ = MIDIPortDisconnectSource(inputPort, source)
        }
        MIDIPortDispose(inputPort)
        inputPort = MIDIPortRef()
        unsafe selfRef?.release()
        unsafe selfRef = nil
    }

    // MARK: - Fileprivate (called from the file-scope receive handler above)

    fileprivate func handleIncomingMessages(_ messages: [MIDIUniversalMessage]) {
        guard !isDestroyed, let callback = _callback else { return }
        for message in messages {
            guard let decoded = decodeUniversalMessage(message, sysexAccumulator: &sysexAccumulator) else { continue }
            _ = callback.value?.call(withArguments: [self, name, decoded.commandType, decoded.description, decoded.metadata])
        }
    }
}
