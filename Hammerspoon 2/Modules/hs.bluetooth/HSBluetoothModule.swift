//
//  HSBluetoothModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOBluetooth
import CoreBluetooth

// MARK: - JavaScript API

/// Inspect, connect to and scan for Bluetooth devices, and watch them connect and disconnect.
///
/// Devices are `HSBluetoothDevice` objects, whether they are paired with this Mac or Bluetooth Low
/// Energy (BLE) peripherals found nearby, and offer battery levels, connection control and GATT
/// access through the same API.
///
/// ```javascript
/// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
///
/// hs.bluetooth.connectedDevices()
///     .filter(d => d.batteryLevel !== null)
///     .forEach(d => console.log(d.name + ": " + d.batteryLevel + "%"))
///
/// const nearby = await hs.bluetooth.scan({ seconds: 5 })
/// nearby.forEach(d => console.log((d.name ?? d.identifier) + " " + d.rssi + " dBm"))
///
/// hs.bluetooth.on('connected', d => console.log(d.name + " connected"))
/// hs.bluetooth.on('powerChanged', on => console.log("Bluetooth is " + (on ? "on" : "off")))
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

    /// Whether a scan started by `scan()` is running.
    /// - Example:
    /// ```js
    /// if (!hs.bluetooth.isScanning) hs.bluetooth.scan()
    /// ```
    @objc var isScanning: Bool { get }

    /// All devices paired with this Mac, connected or not.
    ///
    /// - Returns: An array of `HSBluetoothDevice` objects
    /// - Example:
    /// ```js
    /// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
    /// ```
    @objc func pairedDevices() -> [HSBluetoothDevice]

    /// All connected devices: paired devices macOS has connected, and BLE peripherals connected with `connect()`.
    ///
    /// - Returns: An array of `HSBluetoothDevice` objects
    /// - Example:
    /// ```js
    /// hs.bluetooth.connectedDevices().forEach(d => console.log(d.name + " is connected"))
    /// ```
    @objc func connectedDevices() -> [HSBluetoothDevice]

    /// Looks up a device by its address or identifier.
    ///
    /// - Parameter id: A Bluetooth address (`"a4-83-e7-12-34-56"` or `"A4:83:E7:12:34:56"`) of a device macOS knows, or the `identifier` of a BLE peripheral Hammerspoon has seen
    /// - Returns: The `HSBluetoothDevice`, or `null` if no such device is known
    /// - Example:
    /// ```js
    /// const keyboard = hs.bluetooth.device("a4-83-e7-12-34-56")
    /// if (keyboard) console.log(keyboard.name + " battery: " + keyboard.batteryLevel + "%")
    /// ```
    @objc func device(_ id: String) -> HSBluetoothDevice?

    /// Scans for devices nearby. Only one scan can run at a time.
    ///
    /// Each device found is also delivered to `'discovered'` listeners (see `on()`) as soon as it's seen.
    ///
    /// - Parameter options?: An object with any of:
    ///   - `seconds` (number, default `10`): how long to scan for
    ///   - `lowEnergy` (boolean, default `true`): look for BLE peripherals
    ///   - `classic` (boolean, default `false`): look for discoverable classic devices. This interrupts the audio of connected Bluetooth headphones while it runs, and only runs for up to 255 seconds
    ///   - `services` (string[]): only report BLE peripherals advertising one of these service UUIDs
    ///   - `allowDuplicates` (boolean, default `false`): deliver every advertisement to `'discovered'` listeners, not just the first from each device, e.g. to follow signal strength
    /// - Returns: {Promise<HSBluetoothDevice[]>} A Promise resolving to the devices found when the scan ends, or when `stopScan()` is called. Rejects if a scan is already running, the options are invalid, or Bluetooth is unavailable
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan({ seconds: 5 })
    /// nearby.forEach(d => console.log((d.name ?? d.identifier) + " " + d.rssi + " dBm"))
    ///
    /// const heartStraps = await hs.bluetooth.scan({ services: ["180D"] })
    /// ```
    @objc func scan(_ options: [String: Any]?) -> JSPromise?

    /// Ends a scan started by `scan()` early. Its Promise resolves with the devices found so far.
    /// - Example:
    /// ```js
    /// hs.bluetooth.once('discovered', d => hs.bluetooth.stopScan())
    /// const [first] = await hs.bluetooth.scan({ seconds: 30 })
    /// ```
    @objc func stopScan()

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.bluetooth.js
    /// SKIP_DOCS
    @objc(_addWatcher::) func _addWatcher(_ event: String, _ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher(_ event: String)
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var _makeDeviceEmitter: JSFunction? { get set }

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

    /// Every device handed to JS, so the same device is always the same object while it's alive
    let devices = HSObjectTracker<HSBluetoothDevice>()

    // Module-level watcher
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _makeDeviceEmitter: JSFunction? = nil
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
    var readyWaiters: [CheckedContinuation<Void, Error>] = []
    var lastKnownPowered: Bool?
    /// What CoreBluetooth has told us about each BLE peripheral seen, keyed by identifier
    var peripheralRecords: [UUID: BluetoothPeripheralRecord] = [:]

    // Scanning
    var activeScan: BluetoothScan?
    var inquiry: IOBluetoothDeviceInquiry?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        endScan(nil, settlingPromise: false)
        for callback in watcherCallbacks.values {
            callback.detach(from: self)
        }
        watcherCallbacks.removeAll()
        devices.shutdown()
        stopClassicNotifications()
        shutdownCentral()
        _watcherEmitter = nil
        _makeDeviceEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    // Deliberately doesn't touch Bluetooth: logging the module mustn't show the permission prompt
    @objc func toString() -> String {
        "<\(moduleName)\(activeScan == nil ? "" : ": scanning")>"
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

    @objc func pairedDevices() -> [HSBluetoothDevice] {
        Self.pairedIOBluetoothDevices().map(device(for:))
    }

    @objc func connectedDevices() -> [HSBluetoothDevice] {
        let paired = Self.pairedIOBluetoothDevices().filter { $0.isConnected() }.map(device(for:))
        let lowEnergy = devices.allObjects.filter { $0.classic == nil && $0.isConnected }
        return paired + lowEnergy
    }

    @objc func device(_ id: String) -> HSBluetoothDevice? {
        if let address = HSBluetoothAddress.normalize(id) {
            guard let classic = IOBluetoothDevice(addressString: address),
                  classic.isPaired() || classic.name != nil || classic.getLastInquiryUpdate() != nil else {
                return nil
            }
            return device(for: classic)
        }
        if let uuid = UUID(uuidString: id) {
            if let record = peripheralRecords[uuid] {
                return device(for: record)
            }
            // Only if CoreBluetooth is already running: this lookup mustn't start it
            if let central, central.state == .poweredOn,
               let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first {
                return device(for: record(for: peripheral))
            }
        }
        return nil
    }

    // MARK: - Device objects

    static func pairedIOBluetoothDevices() -> [IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    /// The object for a device macOS knows, reusing the existing one if JS still holds it
    func device(for classic: IOBluetoothDevice) -> HSBluetoothDevice {
        if let address = classic.addressString.flatMap(HSBluetoothAddress.normalize),
           let existing = existingDevice(address: address) {
            return existing
        }
        return makeDevice(classic: classic, record: nil)
    }

    /// The object for a BLE peripheral, reusing the existing one if JS still holds it
    func device(for record: BluetoothPeripheralRecord) -> HSBluetoothDevice {
        existingDevice(identifier: record.peripheral.identifier) ?? makeDevice(classic: nil, record: record)
    }

    /// Creates and tracks a device object. Internal so tests can make one without any Bluetooth hardware.
    func makeDevice(classic: IOBluetoothDevice?, record: BluetoothPeripheralRecord?) -> HSBluetoothDevice {
        let device = HSBluetoothDevice(module: self, tracker: devices, classic: classic, record: record)
        devices.add(device)
        return device
    }

    func existingDevice(address: String) -> HSBluetoothDevice? {
        devices.allObjects.first { $0.address == address }
    }

    func existingDevice(identifier: UUID) -> HSBluetoothDevice? {
        devices.allObjects.first { $0.record?.peripheral.identifier == identifier }
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

    /// Delivers a connection event for a BLE peripheral Hammerspoon connected to itself
    func deliverLowEnergyEvent(_ event: HSBluetoothEvent, _ device: HSBluetoothDevice) {
        emit(event, device)
    }

    // MARK: - IOBluetooth connection notifications

    var isReceivingClassicNotifications: Bool { connectNotification != nil }

    /// Starts or stops IOBluetooth's connect/disconnect notifications, so they run exactly while
    /// the module or some device has listeners for them
    func updateClassicNotifications() {
        let needed = isWatching(.connected) || isWatching(.disconnected)
            || devices.allObjects.contains { $0.isWatching && $0.classic != nil }
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
            module.deliverClassicEvent(.connected, device, address: address)
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
            module.deliverClassicEvent(.disconnected, device, address: address)
        }
    }

    private func deliverClassicEvent(_ event: HSBluetoothEvent, _ classic: IOBluetoothDevice, address: String) {
        // Only make a device object if the module's listeners need one
        let object = isWatching(event) ? device(for: classic) : existingDevice(address: address)
        object?.fire(event == .connected ? .connected : .disconnected)
        if let object, isWatching(event) {
            emit(event, object)
        }
    }

    /// IOBluetooth delivers its notifications and delegate calls on whatever thread its XPC
    /// connection to bluetoothd uses, not the main thread, so every one hops to the main actor
    /// before touching state.
    nonisolated func onMain(_ body: @escaping @MainActor (HSBluetoothModule) -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body(self) } }
    }
}
