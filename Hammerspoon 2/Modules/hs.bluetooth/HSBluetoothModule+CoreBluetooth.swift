//
//  HSBluetoothModule+CoreBluetooth.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOBluetooth
import CoreBluetooth

/// A scan started by `hs.bluetooth.scan()`, until it resolves
@MainActor
final class BluetoothScan {
    let holder: JSPromiseHolder
    let includesLowEnergy: Bool
    let includesClassic: Bool
    let allowsDuplicates: Bool
    var timer: Timer?
    /// The devices found, in the order they were found: `le:<identifier>` or a classic address.
    /// Keys rather than objects, so a device the user drops during the scan can be collected (and
    /// is simply recreated when the scan resolves).
    private(set) var found: [String] = []
    private var seen: Set<String> = []

    init(holder: JSPromiseHolder, includesLowEnergy: Bool, includesClassic: Bool, allowsDuplicates: Bool) {
        self.holder = holder
        self.includesLowEnergy = includesLowEnergy
        self.includesClassic = includesClassic
        self.allowsDuplicates = allowsDuplicates
    }

    /// Records a sighting, returning whether `'discovered'` listeners should hear about it
    func record(_ key: String) -> Bool {
        guard seen.insert(key).inserted else { return allowsDuplicates }
        found.append(key)
        return true
    }

    static func key(for identifier: UUID) -> String { "le:\(identifier.uuidString)" }
}

extension HSBluetoothModule: CBCentralManagerDelegate, IOBluetoothDeviceInquiryDelegate {

    // MARK: - The CoreBluetooth central

    /// The central, if CoreBluetooth has been started
    var existingCentral: CBCentralManager? { central }

    /// Starts CoreBluetooth if it isn't running yet. The first time, this is what makes macOS ask
    /// for Bluetooth permission.
    @discardableResult
    func makeCentral() -> CBCentralManager {
        if let central { return central }
        // Delivered on the main queue, which the delegate methods here and in HSBluetoothDevice
        // rely on. No power alert: Bluetooth being off is reported to the caller instead.
        let central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        self.central = central
        AKDebug("hs.bluetooth: started CoreBluetooth")
        return central
    }

    /// The central, once it's powered on. Waits while CoreBluetooth starts up (and while the user
    /// answers the permission prompt), and fails if Bluetooth is off, not allowed or unsupported.
    func readyCentral() async throws -> CBCentralManager {
        let central = makeCentral()
        if central.state == .poweredOn { return central }
        if let error = HSBluetoothError.forState(central.state) { throw error }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        // Resumed only once the central is powered on
        guard let ready = self.central, ready.state == .poweredOn else {
            throw HSBluetoothError("Bluetooth is unavailable")
        }
        return ready
    }

    func shutdownCentral() {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: HSBluetoothError("Hammerspoon is shutting down")) }
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

    /// Finds the BLE side of a paired device that macOS has connected. CoreBluetooth doesn't
    /// reveal addresses, so this matches on the device's name among the LE peripherals connected
    /// to the system.
    func connectedPeripheralRecord(named name: String) async throws -> BluetoothPeripheralRecord? {
        let central = try await readyCentral()
        let connected = central.retrieveConnectedPeripherals(withServices: HSBluetoothUUID.commonAccessoryServices)
        return connected.first { $0.name == name }.map(record(for:))
    }

    /// Drops records of peripherals not seen for a while and not used by any device object, so
    /// long or repeated scans (where phones keep changing their identifiers) don't grow forever
    private func pruneRecords() {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let inUse = Set(devices.allObjects.compactMap { $0.record?.peripheral.identifier })
        peripheralRecords = peripheralRecords.filter { identifier, record in
            inUse.contains(identifier) || (record.lastSeen ?? .distantPast) > cutoff
        }
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

            if state == .poweredOn || HSBluetoothError.forState(state) != nil {
                let waiters = readyWaiters
                readyWaiters.removeAll()
                for waiter in waiters {
                    if let error = HSBluetoothError.forState(state) {
                        waiter.resume(throwing: error)
                    } else {
                        waiter.resume()
                    }
                }
            }

            if state != .poweredOn {
                // Every connection and the scan have ended, without their own callbacks
                let error = HSBluetoothError.forState(state) ?? HSBluetoothError("Bluetooth was reset")
                for device in devices.allObjects where device.record != nil {
                    device.peripheralDidDisconnect(error)
                }
                if let scan = activeScan, scan.includesLowEnergy, !scan.includesClassic {
                    endScan(error)
                }
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
            if scan.record(BluetoothScan.key(for: peripheral.identifier)), isWatching(.discovered) {
                emit(.discovered, device(for: record))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingDevice(identifier: identifier)?.peripheralDidConnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingDevice(identifier: identifier)?.peripheralDidFailToConnect(error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        MainActor.assumeIsolated {
            existingDevice(identifier: identifier)?.peripheralDidDisconnect(error)
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
        let lowEnergy = options["lowEnergy"] as? Bool ?? true
        let classic = options["classic"] as? Bool ?? false
        guard lowEnergy || classic else { return reject("lowEnergy and classic can't both be false") }
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
            let scan = BluetoothScan(holder: holder, includesLowEnergy: lowEnergy, includesClassic: classic,
                                     allowsDuplicates: allowDuplicates)
            activeScan = scan
            pruneRecords()

            if classic {
                startInquiry(seconds: seconds)
            }
            if lowEnergy {
                Task {
                    do {
                        let central = try await readyCentral()
                        guard activeScan === scan else { return }
                        central.scanForPeripherals(withServices: services.isEmpty ? nil : services,
                                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates])
                        AKDebug("hs.bluetooth.scan(): scanning for BLE peripherals")
                    } catch {
                        guard activeScan === scan else { return }
                        if classic {
                            AKWarning("hs.bluetooth.scan(): only scanning for classic devices: \(error.localizedDescription)")
                        } else {
                            endScan(error as? HSBluetoothError ?? HSBluetoothError(error.localizedDescription))
                        }
                    }
                }
            }

            scan.timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self, weak scan] _ in
                MainActor.assumeIsolated {
                    guard let self, let scan, self.activeScan === scan else { return }
                    self.endScan(nil)
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
        if scan.includesLowEnergy, central?.state == .poweredOn {
            central?.stopScan()
        }
        stopInquiry()
        guard settlingPromise else { return }
        if let error {
            scan.holder.rejectWithMessage("hs.bluetooth.scan(): \(error.message)")
        } else {
            scan.holder.resolveWith(scan.found.compactMap(scannedDevice))
        }
    }

    private func scannedDevice(_ key: String) -> HSBluetoothDevice? {
        if key.hasPrefix("le:") {
            guard let uuid = UUID(uuidString: String(key.dropFirst(3))), let record = peripheralRecords[uuid] else { return nil }
            return device(for: record)
        }
        return IOBluetoothDevice(addressString: key).map(device(for:))
    }

    // MARK: - Classic inquiry

    private func startInquiry(seconds: Double) {
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
            AKError("hs.bluetooth.scan(): could not create a classic Bluetooth inquiry")
            if activeScan?.includesLowEnergy == false {
                endScan(HSBluetoothError("classic Bluetooth scanning is unavailable"))
            }
            return
        }
        // Clamped before converting: Int(_:) traps on a Double too large for it
        inquiry.inquiryLength = UInt8(min(seconds, 255).rounded(.up))
        inquiry.updateNewDeviceNames = true
        let status = inquiry.start()
        guard status == kIOReturnSuccess else {
            AKError("hs.bluetooth.scan(): failed to start a classic Bluetooth inquiry (IOReturn \(status))")
            if activeScan?.includesLowEnergy == false {
                endScan(HSBluetoothError.forIOReturn(status, "Starting the classic Bluetooth scan"))
            }
            return
        }
        self.inquiry = inquiry
    }

    private func stopInquiry() {
        guard let inquiry else { return }
        self.inquiry = nil
        // The delegate is unretained, so clear it before this module can go away
        unsafe inquiry.delegate = nil
        inquiry.stop()
    }

    nonisolated func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        nonisolated(unsafe) let unsafeSender = sender
        nonisolated(unsafe) let unsafeDevice = device
        onMain { module in
            let (sender, device) = unsafe (unsafeSender, unsafeDevice)
            guard let sender, sender === module.inquiry, let scan = module.activeScan,
                  let device, let address = device.addressString.flatMap(HSBluetoothAddress.normalize) else { return }
            if scan.record(address), module.isWatching(.discovered) {
                module.emit(.discovered, module.device(for: device))
            }
        }
    }

    nonisolated func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        nonisolated(unsafe) let unsafeSender = sender
        onMain { module in
            let sender = unsafe unsafeSender
            // An inquiry stopped by endScan() has already been forgotten
            guard let sender, sender === module.inquiry else { return }
            module.inquiry = nil
            guard let scan = module.activeScan else { return }
            if error != kIOReturnSuccess || aborted {
                let reason = aborted ? HSBluetoothError("the classic Bluetooth scan was aborted")
                                     : HSBluetoothError.forIOReturn(error, "The classic Bluetooth scan")
                AKWarning("hs.bluetooth.scan(): \(reason.message)")
                if !scan.includesLowEnergy {
                    module.endScan(reason)
                }
            } else if !scan.includesLowEnergy {
                // The inquiry ran its full length, which is the scan's length rounded up
                module.endScan(nil)
            }
        }
    }
}
