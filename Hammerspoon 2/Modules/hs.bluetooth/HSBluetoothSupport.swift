//
//  HSBluetoothSupport.swift
//  Hammerspoon 2
//

import Foundation
import IOKit
import IOBluetooth
import CoreBluetooth

// MARK: - Errors

/// The reason an hs.bluetooth Promise rejects. The message is what JavaScript receives.
nonisolated struct HSBluetoothError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }

    /// The error for a CoreBluetooth manager that can't be used, or nil if it's usable (or still
    /// starting up)
    static func forState(_ state: CBManagerState) -> HSBluetoothError? {
        switch state {
        case .poweredOn, .unknown, .resetting:
            return nil
        case .poweredOff:
            return HSBluetoothError("Bluetooth is turned off")
        case .unauthorized:
            return HSBluetoothError("Bluetooth access has not been allowed, see hs.permissions.requestBluetooth()")
        case .unsupported:
            return HSBluetoothError("Bluetooth Low Energy is not supported on this Mac")
        @unknown default:
            return HSBluetoothError("Bluetooth is unavailable")
        }
    }

    /// The error for a failed IOBluetooth call
    static func forIOReturn(_ status: IOReturn, _ action: String) -> HSBluetoothError {
        HSBluetoothError("\(action) failed (IOReturn 0x\(String(UInt32(bitPattern: status), radix: 16)))")
    }
}

// MARK: - Addresses and UUIDs

nonisolated enum HSBluetoothAddress {
    /// Normalises a Bluetooth address to IOBluetooth's `xx-xx-xx-xx-xx-xx` form, accepting `:` or
    /// `-` separators in either case. Returns nil if it isn't a well-formed address.
    static func normalize(_ address: String) -> String? {
        let parts = address.lowercased().split(whereSeparator: { $0 == "-" || $0 == ":" })
        guard parts.count == 6,
              parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return parts.joined(separator: "-")
    }
}

nonisolated enum HSBluetoothUUID {
    /// Parses a GATT service or characteristic UUID: a 16-bit (`"180F"`, `"0x180f"`) or 32-bit
    /// short form, or a full 128-bit UUID. Returns nil for anything else, rather than letting
    /// `CBUUID(string:)` raise an Objective-C exception.
    static func parse(_ string: String) -> CBUUID? {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
        if (s.count == 4 || s.count == 8), s.allSatisfy(\.isHexDigit) {
            return CBUUID(string: s.uppercased())
        }
        if let uuid = UUID(uuidString: s) {
            return CBUUID(nsuuid: uuid)
        }
        return nil
    }

    // Computed, since CBUUID isn't Sendable
    static var batteryService: CBUUID { CBUUID(string: "180F") }
    static var batteryLevel: CBUUID { CBUUID(string: "2A19") }
    static var deviceInformation: CBUUID { CBUUID(string: "180A") }
    static var humanInterfaceDevice: CBUUID { CBUUID(string: "1812") }

    /// Services that most system-connected LE accessories expose, used to find the CoreBluetooth
    /// peripheral behind a device macOS has already connected. `retrieveConnectedPeripherals`
    /// only returns peripherals offering at least one of the services it's asked about.
    static var commonAccessoryServices: [CBUUID] { [batteryService, deviceInformation, humanInterfaceDevice] }
}

extension CBCharacteristicProperties {
    /// The property names reported to JavaScript
    var names: [String] {
        let all: [(CBCharacteristicProperties, String)] = [
            (.broadcast, "broadcast"),
            (.read, "read"),
            (.writeWithoutResponse, "writeWithoutResponse"),
            (.write, "write"),
            (.notify, "notify"),
            (.indicate, "indicate"),
            (.authenticatedSignedWrites, "authenticatedSignedWrites"),
            (.extendedProperties, "extendedProperties"),
        ]
        return all.filter { contains($0.0) }.map(\.1)
    }
}

// MARK: - Battery levels

/// Battery levels macOS knows for a paired device, without connecting to it
struct HSBluetoothBatteryLevels {
    var level: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    /// The levels of a multi-battery device (e.g. earbuds and their case), as reported to JS
    var components: [String: Int]? {
        var result: [String: Int] = [:]
        if let left { result["left"] = left }
        if let right { result["right"] = right }
        if let caseLevel { result["case"] = caseLevel }
        return result.isEmpty ? nil : result
    }

    /// The single number reported as `batteryLevel`: the device's own level, or for earbuds the
    /// lower of the two buds (the case is a charger, not the device)
    var overall: Int? {
        level ?? [left, right].compactMap { $0 }.min()
    }

    /// Reads every source macOS offers for a paired device's battery:
    ///  - The IORegistry, where Apple's HID accessories (Magic Keyboard, Mouse and Trackpad)
    ///    publish `BatteryPercent`, keyed by their Bluetooth address. Public API.
    ///  - IOBluetoothDevice's `batteryPercent*` methods, which bluetoothd fills in for AirPods,
    ///    Beats and similar. These are private, so each is checked with `responds(to:)` first and
    ///    simply skipped if a macOS update removes it.
    static func read(_ device: IOBluetoothDevice) -> HSBluetoothBatteryLevels {
        var levels = HSBluetoothBatteryLevels()
        if let address = device.addressString.flatMap(HSBluetoothAddress.normalize) {
            levels.level = registryBatteryPercent(forAddress: address)
        }
        if levels.level == nil {
            levels.level = privatePercent(device, "batteryPercentSingle") ?? privatePercent(device, "batteryPercentCombined")
        }
        levels.left = privatePercent(device, "batteryPercentLeft")
        levels.right = privatePercent(device, "batteryPercentRight")
        levels.caseLevel = privatePercent(device, "batteryPercentCase")
        return levels
    }

    /// `BatteryPercent` of the AppleDeviceManagementHIDEventService whose `DeviceAddress` matches
    private static func registryBatteryPercent(forAddress address: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard let matching = unsafe IOServiceMatching("AppleDeviceManagementHIDEventService"),
              unsafe IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let serviceAddress = unsafe IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard let serviceAddress, HSBluetoothAddress.normalize(serviceAddress) == address else { continue }
            let percent = unsafe IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if let percent, percent > 0 { return percent }
        }
        return nil
    }

    /// Calls a private `-(uint8_t)batteryPercentXxx` method, if this macOS has it. 0 means unknown.
    private static func privatePercent(_ device: IOBluetoothDevice, _ name: String) -> Int? {
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        let getter = unsafe unsafeBitCast(device.method(for: selector), to: Getter.self)
        let percent = Int(getter(device, selector))
        return (1...100).contains(percent) ? percent : nil
    }
}
