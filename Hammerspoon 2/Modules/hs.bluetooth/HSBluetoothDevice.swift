//
//  HSBluetoothDevice.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import IOBluetooth

// MARK: - JavaScript API

/// A Bluetooth device macOS knows: one paired with this Mac, or one found by `hs.bluetooth.inquiry()`.
///
/// Obtain devices from the ``hs.bluetooth`` module; do not instantiate them directly. A device is
/// identified by its `address`, and the same device is returned as the same object for as long as
/// you hold on to it.
///
/// Bluetooth Low Energy (BLE) peripherals found by `hs.bluetooth.scan()` are `HSBluetoothPeripheral`
/// objects instead. A paired device that also speaks BLE can give you its peripheral with
/// `lowEnergyPeripheral()`, e.g. to read its GATT characteristics.
///
/// ## Battery levels
///
/// ```javascript
/// hs.bluetooth.connectedDevices().forEach(d => {
///     if (d.batteryLevel !== null) console.log(d.name + ": " + d.batteryLevel + "%")
/// })
/// ```
@objc protocol HSBluetoothDeviceAPI: HSTypeAPI, JSExport {
    /// The type name for JavaScript introspection. Always `"HSBluetoothDevice"`.
    @objc var typeName: String { get }

    /// The device's name, or `null` if it hasn't reported one.
    /// - Example:
    /// ```js
    /// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name))
    /// ```
    @objc var name: String? { get }

    /// The device's Bluetooth address, in the form `xx-xx-xx-xx-xx-xx`.
    /// - Example:
    /// ```js
    /// console.log(hs.bluetooth.pairedDevices()[0].address)
    /// ```
    @objc var address: String { get }

    /// Whether the device is paired with this Mac.
    /// - Example:
    /// ```js
    /// console.log(device.isPaired)
    /// ```
    @objc var isPaired: Bool { get }

    /// Whether macOS currently has the device connected.
    /// - Example:
    /// ```js
    /// if (headphones.isConnected) console.log("Headphones are connected")
    /// ```
    @objc var isConnected: Bool { get }

    /// Whether the device is marked as a favorite in macOS.
    /// - Example:
    /// ```js
    /// console.log(device.isFavorite)
    /// ```
    @objc var isFavorite: Bool { get }

    /// The device's raw Bluetooth Class of Device value.
    /// - Example:
    /// ```js
    /// console.log(device.classOfDevice)
    /// ```
    @objc var classOfDevice: Int { get }

    /// The major device class, e.g. `4` for audio devices or `5` for peripherals such as keyboards and mice.
    /// - Example:
    /// ```js
    /// const peripherals = hs.bluetooth.pairedDevices().filter(d => d.majorClass === 5)
    /// ```
    @objc var majorClass: Int { get }

    /// The minor device class, whose meaning depends on `majorClass`.
    /// - Example:
    /// ```js
    /// console.log(device.minorClass)
    /// ```
    @objc var minorClass: Int { get }

    /// The major service classes the device advertises, as a bitmask.
    /// - Example:
    /// ```js
    /// console.log(device.serviceClasses)
    /// ```
    @objc var serviceClasses: Int { get }

    /// The names of the device's classic Bluetooth (SDP) services, e.g. `["Audio Sink", "AVRCP Controller"]`.
    /// - Example:
    /// ```js
    /// console.log(device.serviceNames.join(", "))
    /// ```
    @objc var serviceNames: [String] { get }

    /// The signal strength in dBm that macOS last measured for the device, or `null` if there is none. Call `readRSSI()` for a fresh reading from a connected device.
    /// - Example:
    /// ```js
    /// console.log(device.name + " " + device.rssi + " dBm")
    /// ```
    @objc var rssi: NSNumber? { get }

    /// When the device was last used or found by an inquiry, in Unix seconds, or `null` if unknown.
    /// - Example:
    /// ```js
    /// console.log(new Date(device.lastSeen * 1000))
    /// ```
    @objc var lastSeen: NSNumber? { get }

    /// The device's battery level as a percentage, or `null` if macOS doesn't know it.
    ///
    /// This is what macOS itself reports: for Apple's Magic accessories from the system, and for AirPods and Beats from what macOS last heard from them. For earbuds it is the lower of the two buds; see `batteryLevels` for each one. For a device that reports its battery over BLE instead, read it with `lowEnergyPeripheral()` and `readBatteryLevel()`.
    /// - Example:
    /// ```js
    /// hs.bluetooth.connectedDevices()
    ///     .filter(d => d.batteryLevel !== null)
    ///     .forEach(d => console.log(d.name + ": " + d.batteryLevel + "%"))
    /// ```
    @objc var batteryLevel: NSNumber? { get }

    /// The individual battery levels of a device with several batteries, such as earbuds and their case, or `null` if it has only one (or none is known).
    ///
    /// The object has any of `left`, `right` and `case`, each a percentage.
    /// - Example:
    /// ```js
    /// const levels = airpods.batteryLevels
    /// if (levels) console.log("L " + levels.left + "% R " + levels.right + "% case " + levels.case + "%")
    /// ```
    @objc var batteryLevels: [String: Int]? { get }

    /// Connects the device to the Mac, the same way macOS would, e.g. so headphones become available as an audio device.
    /// - Returns: {Promise<HSBluetoothDevice>} A Promise resolving to this device once it's connected, or rejecting if the connection fails or takes longer than 20 seconds
    /// - Example:
    /// ```js
    /// const headphones = hs.bluetooth.pairedDevices().find(d => d.name === "My Headphones")
    /// await headphones.connect()
    /// ```
    @objc func connect() -> JSPromise?

    /// Disconnects the device from the Mac. This ends macOS's own connection, not just Hammerspoon's, as if you had disconnected it in System Settings.
    /// - Returns: {Promise<HSBluetoothDevice>} A Promise resolving to this device once it's disconnected
    /// - Example:
    /// ```js
    /// await headphones.disconnect()
    /// ```
    @objc func disconnect() -> JSPromise?

    /// Reads the current signal strength of a connected device.
    /// - Returns: {Promise<number>} A Promise resolving to the signal strength in dBm, or rejecting if the device isn't connected
    /// - Example:
    /// ```js
    /// console.log(await device.readRSSI() + " dBm")
    /// ```
    @objc func readRSSI() -> JSPromise?

    /// Finds the BLE peripheral of a connected device that also speaks Bluetooth Low Energy, such as a Magic Keyboard or a heart-rate strap, so you can use its GATT services.
    ///
    /// macOS doesn't link a paired device to its BLE side, so this looks for the BLE peripheral connected to the Mac with the same name. It rejects rather than guess if several have that name, and resolves to `null` if none does (e.g. the device doesn't use BLE, or it was renamed after pairing). The peripheral still needs `connect()` before its GATT methods can be used.
    /// - Returns: {Promise<HSBluetoothPeripheral | null>} A Promise resolving to the device's peripheral, or `null` if it has none. Rejects if the device isn't connected, several peripherals match, or Bluetooth is unavailable
    /// - Example:
    /// ```js
    /// const keyboard = hs.bluetooth.connectedDevices().find(d => d.name === "Magic Keyboard")
    /// const peripheral = await keyboard.lowEnergyPeripheral()
    /// if (peripheral) {
    ///     await peripheral.connect()
    ///     console.log(await peripheral.discoverServices())
    /// }
    /// ```
    @objc func lowEnergyPeripheral() -> JSPromise?

    /// Register a listener for this device's events.
    ///
    /// Listeners for `"connected"` and `"disconnected"` are called with no arguments whenever macOS connects or disconnects the device. A device with listeners keeps working after you drop your reference to it.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected"} The event to listen for
    ///   - listener: {() => void} Called when the event occurs
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     keyboard.on('disconnected', () => console.log(keyboard.name + " went away"))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func on(_ event: String, _ listener: JSFunction)

    /// Remove a previously registered listener for this device's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected"} The event the listener was registered for
    ///   - listener: The function originally passed to `on`
    /// - Example:
    /// ```js
    /// keyboard.off('disconnected', myListener)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Register a listener that fires at most once for one of this device's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected"} The event to listen for
    ///   - listener: {() => void} Called once, then automatically removed
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     headphones.once('connected', () => console.log("Headphones are back"))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func once(_ event: String, _ listener: JSFunction)

    // NOTE: Private API consumed only by hs.bluetooth.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc(_removeWatcher) func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSBluetoothDeviceEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    /// Returns a plain object describing this device, for JSON serialisation
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with the device's `name`, `address`, `isPaired`, `isConnected`, `rssi`, `batteryLevel`, `batteryLevels`, `majorClass` and `minorClass`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.bluetooth.pairedDevices(), null, 2))
    /// ```
    @objc func toJSON() -> [String: Any]
}

// MARK: - Implementation

/// Events emitted by a single HSBluetoothDevice's watcher
nonisolated enum HSBluetoothDeviceEvent: String, HSEventName {
    case connected, disconnected
}

@_documentation(visibility: private)
@MainActor
@objc class HSBluetoothDevice: NSObject, HSBluetoothDeviceAPI, HSTrackedObject {
    @objc var typeName = "HSBluetoothDevice"

    private weak var module: HSBluetoothModule?
    private weak var tracker: HSObjectTracker<HSBluetoothDevice>?

    let classic: any HSClassicBluetoothDevice
    @objc let address: String

    /// JS-facing operations in flight. Each one keeps the object alive until its Promise settles.
    private var operations = 0 {
        didSet { updateActivity() }
    }

    private var watcherCallback: JSCallback? {
        didSet {
            updateActivity()
            module?.updateClassicNotifications()
        }
    }
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSBluetoothDeviceEvent.allNames }

    /// Whether anything is listening for this device's events
    var isWatching: Bool { watcherCallback != nil }

    private let requests = HSBluetoothRequests()

    /// Set by destroy(), after which no Promise is settled: the JSContext is going away
    private var isDestroyed = false

    init(module: HSBluetoothModule, tracker: HSObjectTracker<HSBluetoothDevice>, classic: any HSClassicBluetoothDevice, address: String) {
        self.module = module
        self.tracker = tracker
        self.classic = classic
        self.address = address
        super.init()
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of HSBluetoothDevice: \(address)")
    }

    func destroy() {
        isDestroyed = true
        _removeWatcher()
        requests.close(HSBluetoothError("Hammerspoon is shutting down"))
    }

    private func updateActivity() {
        tracker?.setActive(self, isWatching || operations > 0, finishesOnItsOwn: !isWatching)
    }

    @objc func toString() -> String {
        "<\(typeName): \(name ?? "unnamed") (\(address))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Properties

    @objc var name: String? { classic.name }
    @objc var isPaired: Bool { classic.isPaired }
    @objc var isConnected: Bool { classic.isConnected }
    @objc var isFavorite: Bool { classic.isFavorite }
    @objc var classOfDevice: Int { classic.classOfDevice }
    @objc var majorClass: Int { classic.majorClass }
    @objc var minorClass: Int { classic.minorClass }
    @objc var serviceClasses: Int { classic.serviceClasses }
    @objc var serviceNames: [String] { classic.serviceNames }
    @objc var rssi: NSNumber? { classic.lastRSSI.map { NSNumber(value: $0) } }
    @objc var lastSeen: NSNumber? { classic.lastSeen.map { NSNumber(value: $0.timeIntervalSince1970) } }
    @objc var batteryLevel: NSNumber? { classic.batteryLevels.overall.map { NSNumber(value: $0) } }
    @objc var batteryLevels: [String: Int]? { classic.batteryLevels.components }

    @objc func toJSON() -> [String: Any] {
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        // Read once: each read asks the system
        let battery = classic.batteryLevels
        return [
            "name": orNull(name),
            "address": address,
            "isPaired": isPaired,
            "isConnected": isConnected,
            "rssi": orNull(rssi),
            "batteryLevel": orNull(battery.overall),
            "batteryLevels": orNull(battery.components),
            "majorClass": majorClass,
            "minorClass": minorClass,
        ]
    }

    // MARK: - Operations

    /// Runs a JS-facing asynchronous operation, settling its Promise with the result. The object
    /// stays alive (active in its tracker) until the operation finishes.
    private func perform(_ method: String, _ body: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { [self] holder in
            operations += 1
            Task {
                defer { operations -= 1 }
                do {
                    let result = try await body()
                    if !isDestroyed { holder.resolveWith(result) }
                } catch {
                    if !isDestroyed { holder.rejectWithMessage("hs.bluetooth device.\(method)(): \(error.localizedDescription)") }
                }
            }
        }
    }

    @objc func connect() -> JSPromise? {
        perform("connect") {
            guard !self.classic.isConnected else { return self }
            try await self.requests.wait(for: "connect", timeout: .seconds(20)) {
                try self.classic.openConnection { [weak self] status in
                    self?.requests.settle("connect", status == kIOReturnSuccess ? nil : HSBluetoothError.forIOReturn(status, "Connecting"))
                }
            }
            return self
        }
    }

    @objc func disconnect() -> JSPromise? {
        perform("disconnect") {
            if self.classic.isConnected {
                let status = self.classic.closeConnection()
                guard status == kIOReturnSuccess else { throw HSBluetoothError.forIOReturn(status, "Closing the connection") }
            }
            return self
        }
    }

    @objc func readRSSI() -> JSPromise? {
        perform("readRSSI") {
            guard self.classic.isConnected else { throw HSBluetoothError("the device is not connected") }
            guard let rssi = self.classic.currentRSSI() else { throw HSBluetoothError("the device has no signal strength reading") }
            return rssi
        }
    }

    @objc func lowEnergyPeripheral() -> JSPromise? {
        perform("lowEnergyPeripheral") {
            guard self.classic.isConnected else { throw HSBluetoothError("the device is not connected") }
            guard let name = self.classic.name, let module = self.module else { return nil }
            let matches = try await module.systemConnectedPeripherals(named: name)
            guard matches.count <= 1 else {
                throw HSBluetoothError("\(matches.count) connected BLE peripherals are named '\(name)', so which is this device can't be told")
            }
            return matches.first.map(module.peripheral(for:))
        }
    }

    // MARK: - Watcher

    /// Lazily creates this device's JS watcher emitter (via the module's `_makeObjectEmitter`
    /// factory). Returns nil, having set `ctx.exception`, on failure, so on()/once() never return
    /// without registering - same as HSCamera's.
    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let emitter = module?.makeObjectEmitter(for: self, in: ctx) else { return nil }
            _watcherEmitter = emitter
        }
        return _watcherEmitter
    }

    @objc func on(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        // callCapturingException, not plain invokeMethod: a throw from inside the emitter's on()
        // must reach this call's own JS caller
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
        guard watcherCallback == nil else {
            AKWarning("hs.bluetooth device._addWatcher(): already watching \(toString()), refusing a second subscription")
            return false
        }
        // The events come from the module's IOBluetooth notifications, which watcherCallback's
        // didSet asks for
        watcherCallback = JSCallback(value: listener, owner: self)
        guard module?.isReceivingClassicNotifications == true else {
            AKError("hs.bluetooth device._addWatcher(): failed to register for connection notifications for \(toString())")
            watcherCallback?.detach(from: self)
            watcherCallback = nil
            return false
        }
        AKDebug("hs.bluetooth device._addWatcher(): started watching \(toString())")
        return true
    }

    @objc(_removeWatcher) func _removeWatcher() {
        // Cleared first so the next on() creates a fresh emitter, in the caller's VM
        _watcherEmitter = nil
        guard watcherCallback != nil else { return }
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("hs.bluetooth device._removeWatcher(): stopped watching \(toString())")
    }

    /// Delivers one of this device's events to its listeners
    func fire(_ event: HSBluetoothDeviceEvent) {
        _ = watcherCallback?.call(withArguments: [event.rawValue])
    }
}

/// What HSBluetoothDevice needs from IOBluetooth. Tests stand in a fake, since touching a real
/// IOBluetoothDevice can wait for the user to answer the Bluetooth permission prompt.
protocol HSClassicBluetoothDevice: AnyObject {
    var name: String? { get }
    var isPaired: Bool { get }
    var isConnected: Bool { get }
    var isFavorite: Bool { get }
    var classOfDevice: Int { get }
    var majorClass: Int { get }
    var minorClass: Int { get }
    var serviceClasses: Int { get }
    var serviceNames: [String] { get }
    /// The signal strength macOS last measured, if it has one
    var lastRSSI: Int? { get }
    /// When the device was last used or found by an inquiry
    var lastSeen: Date? { get }
    var batteryLevels: HSBluetoothBatteryLevels { get }
    /// Measures the signal strength of the connected device, if it can
    func currentRSSI() -> Int?
    /// Starts connecting, calling `completion` (on the main actor) when that finishes
    func openConnection(completion: @escaping @MainActor (IOReturn) -> Void) throws
    func closeConnection() -> IOReturn
}

/// A device known to IOBluetooth
final class IOBluetoothClassicDevice: HSClassicBluetoothDevice {
    let device: IOBluetoothDevice

    init(_ device: IOBluetoothDevice) {
        self.device = device
    }

    var name: String? { device.name }
    var isPaired: Bool { device.isPaired() }
    var isConnected: Bool { device.isConnected() }
    var isFavorite: Bool { device.isFavorite() }
    var classOfDevice: Int { Int(device.classOfDevice) }
    var majorClass: Int { Int(device.deviceClassMajor) }
    var minorClass: Int { Int(device.deviceClassMinor) }
    var serviceClasses: Int { Int(device.serviceClassMajor) }

    var serviceNames: [String] {
        (device.services as? [IOBluetoothSDPServiceRecord] ?? []).compactMap { $0.getServiceName() }
    }

    var lastRSSI: Int? {
        // IOBluetooth reports 0 or +127 when it has no reading
        let rssi = device.rssi()
        return rssi == 0 || rssi == 127 ? nil : Int(rssi)
    }

    var lastSeen: Date? {
        [device.recentAccessDate(), device.getLastInquiryUpdate()].compactMap { $0 }.max()
    }

    var batteryLevels: HSBluetoothBatteryLevels { HSBluetoothBatteryLevels.read(device) }

    func currentRSSI() -> Int? {
        let rssi = device.rawRSSI()
        return rssi == 127 ? nil : Int(rssi)
    }

    func openConnection(completion: @escaping @MainActor (IOReturn) -> Void) throws {
        try ClassicConnectionRequest.open(device, completion: completion)
    }

    func closeConnection() -> IOReturn {
        device.closeConnection()
    }
}

/// The target of one `IOBluetoothDevice.openConnection(_:)`. IOBluetooth doesn't document
/// whether it retains the target until `connectionComplete:status:` arrives, so each request
/// keeps itself alive until then, even after the caller has stopped waiting for it.
private final class ClassicConnectionRequest: NSObject {
    private static var pending: Set<ClassicConnectionRequest> = []
    private let completion: @MainActor (IOReturn) -> Void

    private init(completion: @escaping @MainActor (IOReturn) -> Void) {
        self.completion = completion
    }

    /// Starts connecting `device`, calling `completion` (on the main actor) when it finishes
    static func open(_ device: IOBluetoothDevice, completion: @escaping @MainActor (IOReturn) -> Void) throws {
        let request = ClassicConnectionRequest(completion: completion)
        let status = device.openConnection(request)
        guard status == kIOReturnSuccess else { throw HSBluetoothError.forIOReturn(status, "Opening the connection") }
        pending.insert(request)
    }

    /// Called by IOBluetooth, on whatever thread its connection to bluetoothd uses
    @objc(connectionComplete:status:) nonisolated func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Self.pending.remove(self)
                self.completion(status)
            }
        }
    }
}
