//
//  HSMIDIModule.swift
//  Hammerspoon 2
//
//  NOTE: this file lives in "Modules/hs.midi_" (hyphen), not "Modules/hs.midi" (dot), unlike
//  every other module's folder. Xcode's file-system-synchronized group scanner misclassifies
//  any brand-new folder whose name ends in ".midi" as an opaque resource bundle to copy
//  wholesale (".midi"/".mid" is a recognized system UTI for Standard MIDI Files) instead of a
//  normal group to recurse into, which silently drops every .swift file inside from the
//  Sources build phase — see the reproduction notes in the project's task history. The JS
//  module name itself is unaffected ("midi", giving hs.midi) since that's driven entirely by
//  the string passed to ModuleRoot.getOrCreate(name:type:), not the folder name. The docs
//  pipeline needed a matching entry in MODULE_NAME_OVERRIDES (scripts/extract-docs.js) to
//  undo the folder-name-derived "hs.midi_" back to "hs.midi".
//

import Foundation
import JavaScriptCore
import CoreMIDI

// MARK: - CoreMIDI helpers (file-scope, no actor isolation needed)

// Not marked `private` — shared with HSMIDIDevice.swift (file-scope `private` in Swift
// is file-local, not type-local, so these need at least internal visibility to cross files).
func midiStringProperty(_ object: MIDIObjectRef, _ selector: CFString) -> String {
    var unmanagedString: Unmanaged<CFString>?
    guard unsafe MIDIObjectGetStringProperty(object, selector, &unmanagedString) == noErr,
          let cfString = unsafe unmanagedString?.takeRetainedValue() else {
        return ""
    }
    return cfString as String
}

func midiIsOffline(_ object: MIDIObjectRef) -> Bool {
    var value: Int32 = 0
    _ = unsafe MIDIObjectGetIntegerProperty(object, kMIDIPropertyOffline, &value)
    return value == 1
}

// MIDIClientCreateWithBlock's notifyBlock is documented as being called "on an arbitrary
// thread" (thread-safety is the block's responsibility) — NOT necessarily the calling
// thread's run loop. This must be built by a file-scope `nonisolated` function (mirroring
// HSMIDIDevice's `hsMIDIMakeReceiveHandler`/HSSerialPort's `hsSerialPortReadHandler`): a
// closure literal written directly inside an `@MainActor` method would wrongly infer
// @MainActor isolation under this project's default-actor-isolation setting, making
// `MainActor.assumeIsolated` trap when CoreMIDI actually calls it off-main. Only `messageID`
// (a plain value) is extracted synchronously before hopping via `Task { @MainActor in }` —
// the `MIDINotification` pointer itself is only valid for the duration of this call.
nonisolated private func hsMIDIMakeSetupNotifyHandler(module: HSMIDIModule) -> (UnsafePointer<MIDINotification>) -> Void {
    return { [weak module] notification in
        let messageID = unsafe notification.pointee.messageID
        Task { @MainActor [weak module] in
            guard let module else { return }
            module.handleSetupNotification(messageID: messageID)
        }
    }
}

/// A MIDI endpoint is "virtual" when it has no owning entity — i.e. it was published
/// directly by another app/driver (IAC bus, software instrument, etc.) rather than
/// belonging to a physical device's entity/endpoint hierarchy.
private func midiEndpointIsVirtual(_ endpoint: MIDIEndpointRef) -> Bool {
    var entity = MIDIEntityRef()
    return unsafe MIDIEndpointGetEntity(endpoint, &entity) != noErr
}

private func allMIDIDevices() -> [MIDIDeviceRef] {
    (0..<MIDIGetNumberOfDevices()).map { MIDIGetDevice($0) }
}

private func allVirtualSourceEndpoints() -> [MIDIEndpointRef] {
    (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { midiEndpointIsVirtual($0) }
}

/// Returns the first entity on `device` that has a source and/or destination endpoint.
private func firstSourceAndDestination(of device: MIDIDeviceRef) -> (source: MIDIEndpointRef?, destination: MIDIEndpointRef?) {
    for entityIndex in 0..<MIDIDeviceGetNumberOfEntities(device) {
        let entity = MIDIDeviceGetEntity(device, entityIndex)
        let source = MIDIEntityGetNumberOfSources(entity) > 0 ? MIDIEntityGetSource(entity, 0) : nil
        let destination = MIDIEntityGetNumberOfDestinations(entity) > 0 ? MIDIEntityGetDestination(entity, 0) : nil
        if source != nil || destination != nil {
            return (source, destination)
        }
    }
    return (nil, nil)
}

/// Builds `MIDIEventList`(s) from `packets` (each inner array is one packet's UMP words —
/// 1 word for a channel voice message, 2 words per sysex chunk) and sends them. Batches
/// across multiple event lists if the total would exceed `MIDIEventListAdd`'s documented
/// 65536-byte-per-list cap — relevant for large sysex dumps, since each 6-byte sysex chunk
/// costs ~20 bytes of UMP + packet-header overhead, a much worse ratio than the byte-packed
/// format this replaces.
func sendMIDIPackets(_ packets: [[UInt32]], via port: MIDIPortRef, to destination: MIDIEndpointRef) -> Bool {
    guard !packets.isEmpty else { return false }

    let maxListBytes = 65536
    var batch: [[UInt32]] = []
    var batchBytes = 16 // event-list header slack

    for packet in packets {
        let packetBytes = packet.count * 4 + 16
        if !batch.isEmpty && batchBytes + packetBytes > maxListBytes {
            guard sendMIDIEventList(batch, via: port, to: destination) else { return false }
            batch = []
            batchBytes = 16
        }
        batch.append(packet)
        batchBytes += packetBytes
    }
    guard !batch.isEmpty else { return true }
    return sendMIDIEventList(batch, via: port, to: destination)
}

private func sendMIDIEventList(_ packets: [[UInt32]], via port: MIDIPortRef, to destination: MIDIEndpointRef) -> Bool {
    let totalWords = packets.reduce(0) { $0 + $1.count }
    let bufferSize = totalWords * 4 + packets.count * 16 + 64
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<MIDIEventList>.alignment)
    defer { unsafe rawBuffer.deallocate() }
    let eventListPtr = unsafe rawBuffer.bindMemory(to: MIDIEventList.self, capacity: 1)
    // MIDIEventListInit/Add return non-optional pointers on this SDK — no way to signal
    // "buffer too small" to Swift. That's fine here: bufferSize always has generous slack
    // over the actual content.
    var packetPtr = unsafe MIDIEventListInit(eventListPtr, ._1_0)
    for packet in packets {
        unsafe packetPtr = packet.withUnsafeBufferPointer { wordsPtr in
            unsafe MIDIEventListAdd(eventListPtr, bufferSize, packetPtr, 0, wordsPtr.count, wordsPtr.baseAddress!)
        }
    }

    let status = unsafe MIDISendEventList(port, destination, eventListPtr)
    guard status == noErr else {
        AKError("hs.midi: MIDISendEventList failed with status \(status)")
        return false
    }
    return true
}

// MARK: - Protocol

/// A module for enumerating, watching, and communicating with MIDI devices.
/// IMPORTANT NOTE: This module has not had very much real-world testing yet. Please report positive or
/// negative feedback via GitHub Issues.
@objc protocol HSMIDIModuleAPI: JSExport {

    /// A table mapping each MIDI command type name to a stable numeric identifier.
    /// - Example:
    /// ```js
    /// console.log(hs.midi.commandTypes.noteOn)
    /// ```
    @objc var commandTypes: [String: Int] { get }

    /// Returns the names of all currently connected (online) physical MIDI devices.
    /// - Returns: An array of device name strings
    /// - Example:
    /// ```js
    /// console.log(hs.midi.devices())
    /// ```
    @objc func devices() -> [String]

    /// Returns the names of all available virtual MIDI sources — endpoints published
    /// by other apps/drivers (e.g. the IAC Driver, virtual instruments) rather than
    /// belonging to a physical device.
    /// - Returns: An array of virtual source name strings
    /// - Example:
    /// ```js
    /// console.log(hs.midi.virtualSources())
    /// ```
    @objc func virtualSources() -> [String]

    /// Sets or removes a callback fired whenever the set of connected MIDI devices
    /// or virtual sources changes.
    ///
    /// The callback receives two arguments: the current result of `devices()` and the
    /// current result of `virtualSources()`.
    /// - Parameter fn: {((devices: string[], virtualSources: string[]) => void) | null} The function to call on any MIDI setup change, or `null` to remove it
    /// - Example:
    /// ```js
    /// hs.midi.deviceCallback((devices, virtualSources) => {
    ///     console.log("MIDI devices changed: " + devices.join(", "))
    /// })
    /// ```
    @objc func deviceCallback(_ fn: JSValue?)

    /// Creates an `hs.midi` object for a physical device.
    ///
    /// Note: named `deviceNamed()` rather than v1's `new()` — Hammerspoon 2 avoids
    /// `new`/`alloc`/`copy`-prefixed method names, which have special meaning under
    /// Objective-C's ARC ownership conventions.
    /// - Parameter deviceName: The name of the device, as returned by `devices()`
    /// - Returns: An `HSMIDIDevice` object, or `nil` if no device has that name
    /// - Example:
    /// ```js
    /// const kb = hs.midi.deviceNamed(hs.midi.devices()[0])
    /// ```
    @objc func deviceNamed(_ deviceName: String) -> HSMIDIDevice?

    /// Creates an `hs.midi` object for an existing virtual source (receive-only —
    /// a "source" endpoint can only be read from).
    ///
    /// Note: named `virtualSourceNamed()` rather than v1's `newVirtualSource()`, for
    /// the same ARC-related reason as `deviceNamed()`.
    /// - Parameter virtualSourceName: The name of the virtual source, as returned by `virtualSources()`
    /// - Returns: An `HSMIDIDevice` object, or `nil` if no virtual source has that name
    /// - Example:
    /// ```js
    /// const iac = hs.midi.virtualSourceNamed(hs.midi.virtualSources()[0])
    /// ```
    @objc func virtualSourceNamed(_ virtualSourceName: String) -> HSMIDIDevice?
}

// MARK: - Implementation

@safe @MainActor
@_documentation(visibility: private)
@objc class HSMIDIModule: NSObject, HSModuleAPI, HSMIDIModuleAPI {
    var moduleName = "hs.midi"
    let engineID: UUID

    @objc var commandTypes: [String: Int] { midiCommandTypeNumbers }

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var deviceCallbackHandler: JSCallback?
    private var children = HSWeakObjectSet<HSMIDIDevice>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        deviceCallbackHandler?.detach(from: self)
        deviceCallbackHandler = nil

        for device in children.allObjects {
            device.destroy()
        }
        children.removeAllObjects()

        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = MIDIPortRef()
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = MIDIClientRef()
        }
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = children.allObjects.count
        return "<\(moduleName): \(n) device\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func devices() -> [String] {
        allMIDIDevices().filter { !midiIsOffline($0) }.map { midiStringProperty($0, kMIDIPropertyName) }
    }

    @objc func virtualSources() -> [String] {
        allVirtualSourceEndpoints().map { midiStringProperty($0, kMIDIPropertyName) }
    }

    @objc func deviceCallback(_ fn: JSValue?) {
        deviceCallbackHandler?.detach(from: self)
        deviceCallbackHandler = nil
        guard let fn else { return }
        deviceCallbackHandler = JSCallback(value: fn, owner: self)
        ensureClient()
    }

    @objc func deviceNamed(_ deviceName: String) -> HSMIDIDevice? {
        guard let device = allMIDIDevices().first(where: { midiStringProperty($0, kMIDIPropertyName) == deviceName }) else {
            AKWarning("hs.midi.deviceNamed(): No device named '\(deviceName)'")
            return nil
        }
        let (source, destination) = firstSourceAndDestination(of: device)
        let midiDevice = HSMIDIDevice(module: self, infoObject: device, sourceEndpoint: source, destinationEndpoint: destination, isVirtual: false)
        children.add(midiDevice)
        return midiDevice
    }

    @objc func virtualSourceNamed(_ virtualSourceName: String) -> HSMIDIDevice? {
        guard let endpoint = allVirtualSourceEndpoints().first(where: { midiStringProperty($0, kMIDIPropertyName) == virtualSourceName }) else {
            AKWarning("hs.midi.virtualSourceNamed(): No virtual source named '\(virtualSourceName)'")
            return nil
        }
        let midiDevice = HSMIDIDevice(module: self, infoObject: endpoint, sourceEndpoint: endpoint, destinationEndpoint: nil, isVirtual: true)
        children.add(midiDevice)
        return midiDevice
    }

    // MARK: - Internal (used by HSMIDIDevice)

    /// The shared client, created lazily on first use by either `deviceCallback()`
    /// or the first `HSMIDIDevice` that needs an input/output port.
    var midiClient: MIDIClientRef {
        ensureClient()
        return client
    }

    /// The shared output port used by every `HSMIDIDevice.sendCommand`/`sendSysex`/`identityRequest`.
    func ensureOutputPort() -> MIDIPortRef? {
        ensureClient()
        guard client != 0 else { return nil }
        guard outputPort == 0 else { return outputPort }
        let status = unsafe MIDIOutputPortCreate(client, "Hammerspoon 2 Output" as CFString, &outputPort)
        guard status == noErr else {
            AKError("hs.midi: Failed to create output port (error \(status))")
            outputPort = MIDIPortRef()
            return nil
        }
        return outputPort
    }

    func removeChild(_ device: HSMIDIDevice) {
        children.remove(device)
    }

    private func ensureClient() {
        guard client == 0 else { return }
        let status = unsafe MIDIClientCreateWithBlock("Hammerspoon 2" as CFString, &client, hsMIDIMakeSetupNotifyHandler(module: self))
        guard status == noErr else {
            AKError("hs.midi: Failed to create MIDIClient (error \(status))")
            client = MIDIClientRef()
            return
        }
    }

    fileprivate func handleSetupNotification(messageID: MIDINotificationMessageID) {
        guard let callback = deviceCallbackHandler else { return }
        guard messageID == .msgSetupChanged || messageID == .msgObjectAdded || messageID == .msgObjectRemoved else { return }
        _ = callback.value?.call(withArguments: [devices(), virtualSources()])
    }
}
