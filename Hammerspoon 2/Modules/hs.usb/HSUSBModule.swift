//
//  HSUSBModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOKit

// USB device property keys from the IOKit registry
private let usbProductNameKey = "USB Product Name"
private let usbVendorNameKey = "USB Vendor Name"
private let usbProductIDKey = "idProduct"
private let usbVendorIDKey = "idVendor"
private let usbSerialNumberKey = "USB Serial Number"
private let usbLocationIDKey = "locationID"

// MARK: - IOKit helpers (file-scope, no actor isolation needed)

private func readUSBDeviceProperties(from device: io_service_t) -> [String: Any]? {
    var propertiesRef: Unmanaged<CFMutableDictionary>?
    guard unsafe IORegistryEntryCreateCFProperties(device, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = unsafe propertiesRef?.takeRetainedValue() as? [String: Any] else {
        return nil
    }

    var info: [String: Any] = [
        "productName": (properties[usbProductNameKey] as? String) ?? "",
        "vendorName":  (properties[usbVendorNameKey]  as? String) ?? "",
        "productID":   (properties[usbProductIDKey]   as? Int)    ?? 0,
        "vendorID":    (properties[usbVendorIDKey]    as? Int)    ?? 0
    ]
    if let serial = properties[usbSerialNumberKey] as? String, !serial.isEmpty {
        info["serialNumber"] = serial
    }
    if let locationID = properties[usbLocationIDKey] {
        info["locationID"] = locationID
    }
    return info
}

private func drainUSBIterator(_ iterator: io_iterator_t) -> [[String: Any]] {
    var infos: [[String: Any]] = []
    var device = IOIteratorNext(iterator)
    while device != IO_OBJECT_NULL {
        if let info = readUSBDeviceProperties(from: device) {
            infos.append(info)
        }
        IOObjectRelease(device)
        device = IOIteratorNext(iterator)
    }
    return infos
}

// MARK: - Protocol

/// Module for monitoring USB device connections and disconnections
@objc protocol HSUSBModuleAPI: JSExport {

    /// Returns all currently attached USB devices.
    ///
    /// - Returns: An array of objects describing each attached USB device. Each object has `productName` (string), `vendorName` (string), `productID` (number), and `vendorID` (number). `serialNumber` (string) and `locationID` (number) are included when available.
    /// - Example:
    /// ```js
    /// const devices = hs.usb.attachedDevices()
    /// devices.forEach(d => console.log(d.vendorName + " " + d.productName))
    /// ```
    @objc func attachedDevices() -> [[String: Any]]

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSValue? { get set }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.usb.js. They must be real, pre-declared properties (not
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

@safe @MainActor
@_documentation(visibility: private)
@objc class HSUSBModule: NSObject, HSModuleAPI, HSUSBModuleAPI {
    var moduleName = "hs.usb"
    let engineID: UUID

    @objc var _watcherEmitter: JSValue? = nil
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    // A plain strong reference, not a JSCallback/JSManagedValue: this module is a Swift-lifecycle
    // singleton (torn down deterministically via shutdown(), not by JS reachability), and
    // ModuleRoot.usb is a computed accessor with no JS wrapper ever pinned for it - so
    // JSManagedValue's "owner reachable from JS" condition goes false on the very next GC pass
    // after _addWatcher() returns, silently killing the callback while the native IOKit watcher
    // keeps running. shutdown()/_removeWatcher() already explicitly nil this out, same as
    // _watcherEmitter above, so there is no actual leak risk in holding it directly.
    private var listener: JSFunction?
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var addedIterator: io_iterator_t = IO_OBJECT_NULL
    private var removedIterator: io_iterator_t = IO_OBJECT_NULL
    // Retained reference passed as IOKit refCon; balanced by .release() in _removeWatcher()
    nonisolated(unsafe) private var selfRef: Unmanaged<HSUSBModule>?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = attachedDevices().count
        return "<\(moduleName): \(n) attached device\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func attachedDevices() -> [[String: Any]] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard unsafe IOServiceGetMatchingServices(kIOMainPortDefault,
                                          IOServiceMatching("IOUSBHostDevice"),
                                          &iterator) == KERN_SUCCESS else {
            AKWarning("hs.usb.attachedDevices(): Failed to enumerate USB devices")
            return []
        }
        defer { IOObjectRelease(iterator) }
        return drainUSBIterator(iterator)
    }

    // MARK: - Pattern A watcher internals

    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool {
        guard self.listener == nil else {
            AKWarning("hs.usb._addWatcher(): Already watching. Refusing to create a second.")
            return false
        }

        self.listener = listener

        guard let port = unsafe IONotificationPortCreate(kIOMainPortDefault) else {
            AKError("hs.usb._addWatcher(): Failed to create IOKit notification port")
            self.listener = nil
            return false
        }
        unsafe notificationPort = port

        let source = unsafe IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        // Retain self so the raw pointer passed to IOKit stays valid for the watcher lifetime.
        // IOServiceAddMatchingNotification consumes the matching dict reference it is given,
        // so we pass matching dicts inline — ARC manages their lifetime around the call.
        unsafe selfRef = Unmanaged.passRetained(self)
        let refCon: UnsafeMutableRawPointer = unsafe selfRef!.toOpaque()

        // "Device added" notifications
        let addedStatus = unsafe IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
            { (refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) in
                guard let refCon = unsafe refCon else { return }
                let infos = drainUSBIterator(iterator)
                let module: HSUSBModule = unsafe Unmanaged<HSUSBModule>.fromOpaque(refCon).takeUnretainedValue()
                MainActor.assumeIsolated { module.fireWatcherEvent("added", infos: infos) }
            },
            refCon, &addedIterator
        )
        // Drain devices already present at watcher start without firing events
        _ = drainUSBIterator(addedIterator)
        guard addedStatus == KERN_SUCCESS else {
            AKError("hs.usb._addWatcher(): Failed to register 'added' notification (error \(addedStatus))")
            _removeWatcher()
            return false
        }

        // "Device removed" notifications
        let removedStatus = unsafe IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
            { (refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) in
                guard let refCon = unsafe refCon else { return }
                let infos = drainUSBIterator(iterator)
                let module: HSUSBModule = unsafe Unmanaged<HSUSBModule>.fromOpaque(refCon).takeUnretainedValue()
                MainActor.assumeIsolated { module.fireWatcherEvent("removed", infos: infos) }
            },
            refCon, &removedIterator
        )
        _ = drainUSBIterator(removedIterator)
        guard removedStatus == KERN_SUCCESS else {
            AKError("hs.usb._addWatcher(): Failed to register 'removed' notification (error \(removedStatus))")
            _removeWatcher()
            return false
        }

        AKDebug("hs.usb._addWatcher(): Started")
        return true
    }

    @objc func _removeWatcher() {
        guard listener != nil else { return }

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

        listener = nil

        AKDebug("hs.usb._removeWatcher(): Stopped")
    }

    // MARK: - Private

    private func fireWatcherEvent(_ eventType: String, infos: [[String: Any]]) {
        for info in infos {
            _ = listener?.call(withArguments: [eventType, info])
        }
    }
}
