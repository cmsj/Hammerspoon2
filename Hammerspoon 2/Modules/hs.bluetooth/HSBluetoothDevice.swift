//
//  HSBluetoothDevice.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import IOBluetooth
import CoreBluetooth

// MARK: - JavaScript API

/// A Bluetooth device: one paired with this Mac, or one found nearby by `hs.bluetooth.scan()`.
///
/// Obtain devices from the ``hs.bluetooth`` module; do not instantiate them directly. The same
/// device is returned as the same object for as long as you hold on to it.
///
/// A device macOS knows from pairing has an `address`. A Bluetooth Low Energy (BLE) peripheral
/// found by a scan has an `identifier` instead: macOS doesn't reveal BLE addresses, and the
/// identifier is a UUID that is only stable on this Mac. A paired device that also speaks BLE gains
/// an `identifier` the first time you use one of the GATT methods on it while it's connected.
///
/// ## Battery levels
///
/// ```javascript
/// hs.bluetooth.connectedDevices().forEach(d => {
///     if (d.batteryLevel !== null) console.log(d.name + ": " + d.batteryLevel + "%")
/// })
/// ```
///
/// ## Reading and writing GATT characteristics
///
/// ```javascript
/// const [sensor] = await hs.bluetooth.scan({ seconds: 5, services: ["181A"] })
/// await sensor.connect()
/// const bytes = await sensor.readValue("181A", "2A6E")
/// await sensor.subscribe("181A", "2A6E")
/// sensor.on("value", (service, characteristic, value) => console.log(characteristic + ": " + value))
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

    /// The device's Bluetooth address (`xx-xx-xx-xx-xx-xx`), or `null` for a BLE peripheral, whose address macOS doesn't reveal.
    /// - Example:
    /// ```js
    /// console.log(hs.bluetooth.pairedDevices()[0].address)
    /// ```
    @objc var address: String? { get }

    /// The CoreBluetooth identifier (a UUID) of the device's BLE side, or `null` if Hammerspoon hasn't talked to it over BLE. It is stable on this Mac, but differs between Macs.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.forEach(d => console.log(d.identifier))
    /// ```
    @objc var identifier: String? { get }

    /// Whether the device is paired with this Mac.
    /// - Example:
    /// ```js
    /// console.log(device.isPaired)
    /// ```
    @objc var isPaired: Bool { get }

    /// Whether the device is currently connected, either to macOS or to Hammerspoon over BLE.
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

    /// The device's raw Bluetooth Class of Device value, or `null` for a BLE peripheral.
    /// - Example:
    /// ```js
    /// console.log(device.classOfDevice)
    /// ```
    @objc var classOfDevice: NSNumber? { get }

    /// The major device class (e.g. `5` for peripherals such as keyboards and mice), or `null` for a BLE peripheral.
    /// - Example:
    /// ```js
    /// const peripherals = hs.bluetooth.pairedDevices().filter(d => d.majorClass === 5)
    /// ```
    @objc var majorClass: NSNumber? { get }

    /// The minor device class, whose meaning depends on `majorClass`, or `null` for a BLE peripheral.
    /// - Example:
    /// ```js
    /// console.log(device.minorClass)
    /// ```
    @objc var minorClass: NSNumber? { get }

    /// The major service classes the device advertises, as a bitmask, or `null` for a BLE peripheral.
    /// - Example:
    /// ```js
    /// console.log(device.serviceClasses)
    /// ```
    @objc var serviceClasses: NSNumber? { get }

    /// The names of the device's classic Bluetooth (SDP) services, e.g. `["Audio Sink", "AVRCP Controller"]`. Empty for a BLE peripheral; use `discoverServices()` for its GATT services.
    /// - Example:
    /// ```js
    /// console.log(device.serviceNames.join(", "))
    /// ```
    @objc var serviceNames: [String] { get }

    /// The last known signal strength in dBm, or `null` if there is none.
    ///
    /// It is updated by `hs.bluetooth.scan()` and `readRSSI()`. Call `readRSSI()` for a fresh reading from a connected device.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.forEach(d => console.log(d.name + " " + d.rssi + " dBm"))
    /// ```
    @objc var rssi: NSNumber? { get }

    /// When the device was last seen, in Unix seconds: in a scan, or when it was last connected. `null` if unknown.
    /// - Example:
    /// ```js
    /// console.log(new Date(device.lastSeen * 1000))
    /// ```
    @objc var lastSeen: NSNumber? { get }

    /// The device's last advertisement, if it was found by a BLE scan, otherwise `null`.
    ///
    /// The object has `localName` (string or `null`), `isConnectable` (boolean or `null`), `txPower` (number or `null`), `serviceUUIDs` (string[]), `manufacturerData` (Uint8Array or `null`) and `serviceData` (an object mapping service UUIDs to Uint8Array).
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.filter(d => d.advertisement.manufacturerData)
    ///       .forEach(d => console.log(d.identifier + " " + d.advertisement.manufacturerData))
    /// ```
    @objc var advertisement: JSValue? { get }

    /// The device's battery level as a percentage, or `null` if unknown.
    ///
    /// For Apple's Magic accessories this comes from the system, and for AirPods and Beats from what macOS last heard from them. For earbuds it is the lower of the two buds; see `batteryLevels` for each one. For other BLE devices it is the last value read by `readBatteryLevel()`.
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

    /// Reads the device's battery level, asking the device itself over BLE when macOS doesn't already know it.
    ///
    /// The device must be connected for the BLE read. Paired devices that macOS has connected are read without any extra steps; a BLE peripheral needs `connect()` first.
    /// - Returns: {Promise<number | null>} A Promise resolving to the battery percentage, or `null` if the device doesn't report one
    /// - Example:
    /// ```js
    /// const level = await device.readBatteryLevel()
    /// console.log(device.name + ": " + level + "%")
    /// ```
    @objc func readBatteryLevel() -> JSPromise?

    /// Connects to the device.
    ///
    /// A paired device is connected the same way macOS would, e.g. so headphones become available as an audio device. A BLE peripheral is connected to Hammerspoon, so its GATT services can be used; it stays connected until `disconnect()` is called, even if you drop your reference to it.
    /// - Returns: {Promise<HSBluetoothDevice>} A Promise resolving to this device once it's connected, or rejecting if the connection fails or takes longer than 20 seconds
    /// - Example:
    /// ```js
    /// const headphones = hs.bluetooth.pairedDevices().find(d => d.name === "My Headphones")
    /// await headphones.connect()
    /// ```
    @objc func connect() -> JSPromise?

    /// Disconnects from the device.
    ///
    /// A paired device is disconnected from the Mac. A BLE peripheral is disconnected from Hammerspoon; if macOS has its own connection to it, that connection stays.
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

    /// Discovers the GATT services of a connected BLE device.
    /// - Returns: {Promise<string[]>} A Promise resolving to the UUIDs of the device's services, e.g. `["180A", "180F"]`
    /// - Example:
    /// ```js
    /// await sensor.connect()
    /// console.log((await sensor.discoverServices()).join(", "))
    /// ```
    @objc func discoverServices() -> JSPromise?

    /// Discovers the characteristics of one of a connected BLE device's GATT services.
    /// - Parameter service: The service UUID: 16-bit (`"180F"`), 32-bit, or 128-bit
    /// - Returns: {Promise<{uuid: string, properties: string[], isNotifying: boolean}[]>} A Promise resolving to the service's characteristics. `properties` lists what each supports: `"read"`, `"write"`, `"writeWithoutResponse"`, `"notify"`, `"indicate"`, `"broadcast"`, `"authenticatedSignedWrites"` and `"extendedProperties"`
    /// - Example:
    /// ```js
    /// const chars = await sensor.discoverCharacteristics("180F")
    /// chars.forEach(c => console.log(c.uuid + ": " + c.properties.join(", ")))
    /// ```
    @objc func discoverCharacteristics(_ service: String) -> JSPromise?

    /// Reads the value of a GATT characteristic.
    ///
    /// The service and characteristic are discovered first if needed. A paired device that macOS has connected can be read directly; a BLE peripheral needs `connect()` first.
    /// - Parameters:
    ///   - service: The service UUID, e.g. `"180F"`
    ///   - characteristic: The characteristic UUID, e.g. `"2A19"`
    /// - Returns: {Promise<Uint8Array>} A Promise resolving to the characteristic's value
    /// - Example:
    /// ```js
    /// const value = await device.readValue("180F", "2A19")
    /// console.log("Battery: " + value[0] + "%")
    /// ```
    @objc func readValue(_ service: String, _ characteristic: String) -> JSPromise?

    /// Writes the value of a GATT characteristic.
    /// - Parameters:
    ///   - service: The service UUID
    ///   - characteristic: The characteristic UUID
    ///   - value: {Uint8Array | ArrayBuffer | number[] | string} The bytes to write. A string is written as UTF-8
    ///   - withoutResponse?: If `true`, write without asking the device to confirm it. Defaults to `false`
    /// - Returns: {Promise<void>} A Promise resolving once the device has accepted the write (or, without a response, once it has been sent)
    /// - Example:
    /// ```js
    /// await lamp.writeValue("FFE5", "FFE9", [0x56, 0xFF, 0x00, 0x00, 0x00, 0xF0, 0xAA])
    /// ```
    @objc func writeValue(_ service: String, _ characteristic: String, _ value: JSValue, _ withoutResponse: Bool) -> JSPromise?

    /// Subscribes to a GATT characteristic, so each new value is delivered as a `"value"` event (see `on()`).
    /// - Parameters:
    ///   - service: The service UUID
    ///   - characteristic: The characteristic UUID, which must support `"notify"` or `"indicate"`
    /// - Returns: {Promise<void>} A Promise resolving once the device has started sending values
    /// - Example:
    /// ```js
    /// heartStrap.on("value", (service, characteristic, value) => console.log("Heart rate: " + value[1]))
    /// await heartStrap.subscribe("180D", "2A37")
    /// ```
    @objc func subscribe(_ service: String, _ characteristic: String) -> JSPromise?

    /// Stops a subscription started by `subscribe()`.
    /// - Parameters:
    ///   - service: The service UUID
    ///   - characteristic: The characteristic UUID
    /// - Returns: {Promise<void>} A Promise resolving once the device has stopped sending values
    /// - Example:
    /// ```js
    /// await heartStrap.unsubscribe("180D", "2A37")
    /// ```
    @objc func unsubscribe(_ service: String, _ characteristic: String) -> JSPromise?

    /// Register a listener for this device's events.
    ///
    /// Listeners receive:
    ///  - `"connected"`, `"disconnected"`: no arguments
    ///  - `"value"`: `(service, characteristic, value)`, the UUIDs and the new value (a Uint8Array) of a characteristic you subscribed to. While subscribed, values fetched by `readValue()` arrive here too
    ///
    /// A device with listeners keeps working after you drop your reference to it.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "value"} The event to listen for
    ///   - listener: {(service?: string, characteristic?: string, value?: Uint8Array) => void} Called when the event occurs
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
    ///   - event: {"connected" | "disconnected" | "value"} The event the listener was registered for
    ///   - listener: The function originally passed to `on`
    /// - Example:
    /// ```js
    /// keyboard.off('disconnected', myListener)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Register a listener that fires at most once for one of this device's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "value"} The event to listen for
    ///   - listener: {(service?: string, characteristic?: string, value?: Uint8Array) => void} Called once, then automatically removed
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
    /// - Returns: An object with the device's `name`, `address`, `identifier`, `isPaired`, `isConnected`, `rssi`, `batteryLevel`, `batteryLevels`, `majorClass` and `minorClass`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.bluetooth.pairedDevices(), null, 2))
    /// ```
    @objc func toJSON() -> [String: Any]
}

// MARK: - Implementation

/// Events emitted by a single HSBluetoothDevice's watcher
nonisolated enum HSBluetoothDeviceEvent: String, HSEventName {
    case connected, disconnected, value
}

/// What CoreBluetooth has told us about one BLE peripheral. The module keeps one per peripheral
/// it has seen, so the latest advertisement and readings survive the device object being
/// garbage collected and recreated.
final class BluetoothPeripheralRecord: NSObject, CBPeripheralDelegate {
    struct Advertisement {
        var localName: String?
        var isConnectable: Bool?
        var txPower: Int?
        var serviceUUIDs: [String] = []
        var manufacturerData: Data?
        var serviceData: [String: Data] = [:]

        init(_ data: [String: Any]) {
            localName = data[CBAdvertisementDataLocalNameKey] as? String
            isConnectable = (data[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
            txPower = (data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
            serviceUUIDs = (data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
            manufacturerData = data[CBAdvertisementDataManufacturerDataKey] as? Data
            for (uuid, value) in data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:] {
                serviceData[uuid.uuidString] = value
            }
        }
    }

    let peripheral: CBPeripheral
    var advertisement: Advertisement?
    var rssi: Int?
    var lastSeen: Date?
    var batteryLevel: Int?

    /// The device objects using this peripheral. Usually one, but a scan can make an object for
    /// a paired device's BLE side before `pairedDevices()` makes the paired one, so every
    /// CoreBluetooth callback goes to each of them.
    private let owners = NSHashTable<HSBluetoothDevice>.weakObjects()

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func addOwner(_ device: HSBluetoothDevice) { owners.add(device) }
    func removeOwner(_ device: HSBluetoothDevice) { owners.remove(device) }
    var allOwners: [HSBluetoothDevice] { owners.allObjects }

    // MARK: - CBPeripheralDelegate (delivered on the main queue, see HSBluetoothModule.makeCentral)

    private nonisolated func forEachOwner(_ body: (HSBluetoothDevice) -> Void) {
        MainActor.assumeIsolated { allOwners }.forEach(body)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didDiscoverServices: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didUpdateValueFor: characteristic, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didWriteValueFor: characteristic, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        forEachOwner { $0.peripheral(peripheral, didReadRSSI: RSSI, error: error) }
    }
}

@_documentation(visibility: private)
@MainActor
@objc class HSBluetoothDevice: NSObject, HSBluetoothDeviceAPI, HSTrackedObject {
    @objc var typeName = "HSBluetoothDevice"

    private weak var module: HSBluetoothModule?
    private weak var tracker: HSObjectTracker<HSBluetoothDevice>?

    /// The device as macOS knows it from pairing (or a classic inquiry), if it does
    let classic: IOBluetoothDevice?
    /// The device's BLE side, once Hammerspoon has seen it through CoreBluetooth
    private(set) var record: BluetoothPeripheralRecord? {
        didSet {
            oldValue?.removeOwner(self)
            record?.addOwner(self)
        }
    }

    /// How Hammerspoon holds a CoreBluetooth connection to the peripheral, if it does
    private enum CBConnection {
        /// Opened by `connect()`. This is real activity: the device stays connected until
        /// `disconnect()`, so the object is kept alive.
        case explicit
        /// Opened to use GATT on a device macOS has already connected. It rides on the system's
        /// own connection, so dropping it has no visible effect and doesn't keep the object alive.
        case attached
    }
    private var cbConnection: CBConnection? {
        didSet { updateActivity() }
    }
    private var pendingConnection: CBConnection?

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

    /// Set by destroy(), after which no Promise is settled: the JSContext is going away
    private var isDestroyed = false

    init(module: HSBluetoothModule, tracker: HSObjectTracker<HSBluetoothDevice>,
         classic: IOBluetoothDevice?, record: BluetoothPeripheralRecord?) {
        self.module = module
        self.tracker = tracker
        self.classic = classic
        self.record = record
        super.init()
        record?.addOwner(self)
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of HSBluetoothDevice: \(name ?? "unnamed")")
    }

    func destroy() {
        isDestroyed = true
        _removeWatcher()
        failAllWaiters(HSBluetoothError("Hammerspoon is shutting down"))
        record?.removeOwner(self)
        // Another object for the same device may still be using the connection
        if holdsConnection, let record, !record.allOwners.contains(where: \.holdsConnection) {
            module?.existingCentral?.cancelPeripheralConnection(record.peripheral)
        }
        pendingConnection = nil
        cbConnection = nil
    }

    /// Whether this object has opened, or is opening, a CoreBluetooth connection to the peripheral
    var holdsConnection: Bool { cbConnection != nil || pendingConnection != nil }

    private func updateActivity() {
        let held = cbConnection == .explicit || isWatching
        tracker?.setActive(self, held || operations > 0, finishesOnItsOwn: !held)
    }

    @objc func toString() -> String {
        "<\(typeName): \(name ?? "unnamed") (\(address ?? identifier ?? "unknown"))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Identity

    @objc var name: String? {
        classic?.name ?? record?.peripheral.name ?? record?.advertisement?.localName
    }

    @objc var address: String? {
        classic?.addressString.flatMap(HSBluetoothAddress.normalize)
    }

    @objc var identifier: String? {
        record?.peripheral.identifier.uuidString
    }

    /// Attaches the BLE side of a paired device, once it has been found
    func attach(_ record: BluetoothPeripheralRecord) {
        guard self.record == nil else { return }
        self.record = record
    }

    // MARK: - State

    @objc var isPaired: Bool { classic?.isPaired() ?? false }

    @objc var isConnected: Bool {
        (classic?.isConnected() ?? false) || record?.peripheral.state == .connected
    }

    @objc var isFavorite: Bool { classic?.isFavorite() ?? false }

    @objc var classOfDevice: NSNumber? { classic.map { NSNumber(value: $0.classOfDevice) } }
    @objc var majorClass: NSNumber? { classic.map { NSNumber(value: $0.deviceClassMajor) } }
    @objc var minorClass: NSNumber? { classic.map { NSNumber(value: $0.deviceClassMinor) } }
    @objc var serviceClasses: NSNumber? { classic.map { NSNumber(value: $0.serviceClassMajor) } }

    @objc var serviceNames: [String] {
        (classic?.services as? [IOBluetoothSDPServiceRecord] ?? []).compactMap { $0.getServiceName() }
    }

    @objc var rssi: NSNumber? {
        if let rssi = record?.rssi { return NSNumber(value: rssi) }
        // IOBluetooth caches a reading for classic devices found by an inquiry, and reports 0 or
        // +127 when it has none
        guard let rssi = classic?.rssi(), rssi != 0, rssi != 127 else { return nil }
        return NSNumber(value: rssi)
    }

    @objc var lastSeen: NSNumber? {
        let date = [record?.lastSeen, classic?.recentAccessDate(), classic?.getLastInquiryUpdate()]
            .compactMap { $0 }
            .max()
        return date.map { NSNumber(value: $0.timeIntervalSince1970) }
    }

    @objc var advertisement: JSValue? {
        guard let ad = record?.advertisement, let context = JSContext.current() else { return nil }
        let object = JSValue(newObjectIn: context)
        func orNull(_ value: Any?) -> Any { value ?? JSValue(nullIn: context) as Any }
        object?.setValue(orNull(ad.localName), forProperty: "localName")
        object?.setValue(orNull(ad.isConnectable), forProperty: "isConnectable")
        object?.setValue(orNull(ad.txPower), forProperty: "txPower")
        object?.setValue(ad.serviceUUIDs, forProperty: "serviceUUIDs")
        object?.setValue(orNull(ad.manufacturerData.flatMap { context.makeUint8Array($0) }), forProperty: "manufacturerData")
        let serviceData = JSValue(newObjectIn: context)
        for (uuid, data) in ad.serviceData {
            serviceData?.setValue(orNull(context.makeUint8Array(data)), forProperty: uuid)
        }
        object?.setValue(serviceData, forProperty: "serviceData")
        return object
    }

    private var systemBatteryLevels: HSBluetoothBatteryLevels? {
        classic.map(HSBluetoothBatteryLevels.read)
    }

    @objc var batteryLevel: NSNumber? {
        (systemBatteryLevels?.overall ?? record?.batteryLevel).map { NSNumber(value: $0) }
    }

    @objc var batteryLevels: [String: Int]? {
        systemBatteryLevels?.components
    }

    @objc func toJSON() -> [String: Any] {
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        return [
            "name": orNull(name),
            "address": orNull(address),
            "identifier": orNull(identifier),
            "isPaired": isPaired,
            "isConnected": isConnected,
            "rssi": orNull(rssi),
            "batteryLevel": orNull(batteryLevel),
            "batteryLevels": orNull(batteryLevels),
            "majorClass": orNull(majorClass),
            "minorClass": orNull(minorClass),
        ]
    }

    // MARK: - Operations

    /// Runs a JS-facing asynchronous operation, settling its Promise with the result. The object
    /// stays alive (active in its tracker) until the operation finishes.
    private func perform(_ method: String, _ body: @escaping @MainActor (JSContext) async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return wrapAsyncInJSPromise(in: context) { [self] holder in
            operations += 1
            Task {
                defer { operations -= 1 }
                do {
                    let result = try await body(context)
                    if !isDestroyed { holder.resolveWith(result) }
                } catch {
                    if !isDestroyed { holder.rejectWithMessage("hs.bluetooth device.\(method)(): \(error.localizedDescription)") }
                }
            }
        }
    }

    @objc func readBatteryLevel() -> JSPromise? {
        perform("readBatteryLevel") { _ in
            if let level = self.systemBatteryLevels?.overall { return level }
            guard self.canUseGATT else { return self.record?.batteryLevel }
            do {
                let level = try await self.characteristic(HSBluetoothUUID.batteryService, HSBluetoothUUID.batteryLevel)
                try await self.read(level)
                return self.record?.batteryLevel
            } catch {
                // A device without a battery service simply has no level to report
                AKDebug("hs.bluetooth: no BLE battery level for \(self.toString()): \(error.localizedDescription)")
                return self.record?.batteryLevel
            }
        }
    }

    @objc func connect() -> JSPromise? {
        perform("connect") { _ in
            if let classic = self.classic {
                try await self.connectClassic(classic)
            } else if let record = self.record {
                try await self.connectLE(record, as: .explicit)
            } else {
                throw HSBluetoothError("this device can't be connected to")
            }
            return self
        }
    }

    @objc func disconnect() -> JSPromise? {
        perform("disconnect") { _ in
            if let classic = self.classic {
                // Drop Hammerspoon's own BLE attachment, then the system's connection
                if let record = self.record, self.cbConnection != nil {
                    self.module?.existingCentral?.cancelPeripheralConnection(record.peripheral)
                }
                if classic.isConnected() {
                    let status = classic.closeConnection()
                    guard status == kIOReturnSuccess else { throw HSBluetoothError.forIOReturn(status, "Closing the connection") }
                }
            } else if let record = self.record, record.peripheral.state != .disconnected {
                let central = try await self.requireCentral()
                try await self.wait(for: Key.disconnect) {
                    central.cancelPeripheralConnection(record.peripheral)
                }
            }
            return self
        }
    }

    @objc func readRSSI() -> JSPromise? {
        perform("readRSSI") { _ in
            if let classic = self.classic, classic.isConnected() {
                let rssi = classic.rawRSSI()
                guard rssi != 127 else { throw HSBluetoothError("the device has no signal strength reading") }
                return Int(rssi)
            }
            guard let record = self.record, self.cbConnection != nil else {
                throw HSBluetoothError("the device is not connected, call connect() first")
            }
            try await self.wait(for: Key.rssi) { record.peripheral.readRSSI() }
            return record.rssi
        }
    }

    @objc func discoverServices() -> JSPromise? {
        perform("discoverServices") { _ in
            let peripheral = try await self.gattPeripheral()
            try await self.wait(for: Key.services) { peripheral.discoverServices(nil) }
            return (peripheral.services ?? []).map(\.uuid.uuidString)
        }
    }

    @objc func discoverCharacteristics(_ service: String) -> JSPromise? {
        perform("discoverCharacteristics") { _ in
            let uuid = try Self.parseUUID(service)
            let peripheral = try await self.gattPeripheral()
            let found = try await self.service(uuid, on: peripheral)
            try await self.wait(for: Key.characteristics(found)) { peripheral.discoverCharacteristics(nil, for: found) }
            return (found.characteristics ?? []).map { characteristic -> [String: Any] in
                [
                    "uuid": characteristic.uuid.uuidString,
                    "properties": characteristic.properties.names,
                    "isNotifying": characteristic.isNotifying,
                ]
            }
        }
    }

    @objc func readValue(_ service: String, _ characteristic: String) -> JSPromise? {
        perform("readValue") { context in
            let found = try await self.characteristic(try Self.parseUUID(service), try Self.parseUUID(characteristic))
            try await self.read(found)
            return context.makeUint8Array(found.value ?? Data())
        }
    }

    @objc func writeValue(_ service: String, _ characteristic: String, _ value: JSValue, _ withoutResponse: Bool) -> JSPromise? {
        // Converted now, while the value is certainly still what the caller passed
        let bytes = Self.bytes(from: value)
        return perform("writeValue") { _ in
            guard let bytes else {
                throw HSBluetoothError("value must be a Uint8Array, an ArrayBuffer, an array of numbers from 0 to 255, or a string")
            }
            let found = try await self.characteristic(try Self.parseUUID(service), try Self.parseUUID(characteristic))
            if withoutResponse {
                try Self.connectedPeripheral(of: found).writeValue(bytes, for: found, type: .withoutResponse)
            } else {
                try await self.serially(Key.write(found)) {
                    let peripheral = try Self.connectedPeripheral(of: found)
                    try await self.wait(for: Key.write(found)) {
                        peripheral.writeValue(bytes, for: found, type: .withResponse)
                    }
                }
            }
            return nil
        }
    }

    @objc func subscribe(_ service: String, _ characteristic: String) -> JSPromise? {
        perform("subscribe") { _ in
            try await self.setNotifying(true, service, characteristic)
            return nil
        }
    }

    @objc func unsubscribe(_ service: String, _ characteristic: String) -> JSPromise? {
        perform("unsubscribe") { _ in
            try await self.setNotifying(false, service, characteristic)
            return nil
        }
    }

    // MARK: - Connecting

    private func connectClassic(_ classic: IOBluetoothDevice) async throws {
        guard !classic.isConnected() else { return }
        try await wait(for: Key.connect, timeout: .seconds(20)) {
            // Completes asynchronously, in connectionComplete(_:status:)
            let status = classic.openConnection(self)
            guard status == kIOReturnSuccess else { throw HSBluetoothError.forIOReturn(status, "Opening the connection") }
        }
    }

    private func connectLE(_ record: BluetoothPeripheralRecord, as kind: CBConnection) async throws {
        let central = try await requireCentral()
        // Already connected through Hammerspoon's central, perhaps by another object for the same device
        if record.peripheral.state == .connected {
            if kind == .explicit || cbConnection == nil { cbConnection = kind }
            return
        }
        do {
            try await wait(for: Key.connect, timeout: .seconds(20)) {
                pendingConnection = kind
                central.connect(record.peripheral)
            }
        } catch {
            // A connection CoreBluetooth never completes stays pending forever unless cancelled
            if record.peripheral.state != .connected {
                pendingConnection = nil
                central.cancelPeripheralConnection(record.peripheral)
            }
            throw error
        }
    }

    private func requireCentral() async throws -> CBCentralManager {
        guard let module else { throw HSBluetoothError("hs.bluetooth is no longer loaded") }
        return try await module.readyCentral()
    }

    /// Called by IOBluetooth when `openConnection(_:)` finishes
    @objc(connectionComplete:status:) nonisolated func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.settle(Key.connect, status == kIOReturnSuccess ? nil : HSBluetoothError.forIOReturn(status, "Connecting"))
            }
        }
    }

    // The module's CoreBluetooth delegate routes these here

    func peripheralDidConnect() {
        cbConnection = pendingConnection ?? .attached
        pendingConnection = nil
        record?.lastSeen = Date()
        settle(Key.connect, nil)
        // A paired device's own connection events come from IOBluetooth
        if classic == nil {
            fire(.connected)
            module?.deliverLowEnergyEvent(.connected, self)
        }
    }

    func peripheralDidFailToConnect(_ error: Error?) {
        pendingConnection = nil
        settle(Key.connect, HSBluetoothError(error?.localizedDescription ?? "the connection failed"))
    }

    func peripheralDidDisconnect(_ error: Error?) {
        let wasConnected = cbConnection != nil
        cbConnection = nil
        pendingConnection = nil
        settle(Key.disconnect, nil)
        failAllWaiters(HSBluetoothError(error.map { "the device disconnected: \($0.localizedDescription)" } ?? "the device disconnected"))
        if wasConnected && classic == nil {
            fire(.disconnected)
            module?.deliverLowEnergyEvent(.disconnected, self)
        }
    }

    // MARK: - GATT

    /// Whether GATT operations can work right now, without the user connecting first
    private var canUseGATT: Bool {
        cbConnection != nil || (classic?.isConnected() ?? false)
    }

    /// The peripheral to use for GATT operations, connected through CoreBluetooth. A paired device
    /// that macOS has connected is attached automatically; a BLE peripheral must be connected first.
    private func gattPeripheral() async throws -> CBPeripheral {
        if record == nil, let classic, classic.isConnected(), let name = classic.name, let module {
            if let found = try await module.connectedPeripheralRecord(named: name) {
                attach(found)
            }
        }
        guard let record else {
            throw HSBluetoothError(classic?.isConnected() ?? false
                                   ? "the device offers no Bluetooth LE services"
                                   : "the device is not connected, call connect() first")
        }
        if cbConnection == nil {
            guard classic?.isConnected() ?? false else {
                throw HSBluetoothError("the device is not connected, call connect() first")
            }
            try await connectLE(record, as: .attached)
        }
        return record.peripheral
    }

    private func service(_ uuid: CBUUID, on peripheral: CBPeripheral) async throws -> CBService {
        if let found = peripheral.services?.first(where: { $0.uuid == uuid }) { return found }
        try await wait(for: Key.services) { peripheral.discoverServices(nil) }
        guard let found = peripheral.services?.first(where: { $0.uuid == uuid }) else {
            throw HSBluetoothError("the device has no service \(uuid.uuidString)")
        }
        return found
    }

    private func characteristic(_ serviceUUID: CBUUID, _ uuid: CBUUID) async throws -> CBCharacteristic {
        let peripheral = try await gattPeripheral()
        let found = try await service(serviceUUID, on: peripheral)
        if let characteristic = found.characteristics?.first(where: { $0.uuid == uuid }) { return characteristic }
        try await wait(for: Key.characteristics(found)) { peripheral.discoverCharacteristics(nil, for: found) }
        guard let characteristic = found.characteristics?.first(where: { $0.uuid == uuid }) else {
            throw HSBluetoothError("service \(serviceUUID.uuidString) has no characteristic \(uuid.uuidString)")
        }
        return characteristic
    }

    private func read(_ characteristic: CBCharacteristic) async throws {
        guard let peripheral = characteristic.service?.peripheral else { throw HSBluetoothError("the device is no longer available") }
        try await wait(for: Key.read(characteristic)) { peripheral.readValue(for: characteristic) }
    }

    private func setNotifying(_ enabled: Bool, _ service: String, _ characteristic: String) async throws {
        let found = try await self.characteristic(try Self.parseUUID(service), try Self.parseUUID(characteristic))
        guard !enabled || found.properties.contains(.notify) || found.properties.contains(.indicate) else {
            throw HSBluetoothError("characteristic \(found.uuid.uuidString) doesn't support notifications")
        }
        // isNotifying only changes when a request finishes, so it's checked once earlier ones have
        try await serially(Key.notify(found)) {
            guard found.isNotifying != enabled else { return }
            let peripheral = try Self.connectedPeripheral(of: found)
            try await self.wait(for: Key.notify(found)) { peripheral.setNotifyValue(enabled, for: found) }
        }
    }

    /// The peripheral a characteristic belongs to, checked again by queued requests: the device
    /// may have disconnected while they waited their turn
    private static func connectedPeripheral(of characteristic: CBCharacteristic) throws -> CBPeripheral {
        guard let peripheral = characteristic.service?.peripheral else { throw HSBluetoothError("the device is no longer available") }
        guard peripheral.state == .connected else { throw HSBluetoothError("the device disconnected") }
        return peripheral
    }

    private static func parseUUID(_ string: String) throws -> CBUUID {
        guard let uuid = HSBluetoothUUID.parse(string) else {
            throw HSBluetoothError("'\(string)' is not a valid Bluetooth UUID")
        }
        return uuid
    }

    /// The bytes to write for a JS value, or nil if it isn't something that can be written
    private static func bytes(from value: JSValue) -> Data? {
        if let bytes = value.typedArrayBytes { return Data(bytes) }
        if value.isString { return value.toString().data(using: .utf8) }
        guard value.isArray, let elements = value.toArray() else { return nil }
        var bytes: [UInt8] = []
        for element in elements {
            guard let number = element as? NSNumber,
                  let byte = UInt8(exactly: number.doubleValue) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    // MARK: - CoreBluetooth callbacks, forwarded by the record (on the main queue, see HSBluetoothModule.makeCentral)

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { settle(Key.services, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let key = Key.characteristics(service)
        MainActor.assumeIsolated { settle(key, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Only Sendable values cross into the main actor (which this already is, see above)
        let key = Key.read(characteristic)
        let value = characteristic.value ?? Data()
        let uuid = characteristic.uuid.uuidString
        let serviceUUID = characteristic.service?.uuid.uuidString
        let isBatteryLevel = characteristic.uuid == HSBluetoothUUID.batteryLevel
        let isNotifying = characteristic.isNotifying
        MainActor.assumeIsolated {
            if error == nil, isBatteryLevel, let level = value.first {
                record?.batteryLevel = Int(level)
            }
            // A read's reply and a notification arrive the same way, so while subscribed every
            // value goes to "value" listeners, whether or not a read is waiting for it too
            settle(key, error)
            if error == nil, isNotifying, let serviceUUID {
                deliverValue(value, service: serviceUUID, characteristic: uuid)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = Key.write(characteristic)
        MainActor.assumeIsolated { settle(key, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let key = Key.notify(characteristic)
        MainActor.assumeIsolated { settle(key, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        MainActor.assumeIsolated {
            if error == nil {
                record?.rssi = RSSI.intValue
                record?.lastSeen = Date()
            }
            settle(Key.rssi, error)
        }
    }

    // MARK: - Waiting for CoreBluetooth and IOBluetooth callbacks

    /// What a pending operation is waiting for. Several callers waiting for the same thing (e.g.
    /// two reads of one characteristic) share one request and are all settled by its callback.
    private nonisolated enum Key {
        static let connect = "connect"
        static let disconnect = "disconnect"
        static let rssi = "rssi"
        static let services = "services"
        static func characteristics(_ service: CBService) -> String { "characteristics:\(service.uuid.uuidString)" }
        static func read(_ characteristic: CBCharacteristic) -> String { "read:\(path(characteristic))" }
        static func write(_ characteristic: CBCharacteristic) -> String { "write:\(path(characteristic))" }
        static func notify(_ characteristic: CBCharacteristic) -> String { "notify:\(path(characteristic))" }
        private static func path(_ characteristic: CBCharacteristic) -> String {
            "\(characteristic.service?.uuid.uuidString ?? "?")/\(characteristic.uuid.uuidString)"
        }
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }
    private var waiters: [String: [Waiter]] = [:]

    /// Waits for the callback that settles `key`, calling `start` to make the request if nothing
    /// is waiting for it already. Fails if the callback doesn't arrive within `timeout`.
    private func wait(for key: String, timeout: Duration = .seconds(10), start: () throws -> Void) async throws {
        guard !isDestroyed else { throw HSBluetoothError("Hammerspoon is shutting down") }
        let isFirst = waiters[key]?.isEmpty ?? true
        let id = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.expire(key, id)
            }
            waiters[key, default: []].append(Waiter(id: id, continuation: continuation, timeout: timer))
            if isFirst {
                do {
                    try start()
                } catch {
                    settle(key, error)
                }
            }
        }
    }

    /// The last operation queued in each lane of `serially(_:_:)`
    private var lanes: [String: Task<Void, Never>] = [:]

    /// Runs `body` once every operation queued earlier in `lane` has finished. Used where
    /// requests mustn't share one callback the way `wait(for:)` lets them: CoreBluetooth answers a
    /// characteristic's writes (or notification changes) with one callback that doesn't say
    /// which request it is for, and each write has its own bytes to send.
    private func serially(_ lane: String, _ body: @escaping @MainActor () async throws -> Void) async throws {
        let previous = lanes[lane]
        let operation = Task {
            await previous?.value
            try await body()
        }
        let finished = Task { _ = await operation.result }
        lanes[lane] = finished
        defer {
            if lanes[lane] == finished { lanes[lane] = nil }
        }
        try await operation.value
    }

    private func settle(_ key: String, _ error: Error?) {
        guard let settled = waiters.removeValue(forKey: key) else { return }
        for waiter in settled {
            waiter.timeout.cancel()
            if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume()
            }
        }
    }

    private func expire(_ key: String, _ id: UUID) {
        guard let index = waiters[key]?.firstIndex(where: { $0.id == id }),
              let waiter = waiters[key]?.remove(at: index) else { return }
        if waiters[key]?.isEmpty ?? false { waiters[key] = nil }
        waiter.continuation.resume(throwing: HSBluetoothError("the device didn't respond in time"))
    }

    private func failAllWaiters(_ error: Error) {
        for key in Array(waiters.keys) {
            settle(key, error)
        }
    }

    // MARK: - Per-device watcher

    /// Lazily creates this device's JS watcher emitter (via the module's `_makeDeviceEmitter`
    /// factory). Returns nil, having set `ctx.exception`, on failure, so on()/once() never return
    /// without registering - same as HSCamera's.
    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let factory = module?._makeDeviceEmitter, factory.isFunction else {
                ctx.exception = JSValue(newErrorFromMessage: "hs.bluetooth device: device watcher emitter factory is unavailable", in: ctx)
                return nil
            }
            let emitter = ctx.callCapturingException { factory.call(withArguments: [self]) }
            guard ctx.exception == nil, let emitter, emitter.isObject else {
                if ctx.exception == nil {
                    ctx.exception = JSValue(newErrorFromMessage: "hs.bluetooth device: failed to create device watcher emitter", in: ctx)
                }
                return nil
            }
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
        watcherCallback = JSCallback(value: listener, owner: self)
        // A paired device's connect/disconnect events come from the module's IOBluetooth
        // notifications, which watcherCallback's didSet has just asked for
        guard classic == nil || module?.isReceivingClassicNotifications == true else {
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
    func fire(_ event: HSBluetoothDeviceEvent, _ arguments: [Any] = []) {
        _ = watcherCallback?.call(withArguments: [event.rawValue] + arguments)
    }

    private func deliverValue(_ value: Data, service: String, characteristic: String) {
        guard let context = watcherCallback?.value?.context, let bytes = context.makeUint8Array(value) else { return }
        fire(.value, [service, characteristic, bytes])
    }
}
