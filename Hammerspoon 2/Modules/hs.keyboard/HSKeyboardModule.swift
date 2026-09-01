//
//  HSKeyboardModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOKit
import IOKit.hidsystem
import IOKit.hid

// MARK: - LED usage mapping

private enum HSKeyboardLED: String {
    case caps
    case scroll
    case num

    var hidUsage: Int {
        switch self {
        case .caps:   return kHIDUsage_LED_CapsLock
        case .scroll: return kHIDUsage_LED_ScrollLock
        case .num:    return kHIDUsage_LED_NumLock
        }
    }
}

// MARK: - Global HID modifier lock state (IOHIDSystem)
//
// This is a single, system-wide state shared by every keyboard — the same mechanism
// Hammerspoon v1's hs.hid module used. There is no public API to control the *functional*
// caps lock state (i.e. what characters typed keys produce) on a per-keyboard basis.

private func withGlobalHIDConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
    let matching = unsafe IOServiceMatching(kIOHIDSystemClass)
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var connection: io_connect_t = IO_OBJECT_NULL
    guard unsafe IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else {
        return nil
    }
    defer { IOServiceClose(connection) }

    return body(connection)
}

private func readGlobalCapsLockState() -> Bool? {
    withGlobalHIDConnection { connection in
        var state = false
        guard unsafe IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS else {
            return nil
        }
        return state
    }
}

@discardableResult
private func writeGlobalCapsLockState(_ newState: Bool) -> Bool? {
    withGlobalHIDConnection { connection in
        guard IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), newState) == KERN_SUCCESS else {
            return nil
        }
        return newState
    }
}

// MARK: - Keyboard device enumeration (IOHIDManager)
//
// Enumeration (device list + metadata) works without any special permission. Reading or
// writing LED element values requires the user to grant Input Monitoring — see
// hs.permissions.checkInputMonitoring()/requestInputMonitoring(). When permission has not
// been granted, LED reads/writes fail gracefully and return false.

private func withKeyboardManager<T>(_ body: (IOHIDManager) -> T) -> T {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
        kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    // IOHIDManagerOpen() opens both currently-matched and future devices on the manager's
    // behalf, so individual IOHIDDeviceOpen() calls are not needed before
    // IOHIDDeviceGetValue()/IOHIDDeviceSetValue() below.
    _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    return body(manager)
}

private func copyAttachedKeyboardDevices(_ manager: IOHIDManager) -> [IOHIDDevice] {
    guard let deviceSet = IOHIDManagerCopyDevices(manager) else { return [] }
    let count = CFSetGetCount(deviceSet)
    guard count > 0 else { return [] }
    var rawDevices = unsafe [UnsafeRawPointer?](repeating: nil, count: count)
    unsafe CFSetGetValues(deviceSet, &rawDevices)
    return unsafe rawDevices.compactMap { ptr -> IOHIDDevice? in
        guard let ptr = unsafe ptr else { return nil }
        return unsafe Unmanaged<IOHIDDevice>.fromOpaque(ptr).takeUnretainedValue()
    }
}

private func registryEntryID(for device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    guard service != IO_OBJECT_NULL else { return nil }
    var entryID: UInt64 = 0
    guard unsafe IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
    return entryID
}

private func deviceInfo(for device: IOHIDDevice) -> [String: Any]? {
    guard let entryID = registryEntryID(for: device) else { return nil }
    var info: [String: Any] = [
        "keyboardID":  Double(entryID),
        "productName": (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "",
        "vendorName":  (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String) ?? "",
        "productID":   (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0,
        "vendorID":    (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
    ]
    if let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String, !serial.isEmpty {
        info["serialNumber"] = serial
    }
    if let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int {
        info["locationID"] = locationID
    }
    return info
}

private func findKeyboardDevice(withID keyboardID: UInt64, in manager: IOHIDManager) -> IOHIDDevice? {
    copyAttachedKeyboardDevices(manager).first { registryEntryID(for: $0) == keyboardID }
}

private func ledElement(_ usage: Int, on device: IOHIDDevice) -> IOHIDElement? {
    let matching: [String: Any] = [kIOHIDElementUsagePageKey as String: kHIDPage_LEDs]
    guard let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
        return nil
    }
    return elements.first { IOHIDElementGetUsage($0) == UInt32(usage) }
}

private func readLEDState(_ usage: Int, on device: IOHIDDevice) -> Bool? {
    guard let element = ledElement(usage, on: device) else { return nil }
    let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
    defer { unsafe valuePointer.deallocate() }
    guard unsafe IOHIDDeviceGetValue(device, element, valuePointer) == KERN_SUCCESS else { return nil }
    let ref = unsafe valuePointer.pointee.takeUnretainedValue()
    return IOHIDValueGetIntegerValue(ref) != 0
}

@discardableResult
private func writeLEDState(_ usage: Int, _ state: Bool, on device: IOHIDDevice) -> Bool {
    guard let element = ledElement(usage, on: device) else { return false }
    let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, state ? 1 : 0)
    return IOHIDDeviceSetValue(device, element, value) == KERN_SUCCESS
}

// MARK: - Protocol

/// Module for querying and controlling CapsLock state, and for enumerating attached keyboards
/// and controlling their LEDs individually.
@objc protocol HSKeyboardModuleAPI: JSExport {

    /// Checks the system-wide state of CapsLock.
    ///
    /// This reflects a single, global lock state shared by every attached keyboard — macOS has
    /// no public API to query the functional (character-affecting) CapsLock state independently
    /// per keyboard. For a genuinely per-keyboard signal, see `keyboardCapsLockState()`, which
    /// reads each keyboard's own CapsLock LED.
    /// - Returns: true if CapsLock is currently on, false otherwise
    /// - Example:
    /// ```js
    /// console.log(hs.keyboard.capsLockState())
    /// ```
    @objc func capsLockState() -> Bool

    /// Sets the system-wide state of CapsLock.
    /// - Parameter state: true to turn CapsLock on, false to turn it off
    /// - Returns: The new state, or false if the change could not be applied
    /// - Example:
    /// ```js
    /// hs.keyboard.setCapsLockState(true)
    /// ```
    @objc func setCapsLockState(_ state: Bool) -> Bool

    /// Toggles the system-wide state of CapsLock.
    /// - Returns: The new state, or false if the change could not be applied
    /// - Example:
    /// ```js
    /// hs.keyboard.toggleCapsLockState()
    /// ```
    @objc func toggleCapsLockState() -> Bool

    /// Sets a keyboard LED on every attached keyboard that has one.
    /// - Parameter name: The LED to set — one of `"caps"`, `"scroll"`, or `"num"`
    /// - Parameter state: true to turn the LED on, false to turn it off
    /// - Returns: true if the LED was successfully set on at least one keyboard
    /// - Note: Requires Input Monitoring permission — see `hs.permissions.requestInputMonitoring()`.
    /// - Example:
    /// ```js
    /// hs.keyboard.setLED("caps", true)
    /// ```
    @objc func setLED(_ name: String, _ state: Bool) -> Bool

    /// Returns all currently attached keyboard HID devices.
    ///
    /// Each object has `keyboardID` (number — pass to `keyboardCapsLockState()`/`setKeyboardLED()`),
    /// `productName` (string), `vendorName` (string), `productID` (number), and `vendorID` (number).
    /// `serialNumber` (string) and `locationID` (number) are included when available.
    /// - Returns: An array of objects describing each attached keyboard
    /// - Example:
    /// ```js
    /// const keyboards = hs.keyboard.attachedKeyboards()
    /// keyboards.forEach(k => console.log(k.vendorName + " " + k.productName))
    /// ```
    @objc func attachedKeyboards() -> [[String: Any]]

    /// Checks a specific keyboard's own CapsLock LED state.
    ///
    /// Unlike `capsLockState()`, this queries the individual keyboard identified by `keyboardID`
    /// (from `attachedKeyboards()`), reflecting how modern macOS tracks CapsLock independently per
    /// physical keyboard.
    /// - Parameter keyboardID: A keyboard identifier, as returned by `attachedKeyboards()`
    /// - Returns: true if that keyboard's CapsLock LED is on, false if it is off, unavailable, or the keyboard was not found
    /// - Note: Requires Input Monitoring permission — see `hs.permissions.requestInputMonitoring()`.
    /// - Example:
    /// ```js
    /// const keyboards = hs.keyboard.attachedKeyboards()
    /// if (keyboards.length > 0) {
    ///   console.log(hs.keyboard.keyboardCapsLockState(keyboards[0].keyboardID))
    /// }
    /// ```
    @objc func keyboardCapsLockState(_ keyboardID: Double) -> Bool

    /// Sets a specific keyboard's LED, leaving all other attached keyboards untouched.
    /// - Parameter keyboardID: A keyboard identifier, as returned by `attachedKeyboards()`
    /// - Parameter name: The LED to set — one of `"caps"`, `"scroll"`, or `"num"`
    /// - Parameter state: true to turn the LED on, false to turn it off
    /// - Returns: true if the LED was successfully set
    /// - Note: Requires Input Monitoring permission — see `hs.permissions.requestInputMonitoring()`.
    /// - Example:
    /// ```js
    /// const keyboards = hs.keyboard.attachedKeyboards()
    /// if (keyboards.length > 0) {
    ///   hs.keyboard.setKeyboardLED(keyboards[0].keyboardID, "caps", true)
    /// }
    /// ```
    @objc func setKeyboardLED(_ keyboardID: Double, _ name: String, _ state: Bool) -> Bool
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSKeyboardModule: NSObject, HSModuleAPI, HSKeyboardModuleAPI {
    var moduleName = "hs.keyboard"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): capsLock \(capsLockState() ? "on" : "off")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Global CapsLock state

    @objc func capsLockState() -> Bool {
        readGlobalCapsLockState() ?? false
    }

    @objc func setCapsLockState(_ state: Bool) -> Bool {
        guard let result = writeGlobalCapsLockState(state) else {
            AKWarning("hs.keyboard.setCapsLockState(): Failed to set global CapsLock state")
            return false
        }
        return result
    }

    @objc func toggleCapsLockState() -> Bool {
        guard let current = readGlobalCapsLockState() else {
            AKWarning("hs.keyboard.toggleCapsLockState(): Failed to read global CapsLock state")
            return false
        }
        return setCapsLockState(!current)
    }

    // MARK: - Global LED control

    @objc func setLED(_ name: String, _ state: Bool) -> Bool {
        guard let led = HSKeyboardLED(rawValue: name) else {
            AKWarning("hs.keyboard.setLED(): Unsupported LED name '\(name)'")
            return false
        }
        var succeeded = false
        withKeyboardManager { manager in
            for device in copyAttachedKeyboardDevices(manager) where writeLEDState(led.hidUsage, state, on: device) {
                succeeded = true
            }
        }
        if !succeeded {
            AKWarning("hs.keyboard.setLED(): Failed to set '\(name)' LED on any keyboard — Input Monitoring permission may be required")
        }
        return succeeded
    }

    // MARK: - Per-keyboard enumeration and control

    @objc func attachedKeyboards() -> [[String: Any]] {
        withKeyboardManager { manager in
            copyAttachedKeyboardDevices(manager).compactMap { deviceInfo(for: $0) }
        }
    }

    @objc func keyboardCapsLockState(_ keyboardID: Double) -> Bool {
        guard let targetID = UInt64(exactly: keyboardID) else {
            AKWarning("hs.keyboard.keyboardCapsLockState(): Invalid keyboardID \(keyboardID)")
            return false
        }
        return withKeyboardManager { manager -> Bool in
            guard let device = findKeyboardDevice(withID: targetID, in: manager) else {
                AKWarning("hs.keyboard.keyboardCapsLockState(): No attached keyboard with id \(keyboardID)")
                return false
            }
            guard let state = readLEDState(HSKeyboardLED.caps.hidUsage, on: device) else {
                AKWarning("hs.keyboard.keyboardCapsLockState(): Failed to read CapsLock LED — Input Monitoring permission may be required")
                return false
            }
            return state
        }
    }

    @objc func setKeyboardLED(_ keyboardID: Double, _ name: String, _ state: Bool) -> Bool {
        guard let led = HSKeyboardLED(rawValue: name) else {
            AKWarning("hs.keyboard.setKeyboardLED(): Unsupported LED name '\(name)'")
            return false
        }
        guard let targetID = UInt64(exactly: keyboardID) else {
            AKWarning("hs.keyboard.setKeyboardLED(): Invalid keyboardID \(keyboardID)")
            return false
        }
        return withKeyboardManager { manager -> Bool in
            guard let device = findKeyboardDevice(withID: targetID, in: manager) else {
                AKWarning("hs.keyboard.setKeyboardLED(): No attached keyboard with id \(keyboardID)")
                return false
            }
            let succeeded = writeLEDState(led.hidUsage, state, on: device)
            if !succeeded {
                AKWarning("hs.keyboard.setKeyboardLED(): Failed to set '\(name)' LED — Input Monitoring permission may be required")
            }
            return succeeded
        }
    }
}
