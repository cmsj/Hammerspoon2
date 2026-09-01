//
//  HSSerialModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOKit

// MARK: - IOKit helpers (file-scope, no actor isolation needed)

private let serialBaseNameKey = "IOTTYBaseName"
private let serialDeviceNameKey = "IOTTYDevice"
private let serialCalloutPathKey = "IOCalloutDevice"
private let serialDialinPathKey = "IODialinDevice"

private func registryStringProperty(_ device: io_service_t, key: String) -> String? {
    guard let cfValue = unsafe IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0) else {
        return nil
    }
    return unsafe cfValue.takeRetainedValue() as? String
}

/// A JS-safe (String/Int/Double/Bool) snapshot of a serial device's IOKit registry properties.
private func sanitizedProperties(from device: io_service_t) -> [String: Any] {
    var propertiesRef: Unmanaged<CFMutableDictionary>?
    guard unsafe IORegistryEntryCreateCFProperties(device, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = unsafe propertiesRef?.takeRetainedValue() as? [String: Any] else {
        return [:]
    }

    var sanitized: [String: Any] = [:]
    for (key, value) in properties {
        switch value {
        case let v as String: sanitized[key] = v
        case let v as Bool: sanitized[key] = v
        case let v as Int: sanitized[key] = v
        case let v as Double: sanitized[key] = v
        case let v as NSNumber: sanitized[key] = v
        default: continue
        }
    }
    return sanitized
}

private struct SerialDeviceIdentity {
    let name: String
    let path: String
}

private func serialDeviceIdentity(from device: io_service_t) -> SerialDeviceIdentity? {
    guard let name = registryStringProperty(device, key: serialDeviceNameKey),
          let path = registryStringProperty(device, key: serialCalloutPathKey) else {
        return nil
    }
    return SerialDeviceIdentity(name: name, path: path)
}

private func drainSerialIdentities(_ iterator: io_iterator_t) -> [SerialDeviceIdentity] {
    var results: [SerialDeviceIdentity] = []
    var device = IOIteratorNext(iterator)
    while device != IO_OBJECT_NULL {
        if let identity = serialDeviceIdentity(from: device) {
            results.append(identity)
        }
        IOObjectRelease(device)
        device = IOIteratorNext(iterator)
    }
    return results
}

private func drainSerialDeviceInfos(_ iterator: io_iterator_t) -> [[String: Any]] {
    var infos: [[String: Any]] = []
    var device = IOIteratorNext(iterator)
    while device != IO_OBJECT_NULL {
        if let identity = serialDeviceIdentity(from: device) {
            infos.append(["name": identity.name, "path": identity.path])
        }
        IOObjectRelease(device)
        device = IOIteratorNext(iterator)
    }
    return infos
}

private func currentSerialIdentities() -> [SerialDeviceIdentity] {
    var iterator: io_iterator_t = IO_OBJECT_NULL
    guard unsafe IOServiceGetMatchingServices(kIOMainPortDefault,
                                      IOServiceMatching("IOSerialBSDClient"),
                                      &iterator) == KERN_SUCCESS else {
        AKWarning("hs.serial: Failed to enumerate serial devices")
        return []
    }
    defer { IOObjectRelease(iterator) }
    return drainSerialIdentities(iterator)
}

// MARK: - Protocol

/// Communicate with devices connected to serial ports (RS-232, USB-serial adapters, etc).
///
/// IMPORTANT NOTE: This module is not currently very well tested with real hardware. Please provide feedback
/// (positive or negative!) via GitHub Issues.
///
/// Enumerate available ports with `availablePortNames()`/`availablePortPaths()`, then create a
/// port object with `createPortNamed()`/`createPortAtPath()`. The returned object is not open
/// until you call `open()` on it.
///
/// - Example:
/// ```js
/// const port = hs.serial.createPortNamed(hs.serial.availablePortNames()[0])
/// port.baudRate = 9600
/// port.setCallback((event, data) => {
///     if (event === "received") {
///         console.log("Received: " + data)
///     }
/// }).open()
/// port.sendData("AT\r\n")
/// ```
@objc protocol HSSerialModuleAPI: JSExport {

    /// Returns the names of all currently connected serial ports.
    /// - Returns: An array of port name strings (e.g. `"usbserial-1420"`)
    /// - Example:
    /// ```js
    /// console.log(hs.serial.availablePortNames())
    /// ```
    @objc func availablePortNames() -> [String]

    /// Returns the device paths of all currently connected serial ports.
    /// - Returns: An array of path strings (e.g. `"/dev/cu.usbserial-1420"`)
    /// - Example:
    /// ```js
    /// console.log(hs.serial.availablePortPaths())
    /// ```
    @objc func availablePortPaths() -> [String]

    /// Returns IOKit registry details for all currently connected serial ports.
    /// - Returns: An object keyed by port name, whose values are objects containing that port's IOKit registry properties.
    /// - Example:
    /// ```js
    /// const details = hs.serial.availablePortDetails()
    /// Object.keys(details).forEach(name => console.log(name, details[name]))
    /// ```
    @objc func availablePortDetails() -> [String: [String: Any]]

    /// Creates a serial port object for a port discovered via `availablePortNames()`.
    /// - Parameter name: The port name, as returned by `availablePortNames()`
    /// - Returns: A new `HSSerialPort`, or `null` if no port with that name is currently connected
    /// - Example:
    /// ```js
    /// const port = hs.serial.createPortNamed("usbserial-1420")
    /// ```
    @objc func createPortNamed(_ name: String) -> HSSerialPort?

    /// Creates a serial port object for an arbitrary device path.
    ///
    /// Unlike `createPortNamed()`, the path does not need to correspond to a port
    /// currently discoverable via IOKit — it is only validated when you call `open()`.
    /// - Parameter path: The device path (e.g. `"/dev/cu.usbserial-1420"`)
    /// - Returns: A new `HSSerialPort`
    /// - Example:
    /// ```js
    /// const port = hs.serial.createPortAtPath("/dev/cu.usbserial-1420")
    /// ```
    @objc func createPortAtPath(_ path: String) -> HSSerialPort

    /// Register a listener for serial port connection and disconnection events.
    ///
    /// The listener is called with two arguments: the event type string (`"added"` or `"removed"`)
    /// and a port-info object with `name` and `path` fields.
    /// - Parameter listener: {(event: string, port: {name: string, path: string}) => void} The function to call when a serial port is added or removed
    /// - Example:
    /// ```js
    /// hs.serial.addWatcher((event, port) => console.log(event + ": " + port.name))
    /// ```
    @objc func addWatcher(_ listener: JSFunction)

    /// Remove a previously registered serial port event listener.
    /// - Parameter listener: The function originally passed to `addWatcher`
    /// - Example:
    /// ```js
    /// hs.serial.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@safe @MainActor
@_documentation(visibility: private)
@objc class HSSerialModule: NSObject, HSModuleAPI, HSSerialModuleAPI {
    var moduleName = "hs.serial"
    let engineID: UUID
    private var ports = HSWeakObjectSet<HSSerialPort>()

    @objc var _watcherEmitter: JSFunction? = nil
    private var watcherCallback: JSCallback?
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var addedIterator: io_iterator_t = IO_OBJECT_NULL
    private var removedIterator: io_iterator_t = IO_OBJECT_NULL
    // Retained reference passed as IOKit refCon; balanced by .release() in _removeWatcher()
    nonisolated(unsafe) private var selfRef: Unmanaged<HSSerialModule>?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
        for port in ports.allObjects {
            port.destroy()
        }
        ports.removeAllObjects()
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = ports.allObjects.count
        return "<\(moduleName): \(n) open port\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func availablePortNames() -> [String] {
        currentSerialIdentities().map { $0.name }
    }

    @objc func availablePortPaths() -> [String] {
        currentSerialIdentities().map { $0.path }
    }

    @objc func availablePortDetails() -> [String: [String: Any]] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard unsafe IOServiceGetMatchingServices(kIOMainPortDefault,
                                          IOServiceMatching("IOSerialBSDClient"),
                                          &iterator) == KERN_SUCCESS else {
            AKWarning("hs.serial.availablePortDetails(): Failed to enumerate serial devices")
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [String: [String: Any]] = [:]
        var device = IOIteratorNext(iterator)
        while device != IO_OBJECT_NULL {
            if let identity = serialDeviceIdentity(from: device) {
                result[identity.name] = sanitizedProperties(from: device)
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        return result
    }

    @objc func createPortNamed(_ name: String) -> HSSerialPort? {
        guard let identity = currentSerialIdentities().first(where: { $0.name == name }) else {
            AKWarning("hs.serial.createPortNamed(): No port found named '\(name)'")
            return nil
        }
        let port = HSSerialPort(name: identity.name, path: identity.path)
        ports.add(port)
        return port
    }

    @objc func createPortAtPath(_ path: String) -> HSSerialPort {
        let name = (path as NSString).lastPathComponent
        let port = HSSerialPort(name: name, path: path)
        ports.add(port)
        return port
    }

    @objc func addWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    // MARK: - Pattern A watcher internals

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("hs.serial._addWatcher(): Already watching. Refusing to create a second.")
            return false
        }

        watcherCallback = JSCallback(value: callback, owner: self)

        guard let port = unsafe IONotificationPortCreate(kIOMainPortDefault) else {
            AKError("hs.serial._addWatcher(): Failed to create IOKit notification port")
            watcherCallback?.detach(from: self)
            watcherCallback = nil
            return false
        }
        unsafe notificationPort = port

        let source = unsafe IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        // Retain self so the raw pointer passed to IOKit stays valid for the watcher lifetime.
        unsafe selfRef = Unmanaged.passRetained(self)
        let refCon: UnsafeMutableRawPointer = unsafe selfRef!.toOpaque()

        let addedStatus = unsafe IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching("IOSerialBSDClient"),
            { (refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) in
                guard let refCon = unsafe refCon else { return }
                let infos = drainSerialDeviceInfos(iterator)
                let module: HSSerialModule = unsafe Unmanaged<HSSerialModule>.fromOpaque(refCon).takeUnretainedValue()
                MainActor.assumeIsolated { module.fireWatcherEvent("added", infos: infos) }
            },
            refCon, &addedIterator
        )
        // Drain devices already present at watcher start without firing events
        _ = drainSerialDeviceInfos(addedIterator)
        guard addedStatus == KERN_SUCCESS else {
            AKError("hs.serial._addWatcher(): Failed to register 'added' notification (error \(addedStatus))")
            _removeWatcher()
            return false
        }

        let removedStatus = unsafe IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching("IOSerialBSDClient"),
            { (refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) in
                guard let refCon = unsafe refCon else { return }
                let infos = drainSerialDeviceInfos(iterator)
                let module: HSSerialModule = unsafe Unmanaged<HSSerialModule>.fromOpaque(refCon).takeUnretainedValue()
                MainActor.assumeIsolated { module.fireWatcherEvent("removed", infos: infos) }
            },
            refCon, &removedIterator
        )
        _ = drainSerialDeviceInfos(removedIterator)
        guard removedStatus == KERN_SUCCESS else {
            AKError("hs.serial._addWatcher(): Failed to register 'removed' notification (error \(removedStatus))")
            _removeWatcher()
            return false
        }

        AKDebug("hs.serial._addWatcher(): Started")
        return true
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }

        if addedIterator != IO_OBJECT_NULL {
            IOObjectRelease(addedIterator)
            addedIterator = IO_OBJECT_NULL
        }
        if removedIterator != IO_OBJECT_NULL {
            IOObjectRelease(removedIterator)
            removedIterator = IO_OBJECT_NULL
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        if let port = unsafe notificationPort {
            unsafe IONotificationPortDestroy(port)
            unsafe notificationPort = nil
        }

        unsafe selfRef?.release()
        unsafe selfRef = nil

        watcherCallback?.detach(from: self)
        watcherCallback = nil

        AKDebug("hs.serial._removeWatcher(): Stopped")
    }

    // MARK: - Private

    private func fireWatcherEvent(_ eventType: String, infos: [[String: Any]]) {
        for info in infos {
            _ = watcherCallback?.value?.call(withArguments: [eventType, info])
        }
    }
}
