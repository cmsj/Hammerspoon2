//
//  HSWifiModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreWLAN

// MARK: - Enum <-> String helpers (nonisolated: called from both MainActor and background Task contexts)
//
// CoreWLAN's enums are plain NS_ENUM(NSInteger, ...) types; we translate via rawValue rather
// than pattern-matching on case names, since Swift's exact case-name import (prefix-stripping,
// acronym casing) is not part of any documented/stable contract.

nonisolated private let wifiSecurityLabels: [(Int, String)] = [
    (0, "None"), (1, "WEP"), (2, "WPA Personal"), (3, "WPA Personal Mixed"),
    (4, "WPA2 Personal"), (5, "Personal"), (6, "Dynamic WEP"),
    (7, "WPA Enterprise"), (8, "WPA Enterprise Mixed"), (9, "WPA2 Enterprise"),
    (10, "Enterprise"), (11, "WPA3 Personal"), (12, "WPA3 Enterprise"),
    (13, "WPA3 Transition"), (14, "OWE"), (15, "OWE Transition")
]

nonisolated private let wifiPHYModeLabels: [(Int, String)] = [
    (0, "None"), (1, "A"), (2, "B"), (3, "G"), (4, "N"), (5, "AC"), (6, "AX"), (7, "BE")
]

nonisolated private func wifiSecurityString(_ security: CWSecurity) -> String {
    wifiSecurityLabels.first(where: { $0.0 == security.rawValue })?.1 ?? "Unknown (\(security.rawValue))"
}

nonisolated private func supportedSecurityTypes(for network: CWNetwork) -> [String] {
    wifiSecurityLabels.compactMap { raw, label in
        guard let sec = CWSecurity(rawValue: raw) else { return nil }
        return network.supportsSecurity(sec) ? label : nil
    }
}

nonisolated private func wifiPHYModeString(_ mode: CWPHYMode) -> String {
    wifiPHYModeLabels.first(where: { $0.0 == mode.rawValue })?.1 ?? "Unknown (\(mode.rawValue))"
}

nonisolated private func supportedPHYModes(for network: CWNetwork) -> [String] {
    wifiPHYModeLabels.compactMap { raw, label in
        guard let mode = CWPHYMode(rawValue: raw) else { return nil }
        return network.supportsPHYMode(mode) ? label : nil
    }
}

nonisolated private func wifiInterfaceModeString(_ mode: CWInterfaceMode) -> String {
    switch mode.rawValue {
    case 0: return "None"
    case 1: return "Station"
    case 2: return "IBSS"
    case 3: return "Host AP"
    default: return "Unknown (\(mode.rawValue))"
    }
}

nonisolated private func wifiChannelBandString(_ band: CWChannelBand) -> String {
    switch band.rawValue {
    case 1: return "2GHz"
    case 2: return "5GHz"
    case 3: return "6GHz"
    default: return "unknown"
    }
}

nonisolated private func wifiChannelWidthString(_ width: CWChannelWidth) -> String {
    switch width.rawValue {
    case 1: return "20MHz"
    case 2: return "40MHz"
    case 3: return "80MHz"
    case 4: return "160MHz"
    default: return "unknown"
    }
}

nonisolated private func wifiChannelDictionary(_ channel: CWChannel) -> [String: Any] {
    [
        "band": wifiChannelBandString(channel.channelBand),
        "number": channel.channelNumber,
        "width": wifiChannelWidthString(channel.channelWidth)
    ]
}

nonisolated private func wifiChannelDictionary(_ channel: CWChannel?) -> [String: Any]? {
    channel.map { wifiChannelDictionary($0) }
}

nonisolated private func byteArray(from data: Data?) -> [UInt8] {
    guard let data else { return [] }
    return [UInt8](data)
}

/// JSExport bridges an omitted/undefined or explicit-null JS argument to the literal strings
/// "undefined"/"null", not Swift nil (see HSModule skill's JSExport optional-args note). Any
/// optional String parameter meant to have a "not specified" default must be passed through
/// this first.
nonisolated private func sanitizedOptionalString(_ value: String?) -> String? {
    guard let value, !["undefined", "null", ""].contains(value) else { return nil }
    return value
}

/// Sendable snapshot of a CWNetwork's fields, built off-main-thread during a scan and converted
/// to a `[String: Any]` only after hopping back to the main actor (see HSModule skill's
/// "JSValue retention" / Sendable-crossing guidance).
private struct WifiNetworkInfo: Sendable {
    let ssid: String?
    let bssid: String?
    let rssi: Int
    let noise: Int
    let ibss: Bool
    let countryCode: String?
    let beaconInterval: Int
    let security: [String]
    let phyModes: [String]
    let channelBand: String
    let channelNumber: Int
    let channelWidth: String
    let informationElementData: [UInt8]

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "rssi": rssi,
            "noise": noise,
            "ibss": ibss,
            "beaconInterval": beaconInterval,
            "security": security,
            "phyModes": phyModes,
            "wlanChannel": ["band": channelBand, "number": channelNumber, "width": channelWidth],
            "informationElementData": informationElementData
        ]
        d["ssid"] = ssid
        d["bssid"] = bssid
        d["countryCode"] = countryCode
        return d
    }
}

nonisolated private func wifiNetworkInfo(from network: CWNetwork) -> WifiNetworkInfo {
    let channel = network.wlanChannel
    return WifiNetworkInfo(
        ssid: network.ssid,
        bssid: network.bssid,
        rssi: network.rssiValue,
        noise: network.noiseMeasurement,
        ibss: network.ibss,
        countryCode: network.countryCode,
        beaconInterval: network.beaconInterval,
        security: supportedSecurityTypes(for: network),
        phyModes: supportedPHYModes(for: network),
        channelBand: channel.map { wifiChannelBandString($0.channelBand) } ?? "unknown",
        channelNumber: channel?.channelNumber ?? 0,
        channelWidth: channel.map { wifiChannelWidthString($0.channelWidth) } ?? "unknown",
        informationElementData: byteArray(from: network.informationElementData)
    )
}

nonisolated private func wifiConfigurationDictionary(_ config: CWConfiguration) -> [String: Any] {
    let profiles = config.networkProfiles.array.compactMap { $0 as? CWNetworkProfile }.map { profile -> [String: Any] in
        var p: [String: Any] = ["security": wifiSecurityString(profile.security)]
        p["ssid"] = profile.ssid
        return p
    }
    return [
        "rememberJoinedNetworks": config.rememberJoinedNetworks,
        "requireAdministratorForAssociation": config.requireAdministratorForAssociation,
        "requireAdministratorForIBSSMode": config.requireAdministratorForIBSSMode,
        "requireAdministratorForPower": config.requireAdministratorForPower,
        "networkProfiles": profiles
    ]
}

private enum HSWifiError: LocalizedError {
    case interfaceNotFound

    var errorDescription: String? {
        switch self {
        case .interfaceNotFound: return "Wi-Fi interface not found"
        }
    }
}

// MARK: - Module API protocol

/// Control and query Wi-Fi interfaces, scan for networks, and watch for Wi-Fi events.
///
/// Built on CoreWLAN. Fields that reveal network identity — `ssid`, `bssid`, `countryCode`,
/// and BSSIDs inside scan results — are only populated once Location Services is enabled and
/// the user has authorized this app; call `hs.permissions.requestLocation()` first (the same
/// gate `hs.location` uses). Without authorization these fields are `null`/omitted, not errors.
@objc protocol HSWifiModuleAPI: JSExport {

    /// Returns the names of all Wi-Fi interfaces attached to the system (e.g. `["en0"]`).
    /// - Returns: an array of interface name strings
    /// - Example:
    /// ```js
    /// console.log(hs.wifi.interfaces())
    /// ```
    @objc func interfaces() -> [String]

    /// Returns detailed information about a Wi-Fi interface.
    /// - Parameter interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Returns: a table with keys `interface, active, power, ssid, bssid, security, interfaceMode, activePHYMode, rssi, noise, transmitRate, transmitPower, countryCode, hardwareAddress, wlanChannel, supportedChannels, cachedScanResults, configuration`; or null if the interface doesn't exist. `ssid`/`bssid`/`countryCode`/`wlanChannel` may be absent without Location Services authorization.
    /// - Example:
    /// ```js
    /// const info = hs.wifi.interfaceDetails()
    /// if (info) console.log(info.ssid + " on channel " + info.wlanChannel.number)
    /// ```
    @objc func interfaceDetails(_ interface: String?) -> [String: Any]?

    /// Returns the SSID of the network currently joined on an interface.
    /// - Parameter interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Returns: the SSID string, or null if not joined to a network (or Location Services is not authorized)
    /// - Example:
    /// ```js
    /// console.log(hs.wifi.currentNetwork())
    /// ```
    @objc func currentNetwork(_ interface: String?) -> String?

    /// Turns a Wi-Fi interface on or off.
    /// - Parameters:
    ///   - state: true to power the interface on, false to power it off
    ///   - interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Returns: true if the power state was changed successfully, false if the interface doesn't exist or the change failed (see the Console for the reason)
    /// - Example:
    /// ```js
    /// hs.wifi.setPower(false) // turn Wi-Fi off
    /// ```
    @objc func setPower(_ state: Bool, _ interface: String?) -> Bool

    /// Disconnects an interface from its current network.
    /// - Parameter interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Example:
    /// ```js
    /// hs.wifi.disassociate()
    /// ```
    @objc func disassociate(_ interface: String?)

    /// Scans for a network by SSID and joins it. Enterprise networks are not supported.
    ///
    /// This can take several seconds; it runs off the main thread so it does not block the app.
    /// - Parameters:
    ///   - ssid: the SSID of the network to join
    ///   - passphrase?: the network passphrase; required for WEP/WPA/WPA2/WPA3 Personal networks
    ///   - interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Returns: {Promise<boolean>} A Promise that resolves `true` if joined successfully, `false` if no network with that SSID was found, or rejects if the interface doesn't exist or the association attempt fails
    /// - Example:
    /// ```js
    /// hs.wifi.associate("MyNetwork", "hunter2")
    ///     .then(joined => console.log(joined ? "Joined" : "Network not found"))
    ///     .catch(err => console.log("Error: " + err))
    /// ```
    @objc func associate(_ ssid: String, _ passphrase: String?, _ interface: String?) -> JSPromise?

    /// Scans for visible Wi-Fi networks.
    ///
    /// This can take a few seconds; it runs off the main thread so it does not block the app.
    /// - Parameter interface?: the interface name as returned by `interfaces()`; omit for the system's default Wi-Fi interface
    /// - Returns: {Promise<object[]>} A Promise that resolves to an array of network tables, each with keys `ssid, bssid, rssi, noise, ibss, countryCode, beaconInterval, security, phyModes, wlanChannel, informationElementData`; or rejects if the interface doesn't exist or the scan fails. `bssid`/`countryCode` may be absent without Location Services authorization. `informationElementData` is raw beacon/probe-response data returned as an array of byte values (0-255) rather than a string, since it can contain sequences that are unsafe to render as text.
    /// - Example:
    /// ```js
    /// hs.wifi.scanNetworks().then(networks => {
    ///     networks.forEach(n => console.log(n.ssid + " (" + n.rssi + " dBm)"))
    /// })
    /// ```
    @objc func scanNetworks(_ interface: String?) -> JSPromise?

    /// The Wi-Fi event types that can be passed to `HSWifiWatcher.events`.
    /// - Example:
    /// ```js
    /// console.log(hs.wifi.watcherEventTypes)
    /// ```
    @objc var watcherEventTypes: [String] { get }

    /// Creates a new Wi-Fi event watcher. Call `.setCallback()` and `.start()` to activate it.
    /// The watcher is stopped automatically when the module shuts down.
    /// - Returns: an HSWifiWatcher
    /// - Example:
    /// ```js
    /// const w = hs.wifi.addWatcher()
    /// w.setCallback((event, info) => console.log(event, info)).start()
    /// ```
    @objc func addWatcher() -> HSWifiWatcher
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWifiModule: NSObject, HSModuleAPI, HSWifiModuleAPI, CWEventDelegate {
    var name = "hs.wifi"
    let engineID: UUID

    private let client = CWWiFiClient()
    private var eventRefCounts: [CWEventType: Int] = [:]
    private var watchers = HSWeakObjectSet<HSWifiWatcher>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        client.delegate = self
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for watcher in watchers.allObjects { watcher.destroy() }
        watchers.removeAllObjects()
        eventRefCounts.removeAll()
        client.delegate = nil
        try? client.stopMonitoringAllEvents()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
        shutdown()
    }

    // MARK: - HSWifiModuleAPI

    @objc func interfaces() -> [String] {
        client.interfaceNames() ?? []
    }

    @objc func interfaceDetails(_ interfaceName: String?) -> [String: Any]? {
        guard let interface = client.interface(withName: sanitizedOptionalString(interfaceName)) else { return nil }

        var details: [String: Any] = [
            "active": interface.serviceActive(),
            "power": interface.powerOn(),
            "rssi": interface.rssiValue(),
            "noise": interface.noiseMeasurement(),
            "transmitRate": interface.transmitRate(),
            "transmitPower": interface.transmitPower(),
            "security": wifiSecurityString(interface.security()),
            "interfaceMode": wifiInterfaceModeString(interface.interfaceMode()),
            "activePHYMode": wifiPHYModeString(interface.activePHYMode()),
            "supportedChannels": (interface.supportedWLANChannels() ?? []).map { wifiChannelDictionary($0) },
            "cachedScanResults": (interface.cachedScanResults() ?? []).map { wifiNetworkInfo(from: $0).dictionary }
        ]
        details["interface"] = interface.interfaceName
        details["ssid"] = interface.ssid()
        details["bssid"] = interface.bssid()
        details["countryCode"] = interface.countryCode()
        details["hardwareAddress"] = interface.hardwareAddress()
        details["wlanChannel"] = wifiChannelDictionary(interface.wlanChannel())
        if let config = interface.configuration() {
            details["configuration"] = wifiConfigurationDictionary(config)
        }
        return details
    }

    @objc func currentNetwork(_ interfaceName: String?) -> String? {
        client.interface(withName: sanitizedOptionalString(interfaceName))?.ssid()
    }

    @objc func setPower(_ state: Bool, _ interfaceName: String?) -> Bool {
        guard let interface = client.interface(withName: sanitizedOptionalString(interfaceName)) else {
            AKWarning("hs.wifi.setPower(): No such Wi-Fi interface")
            return false
        }
        do {
            try interface.setPower(state)
            return true
        } catch {
            AKWarning("hs.wifi.setPower(): \(error.localizedDescription)")
            return false
        }
    }

    @objc func disassociate(_ interfaceName: String?) {
        client.interface(withName: sanitizedOptionalString(interfaceName))?.disassociate()
    }

    @objc func associate(_ ssid: String, _ passphrase: String?, _ interfaceName: String?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let sanitizedPassphrase = sanitizedOptionalString(passphrase)
        let sanitizedInterfaceName = sanitizedOptionalString(interfaceName)
        return wrapAsyncInJSPromise(in: context) { holder in
            Task.detached(priority: .userInitiated) {
                do {
                    let success = try Self.performAssociate(ssid: ssid, passphrase: sanitizedPassphrase, interfaceName: sanitizedInterfaceName)
                    await MainActor.run { holder.resolveWith(success) }
                } catch {
                    await MainActor.run { holder.rejectWithMessage(error.localizedDescription) }
                }
            }
        }
    }

    @objc func scanNetworks(_ interfaceName: String?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let sanitizedInterfaceName = sanitizedOptionalString(interfaceName)
        return wrapAsyncInJSPromise(in: context) { holder in
            Task.detached(priority: .userInitiated) {
                do {
                    let infos = try Self.performScan(interfaceName: sanitizedInterfaceName)
                    await MainActor.run { holder.resolveWith(infos.map { $0.dictionary }) }
                } catch {
                    await MainActor.run { holder.rejectWithMessage(error.localizedDescription) }
                }
            }
        }
    }

    @objc var watcherEventTypes: [String] {
        wifiWatcherValidEvents.sorted()
    }

    @objc func addWatcher() -> HSWifiWatcher {
        let watcher = HSWifiWatcher()
        watcher.module = self
        watchers.add(watcher)
        return watcher
    }

    // MARK: - Watcher event (de)registration, ref-counted per CWEventType (see HSAXModule for precedent)

    /// Registers `watcher`'s event types, incrementing shared ref counts. If any event type
    /// fails to register, only the increments made by *this* call are rolled back (other
    /// watchers' active subscriptions are left untouched) and `false` is returned, so the
    /// caller (HSWifiWatcher.start()) can leave itself in a retryable, not-running state
    /// rather than getting stuck "running" with no actual registration.
    @discardableResult
    func startWatching(_ watcher: HSWifiWatcher) -> Bool {
        var incrementedTypes: [CWEventType] = []
        var success = true

        for name in watcher.events {
            guard let type = wifiEventTypeMap[name] else { continue }
            let currentCount = eventRefCounts[type, default: 0]
            guard currentCount == 0 else {
                eventRefCounts[type] = currentCount + 1
                incrementedTypes.append(type)
                continue
            }
            do {
                try client.startMonitoringEvent(with: type)
                eventRefCounts[type] = 1
                incrementedTypes.append(type)
                AKTrace("hs.wifi: started monitoring \(name)")
            } catch {
                AKError("hs.wifi: failed to start monitoring \(name): \(error.localizedDescription)")
                success = false
            }
        }

        if !success {
            for type in incrementedTypes {
                let count = eventRefCounts[type, default: 0]
                eventRefCounts[type] = count - 1
                if count - 1 == 0 {
                    try? client.stopMonitoringEvent(with: type)
                }
            }
        }

        return success
    }

    func stopWatching(_ watcher: HSWifiWatcher) {
        for name in watcher.events {
            guard let type = wifiEventTypeMap[name], let currentCount = eventRefCounts[type], currentCount > 0 else { continue }
            guard currentCount == 1 else {
                eventRefCounts[type] = currentCount - 1
                continue
            }
            do {
                try client.stopMonitoringEvent(with: type)
                eventRefCounts[type] = 0
                AKTrace("hs.wifi: stopped monitoring \(name)")
            } catch {
                // Leave the ref count at 1 so we don't lose track of an event type CoreWLAN
                // is (as far as we know) still actually monitoring.
                AKError("hs.wifi: failed to stop monitoring \(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Off-main-thread scan/associate work (nonisolated static — no access to `self`)

    nonisolated private static func performScan(interfaceName: String?) throws -> [WifiNetworkInfo] {
        let client = CWWiFiClient()
        guard let interface = client.interface(withName: interfaceName) else {
            throw HSWifiError.interfaceNotFound
        }
        let networks = try interface.scanForNetworks(withName: nil)
        return networks.map { wifiNetworkInfo(from: $0) }
    }

    nonisolated private static func performAssociate(ssid: String, passphrase: String?, interfaceName: String?) throws -> Bool {
        let client = CWWiFiClient()
        guard let interface = client.interface(withName: interfaceName) else {
            throw HSWifiError.interfaceNotFound
        }
        let networks = try interface.scanForNetworks(withName: ssid)
        guard let network = networks.first else { return false }
        try interface.associate(to: network, password: passphrase)
        return true
    }

    // MARK: - CWEventDelegate
    //
    // CoreWLAN does not guarantee these arrive on the main thread (v1's Objective-C
    // implementation explicitly dispatch_async'd to the main queue for this reason), so each
    // method is nonisolated and hops via Task { @MainActor in ... } rather than
    // MainActor.assumeIsolated, which would crash if invoked off the main thread.

    nonisolated private func fireEvent(_ name: String, interfaceName: String, rssi: Int? = nil, transmitRate: Double? = nil) {
        Task { @MainActor in
            var info: [String: Any] = ["interface": interfaceName]
            if let rssi { info["rssi"] = rssi }
            if let transmitRate { info["transmitRate"] = transmitRate }
            for watcher in self.watchers.allObjects {
                watcher.fire(event: name, info: info)
            }
        }
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("powerChange", interfaceName: interfaceName)
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("ssidChange", interfaceName: interfaceName)
    }

    nonisolated func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("bssidChange", interfaceName: interfaceName)
    }

    nonisolated func countryCodeDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("countryCodeChange", interfaceName: interfaceName)
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("linkChange", interfaceName: interfaceName)
    }

    nonisolated func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        fireEvent("linkQualityChange", interfaceName: interfaceName, rssi: rssi, transmitRate: transmitRate)
    }

    nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        fireEvent("modeChange", interfaceName: interfaceName)
    }

    nonisolated func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        fireEvent("scanCacheUpdated", interfaceName: interfaceName)
    }

    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor in
            AKWarning("hs.wifi: connection to the Wi-Fi subsystem was interrupted; CoreWLAN will re-register active event subscriptions automatically")
        }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor in
            AKError("hs.wifi: connection to the Wi-Fi subsystem was invalidated")
        }
    }
}

private let wifiEventTypeMap: [String: CWEventType] = [
    "powerChange": CWEventType(rawValue: 1)!,
    "ssidChange": CWEventType(rawValue: 2)!,
    "bssidChange": CWEventType(rawValue: 3)!,
    "countryCodeChange": CWEventType(rawValue: 4)!,
    "linkChange": CWEventType(rawValue: 5)!,
    "linkQualityChange": CWEventType(rawValue: 6)!,
    "modeChange": CWEventType(rawValue: 7)!,
    "scanCacheUpdated": CWEventType(rawValue: 8)!
]
