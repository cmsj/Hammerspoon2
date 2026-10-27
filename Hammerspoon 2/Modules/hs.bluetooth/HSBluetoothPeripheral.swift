//
//  HSBluetoothPeripheral.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import CoreBluetooth

// MARK: - JavaScript API

/// A Bluetooth Low Energy (BLE) peripheral, found by `hs.bluetooth.scan()` or through a paired device's `lowEnergyPeripheral()`.
///
/// Obtain peripherals from the ``hs.bluetooth`` module; do not instantiate them directly. A
/// peripheral is identified by its `identifier`, and the same peripheral is returned as the same
/// object for as long as you hold on to it.
///
/// Call `connect()` before using its GATT services. A connected peripheral stays connected, and
/// keeps delivering its events, until you call `disconnect()`, even if you drop your reference to it.
///
/// ```javascript
/// const [sensor] = await hs.bluetooth.scan({ seconds: 5, services: ["181A"] })
/// await sensor.connect()
/// const bytes = await sensor.readValue("181A", "2A6E")
/// sensor.on("value", (service, characteristic, value) => console.log(characteristic + ": " + value))
/// await sensor.subscribe("181A", "2A6E")
/// ```
@objc protocol HSBluetoothPeripheralAPI: HSTypeAPI, JSExport {
    /// The type name for JavaScript introspection. Always `"HSBluetoothPeripheral"`.
    @objc var typeName: String { get }

    /// The peripheral's identifier, a UUID that macOS assigns in place of its Bluetooth address, which it doesn't reveal. It is stable on this Mac, but differs between Macs.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.forEach(p => console.log(p.identifier))
    /// ```
    @objc var identifier: String { get }

    /// The peripheral's name, or `null` if it hasn't reported one.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.forEach(p => console.log(p.name ?? p.identifier))
    /// ```
    @objc var name: String? { get }

    /// Whether Hammerspoon is connected to the peripheral.
    /// - Example:
    /// ```js
    /// if (!sensor.isConnected) await sensor.connect()
    /// ```
    @objc var isConnected: Bool { get }

    /// The last known signal strength in dBm, or `null` if there is none. It is updated by `hs.bluetooth.scan()` and `readRSSI()`.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.forEach(p => console.log(p.name + " " + p.rssi + " dBm"))
    /// ```
    @objc var rssi: NSNumber? { get }

    /// When the peripheral was last seen, in Unix seconds: in a scan, or while connected. `null` if unknown.
    /// - Example:
    /// ```js
    /// console.log(new Date(peripheral.lastSeen * 1000))
    /// ```
    @objc var lastSeen: NSNumber? { get }

    /// The peripheral's last advertisement, if a scan has seen one, otherwise `null`.
    ///
    /// The object has `localName` (string or `null`), `isConnectable` (boolean or `null`), `txPower` (number or `null`), `serviceUUIDs` (string[]), `manufacturerData` (Uint8Array or `null`) and `serviceData` (an object mapping service UUIDs to Uint8Array).
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.scan()
    /// nearby.filter(p => p.advertisement.manufacturerData)
    ///       .forEach(p => console.log(p.identifier + " " + p.advertisement.manufacturerData))
    /// ```
    @objc var advertisement: [String: Any]? { get }

    /// The battery level last read by `readBatteryLevel()`, as a percentage, or `null` if it hasn't been read.
    /// - Example:
    /// ```js
    /// console.log(peripheral.batteryLevel + "%")
    /// ```
    @objc var batteryLevel: NSNumber? { get }

    /// Reads the peripheral's battery level from its standard GATT Battery service. The peripheral must be connected.
    /// - Returns: {Promise<number | null>} A Promise resolving to the battery percentage, or `null` if the peripheral has no Battery service
    /// - Example:
    /// ```js
    /// await peripheral.connect()
    /// console.log(peripheral.name + ": " + await peripheral.readBatteryLevel() + "%")
    /// ```
    @objc func readBatteryLevel() -> JSPromise?

    /// Connects Hammerspoon to the peripheral, so its GATT services can be used. It stays connected until `disconnect()` is called, even if you drop your reference to it.
    /// - Returns: {Promise<HSBluetoothPeripheral>} A Promise resolving to this peripheral once it's connected, or rejecting if the connection fails or takes longer than 20 seconds
    /// - Example:
    /// ```js
    /// await sensor.connect()
    /// ```
    @objc func connect() -> JSPromise?

    /// Disconnects Hammerspoon from the peripheral. If macOS has its own connection to it (e.g. a paired keyboard), that connection stays.
    /// - Returns: {Promise<HSBluetoothPeripheral>} A Promise resolving to this peripheral once it's disconnected
    /// - Example:
    /// ```js
    /// await sensor.disconnect()
    /// ```
    @objc func disconnect() -> JSPromise?

    /// Reads the current signal strength of a connected peripheral.
    /// - Returns: {Promise<number>} A Promise resolving to the signal strength in dBm, or rejecting if the peripheral isn't connected
    /// - Example:
    /// ```js
    /// console.log(await sensor.readRSSI() + " dBm")
    /// ```
    @objc func readRSSI() -> JSPromise?

    /// Discovers the GATT services of a connected peripheral.
    /// - Returns: {Promise<string[]>} A Promise resolving to the UUIDs of the peripheral's services, e.g. `["180A", "180F"]`
    /// - Example:
    /// ```js
    /// await sensor.connect()
    /// console.log((await sensor.discoverServices()).join(", "))
    /// ```
    @objc func discoverServices() -> JSPromise?

    /// Discovers the characteristics of one of a connected peripheral's GATT services.
    /// - Parameter service: The service UUID: 16-bit (`"180F"`), 32-bit, or 128-bit
    /// - Returns: {Promise<{uuid: string, properties: string[], isNotifying: boolean}[]>} A Promise resolving to the service's characteristics. `properties` lists what each supports: `"read"`, `"write"`, `"writeWithoutResponse"`, `"notify"`, `"indicate"`, `"broadcast"`, `"authenticatedSignedWrites"` and `"extendedProperties"`
    /// - Example:
    /// ```js
    /// const chars = await sensor.discoverCharacteristics("180F")
    /// chars.forEach(c => console.log(c.uuid + ": " + c.properties.join(", ")))
    /// ```
    @objc func discoverCharacteristics(_ service: String) -> JSPromise?

    /// Reads the value of a GATT characteristic of a connected peripheral. The service and characteristic are discovered first if needed.
    /// - Parameters:
    ///   - service: The service UUID, e.g. `"180F"`
    ///   - characteristic: The characteristic UUID, e.g. `"2A19"`
    /// - Returns: {Promise<Uint8Array>} A Promise resolving to the characteristic's value
    /// - Example:
    /// ```js
    /// const value = await peripheral.readValue("180F", "2A19")
    /// console.log("Battery: " + value[0] + "%")
    /// ```
    @objc func readValue(_ service: String, _ characteristic: String) -> JSPromise?

    /// Writes the value of a GATT characteristic of a connected peripheral. Writes to one characteristic are sent in the order they're made.
    /// - Parameters:
    ///   - service: The service UUID
    ///   - characteristic: The characteristic UUID
    ///   - value: {Uint8Array | ArrayBuffer | number[] | string} The bytes to write. A string is written as UTF-8
    ///   - options?: {{withoutResponse?: boolean}} With `withoutResponse: true`, write without asking the peripheral to confirm it, which is faster but can't tell whether it arrived. Defaults to `false`
    /// - Returns: {Promise<void>} A Promise resolving once the peripheral has accepted the write (or, without a response, once it has been sent)
    /// - Example:
    /// ```js
    /// await lamp.writeValue("FFE5", "FFE9", [0x56, 0xFF, 0x00, 0x00, 0x00, 0xF0, 0xAA])
    /// await lamp.writeValue("FFE5", "FFE9", frame, { withoutResponse: true })
    /// ```
    @objc func writeValue(_ service: String, _ characteristic: String, _ value: JSValue, _ options: [String: Any]?) -> JSPromise?

    /// Subscribes to a GATT characteristic of a connected peripheral, so each new value is delivered as a `"value"` event (see `on()`).
    /// - Parameters:
    ///   - service: The service UUID
    ///   - characteristic: The characteristic UUID, which must support `"notify"` or `"indicate"`
    /// - Returns: {Promise<void>} A Promise resolving once the peripheral has started sending values
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
    /// - Returns: {Promise<void>} A Promise resolving once the peripheral has stopped sending values
    /// - Example:
    /// ```js
    /// await heartStrap.unsubscribe("180D", "2A37")
    /// ```
    @objc func unsubscribe(_ service: String, _ characteristic: String) -> JSPromise?

    /// Register a listener for this peripheral's events.
    ///
    /// Listeners receive:
    ///  - `"connected"`, `"disconnected"`: no arguments, when Hammerspoon's connection to the peripheral opens or closes
    ///  - `"value"`: `(service, characteristic, value)`, the UUIDs and the new value (a Uint8Array) of a characteristic you subscribed to. While subscribed, values fetched by `readValue()` arrive here too, since the peripheral sends both the same way
    ///
    /// A peripheral with listeners keeps working after you drop your reference to it.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "value"} The event to listen for
    ///   - listener: {(service?: string, characteristic?: string, value?: Uint8Array) => void} Called when the event occurs
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     sensor.on('disconnected', () => console.log(sensor.name + " went away"))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func on(_ event: String, _ listener: JSFunction)

    /// Remove a previously registered listener for this peripheral's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "value"} The event the listener was registered for
    ///   - listener: The function originally passed to `on`
    /// - Example:
    /// ```js
    /// sensor.off('value', myListener)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Register a listener that fires at most once for one of this peripheral's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "value"} The event to listen for
    ///   - listener: {(service?: string, characteristic?: string, value?: Uint8Array) => void} Called once, then automatically removed
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     sensor.once('connected', () => console.log("Connected to " + sensor.name))
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

    /// The event names `on()`/`once()` accept - see HSBluetoothPeripheralEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    /// Returns a plain object describing this peripheral, for JSON serialisation
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with the peripheral's `identifier`, `name`, `isConnected`, `rssi`, `lastSeen` and `batteryLevel`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(await hs.bluetooth.scan(), null, 2))
    /// ```
    @objc func toJSON() -> [String: Any]
}

// MARK: - Implementation

/// Events emitted by a single HSBluetoothPeripheral's watcher
nonisolated enum HSBluetoothPeripheralEvent: String, HSEventName {
    case connected, disconnected, value
}

/// What CoreBluetooth has told us about one BLE peripheral. The module keeps one per peripheral
/// it has seen, so the latest advertisement and readings survive the peripheral object being
/// garbage collected and recreated.
final class BluetoothPeripheralRecord {
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

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
}

@_documentation(visibility: private)
@MainActor
@objc class HSBluetoothPeripheral: NSObject, HSBluetoothPeripheralAPI, HSTrackedObject, CBPeripheralDelegate {
    @objc var typeName = "HSBluetoothPeripheral"

    private weak var module: HSBluetoothModule?
    private weak var tracker: HSObjectTracker<HSBluetoothPeripheral>?

    let record: BluetoothPeripheralRecord
    private var peripheral: CBPeripheral { record.peripheral }

    /// Hammerspoon's connection to the peripheral. While open it keeps the object alive: the
    /// peripheral stays connected until `disconnect()`.
    private var isHeld = false {
        didSet { updateActivity() }
    }

    /// JS-facing operations in flight. Each one keeps the object alive until its Promise settles.
    private var operations = 0 {
        didSet { updateActivity() }
    }

    private var watcherCallback: JSCallback? {
        didSet { updateActivity() }
    }
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSBluetoothPeripheralEvent.allNames }

    /// Whether anything is listening for this peripheral's events
    var isWatching: Bool { watcherCallback != nil }

    private let requests = HSBluetoothRequests()

    /// Set by destroy(), after which no Promise is settled: the JSContext is going away
    private var isDestroyed = false

    init(module: HSBluetoothModule, tracker: HSObjectTracker<HSBluetoothPeripheral>, record: BluetoothPeripheralRecord) {
        self.module = module
        self.tracker = tracker
        self.record = record
        super.init()
        // One object per peripheral at a time (see HSBluetoothModule.peripheral(for:)), so this
        // object gets every callback
        record.peripheral.delegate = self
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of HSBluetoothPeripheral: \(record.peripheral.identifier)")
    }

    func destroy() {
        isDestroyed = true
        _removeWatcher()
        requests.close(HSBluetoothError("Hammerspoon is shutting down"))
        if peripheral.state != .disconnected {
            module?.existingCentral?.cancelPeripheralConnection(peripheral)
        }
        isHeld = false
        if peripheral.delegate === self {
            peripheral.delegate = nil
        }
    }

    private func updateActivity() {
        let held = isHeld || isWatching
        tracker?.setActive(self, held || operations > 0, finishesOnItsOwn: !held)
    }

    @objc func toString() -> String {
        "<\(typeName): \(name ?? "unnamed") (\(identifier))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Properties

    @objc var identifier: String { peripheral.identifier.uuidString }
    @objc var name: String? { peripheral.name ?? record.advertisement?.localName }
    @objc var isConnected: Bool { peripheral.state == .connected }
    @objc var rssi: NSNumber? { record.rssi.map { NSNumber(value: $0) } }
    @objc var lastSeen: NSNumber? { record.lastSeen.map { NSNumber(value: $0.timeIntervalSince1970) } }
    @objc var batteryLevel: NSNumber? { record.batteryLevel.map { NSNumber(value: $0) } }

    @objc var advertisement: [String: Any]? {
        guard let ad = record.advertisement, let context = JSContext.current() else { return nil }
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        var serviceData: [String: Any] = [:]
        for (uuid, data) in ad.serviceData {
            serviceData[uuid] = orNull(context.makeUint8Array(data))
        }
        return [
            "localName": orNull(ad.localName),
            "isConnectable": orNull(ad.isConnectable),
            "txPower": orNull(ad.txPower),
            "serviceUUIDs": ad.serviceUUIDs,
            "manufacturerData": orNull(ad.manufacturerData.flatMap { context.makeUint8Array($0) }),
            "serviceData": serviceData,
        ]
    }

    @objc func toJSON() -> [String: Any] {
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        return [
            "identifier": identifier,
            "name": orNull(name),
            "isConnected": isConnected,
            "rssi": orNull(rssi),
            "lastSeen": orNull(lastSeen),
            "batteryLevel": orNull(batteryLevel),
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
                    if !isDestroyed { holder.rejectWithMessage("hs.bluetooth peripheral.\(method)(): \(error.localizedDescription)") }
                }
            }
        }
    }

    @objc func readBatteryLevel() -> JSPromise? {
        perform("readBatteryLevel") { _ in
            try self.requireConnection()
            let level: CBCharacteristic
            do {
                level = try await self.characteristic(HSBluetoothUUID.batteryService, HSBluetoothUUID.batteryLevel)
            } catch is MissingAttribute {
                // A peripheral without a Battery service simply has no level to report
                return nil
            }
            try await self.read(level)
            return self.record.batteryLevel
        }
    }

    @objc func connect() -> JSPromise? {
        perform("connect") { _ in
            let central = try await self.requireCentral()
            if self.peripheral.state != .connected {
                do {
                    try await self.requests.wait(for: Key.connect, timeout: .seconds(20)) {
                        central.connect(self.peripheral)
                    }
                } catch {
                    // A connection CoreBluetooth never completes stays pending forever unless cancelled
                    if self.peripheral.state != .connected {
                        central.cancelPeripheralConnection(self.peripheral)
                    }
                    throw error
                }
            }
            self.isHeld = true
            return self
        }
    }

    @objc func disconnect() -> JSPromise? {
        perform("disconnect") { _ in
            if self.peripheral.state != .disconnected, let central = self.module?.existingCentral {
                try await self.requests.wait(for: Key.disconnect, timeout: .seconds(10)) {
                    central.cancelPeripheralConnection(self.peripheral)
                }
            }
            self.isHeld = false
            return self
        }
    }

    @objc func readRSSI() -> JSPromise? {
        perform("readRSSI") { _ in
            try self.requireConnection()
            try await self.requests.wait(for: Key.rssi, timeout: Self.gattTimeout) { self.peripheral.readRSSI() }
            return self.record.rssi
        }
    }

    @objc func discoverServices() -> JSPromise? {
        perform("discoverServices") { _ in
            try self.requireConnection()
            try await self.requests.wait(for: Key.services, timeout: Self.gattTimeout) { self.peripheral.discoverServices(nil) }
            return (self.peripheral.services ?? []).map(\.uuid.uuidString)
        }
    }

    @objc func discoverCharacteristics(_ service: String) -> JSPromise? {
        perform("discoverCharacteristics") { _ in
            let found = try await self.service(try Self.parseUUID(service))
            try await self.requests.wait(for: Key.characteristics(found), timeout: Self.gattTimeout) {
                self.peripheral.discoverCharacteristics(nil, for: found)
            }
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

    @objc func writeValue(_ service: String, _ characteristic: String, _ value: JSValue, _ options: [String: Any]?) -> JSPromise? {
        // Converted now, while the value is certainly still what the caller passed
        let bytes = Self.bytes(from: value)
        let withoutResponse = options?["withoutResponse"] as? Bool ?? false
        return perform("writeValue") { _ in
            guard let bytes else {
                throw HSBluetoothError("value must be a Uint8Array, an ArrayBuffer, an array of numbers from 0 to 255, or a string")
            }
            let found = try await self.characteristic(try Self.parseUUID(service), try Self.parseUUID(characteristic))
            if withoutResponse {
                try await self.writeWithoutResponse(bytes, to: found)
            } else {
                // One at a time: CoreBluetooth's callback doesn't say which write it confirms
                try await self.requests.serially(Key.write(found)) {
                    try self.requireConnection()
                    try await self.requests.wait(for: Key.write(found), timeout: Self.gattTimeout) {
                        self.peripheral.writeValue(bytes, for: found, type: .withResponse)
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

    // MARK: - Connection

    private func requireCentral() async throws -> CBCentralManager {
        guard let module else { throw HSBluetoothError("hs.bluetooth is no longer loaded") }
        return try await module.readyCentral()
    }

    private func requireConnection() throws {
        guard peripheral.state == .connected else {
            throw HSBluetoothError("the peripheral is not connected, call connect() first")
        }
    }

    // The module's CoreBluetooth delegate routes these here

    func peripheralDidConnect() {
        record.lastSeen = Date()
        requests.settle(Key.connect, nil)
        fire(.connected)
    }

    func peripheralDidFailToConnect(_ error: Error?) {
        requests.settle(Key.connect, HSBluetoothError(error?.localizedDescription ?? "the connection failed"))
    }

    func peripheralDidDisconnect(_ error: Error?) {
        let wasHeld = isHeld
        isHeld = false
        requests.settle(Key.disconnect, nil)
        requests.failAll(HSBluetoothError(error.map { "the peripheral disconnected: \($0.localizedDescription)" } ?? "the peripheral disconnected"))
        if wasHeld {
            fire(.disconnected)
        }
    }

    // MARK: - GATT

    /// How long a GATT request waits for its answer. Longer than the ATT protocol's own 30-second
    /// transaction timeout, after which the link is dropped (failing the request), so a request
    /// never gives up while its answer can still arrive and be mistaken for a later request's.
    static let gattTimeout: Duration = .seconds(35)

    /// A service or characteristic the peripheral doesn't have
    private struct MissingAttribute: LocalizedError {
        let errorDescription: String?
    }

    private func service(_ uuid: CBUUID) async throws -> CBService {
        try requireConnection()
        if let found = peripheral.services?.first(where: { $0.uuid == uuid }) { return found }
        try await requests.wait(for: Key.services, timeout: Self.gattTimeout) { peripheral.discoverServices(nil) }
        guard let found = peripheral.services?.first(where: { $0.uuid == uuid }) else {
            throw MissingAttribute(errorDescription: "the peripheral has no service \(uuid.uuidString)")
        }
        return found
    }

    private func characteristic(_ serviceUUID: CBUUID, _ uuid: CBUUID) async throws -> CBCharacteristic {
        let found = try await service(serviceUUID)
        if let characteristic = found.characteristics?.first(where: { $0.uuid == uuid }) { return characteristic }
        try await requests.wait(for: Key.characteristics(found), timeout: Self.gattTimeout) {
            peripheral.discoverCharacteristics(nil, for: found)
        }
        guard let characteristic = found.characteristics?.first(where: { $0.uuid == uuid }) else {
            throw MissingAttribute(errorDescription: "service \(serviceUUID.uuidString) has no characteristic \(uuid.uuidString)")
        }
        return characteristic
    }

    private func read(_ characteristic: CBCharacteristic) async throws {
        try requireConnection()
        try await requests.wait(for: Key.read(characteristic), timeout: Self.gattTimeout) {
            peripheral.readValue(for: characteristic)
        }
    }

    /// Writes without a response, waiting first for room in CoreBluetooth's send queue, so a
    /// burst of writes isn't silently dropped. In order, one at a time across the peripheral,
    /// since the queue is the peripheral's.
    private func writeWithoutResponse(_ bytes: Data, to characteristic: CBCharacteristic) async throws {
        try await requests.serially(Key.writeWithoutResponse) {
            try self.requireConnection()
            while !self.peripheral.canSendWriteWithoutResponse {
                try await self.requests.wait(for: Key.readyToWrite, timeout: Self.gattTimeout) {}
                try self.requireConnection()
            }
            self.peripheral.writeValue(bytes, for: characteristic, type: .withoutResponse)
        }
    }

    private func setNotifying(_ enabled: Bool, _ service: String, _ characteristic: String) async throws {
        let found = try await self.characteristic(try Self.parseUUID(service), try Self.parseUUID(characteristic))
        guard !enabled || found.properties.contains(.notify) || found.properties.contains(.indicate) else {
            throw HSBluetoothError("characteristic \(found.uuid.uuidString) doesn't support notifications")
        }
        // isNotifying only changes when a request finishes, so it's checked once earlier ones have
        try await requests.serially(Key.notify(found)) {
            guard found.isNotifying != enabled else { return }
            try self.requireConnection()
            try await self.requests.wait(for: Key.notify(found), timeout: Self.gattTimeout) {
                self.peripheral.setNotifyValue(enabled, for: found)
            }
        }
    }

    private static func parseUUID(_ string: String) throws -> CBUUID {
        guard let uuid = HSBluetoothUUID.parse(string) else {
            throw HSBluetoothError("'\(string)' is not a valid Bluetooth UUID")
        }
        return uuid
    }

    /// The bytes to write for a JS value, or nil if it isn't something that can be written
    static func bytes(from value: JSValue) -> Data? {
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

    // MARK: - CBPeripheralDelegate (delivered on the main queue, see HSBluetoothModule.makeCentral)

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { requests.settle(Key.services, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let key = Key.characteristics(service)
        MainActor.assumeIsolated { requests.settle(key, error) }
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
                record.batteryLevel = Int(level)
            }
            record.lastSeen = Date()
            // A read's reply and a notification arrive the same way, so while subscribed every
            // value goes to "value" listeners, whether or not a read is waiting for it too
            requests.settle(key, error)
            if error == nil, isNotifying, let serviceUUID {
                deliverValue(value, service: serviceUUID, characteristic: uuid)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = Key.write(characteristic)
        MainActor.assumeIsolated { requests.settle(key, error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let key = Key.notify(characteristic)
        MainActor.assumeIsolated { requests.settle(key, error) }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated { requests.settle(Key.readyToWrite, nil) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        MainActor.assumeIsolated {
            if error == nil {
                record.rssi = RSSI.intValue
                record.lastSeen = Date()
            }
            requests.settle(Key.rssi, error)
        }
    }

    /// What each request waits for (see HSBluetoothRequests)
    private nonisolated enum Key {
        static let connect = "connect"
        static let disconnect = "disconnect"
        static let rssi = "rssi"
        static let services = "services"
        static let writeWithoutResponse = "writeWithoutResponse"
        static let readyToWrite = "readyToWrite"
        static func characteristics(_ service: CBService) -> String { "characteristics:\(service.uuid.uuidString)" }
        static func read(_ characteristic: CBCharacteristic) -> String { "read:\(path(characteristic))" }
        static func write(_ characteristic: CBCharacteristic) -> String { "write:\(path(characteristic))" }
        static func notify(_ characteristic: CBCharacteristic) -> String { "notify:\(path(characteristic))" }
        private static func path(_ characteristic: CBCharacteristic) -> String {
            "\(characteristic.service?.uuid.uuidString ?? "?")/\(characteristic.uuid.uuidString)"
        }
    }

    // MARK: - Watcher

    /// Lazily creates this peripheral's JS watcher emitter. Returns nil, having set
    /// `ctx.exception`, on failure, so on()/once() never return without registering.
    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let emitter = module?.makeObjectEmitter(for: self, in: ctx) else { return nil }
            _watcherEmitter = emitter
        }
        return _watcherEmitter
    }

    @objc func on(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
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
            AKWarning("hs.bluetooth peripheral._addWatcher(): already watching \(toString()), refusing a second subscription")
            return false
        }
        watcherCallback = JSCallback(value: listener, owner: self)
        AKDebug("hs.bluetooth peripheral._addWatcher(): started watching \(toString())")
        return true
    }

    @objc(_removeWatcher) func _removeWatcher() {
        // Cleared first so the next on() creates a fresh emitter, in the caller's VM
        _watcherEmitter = nil
        guard watcherCallback != nil else { return }
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("hs.bluetooth peripheral._removeWatcher(): stopped watching \(toString())")
    }

    /// Delivers one of this peripheral's events to its listeners
    func fire(_ event: HSBluetoothPeripheralEvent, _ arguments: [Any] = []) {
        _ = watcherCallback?.call(withArguments: [event.rawValue] + arguments)
    }

    private func deliverValue(_ value: Data, service: String, characteristic: String) {
        guard let context = watcherCallback?.value?.context, let bytes = context.makeUint8Array(value) else { return }
        fire(.value, [service, characteristic, bytes])
    }
}
