//
//  HSBluetoothModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOBluetooth

// MARK: - JavaScript API

/// Inspect Bluetooth devices and watch them connect and disconnect.
///
/// ```javascript
/// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
/// hs.bluetooth.connectedDevices().forEach(d => console.log(d.name + " is connected"))
///
/// const nearby = await hs.bluetooth.availableDevices(5)
///
/// hs.bluetooth.on('connected', d => console.log(d.name + " connected"))
/// hs.bluetooth.on('disconnected', d => console.log(d.name + " disconnected"))
/// ```
///
/// macOS asks the user for Bluetooth permission the first time this module is used.
@objc protocol HSBluetoothModuleAPI: JSExport {
    /// Whether the Bluetooth controller is powered on.
    /// - Example:
    /// ```js
    /// console.log("Bluetooth on: " + hs.bluetooth.powered)
    /// ```
    @objc var powered: Bool { get }

    /// All devices paired with this Mac, connected or not.
    ///
    /// - Returns: An array of device objects. Each has `name` (string), `address` (string, `xx-xx-xx-xx-xx-xx`), `connected` (boolean), `paired` (boolean), `classOfDevice` (number), `majorClass` (number), `minorClass` (number) and `serviceClasses` (number). `rssi` (number, dBm) is included only when IOBluetooth has a reading, which in practice means a classic (non-BLE) device found by `availableDevices()`.
    /// - Example:
    /// ```js
    /// hs.bluetooth.pairedDevices().forEach(d => console.log(d.name + " " + d.address))
    /// ```
    @objc func pairedDevices() -> [[String: Any]]

    /// All paired devices that are currently connected.
    ///
    /// - Returns: An array of device objects, see `pairedDevices()` for the shape.
    /// - Example:
    /// ```js
    /// hs.bluetooth.connectedDevices().forEach(d => console.log(d.name + " is connected"))
    /// ```
    @objc func connectedDevices() -> [[String: Any]]

    /// Scans for discoverable devices nearby. Only one scan can run at a time.
    ///
    /// - Parameter seconds: How long to scan for; `0` uses the system default (10 seconds).
    /// - Returns: {Promise<object[]>} A Promise resolving to the devices found, see `pairedDevices()` for the shape. Rejects if the scan fails or is aborted, for example because Bluetooth was switched off.
    /// - Example:
    /// ```js
    /// const nearby = await hs.bluetooth.availableDevices(5)
    /// nearby.forEach(d => console.log(d.name + " " + d.address))
    /// ```
    @objc func availableDevices(_ seconds: Int) -> JSPromise?

    /// Details for one device, looked up by address.
    ///
    /// - Parameter address: The device address as returned in `address`, e.g. `"a4-83-e7-12-34-56"`.
    /// - Returns: A device object (see `pairedDevices()`) with the additional fields `services` (string[], SDP service names), `favorite` (boolean), `incoming` (boolean, true if the device initiated the connection) and `lastAccess` (number, Unix seconds, when known), or `null` if the address is malformed.
    /// - Example:
    /// ```js
    /// hs.bluetooth.on('connected', d => {
    ///     const info = hs.bluetooth.device(d.address)
    ///     console.log(info.name + " rssi=" + info.rssi + " services=" + info.services.join(", "))
    /// })
    /// ```
    @objc func device(_ address: String) -> [String: Any]?

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.bluetooth.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

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

/// Events emitted by hs.bluetooth's watcher
nonisolated enum HSBluetoothEvent: String, HSEventName {
    case connected, disconnected
}

@_documentation(visibility: private)
@MainActor
@objc class HSBluetoothModule: NSObject, HSModuleAPI, HSBluetoothModuleAPI, IOBluetoothDeviceInquiryDelegate {
    var moduleName = "hs.bluetooth"
    let engineID: UUID

    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSBluetoothEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var watcherCallback: JSCallback?
    private var connectNotification: IOBluetoothUserNotification?
    // One disconnect notification per connected device, keyed by address
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    private var inquiry: IOBluetoothDeviceInquiry?
    private var inquiryPromise: JSPromiseHolder?

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
        // The inquiry's delegate is unretained, so clear it before this module can go away
        inquiry?.delegate = nil
        inquiry?.stop()
        inquiry = nil
        inquiryPromise = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = connectedDevices().count
        return "<\(moduleName): \(n) connected device\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc var powered: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    @objc func pairedDevices() -> [[String: Any]] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).map(deviceInfo)
    }

    @objc func connectedDevices() -> [[String: Any]] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .map(deviceInfo)
    }

    @objc func availableDevices(_ seconds: Int) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard inquiry == nil else {
            return context.createRejectedPromise(with: "hs.bluetooth.availableDevices(): a scan is already running")
        }
        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            let inquiry = IOBluetoothDeviceInquiry(delegate: self)!
            if seconds > 0 { inquiry.inquiryLength = UInt8(clamping: seconds) }
            inquiry.updateNewDeviceNames = true
            let status = inquiry.start()
            guard status == kIOReturnSuccess else {
                AKError("hs.bluetooth.availableDevices(): failed to start inquiry (error \(status))")
                holder.rejectWithMessage("hs.bluetooth.availableDevices(): failed to start scan (error \(status))")
                return
            }
            self.inquiry = inquiry
            self.inquiryPromise = holder
        }
    }

    @objc func device(_ address: String) -> [String: Any]? {
        guard let device = IOBluetoothDevice(addressString: address) else { return nil }
        var info = deviceInfo(device)
        info["services"] = (device.services as? [IOBluetoothSDPServiceRecord] ?? []).compactMap { $0.getServiceName() }
        info["favorite"] = device.isFavorite()
        info["incoming"] = device.isIncoming()
        if let date = device.recentAccessDate() {
            info["lastAccess"] = date.timeIntervalSince1970
        }
        return info
    }

    nonisolated func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        onMain { module in
            let found = module.inquiry?.foundDevices() as? [IOBluetoothDevice] ?? []
            let promise = module.inquiryPromise
            module.inquiryPromise = nil
            module.inquiry = nil
            if error != kIOReturnSuccess {
                AKError("hs.bluetooth.availableDevices(): scan failed (error \(error))")
                promise?.rejectWithMessage("hs.bluetooth.availableDevices(): scan failed (error \(error))")
            } else if aborted {
                AKWarning("hs.bluetooth.availableDevices(): scan was aborted")
                promise?.rejectWithMessage("hs.bluetooth.availableDevices(): scan was aborted")
            } else {
                promise?.resolveWith(found.map(module.deviceInfo))
            }
        }
    }

    /// IOBluetooth delivers its notifications on whatever thread CoreBluetooth's XPC connection
    /// uses, not the main thread, so every callback hops to the main actor before touching state.
    private nonisolated func onMain(_ body: @escaping @MainActor (HSBluetoothModule) -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body(self) } }
    }

    // MARK: - Watcher

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("hs.bluetooth._addWatcher: already watching — refusing second subscription")
            return false
        }
        guard let notification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(deviceConnected(_:device:))) else {
            AKError("hs.bluetooth._addWatcher: failed to register for connect notifications")
            return false
        }
        connectNotification = notification
        watcherCallback = JSCallback(value: callback, owner: self)
        // Devices already connected won't fire a connect notification, so watch them for disconnects now
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            watchForDisconnect(device)
        }
        AKDebug("hs.bluetooth._addWatcher: started")
        return true
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("hs.bluetooth._removeWatcher: stopped")
    }

    private func watchForDisconnect(_ device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(deviceDisconnected(_:device:)))
    }

    // Both selectors hop to the main actor, so they can run after _removeWatcher() has already
    // cleaned up, or after a later _addWatcher() has started a new subscription. Each checks that
    // its notification still belongs to the current watcher before registering or firing anything.

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let notification = notification
        nonisolated(unsafe) let device = device
        onMain { module in
            guard module.connectNotification === notification else { return }
            module.watchForDisconnect(device)
            module.fire(.connected, device)
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let notification = notification
        nonisolated(unsafe) let device = device
        onMain { module in
            let address = device.addressString ?? ""
            guard module.disconnectNotifications[address] === notification else { return }
            notification.unregister()
            module.disconnectNotifications[address] = nil
            module.fire(.disconnected, device)
        }
    }

    private func fire(_ event: HSBluetoothEvent, _ device: IOBluetoothDevice) {
        _ = watcherCallback?.value?.call(withArguments: [event.rawValue, deviceInfo(device)])
    }

    // MARK: - Private

    private func deviceInfo(_ device: IOBluetoothDevice) -> [String: Any] {
        var info: [String: Any] = [
            "name": device.name ?? "",
            "address": device.addressString ?? "",
            "connected": device.isConnected(),
            "paired": device.isPaired(),
            "classOfDevice": Int(device.classOfDevice),
            "majorClass": Int(device.deviceClassMajor),
            "minorClass": Int(device.deviceClassMinor),
            "serviceClasses": Int(device.serviceClassMajor)
        ]
        // IOBluetooth only caches an RSSI for classic devices seen in a recent inquiry; it reports
        // 0 or +127 when it has nothing (BLE peripherals never get one via this API).
        let rssi = device.rssi()
        if rssi != 0 && rssi != 127 {
            info["rssi"] = Int(rssi)
        }
        return info
    }
}
