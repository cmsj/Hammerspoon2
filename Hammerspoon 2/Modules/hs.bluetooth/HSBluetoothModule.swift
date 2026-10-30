//
//  HSBluetoothModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import IOBluetooth
import CoreBluetooth

// MARK: - JavaScript API

/// Inspect, connect to and scan for Bluetooth devices, and watch them connect and disconnect.
///
/// The module offers two kinds of object, because macOS identifies them in two different ways:
///  - `HSBluetoothDevice`: a device macOS knows by its Bluetooth address, such as headphones, a
///    keyboard or a mouse paired with this Mac. These have battery levels and system-wide
///    connect/disconnect events.
///  - `HSBluetoothPeripheral`: a Bluetooth Low Energy (BLE) peripheral, found by `scan()`, which
///    Hammerspoon can connect to itself to read and write its GATT characteristics. macOS gives
///    these a UUID `identifier` instead of revealing their address.
///
/// ```javascript
/// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
///
/// hs.bluetooth.connectedDevices()
///     .filter(d => d.batteryLevel !== null)
///     .forEach(d => console.log(d.name + ": " + d.batteryLevel + "%"))
///
/// hs.bluetooth.on('connected', d => console.log(d.name + " connected"))
/// hs.bluetooth.on('powerChanged', on => console.log("Bluetooth is " + (on ? "on" : "off")))
///
/// const nearby = await hs.bluetooth.scan({ seconds: 5 })
/// nearby.forEach(p => console.log((p.name ?? p.identifier) + " " + p.rssi + " dBm"))
/// ```
///
/// macOS asks the user for Bluetooth permission the first time this module talks to Bluetooth.
/// Use `hs.permissions.checkBluetooth()` to see whether it has been granted.
@objc protocol HSBluetoothModuleAPI: JSExport {
    /// Whether the Mac's Bluetooth is turned on.
    /// - Example:
    /// ```js
    /// console.log("Bluetooth on: " + hs.bluetooth.powered)
    /// ```
    @objc var powered: Bool { get }

    /// Whether a BLE scan started by `scan()` is running.
    /// - Example:
    /// ```js
    /// if (!hs.bluetooth.isScanning) hs.bluetooth.scan()
    /// ```
    @objc var isScanning: Bool { get }

    /// Whether a search for classic devices started by `inquiry()` is running.
    /// - Example:
    /// ```js
    /// console.log(hs.bluetooth.isInquiring)
    /// ```
    @objc var isInquiring: Bool { get }

    /// All devices paired with this Mac, connected or not.
    ///
    /// - Returns: An array of `HSBluetoothDevice` objects
    /// - Example:
    /// ```js
    /// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
    /// ```
    @objc func pairedDevices() -> [HSBluetoothDevice]

    /// The paired devices macOS currently has connected.
    ///
    /// - Returns: An array of `HSBluetoothDevice` objects
    /// - Example:
    /// ```js
    /// hs.bluetooth.connectedDevices().forEach(d => console.log(d.name + " is connected"))
    /// ```
    @objc func connectedDevices() -> [HSBluetoothDevice]

    /// Looks up a device macOS knows by its Bluetooth address.
    ///
    /// - Parameter address: The device's address, as `"a4-83-e7-12-34-56"` or `"A4:83:E7:12:34:56"`
    /// - Returns: The `HSBluetoothDevice`, or `null` if macOS doesn't know a device with that address
    /// - Example:
    /// ```js
    /// const keyboard = hs.bluetooth.device("a4-83-e7-12-34-56")
    /// if (keyboard) console.log(keyboard.name + " battery: " + keyboard.batteryLevel + "%")
    /// ```
    @objc func device(_ address: String) -> HSBluetoothDevice?

    /// The BLE peripherals Hammerspoon is connected to, with `HSBluetoothPeripheral.connect()`.
    ///
    /// - Returns: An array of `HSBluetoothPeripheral` objects
    /// - Example:
    /// ```js
    /// hs.bluetooth.connectedPeripherals().forEach(p => console.log(p.name))
    /// ```
    @objc func connectedPeripherals() -> [HSBluetoothPeripheral]

    /// Looks up a BLE peripheral by its identifier.
    ///
    /// Hammerspoon must have seen the peripheral in a scan, or Bluetooth must already be in use, for it to be found. This lookup doesn't start Bluetooth itself, so it never shows the permission prompt.
    /// - Parameter identifier: The peripheral's `identifier`, a UUID
    /// - Returns: The `HSBluetoothPeripheral`, or `null` if it isn't known
    /// - Example:
    /// ```js
    /// const sensor = hs.bluetooth.peripheral("5D7E2C4A-1B3F-4E8A-9C6D-0F1E2D3C4B5A")
    /// if (sensor) await sensor.connect()
    /// ```
    @objc func peripheral(_ identifier: String) -> HSBluetoothPeripheral?

    /// Scans for BLE peripherals nearby. Only one scan can run at a time.
    ///
    /// Each peripheral found is also delivered to `'discovered'` listeners (see `on()`) as soon as it's seen.
    ///
    /// - Parameter options?: An object with any of:
    ///   - `seconds` (number, default `10`): how long to scan for, counted from when Bluetooth is ready (e.g. after the permission prompt is answered)
    ///   - `services` (string[]): only report peripherals advertising one of these service UUIDs
    ///   - `allowDuplicates` (boolean, default `false`): deliver every advertisement to `'discovered'` listeners, not just the first from each peripheral, e.g. to follow signal strength
    /// - Returns: {Promise<HSBluetoothPeripheral[]>} A Promise resolving to the peripherals found when the scan ends, or when `stopScan()` is called. Rejects if a scan is already running, the options are invalid, or Bluetooth is unavailable
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan({ seconds: 5 })
    /// nearby.forEach(p => console.log((p.name ?? p.identifier) + " " + p.rssi + " dBm"))
    ///
    /// const heartStraps = await hs.bluetooth.scan({ services: ["180D"] })
    /// ```
    @objc func scan(_ options: [String: Any]?) -> JSPromise?

    /// Ends a scan started by `scan()` early. Its Promise resolves with the peripherals found so far.
    /// - Example:
    /// ```js
    /// hs.bluetooth.once('discovered', p => hs.bluetooth.stopScan())
    /// const [first] = await hs.bluetooth.scan({ seconds: 30 })
    /// ```
    @objc func stopScan()

    /// Searches for discoverable classic Bluetooth devices nearby, such as headphones in pairing mode. Only one search can run at a time.
    ///
    /// This interrupts the audio of connected Bluetooth headphones while it runs.
    /// - Parameter options?: An object with `seconds` (number, default `10`, at most `255`): how long to search for
    /// - Returns: {Promise<HSBluetoothDevice[]>} A Promise resolving to the devices found when the search ends, or when `stopInquiry()` is called. Rejects if a search is already running, the options are invalid, or the search fails
    /// - Example:
    /// ```js
    /// const found = await hs.bluetooth.inquiry({ seconds: 10 })
    /// found.forEach(d => console.log(d.name + " " + d.address))
    /// ```
    @objc func inquiry(_ options: [String: Any]?) -> JSPromise?

    /// Ends a search started by `inquiry()` early. Its Promise resolves with the devices found so far.
    /// - Example:
    /// ```js
    /// hs.bluetooth.stopInquiry()
    /// ```
    @objc func stopInquiry()

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.bluetooth.js
    /// SKIP_DOCS
    @objc(_addWatcher::) func _addWatcher(_ event: String, _ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher(_ event: String)
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var _makeObjectEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSBluetoothEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.bluetooth.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Implementation

/// Events emitted by hs.bluetooth's module-level watcher
nonisolated enum HSBluetoothEvent: String, HSEventName {
    case connected, disconnected, powerChanged, discovered
}

@_documentation(visibility: private)
@MainActor
@objc class HSBluetoothModule: NSObject, HSModuleAPI, HSBluetoothModuleAPI {
    var moduleName = "hs.bluetooth"
    let engineID: UUID

    /// Every object handed to JS, so the same device or peripheral is always the same object
    /// while it's alive
    let devices = HSObjectTracker<HSBluetoothDevice>()
    let peripherals = HSObjectTracker<HSBluetoothPeripheral>()

    // Module-level watcher
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _makeObjectEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSBluetoothEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var watcherCallbacks: [String: JSCallback] = [:]

    // IOBluetooth connect/disconnect notifications, shared by the module's watcher and every
    // device that has listeners
    private var connectNotification: IOBluetoothUserNotification?
    // One per connected device, keyed by address
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    // Devices that were already connected when the notifications started. IOBluetooth may replay
    // a connect notification for each of them, which isn't a new connection.
    private var connectedWhenWatchStarted: Set<String> = []

    // CoreBluetooth, created on first use (that's what shows the permission prompt), so internal
    // for the extension in HSBluetoothModule+CoreBluetooth.swift
    var central: CBCentralManager?
    let centralRequests = HSBluetoothRequests()
    var lastKnownPowered: Bool?
    /// What CoreBluetooth has told us about each BLE peripheral seen, keyed by identifier
    var peripheralRecords: [UUID: BluetoothPeripheralRecord] = [:]
    var activeScan: BluetoothScan?

    // Classic inquiry
    private var activeInquiry: BluetoothInquiry?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        endScan(nil, settlingPromise: false)
        endInquiry(nil, settlingPromise: false)
        for callback in watcherCallbacks.values {
            callback.detach(from: self)
        }
        watcherCallbacks.removeAll()
        devices.shutdown()
        peripherals.shutdown()
        stopClassicNotifications()
        shutdownCentral()
        _watcherEmitter = nil
        _makeObjectEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    // Deliberately doesn't touch Bluetooth: logging the module mustn't show the permission prompt
    @objc func toString() -> String {
        let activity = [activeScan == nil ? nil : "scanning", activeInquiry == nil ? nil : "inquiring"].compactMap { $0 }
        return "<\(moduleName)\(activity.isEmpty ? "" : ": " + activity.joined(separator: ", "))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc var powered: Bool {
        switch central?.state {
        case .poweredOn: return true
        case .poweredOff: return false
        default: return IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        }
    }

    @objc var isScanning: Bool { activeScan != nil }
    @objc var isInquiring: Bool { activeInquiry != nil }

    @objc func pairedDevices() -> [HSBluetoothDevice] {
        warnIfAccessDenied("hs.bluetooth.pairedDevices()")
        return Self.pairedIOBluetoothDevices().compactMap(device(for:))
    }

    @objc func connectedDevices() -> [HSBluetoothDevice] {
        warnIfAccessDenied("hs.bluetooth.connectedDevices()")
        return Self.pairedIOBluetoothDevices().filter { $0.isConnected() }.compactMap(device(for:))
    }

    @objc func device(_ address: String) -> HSBluetoothDevice? {
        guard let address = HSBluetoothAddress.normalize(address),
              let classic = IOBluetoothDevice(addressString: address),
              classic.isPaired() || classic.name != nil || classic.getLastInquiryUpdate() != nil else {
            return nil
        }
        return device(for: classic)
    }

    @objc func connectedPeripherals() -> [HSBluetoothPeripheral] {
        peripherals.allObjects.filter(\.isConnected)
    }

    @objc func peripheral(_ identifier: String) -> HSBluetoothPeripheral? {
        guard let uuid = UUID(uuidString: identifier) else { return nil }
        if let record = peripheralRecords[uuid] {
            return peripheral(for: record)
        }
        // Only if CoreBluetooth is already running: this lookup mustn't start it
        if let central, central.state == .poweredOn,
           let found = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            return peripheral(for: record(for: found))
        }
        return nil
    }

    /// IOBluetooth needs the same Bluetooth permission as CoreBluetooth, but without it simply
    /// reports nothing, so say why
    private func warnIfAccessDenied(_ caller: String) {
        switch CBManager.authorization {
        case .denied, .restricted:
            AKWarning("\(caller): Bluetooth access has not been allowed, so macOS reports no devices; see hs.permissions.requestBluetooth()")
        default:
            break
        }
    }

    // MARK: - Device and peripheral objects

    static func pairedIOBluetoothDevices() -> [IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    /// The object for a device macOS knows, reusing the existing one if JS still holds it. Nil if
    /// IOBluetooth has no address for it.
    func device(for classic: IOBluetoothDevice) -> HSBluetoothDevice? {
        guard let address = classic.addressString.flatMap(HSBluetoothAddress.normalize) else { return nil }
        return existingDevice(address: address) ?? makeDevice(IOBluetoothClassicDevice(classic), address: address)
    }

    /// Creates and tracks a device object. Internal so tests can make one with a fake device.
    func makeDevice(_ classic: any HSClassicBluetoothDevice, address: String) -> HSBluetoothDevice {
        let device = HSBluetoothDevice(module: self, tracker: devices, classic: classic, address: address)
        devices.add(device)
        return device
    }

    func existingDevice(address: String) -> HSBluetoothDevice? {
        devices.allObjects.first { $0.address == address }
    }

    /// The object for a BLE peripheral, reusing the existing one if JS still holds it. There is
    /// never more than one per peripheral, since each is the peripheral's delegate.
    func peripheral(for record: BluetoothPeripheralRecord) -> HSBluetoothPeripheral {
        if let existing = existingPeripheral(identifier: record.peripheral.identifier) { return existing }
        let peripheral = HSBluetoothPeripheral(module: self, tracker: peripherals, record: record)
        peripherals.add(peripheral)
        return peripheral
    }

    func existingPeripheral(identifier: UUID) -> HSBluetoothPeripheral? {
        peripherals.allObjects.first { $0.record.peripheral.identifier == identifier }
    }

    /// Makes the JS emitter for a device's or peripheral's on()/once(), via the factory in
    /// hs.bluetooth.js. Returns nil, having set `ctx.exception`, on failure.
    func makeObjectEmitter(for object: NSObject, in ctx: JSContext) -> JSValue? {
        guard let factory = _makeObjectEmitter, factory.isFunction else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.bluetooth: the watcher emitter factory is unavailable", in: ctx)
            return nil
        }
        let emitter = ctx.callCapturingException { factory.call(withArguments: [object]) }
        guard ctx.exception == nil, let emitter, emitter.isObject else {
            if ctx.exception == nil {
                ctx.exception = JSValue(newErrorFromMessage: "hs.bluetooth: failed to create a watcher emitter", in: ctx)
            }
            return nil
        }
        return emitter
    }

    // MARK: - Watcher

    @objc(_addWatcher::) func _addWatcher(_ event: String, _ listener: JSFunction) -> Bool {
        guard let kind = HSBluetoothEvent(rawValue: event) else {
            AKWarning("hs.bluetooth._addWatcher: unknown event '\(event)'")
            return false
        }
        guard watcherCallbacks[event] == nil else {
            AKWarning("hs.bluetooth._addWatcher: already watching '\(event)', refusing a second subscription")
            return false
        }
        if kind == .powerChanged {
            guard startPowerWatching() else { return false }
        }
        watcherCallbacks[event] = JSCallback(value: listener, owner: self)
        if kind == .connected || kind == .disconnected {
            warnIfAccessDenied("hs.bluetooth.on('\(event)')")
            updateClassicNotifications()
            guard isReceivingClassicNotifications else {
                AKError("hs.bluetooth._addWatcher: failed to register for Bluetooth connection notifications")
                watcherCallbacks.removeValue(forKey: event)?.detach(from: self)
                return false
            }
        }
        AKDebug("hs.bluetooth._addWatcher: started watching '\(event)'")
        return true
    }

    @objc func _removeWatcher(_ event: String) {
        guard let callback = watcherCallbacks.removeValue(forKey: event) else { return }
        callback.detach(from: self)
        updateClassicNotifications()
        AKDebug("hs.bluetooth._removeWatcher: stopped watching '\(event)'")
    }

    /// Whether anything is listening for an event
    func isWatching(_ event: HSBluetoothEvent) -> Bool {
        watcherCallbacks[event.rawValue] != nil
    }

    /// Delivers an event to the module's listeners
    func emit(_ event: HSBluetoothEvent, _ argument: Any) {
        _ = watcherCallbacks[event.rawValue]?.call(withArguments: [argument])
    }

    // MARK: - IOBluetooth connection notifications

    var isReceivingClassicNotifications: Bool { connectNotification != nil || isSimulatingClassicNotifications }

    /// Set by tests, which mustn't need Bluetooth access: the notifications are then only
    /// pretended to start, and events come from the test calling `deliverClassicEvent`
    var simulatesClassicNotifications = false
    private var isSimulatingClassicNotifications = false

    /// Starts or stops IOBluetooth's connect/disconnect notifications, so they run exactly while
    /// the module or some device has listeners for them
    func updateClassicNotifications() {
        let needed = isWatching(.connected) || isWatching(.disconnected) || devices.allObjects.contains(where: \.isWatching)
        if simulatesClassicNotifications {
            isSimulatingClassicNotifications = needed
            return
        }
        if needed && connectNotification == nil {
            startClassicNotifications()
        } else if !needed && connectNotification != nil {
            stopClassicNotifications()
        }
    }

    private func startClassicNotifications() {
        guard let notification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(classicDeviceConnected(_:device:))) else {
            AKError("hs.bluetooth: failed to register for connect notifications")
            return
        }
        connectNotification = notification
        // Devices already connected won't get a connect notification (or get a replayed one, see
        // classicDeviceConnected), so watch them for disconnects now
        for device in Self.pairedIOBluetoothDevices() where device.isConnected() {
            guard let address = device.addressString.flatMap(HSBluetoothAddress.normalize) else { continue }
            connectedWhenWatchStarted.insert(address)
            watchForDisconnect(device, address: address)
        }
        AKDebug("hs.bluetooth: started connection notifications")
    }

    private func stopClassicNotifications() {
        guard let connectNotification else { return }
        connectNotification.unregister()
        self.connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        connectedWhenWatchStarted.removeAll()
        AKDebug("hs.bluetooth: stopped connection notifications")
    }

    private func watchForDisconnect(_ device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(classicDeviceDisconnected(_:device:)))
    }

    // Both selectors hop to the main actor, so they can run after the notifications have been
    // stopped, or restarted. Each checks that its notification is still current first.

    @objc private nonisolated func classicDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let unsafeNotification = notification
        nonisolated(unsafe) let unsafeDevice = device
        onMain { module in
            let (notification, device) = unsafe (unsafeNotification, unsafeDevice)
            guard module.connectNotification === notification,
                  let address = device.addressString.flatMap(HSBluetoothAddress.normalize) else { return }
            // A device that was connected when the notifications started, and hasn't disconnected
            // since, can't be connecting now: this is IOBluetooth replaying its existing connection
            if module.connectedWhenWatchStarted.remove(address) != nil, module.disconnectNotifications[address] != nil {
                return
            }
            module.watchForDisconnect(device, address: address)
            module.deliverClassicEvent(.connected, address: address, device: device)
        }
    }

    @objc private nonisolated func classicDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let unsafeNotification = notification
        nonisolated(unsafe) let unsafeDevice = device
        onMain { module in
            let (notification, device) = unsafe (unsafeNotification, unsafeDevice)
            guard let address = device.addressString.flatMap(HSBluetoothAddress.normalize),
                  module.disconnectNotifications[address] === notification else { return }
            notification.unregister()
            module.disconnectNotifications[address] = nil
            module.connectedWhenWatchStarted.remove(address)
            module.deliverClassicEvent(.disconnected, address: address, device: device)
        }
    }

    /// Delivers a connection event for the device at `address` to its object's listeners and the
    /// module's. `device` is used to make the object if the module's listeners need one.
    func deliverClassicEvent(_ event: HSBluetoothEvent, address: String, device: IOBluetoothDevice?) {
        let object = existingDevice(address: address) ?? (isWatching(event) ? device.flatMap(self.device(for:)) : nil)
        object?.fire(event == .connected ? .connected : .disconnected)
        if let object, isWatching(event) {
            emit(event, object)
        }
    }

    // MARK: - Classic inquiry

    @objc func inquiry(_ options: [String: Any]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        func reject(_ message: String) -> JSPromise? {
            context.createRejectedPromise(with: "hs.bluetooth.inquiry(): \(message)")
        }
        guard activeInquiry == nil else { return reject("a search is already running") }
        let seconds = (options?["seconds"] as? NSNumber)?.doubleValue ?? 10
        guard seconds.isFinite, seconds > 0, seconds <= 255 else { return reject("seconds must be a number from 1 to 255") }
        warnIfAccessDenied("hs.bluetooth.inquiry()")

        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
            return reject("classic Bluetooth searching is unavailable")
        }
        inquiry.inquiryLength = UInt8(seconds.rounded(.up))
        inquiry.updateNewDeviceNames = true
        let status = inquiry.start()
        guard status == kIOReturnSuccess else {
            unsafe inquiry.delegate = nil
            return reject(HSBluetoothError.forIOReturn(status, "Starting the search").message)
        }
        return wrapAsyncInJSPromise(in: context) { [self] holder in
            activeInquiry = BluetoothInquiry(inquiry: inquiry, holder: holder)
            AKDebug("hs.bluetooth.inquiry(): searching for classic devices")
        }
    }

    @objc func stopInquiry() {
        endInquiry(nil)
    }

    /// Ends the active inquiry, resolving its Promise with what was found or rejecting it
    private func endInquiry(_ error: HSBluetoothError?, settlingPromise: Bool = true) {
        guard let active = activeInquiry else { return }
        activeInquiry = nil
        // The delegate is unretained, so clear it before this module can go away
        unsafe active.inquiry.delegate = nil
        active.inquiry.stop()
        guard settlingPromise else { return }
        if let error {
            active.holder.rejectWithMessage("hs.bluetooth.inquiry(): \(error.message)")
        } else {
            let found = (active.inquiry.foundDevices() as? [IOBluetoothDevice] ?? []).compactMap(device(for:))
            active.holder.resolveWith(found)
        }
    }

    /// IOBluetooth delivers its notifications and delegate calls on whatever thread its XPC
    /// connection to bluetoothd uses, not the main thread, so every one hops to the main actor
    /// before touching state.
    nonisolated func onMain(_ body: @escaping @MainActor (HSBluetoothModule) -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body(self) } }
    }
}

/// A search started by `hs.bluetooth.inquiry()`, until it resolves
@MainActor
final class BluetoothInquiry {
    let inquiry: IOBluetoothDeviceInquiry
    let holder: JSPromiseHolder

    init(inquiry: IOBluetoothDeviceInquiry, holder: JSPromiseHolder) {
        self.inquiry = inquiry
        self.holder = holder
    }
}

extension HSBluetoothModule: IOBluetoothDeviceInquiryDelegate {
    nonisolated func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        nonisolated(unsafe) let unsafeSender = sender
        onMain { module in
            let sender = unsafe unsafeSender
            // An inquiry stopped by endInquiry() has already been forgotten
            guard let sender, sender === module.activeInquiry?.inquiry else { return }
            if aborted {
                module.endInquiry(HSBluetoothError("the search was aborted"))
            } else if error != kIOReturnSuccess {
                module.endInquiry(HSBluetoothError.forIOReturn(error, "The search"))
            } else {
                module.endInquiry(nil)
            }
        }
    }
}
