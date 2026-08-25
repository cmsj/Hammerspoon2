//
//  HSStreamDeckModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOKit
import IOKit.hid

// MARK: - IOKit helpers (file-scope, no actor isolation needed)

private func hsStreamDeckRegistryEntryID(for device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    guard service != IO_OBJECT_NULL else { return nil }
    var entryID: UInt64 = 0
    guard unsafe IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
    return entryID
}

// MARK: - Protocol

/// Direct hardware control of Elgato Stream Deck devices — buttons, encoders, and the
/// LCD touch strip on the Stream Deck Plus.
///
/// ## Enumerating devices
///
/// ```javascript
/// const decks = hs.streamdeck.all()
/// decks.forEach(d => console.log(d.deckType + " — " + d.serialNumber))
/// ```
///
/// ## Watching for connect / disconnect events
///
/// ```javascript
/// hs.streamdeck.addWatcher((event, device) => {
///     if (event === "connected") console.log("Connected: " + device.deckType)
///     if (event === "disconnected") console.log("Disconnected: " + device.deckType)
/// })
/// ```
///
/// ## Driving a device
///
/// ```javascript
/// const deck = hs.streamdeck.all()[0]
/// deck.setBrightness(50)
/// deck.setButtonColor(1, HSColor.named("red"))
/// deck.buttonCallback((device, button, isDown) => {
///     console.log("button " + button + (isDown ? " down" : " up"))
/// })
/// ```
@objc protocol HSStreamDeckModuleAPI: JSExport {

    /// All Stream Deck devices currently connected to the system.
    /// - Returns: An array of `HSStreamDeckDevice` objects
    /// - Example:
    /// ```js
    /// hs.streamdeck.all().forEach(d => console.log(d.deckType))
    /// ```
    @objc func all() -> [HSStreamDeckDevice]

    /// Find the connected device with the given serial number.
    /// - Parameter serialNumber: The serial number to search for
    /// - Returns: An `HSStreamDeckDevice` if found, `null` otherwise
    /// - Example:
    /// ```js
    /// const deck = hs.streamdeck.findBySerialNumber("AL12K1A00000")
    /// ```
    @objc func findBySerialNumber(_ serialNumber: String) -> HSStreamDeckDevice?

    /// Register a listener for Stream Deck connect/disconnect events.
    ///
    /// The listener is called with two arguments:
    /// - `event` — either `"connected"` or `"disconnected"`
    /// - `device` — an `HSStreamDeckDevice` representing the affected device
    /// - Parameter listener: {(event: string, device: HSStreamDeckDevice) => void} A JavaScript function called with the event name and the affected device
    /// - Example:
    /// ```js
    /// hs.streamdeck.addWatcher((event, device) => console.log(event + ": " + device.deckType))
    /// ```
    @objc func addWatcher(_ listener: JSFunction)

    /// Remove a previously registered connect/disconnect listener.
    /// - Parameter listener: The function originally passed to ``addWatcher(_:)``
    /// - Example:
    /// ```js
    /// hs.streamdeck.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSStreamDeckModule: NSObject, HSModuleAPI, HSStreamDeckModuleAPI {
    var moduleName = "hs.streamdeck"
    let engineID: UUID

    private let ioHIDManager: IOHIDManager
    private var devices: [UInt64: HSStreamDeckDevice] = [:]
    private var hasShutDown = false

    // Retained reference passed as the IOHIDManager callback context; balanced by
    // .release() in shutdown().
    nonisolated(unsafe) private var selfRef: Unmanaged<HSStreamDeckModule>?

    required init(engineID: UUID) {
        self.engineID = engineID
        self.ioHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        super.init()

        let vendorIDKey = kIOHIDVendorIDKey as String
        let productIDKey = kIOHIDProductIDKey as String
        let matchingDicts: [[String: Any]] = HSStreamDeckModel.allProductIDs.map {
            [vendorIDKey: HSStreamDeckModel.usbVendorIDElgato, productIDKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(ioHIDManager, matchingDicts as CFArray)

        unsafe selfRef = Unmanaged.passRetained(self)
        let refCon: UnsafeMutableRawPointer = unsafe selfRef!.toOpaque()

        unsafe IOHIDManagerRegisterDeviceMatchingCallback(ioHIDManager, { context, _, _, device in
            guard let context = unsafe context else { return }
            let module = unsafe Unmanaged<HSStreamDeckModule>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { module.deviceConnected(device) }
        }, refCon)

        unsafe IOHIDManagerRegisterDeviceRemovalCallback(ioHIDManager, { context, _, _, device in
            guard let context = unsafe context else { return }
            let module = unsafe Unmanaged<HSStreamDeckModule>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { module.deviceDisconnected(device) }
        }, refCon)

        IOHIDManagerScheduleWithRunLoop(ioHIDManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(ioHIDManager, IOOptionBits(kIOHIDOptionsTypeNone))

        AKDebug("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true

        _removeWatcher()
        _watcherEmitter = nil

        IOHIDManagerRegisterDeviceMatchingCallback(ioHIDManager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(ioHIDManager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(ioHIDManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(ioHIDManager, IOOptionBits(kIOHIDOptionsTypeNone))

        for device in devices.values { device.destroy() }
        devices.removeAll()

        unsafe selfRef?.release()
        unsafe selfRef = nil
    }

    isolated deinit {
        shutdown()
        AKDebug("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = devices.count
        return "<hs.streamdeck: \(n) connected device\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Device enumeration

    // IOHIDManagerRegisterDeviceMatchingCallback fires for already-connected devices
    // asynchronously via the run loop, not synchronously when the callback is registered —
    // so a device present before the module loaded may not have reached `devices` yet by
    // the time `all()` is called. all()/findBySerialNumber() therefore query IOHIDManager
    // directly (matching HSCameraModule.all()'s fresh-enumeration approach) and get-or-create
    // the cached wrapper, rather than trusting the cache alone.

    @objc func all() -> [HSStreamDeckDevice] {
        currentlyConnectedDevices().compactMap { existingOrNewDevice(for: $0) }
    }

    @objc func findBySerialNumber(_ serialNumber: String) -> HSStreamDeckDevice? {
        all().first { $0.serialNumber == serialNumber }
    }

    private func currentlyConnectedDevices() -> [IOHIDDevice] {
        guard let deviceSet = IOHIDManagerCopyDevices(ioHIDManager) else { return [] }
        let count = CFSetGetCount(deviceSet)
        guard count > 0 else { return [] }
        var rawDevices = unsafe [UnsafeRawPointer?](repeating: nil, count: count)
        unsafe CFSetGetValues(deviceSet, &rawDevices)
        return unsafe rawDevices.compactMap { ptr -> IOHIDDevice? in
            guard let ptr = unsafe ptr else { return nil }
            return unsafe Unmanaged<IOHIDDevice>.fromOpaque(ptr).takeUnretainedValue()
        }
    }

    /// Returns the cached wrapper for `device`, creating and registering one if this is
    /// the first time it's been seen. Shared by `all()` (synchronous, fresh enumeration)
    /// and the async matching callback (`deviceConnected`), so a device is never wrapped
    /// twice regardless of which path notices it first.
    @discardableResult
    private func existingOrNewDevice(for device: IOHIDDevice) -> HSStreamDeckDevice? {
        guard let entryID = hsStreamDeckRegistryEntryID(for: device) else { return nil }
        if let cached = devices[entryID] { return cached }

        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              vendorID == HSStreamDeckModel.usbVendorIDElgato,
              let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
              let model = HSStreamDeckModel.forProductID(productID) else {
            return nil
        }

        let deck = HSStreamDeckDevice(device: device, model: model)
        devices[entryID] = deck
        deck.startReceivingInputReports()
        AKTrace("hs.streamdeck: connected \(model.deckType) (\(deck.serialNumber))")
        return deck
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        guard let deck = existingOrNewDevice(for: device) else { return }
        fireWatcherEvent("connected", device: deck)
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        guard let entryID = hsStreamDeckRegistryEntryID(for: device),
              let deck = devices.removeValue(forKey: entryID) else {
            return
        }
        deck.destroy()
        AKTrace("hs.streamdeck: disconnected \(deck.deckType)")
        fireWatcherEvent("disconnected", device: deck)
    }

    // MARK: - Module-level watcher

    @objc var _watcherEmitter: JSFunction? = nil
    private var moduleCallback: JSFunction? = nil

    @objc func addWatcher(_ listener: JSFunction) {
        // invokeMethod doesn't propagate JS exceptions to the calling context's try-catch,
        // so we validate here and throw via context.exception before delegating.
        guard let context = JSContext.current() else { return }
        guard listener.isObject else {
            context.exception = JSValue(newErrorFromMessage: "hs.streamdeck.addWatcher(): listener must be a function", in: context)
            return
        }
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard moduleCallback == nil else {
            AKWarning("hs.streamdeck._addWatcher(): Already watching. Refusing to create a second.")
            return
        }
        moduleCallback = callback
        AKTrace("hs.streamdeck._addWatcher(): Started")
    }

    @objc func _removeWatcher() {
        guard moduleCallback != nil else { return }
        moduleCallback = nil
        AKTrace("hs.streamdeck._removeWatcher(): Stopped")
    }

    private func fireWatcherEvent(_ eventType: String, device: HSStreamDeckDevice) {
        _ = moduleCallback?.call(withArguments: [eventType, device])
    }
}
