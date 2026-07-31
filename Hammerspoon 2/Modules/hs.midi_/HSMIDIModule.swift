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

/// Builds a single-message `MIDIPacketList` and sends it. Allocates enough room for
/// `bytes` plus packet-list/packet header overhead so arbitrarily long sysex messages
/// (which don't fit in a stack-sized packet list) are handled safely.
func sendMIDIBytes(_ bytes: [UInt8], via port: MIDIPortRef, to destination: MIDIEndpointRef) -> Bool {
    guard !bytes.isEmpty else { return false }
    let bufferSize = bytes.count + 512
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<MIDIPacketList>.alignment)
    defer { unsafe rawBuffer.deallocate() }
    let packetListPtr = unsafe rawBuffer.bindMemory(to: MIDIPacketList.self, capacity: 1)
    let firstPacket = unsafe MIDIPacketListInit(packetListPtr)
    // MIDIPacketListAdd returns a non-optional pointer on this SDK — it has no way to
    // signal "buffer too small" to Swift. That's fine here: bufferSize always has 512
    // bytes of slack over the actual message, far more than any command this module
    // sends (including sysex) needs.
    _ = bytes.withUnsafeBufferPointer { bufferPtr in
        unsafe MIDIPacketListAdd(packetListPtr, bufferSize, firstPacket, 0, bufferPtr.count, bufferPtr.baseAddress!)
    }
    let status = unsafe MIDISend(port, destination, packetListPtr)
    guard status == noErr else {
        AKError("hs.midi: MIDISend failed with status \(status)")
        return false
    }
    return true
}

// MARK: - Protocol

/// A module for enumerating, watching, and communicating with MIDI devices.
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
    var name = "hs.midi"
    let engineID: UUID

    @objc var commandTypes: [String: Int] { midiCommandTypeNumbers }

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var deviceCallbackHandler: JSCallback?
    private var children = HSWeakObjectSet<HSMIDIDevice>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
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
        AKDebug("Deinit of \(name): \(engineID)")
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
        let status = unsafe MIDIClientCreateWithBlock("Hammerspoon 2" as CFString, &client) { [weak self] notification in
            MainActor.assumeIsolated {
                unsafe self?.handleSetupNotification(notification)
            }
        }
        guard status == noErr else {
            AKError("hs.midi: Failed to create MIDIClient (error \(status))")
            client = MIDIClientRef()
            return
        }
    }

    private func handleSetupNotification(_ notification: UnsafePointer<MIDINotification>) {
        guard let callback = deviceCallbackHandler else { return }
        let messageID = unsafe notification.pointee.messageID
        guard messageID == .msgSetupChanged || messageID == .msgObjectAdded || messageID == .msgObjectRemoved else { return }
        _ = callback.value?.call(withArguments: [devices(), virtualSources()])
    }
}
