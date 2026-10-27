//
//  HSBluetoothModule+CoreBluetooth.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreBluetooth

/// A scan started by `hs.bluetooth.scan()`, until it resolves
@MainActor
final class BluetoothScan {
    let holder: JSPromiseHolder
    let allowsDuplicates: Bool
    var timer: Timer?
    /// The peripherals found, in the order they were found. Identifiers rather than objects, so a
    /// peripheral the user drops during the scan can be collected (and is simply recreated when
    /// the scan resolves).
    private(set) var found: [UUID] = []
    private var seen: Set<UUID> = []

    init(holder: JSPromiseHolder, allowsDuplicates: Bool) {
        self.holder = holder
        self.allowsDuplicates = allowsDuplicates
    }

    /// Records a sighting, returning whether `'discovered'` listeners should hear about it
    func record(_ identifier: UUID) -> Bool {
        guard seen.insert(identifier).inserted else { return allowsDuplicates }
        found.append(identifier)
        return true
    }
}

extension HSBluetoothModule: CBCentralManagerDelegate {

    // MARK: - The CoreBluetooth central

    /// The central, if CoreBluetooth has been started
    var existingCentral: CBCentralManager? { central }

    /// How long `readyCentral()` waits for CoreBluetooth to start, which includes the user
    /// answering the permission prompt the first time
    static let readyTimeout: Duration = .seconds(60)

    /// Starts CoreBluetooth if it isn't running yet. The first time, this is what makes macOS ask
    /// for Bluetooth permission.
    @discardableResult
    func makeCentral() -> CBCentralManager {
        if let central { return central }
        // Delivered on the main queue, which the delegate methods here and in
        // HSBluetoothPeripheral rely on. No power alert: Bluetooth being off is reported to the
        // caller instead.
        let central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        self.central = central
        AKDebug("hs.bluetooth: started CoreBluetooth")
        return central
    }

    /// The central, once it's powered on. Waits while CoreBluetooth starts up (and while the user
    /// answers the permission prompt), and fails if Bluetooth is off, not allowed or unsupported,
    /// or isn't ready within `readyTimeout`.
    func readyCentral() async throws -> CBCentralManager {
        let central = makeCentral()
        if central.state != .poweredOn {
            if let error = HSBluetoothError.forState(central.state) { throw error }
            try await centralRequests.wait(for: CentralKey.ready, timeout: Self.readyTimeout,
                                           timeoutError: HSBluetoothError("Bluetooth didn't become ready in time; is the permission prompt still waiting for an answer?")) {}
        }
        guard let ready = self.central, ready.state == .poweredOn else {
            throw HSBluetoothError("Bluetooth is unavailable")
        }
        return ready
    }

    func shutdownCentral() {
        centralRequests.close(HSBluetoothError("Hammerspoon is shutting down"))
        if central?.state == .poweredOn {
            central?.stopScan()
        }
        central?.delegate = nil
        central = nil
        peripheralRecords.removeAll()
        lastKnownPowered = nil
    }

    /// The module's record of a peripheral, made the first time it's seen
    func record(for peripheral: CBPeripheral) -> BluetoothPeripheralRecord {
        if let existing = peripheralRecords[peripheral.identifier] { return existing }
        let record = BluetoothPeripheralRecord(peripheral: peripheral)
        peripheralRecords[peripheral.identifier] = record
        return record
    }

    /// The BLE peripherals connected to the Mac (by macOS or any app) with this name. CoreBluetooth
    /// doesn't reveal addresses, so a name is all that links a paired device to its BLE side.
    func systemConnectedPeripherals(named name: String) async throws -> [BluetoothPeripheralRecord] {
        let central = try await readyCentral()
        return central.retrieveConnectedPeripherals(withServices: HSBluetoothUUID.commonAccessoryServices)
            .filter { $0.name == name }
            .map(record(for:))
    }

    /// Drops records of peripherals not seen for a while and not used by any object, so long or
    /// repeated scans (where phones keep changing their identifiers) don't grow forever
    func pruneRecords() {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let inUse = Set(peripherals.allObjects.map(\.record.peripheral.identifier))
        peripheralRecords = peripheralRecords.filter { identifier, record in
            inUse.contains(identifier) || (record.lastSeen ?? .distantPast) > cutoff
        }
    }

    private nonisolated enum CentralKey {
        static let ready = "ready"
    }

    // MARK: - Power

    /// Starts following Bluetooth's power state, for `'powerChanged'` listeners
    func startPowerWatching() -> Bool {
        switch CBManager.authorization {
        case .denied, .restricted:
            AKError("hs.bluetooth.on('powerChanged'): Bluetooth access has not been allowed, see hs.permissions.requestBluetooth()")
            return false
        default:
            break
        }
        if lastKnownPowered == nil {
            lastKnownPowered = powered
        }
        makeCentral()
        return true
    }

    // MARK: - CBCentralManagerDelegate
    //
    // Delivered on the main queue (see makeCentral), so assumeIsolated always holds. CoreBluetooth's
    // objects aren't Sendable; the nonisolated(unsafe) copies only ever cross from the main queue
    // to the main actor, i.e. stay on the main thread.

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        nonisolated(unsafe) let unsafeCentral = central
        MainActor.assumeIsolated {
            let central = unsafe unsafeCentral
            guard central === self.central else { return }
            let state = central.state
            AKDebug("hs.bluetooth: CoreBluetooth state is \(state.rawValue)")

            if state == .poweredOn {
                centralRequests.settle(CentralKey.ready, nil)
            } else if let error = HSBluetoothError.forState(state) {
                centralRequests.settle(CentralKey.ready, error)
            }

            if state != .poweredOn {
                // Every connection and the scan have ended, without their own callbacks
                let error = HSBluetoothError.forState(state) ?? HSBluetoothError("Bluetooth was reset")
                for peripheral in peripherals.allObjects {
                    peripheral.peripheralDidDisconnect(error)
                }
                endScan(error)
            }

            let nowPowered: Bool? = state == .poweredOn ? true : (state == .poweredOff ? false : nil)
            if let nowPowered, nowPowered != lastKnownPowered {
                let wasKnown = lastKnownPowered != nil
                lastKnownPowered = nowPowered
                if wasKnown && isWatching(.powerChanged) {
                    emit(.powerChanged, nowPowered)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        nonisolated(unsafe) let unsafeCentral = central
        nonisolated(unsafe) let unsafePeripheral = peripheral
        nonisolated(unsafe) let unsafeAdvertisementData = advertisementData
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            let (central, peripheral, advertisementData) = unsafe (unsafeCentral, unsafePeripheral, unsafeAdvertisementData)
            guard central === self.central, let scan = activeScan else { return }
            let record = record(for: peripheral)
            record.advertisement = BluetoothPeripheralRecord.Advertisement(advertisementData)
            // 127 means CoreBluetooth has no reading
            if rssi != 127 {
                record.rssi = rssi
            }
            record.lastSeen = Date()
            if scan.record(peripheral.identifier), isWatching(.discovered) {
                emit(.discovered, self.peripheral(for: record))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingPeripheral(identifier: identifier)?.peripheralDidConnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingPeripheral(identifier: identifier)?.peripheralDidFailToConnect(error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingPeripheral(identifier: identifier)?.peripheralDidDisconnect(error)
        }
    }

    // MARK: - Scanning

    @objc func scan(_ options: [String: Any]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        func reject(_ message: String) -> JSPromise? {
            context.createRejectedPromise(with: "hs.bluetooth.scan(): \(message)")
        }
        guard activeScan == nil else { return reject("a scan is already running") }

        let options = options ?? [:]
        let seconds = (options["seconds"] as? NSNumber)?.doubleValue ?? 10
        guard seconds.isFinite, seconds > 0 else { return reject("seconds must be a positive number") }
        var services: [CBUUID] = []
        if let requested = options["services"] {
            guard let strings = requested as? [String] else { return reject("services must be an array of UUID strings") }
            for string in strings {
                guard let uuid = HSBluetoothUUID.parse(string) else { return reject("'\(string)' is not a valid Bluetooth UUID") }
                services.append(uuid)
            }
        }
        let allowDuplicates = options["allowDuplicates"] as? Bool ?? false

        return wrapAsyncInJSPromise(in: context) { [self] holder in
            let scan = BluetoothScan(holder: holder, allowsDuplicates: allowDuplicates)
            activeScan = scan
            pruneRecords()

            Task {
                do {
                    let central = try await readyCentral()
                    guard activeScan === scan else { return }
                    // The countdown starts now, so time spent answering the permission prompt
                    // doesn't use up the scan
                    scan.timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self, weak scan] _ in
                        MainActor.assumeIsolated {
                            guard let self, let scan, self.activeScan === scan else { return }
                            self.endScan(nil)
                        }
                    }
                    central.scanForPeripherals(withServices: services.isEmpty ? nil : services,
                                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates])
                    AKDebug("hs.bluetooth.scan(): scanning for BLE peripherals")
                } catch {
                    guard activeScan === scan else { return }
                    endScan(error as? HSBluetoothError ?? HSBluetoothError(error.localizedDescription))
                }
            }
        }
    }

    @objc func stopScan() {
        endScan(nil)
    }

    /// Ends the active scan, resolving its Promise with what was found or rejecting it
    func endScan(_ error: HSBluetoothError?, settlingPromise: Bool = true) {
        guard let scan = activeScan else { return }
        activeScan = nil
        scan.timer?.invalidate()
        if central?.state == .poweredOn {
            central?.stopScan()
        }
        guard settlingPromise else { return }
        if let error {
            scan.holder.rejectWithMessage("hs.bluetooth.scan(): \(error.message)")
        } else {
            let found = scan.found.compactMap { peripheralRecords[$0] }.map(peripheral(for:))
            scan.holder.resolveWith(found)
        }
    }
}
