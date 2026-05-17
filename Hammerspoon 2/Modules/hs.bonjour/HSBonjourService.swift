//
//  HSBonjourService.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin

// MARK: - Service API protocol

/// A Bonjour service record for publishing or resolving on the local network.
///
/// Obtain a local service via `hs.bonjour.createService()` and call `publish()`.
/// Remote services are delivered by an `HSBonjourBrowser` search callback; call
/// `resolve()` on them to discover their hostname, port, and addresses.
///
/// ## Callback events
///
/// | Method | Event | Extra data |
/// |--------|-------|------------|
/// | `publish()` | `"published"` | _(none)_ |
/// | `publish()` | `"stopped"` | _(none)_ |
/// | `publish()` | `"error"` | error message string |
/// | `resolve()` | `"resolved"` | _(none)_ |
/// | `resolve()` | `"stopped"` | _(none)_ |
/// | `resolve()` | `"error"` | error message string |
/// | `monitor()` | `"txtRecord"` | updated TXT record dict |
@objc protocol HSBonjourServiceAPI: HSTypeAPI, JSExport {

    /// A unique identifier assigned to this service object.
    /// - Example:
    /// ```js
    /// const svc = hs.bonjour.createService('My Server', '_http._tcp.', 8080, 'local.')
    /// console.log(svc.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The service name (e.g. `"My Web Server"`).
    /// - Example:
    /// ```js
    /// console.log(service.name)
    /// ```
    @objc var name: String { get }

    /// The service type string (e.g. `"_http._tcp."`).
    /// - Example:
    /// ```js
    /// console.log(service.type)
    /// ```
    @objc var type: String { get }

    /// The mDNS domain (almost always `"local."`).
    /// - Example:
    /// ```js
    /// console.log(service.domain)
    /// ```
    @objc var domain: String { get }

    /// The resolved hostname, or `null` before `resolve()` completes.
    /// - Example:
    /// ```js
    /// service.resolve(5, ev => {
    ///     if (ev === 'resolved') console.log(service.hostname)
    /// })
    /// ```
    @objc var hostname: String? { get }

    /// The service port. For local services this is set immediately; for remote
    /// services it is `-1` until `resolve()` completes.
    /// - Example:
    /// ```js
    /// console.log(service.port)
    /// ```
    @objc var port: Int { get }

    /// IP address strings (IPv4 and/or IPv6) populated after `resolve()` completes.
    /// - Example:
    /// ```js
    /// service.resolve(5, ev => {
    ///     if (ev === 'resolved') console.log(service.addresses)
    /// })
    /// ```
    @objc var addresses: [String] { get }

    /// The TXT record as a `{key: value}` object, or `null` if none is set.
    /// Populated after `resolve()` or `publish()`, or when updated via `monitor()`.
    /// - Example:
    /// ```js
    /// console.log(service.txtRecord)
    /// ```
    @objc var txtRecord: [String: String]? { get }

    /// `true` if this is a locally-created service that can be published;
    /// `false` for services discovered by a browser that can only be resolved.
    /// - Example:
    /// ```js
    /// console.log(service.isLocal)
    /// ```
    @objc var isLocal: Bool { get }

    /// Whether peer-to-peer Bluetooth/Wi-Fi is included in publication/resolution.
    /// - Example:
    /// ```js
    /// service.includesPeerToPeer = true
    /// ```
    @objc var includesPeerToPeer: Bool { get set }

    /// Publishes this service on the local network. Only valid for local services.
    ///
    /// The callback is called with `(event)` or `(event, errorMessage)`:
    /// - `"published"` — now advertising
    /// - `"stopped"` — advertisement stopped
    /// - `"error"` — publication failed; error message in second argument
    /// - Parameter callback: `function(event, data?)` called on status changes
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.bonjour.createService('My Server', '_http._tcp.', 8080, 'local.')
    ///     .publish(ev => console.log('Publish event:', ev))
    /// ```
    @objc @discardableResult func publish(_ callback: JSValue) -> HSBonjourService

    /// Resolves the hostname, port, addresses, and TXT record of a remote service.
    ///
    /// The callback is called with `(event)` or `(event, errorMessage)`:
    /// - `"resolved"` — resolution complete; read `hostname`, `port`, `addresses`, `txtRecord`
    /// - `"stopped"` — resolution stopped before completing
    /// - `"error"` — resolution failed; error message in second argument
    /// - Parameter timeout: seconds before giving up; pass `0` for no timeout
    /// - Parameter callback: `function(event, data?)` called on status changes
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// service.resolve(5, (ev, err) => {
    ///     if (ev === 'resolved') console.log(service.hostname, service.port)
    ///     else console.error('Resolve failed:', err)
    /// })
    /// ```
    @objc @discardableResult func resolve(_ timeout: Double, _ callback: JSValue) -> HSBonjourService

    /// Starts monitoring the TXT record for changes. The callback fires with the
    /// updated TXT record dict whenever it changes.
    ///
    /// Call `stopMonitoring()` to unsubscribe.
    /// - Parameter callback: `function(txtRecord)` called when TXT data changes
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// service.monitor(txt => console.log('TXT updated:', txt))
    /// ```
    @objc @discardableResult func monitor(_ callback: JSValue) -> HSBonjourService

    /// Stops any active publication or resolution.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// service.stop()
    /// ```
    @objc @discardableResult func stop() -> HSBonjourService

    /// Stops TXT record monitoring started by `monitor()`.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// service.stopMonitoring()
    /// ```
    @objc @discardableResult func stopMonitoring() -> HSBonjourService

    /// Updates the TXT record for a published service.
    ///
    /// Has no effect before `publish()` is called.
    /// - Parameter record: a `{key: value}` object of string pairs
    /// - Returns: `true` if the update succeeded, `false` otherwise
    /// - Example:
    /// ```js
    /// service.setTXTRecord({ version: '2', status: 'online' })
    /// ```
    @objc func setTXTRecord(_ record: [String: String]) -> Bool
}

// MARK: - Service implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourService: NSObject, HSBonjourServiceAPI, NetServiceDelegate {
    @objc var typeName = "HSBonjourService"
    @objc let identifier = UUID().uuidString
    @objc let isLocal: Bool

    private let service: NetService
    private var publishCallback: JSValue?
    private var resolveCallback: JSValue?
    private var monitorCallback: JSValue?

    // MARK: - Init (local service for publishing)

    init(name: String, type: String, port: Int32, domain: String) {
        self.service = NetService(domain: domain, type: type, name: name, port: port)
        self.isLocal = true
        super.init()
        unsafe service.delegate = self
    }

    // MARK: - Init (remote service discovered by a browser)

    init(netService: NetService) {
        self.service = netService
        self.isLocal = false
        super.init()
        unsafe service.delegate = self
    }

    // MARK: - HSBonjourServiceAPI properties

    @objc var name: String { service.name }
    @objc var type: String { service.type }
    @objc var domain: String { service.domain }
    @objc var hostname: String? { service.hostName }
    @objc var port: Int { service.port }

    @objc var includesPeerToPeer: Bool {
        get { service.includesPeerToPeer }
        set { service.includesPeerToPeer = newValue }
    }

    @objc var addresses: [String] {
        guard let data = service.addresses else { return [] }
        return Self.parseIPAddresses(from: data)
    }

    @objc var txtRecord: [String: String]? {
        guard let data = service.txtRecordData() else { return nil }
        let dict = Self.parseTXTRecord(data)
        return dict.isEmpty ? nil : dict
    }

    // MARK: - HSBonjourServiceAPI methods

    @objc @discardableResult func publish(_ callback: JSValue) -> HSBonjourService {
        guard isLocal else {
            AKWarning("hs.bonjour service '\(name)': publish() called on a remote service — ignoring")
            return self
        }
        publishCallback = callback.isObject ? callback : nil
        service.publish()
        AKTrace("HSBonjourService(\(identifier)).publish(): Started publishing '\(name)'")
        return self
    }

    @objc @discardableResult func resolve(_ timeout: Double, _ callback: JSValue) -> HSBonjourService {
        guard !isLocal else {
            AKWarning("hs.bonjour service '\(name)': resolve() called on a local service — ignoring")
            return self
        }
        resolveCallback = callback.isObject ? callback : nil
        service.resolve(withTimeout: timeout)
        AKTrace("HSBonjourService(\(identifier)).resolve(): Resolving '\(name)' (timeout: \(timeout)s)")
        return self
    }

    @objc @discardableResult func monitor(_ callback: JSValue) -> HSBonjourService {
        monitorCallback = callback.isObject ? callback : nil
        service.startMonitoring()
        AKTrace("HSBonjourService(\(identifier)).monitor(): Started TXT monitoring for '\(name)'")
        return self
    }

    @objc @discardableResult func stop() -> HSBonjourService {
        service.stop()
        AKTrace("HSBonjourService(\(identifier)).stop(): Stopped '\(name)'")
        return self
    }

    @objc @discardableResult func stopMonitoring() -> HSBonjourService {
        service.stopMonitoring()
        monitorCallback = nil
        AKTrace("HSBonjourService(\(identifier)).stopMonitoring(): Stopped TXT monitoring for '\(name)'")
        return self
    }

    @objc func setTXTRecord(_ record: [String: String]) -> Bool {
        let data = NetService.data(fromTXTRecord: record.mapValues { Data($0.utf8) })
        let success = service.setTXTRecord(data)
        if !success {
            AKWarning("hs.bonjour service '\(name)': setTXTRecord() failed")
        }
        return success
    }

    // MARK: - Internal helpers for module shutdown

    func clearCallbacks() {
        publishCallback = nil
        resolveCallback = nil
        monitorCallback = nil
    }

    // MARK: - NetServiceDelegate
    // Apple guarantees that these callbacks arrive on the main thread, so they
    // are inferred @MainActor alongside the class — no nonisolated needed.

    func netServiceDidPublish(_ sender: NetService) {
        AKTrace("HSBonjourService(\(identifier)): Published '\(name)'")
        _ = publishCallback?.call(withArguments: ["published"])
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let msg = Self.errorMessage(from: errorDict)
        AKError("HSBonjourService(\(identifier)): Failed to publish '\(name)': \(msg)")
        _ = publishCallback?.call(withArguments: ["error", msg])
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        AKTrace("HSBonjourService(\(identifier)): Resolved '\(name)' → \(sender.hostName ?? "?")")
        _ = resolveCallback?.call(withArguments: ["resolved"])
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let msg = Self.errorMessage(from: errorDict)
        AKError("HSBonjourService(\(identifier)): Failed to resolve '\(name)': \(msg)")
        _ = resolveCallback?.call(withArguments: ["error", msg])
    }

    func netServiceDidStop(_ sender: NetService) {
        AKTrace("HSBonjourService(\(identifier)): Stopped '\(name)'")
        _ = publishCallback?.call(withArguments: ["stopped"])
        _ = resolveCallback?.call(withArguments: ["stopped"])
        publishCallback = nil
        resolveCallback = nil
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        let record = Self.parseTXTRecord(data)
        AKTrace("HSBonjourService(\(identifier)): TXT record updated for '\(name)'")
        _ = monitorCallback?.call(withArguments: [record])
    }

    // MARK: - Static helpers

    private nonisolated static func errorMessage(from dict: [String: NSNumber]) -> String {
        let code = dict["NSNetServicesErrorCode"]?.intValue ?? -1
        switch code {
        case 0:  return "Unknown Bonjour error"
        case 1:  return "Service name collision"
        case 2:  return "Service not found"
        case 3:  return "Another operation is already in progress"
        case 4:  return "Bad argument"
        case 5:  return "Cancelled"
        case 6:  return "Invalid"
        case 7:  return "Timed out"
        case 8:  return "Missing required configuration"
        default: return "Bonjour error code \(code)"
        }
    }

    static func parseIPAddresses(from addressData: [Data]) -> [String] {
        return addressData.compactMap { data in
            data.withUnsafeBytes { rawBuffer -> String? in
                guard let base = rawBuffer.baseAddress else { return nil }
                let family = Int32(base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family)
                switch family {
                case AF_INET:
                    var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                    return String(cString: buffer)
                case AF_INET6:
                    var addr = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                    return String(cString: buffer)
                default:
                    return nil
                }
            }
        }
    }

    static func parseTXTRecord(_ data: Data) -> [String: String] {
        NetService.dictionary(fromTXTRecord: data).compactMapValues { valueData in
            valueData.isEmpty ? nil : String(bytes: valueData, encoding: .utf8)
        }
    }
}
