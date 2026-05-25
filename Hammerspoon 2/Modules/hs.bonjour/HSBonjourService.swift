//
//  HSBonjourService.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin

// MARK: - Service API protocol

/// A discovered Bonjour service record. Call `resolve()` to look up its
/// hostname, port, and addresses.
///
/// Instances are delivered by an `HSBonjourSearch` callback. Call `resolve()`
/// to discover their hostname, port, and addresses, and optionally `monitor()`
/// to watch for TXT record changes.
///
/// ## Callback events
///
/// | Method | Event | Extra data |
/// |--------|-------|------------|
/// | `resolve()` | `"resolved"` | _(none)_ |
/// | `resolve()` | `"stopped"` | _(none)_ |
/// | `resolve()` | `"error"` | error message string |
/// | `monitor()` | `"txtRecord"` | updated TXT record dict |
@objc protocol HSBonjourServiceAPI: HSTypeAPI, JSExport {

    /// A unique identifier assigned to this service object.
    /// - Example:
    /// ```js
    /// console.log(service.identifier)
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

    /// The service port. `-1` until `resolve()` completes.
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

    /// The TXT record as a `{key: value}` object, or `null` if none is available.
    /// Populated after `resolve()` completes or when updated via `monitor()`.
    /// - Example:
    /// ```js
    /// console.log(service.txtRecord)
    /// ```
    @objc var txtRecord: [String: String]? { get }

    /// Whether peer-to-peer Bluetooth/Wi-Fi is included in resolution.
    /// - Example:
    /// ```js
    /// service.includesPeerToPeer = true
    /// ```
    @objc var includesPeerToPeer: Bool { get set }

    /// Resolves the hostname, port, addresses, and TXT record of this service.
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

    /// Starts monitoring the TXT record for changes. The callback fires whenever
    /// the TXT record is updated.
    ///
    /// Call `stopMonitoring()` to unsubscribe.
    /// - Parameter callback: `function(txtRecord)` called when TXT data changes
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// service.monitor(txt => console.log('TXT updated:', txt))
    /// ```
    @objc @discardableResult func monitor(_ callback: JSValue) -> HSBonjourService

    /// Stops any active resolution.
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
}

// MARK: - Service implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourService: NSObject, HSBonjourServiceAPI, NetServiceDelegate {
    @objc var typeName = "HSBonjourService"
    @objc let identifier = UUID().uuidString

    let service: NetService
    private var resolveCallback: JSCallback?
    private var monitorCallback: JSCallback?

    init(netService: NetService) {
        self.service = netService
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

    @objc @discardableResult func resolve(_ timeout: Double, _ callback: JSValue) -> HSBonjourService {
        service.stop()
        resolveCallback = callback.isObject ? JSCallback(value: callback, owner: self) : nil
        service.resolve(withTimeout: timeout)
        AKTrace("HSBonjourService(\(identifier)).resolve(): Resolving '\(name)' (timeout: \(timeout)s)")
        return self
    }

    @objc @discardableResult func monitor(_ callback: JSValue) -> HSBonjourService {
        monitorCallback = callback.isObject ? JSCallback(value: callback, owner: self) : nil
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

    // MARK: - Internal helpers for module shutdown

    func clearCallbacks() {
        resolveCallback?.detach(from: self)
        monitorCallback?.detach(from: self)
        resolveCallback = nil
        monitorCallback = nil
    }

    // MARK: - NetServiceDelegate
    // Apple guarantees main-thread delivery, so these are inferred @MainActor.

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
        _ = resolveCallback?.call(withArguments: ["stopped"])
        resolveCallback = nil
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        let record = Self.parseTXTRecord(data)
        AKTrace("HSBonjourService(\(identifier)): TXT record updated for '\(name)'")
        _ = monitorCallback?.call(withArguments: [record])
    }

    // MARK: - Static helpers

    nonisolated static func errorMessage(from dict: [String: NSNumber]) -> String {
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
            unsafe data.withUnsafeBytes { rawBuffer -> String? in
                guard let base = rawBuffer.baseAddress else { return nil }
                let family = unsafe Int32(base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family)
                switch family {
                case AF_INET:
                    var addr = unsafe base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    guard unsafe inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                    let address = String(utf8String: buffer)
                    return address
                case AF_INET6:
                    var addr = unsafe base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    guard unsafe inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                    let address = String(utf8String: buffer)
                    return address
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
