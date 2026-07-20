//
//  HSNetworkModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Darwin
import SystemConfiguration

// MARK: - File-scope helpers (interface & address enumeration)

private func buildDisplayNameMap() -> [String: String] {
    var map: [String: String] = [:]
    let ifaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
    for iface in ifaces {
        guard let bsdName = SCNetworkInterfaceGetBSDName(iface) as String?,
              let displayName = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? else { continue }
        map[bsdName] = displayName
    }
    return map
}

private func addressString(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let rc = unsafe getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
    guard rc == 0 else { return nil }
    return String(utf8String: hostname)
}

private struct NetworkSnapshot {
    let interfaces: [[String: Any]]
    let addresses:  [[String: Any]]
}

private func snapshotNetwork() -> NetworkSnapshot {
    var ifap: UnsafeMutablePointer<ifaddrs>? = nil
    guard unsafe getifaddrs(&ifap) == 0, let root = unsafe ifap else {
        return NetworkSnapshot(interfaces: [], addresses: [])
    }
    defer { unsafe freeifaddrs(root) }

    let displayNames = buildDisplayNameMap()
    var seenNames = Set<String>()
    var interfaces: [[String: Any]] = []
    var addresses:  [[String: Any]] = []

    var ifa: UnsafeMutablePointer<ifaddrs>? = unsafe root
    while let current = unsafe ifa {
        let name  = unsafe String(cString: unsafe current.pointee.ifa_name)
        let flags = unsafe current.pointee.ifa_flags

        if !seenNames.contains(name) {
            seenNames.insert(name)
            var entry: [String: Any] = [
                "name":      name,
                "isLoopback": (flags & UInt32(IFF_LOOPBACK)) != 0,
                "isUp":       (flags & UInt32(IFF_UP))       != 0,
                "isRunning":  (flags & UInt32(IFF_RUNNING))  != 0
            ]
            if let displayName = displayNames[name] {
                entry["displayName"] = displayName
            }
            interfaces.append(entry)
        }

        if let addr = unsafe current.pointee.ifa_addr {
            let family = unsafe addr.pointee.sa_family
            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                if let addrStr = unsafe addressString(from: addr) {
                    addresses.append([
                        "interface": name,
                        "address":   addrStr,
                        "family":    family == UInt8(AF_INET) ? "ipv4" : "ipv6"
                    ])
                }
            }
        }

        unsafe ifa = current.pointee.ifa_next
    }

    return NetworkSnapshot(interfaces: interfaces, addresses: addresses)
}

private func queryPrimaryInterface() -> String? {
    guard let store = SCDynamicStoreCreate(nil, "hs.network" as CFString, nil, nil) else {
        return nil
    }
    let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
    for key in keys {
        if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
           let name = dict["PrimaryInterface"] as? String {
            return name
        }
    }
    return nil
}

// MARK: - Protocol

/// Module for inspecting network interfaces and resolving hostnames
@objc protocol HSNetworkModuleAPI: JSExport {

    /// Returns all network interfaces present on this system.
    ///
    /// Each object contains `name` (string), `isLoopback` (boolean), `isUp` (boolean), and `isRunning` (boolean). A `displayName` string is included when the system provides a human-readable label for the interface (e.g. `"Wi-Fi"` or `"Ethernet"`).
    /// - Returns: An array of objects describing each network interface.
    /// - Example:
    /// ```js
    /// const ifaces = hs.network.interfaces()
    /// ifaces.forEach(i => console.log(i.name + ": " + (i.displayName || "(no display name)")))
    /// ```
    @objc func interfaces() -> [[String: Any]]

    /// Returns the name of the primary network interface, i.e. the one currently providing the default route.
    ///
    /// - Returns: The BSD interface name (e.g. `"en0"`), or `null` if no primary interface can be determined.
    /// - Example:
    /// ```js
    /// const primary = hs.network.primaryInterface()
    /// console.log("Primary interface: " + primary)
    /// ```
    @objc func primaryInterface() -> String?

    /// Returns all IP addresses assigned to this host.
    ///
    /// Each object contains `interface` (the BSD name of the interface), `address` (the address string), and `family` (`"ipv4"` or `"ipv6"`).
    /// - Returns: An array of address objects.
    /// - Example:
    /// ```js
    /// const addrs = hs.network.addresses()
    /// addrs.filter(a => a.family === 'ipv4').forEach(a => console.log(a.interface + ": " + a.address))
    /// ```
    @objc func addresses() -> [[String: Any]]

    /// Asynchronously resolves a hostname to its IP addresses using the system DNS resolver.
    ///
    /// Uses CFHost, which respects the system's network configuration including VPN routes and proxy settings.
    /// - Parameter hostname: The hostname to resolve (e.g. `"example.com"` or `"localhost"`).
    /// - Parameter family?: The address family to query: `"ipv4"` for A records only, `"ipv6"` for AAAA records only, or `"both"` to return all addresses. Defaults to `"both"` when omitted.
    /// - Returns: {Promise<string[]>} A Promise that resolves to an array of IP address strings, or rejects with an error message if the lookup fails.
    /// - Example:
    /// ```js
    /// hs.network.resolve("example.com").then(addrs => {
    ///     addrs.forEach(a => console.log(a))
    /// })
    /// hs.network.resolve("example.com", "ipv4").then(addrs => console.log("IPv4: " + addrs[0]))
    /// ```
    @objc func resolve(_ hostname: String, _ family: String?) -> JSPromise?

    /// Sends ICMP Echo Requests to `server` and reports results via a callback.
    ///
    /// DNS resolution and the first ping begin immediately. The returned object can be used to
    /// pause, resume, or cancel the ping, and to read statistics.
    ///
    /// The `options` argument may be:
    /// - Omitted (or `undefined`) — uses all defaults.
    /// - A callback function — used as the event handler with all other options at their defaults.
    /// - An object with any of: `count` (integer, default 5), `interval` (seconds, default 1.0),
    ///   `timeout` (seconds per packet, default 2.0), `family` (`"any"` | `"ipv4"` | `"ipv6"`, default `"any"`),
    ///   and `callback` (function).
    ///
    /// The callback receives `(ping, event, info)`:
    /// - `"didStart"` — info is the resolved IP address string.
    /// - `"didFail"` — info is an error message string (e.g. DNS failure).
    /// - `"sendPacketFailed"` — info is `[packetObject, errorString]`.
    /// - `"receivedPacket"` — info is the packet object (see `HSNetworkPing.packets()`).
    /// - `"didFinish"` — info is the summary string.
    ///
    /// - Parameter server: A hostname or IP address to ping.
    /// - Parameter options?: {((ping: HSNetworkPing, event: string, info: any) => void) | {count?: number, interval?: number, timeout?: number, family?: string, callback?: (ping: HSNetworkPing, event: string, info: any) => void}} A callback function or options object. Optional.
    /// - Returns: An `HSNetworkPing` object, or `null` if the arguments are invalid.
    /// - Example:
    /// ```js
    /// hs.network.ping("8.8.8.8", (ping, event, info) => {
    ///   if (event === "receivedPacket") {
    ///     console.log("seq " + info.sequenceNumber + " rtt=" + (info.rtt * 1000).toFixed(1) + "ms")
    ///   } else if (event === "didFinish") {
    ///     console.log(ping.summary())
    ///   }
    /// })
    /// ```
    @objc func ping(_ server: String, _ options: JSValue) -> HSNetworkPing?
}

// MARK: - Implementation

@safe @MainActor
@_documentation(visibility: private)
@objc class HSNetworkModule: NSObject, HSModuleAPI, HSNetworkModuleAPI {
    var name = "hs.network"
    let engineID: UUID
    private var pings = HSWeakObjectSet<HSNetworkPing>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        AKDebug("Shutdown of \(name): \(engineID)")
        for ping in pings.allObjects {
            ping.cancel()
        }
        pings.removeAllObjects()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - HSNetworkModuleAPI

    @objc func interfaces() -> [[String: Any]] {
        snapshotNetwork().interfaces
    }

    @objc func primaryInterface() -> String? {
        queryPrimaryInterface()
    }

    @objc func addresses() -> [[String: Any]] {
        snapshotNetwork().addresses
    }

    @objc func resolve(_ hostname: String, _ family: String?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }

        let aiFamily: Int32
        switch family?.lowercased() {
        case nil, "both", "", "undefined", "null":
            aiFamily = AF_UNSPEC
        case "ipv4":
            aiFamily = AF_INET
        case "ipv6":
            aiFamily = AF_INET6
        default:
            return context.createRejectedPromise(with: "hs.network.resolve(): unknown family '\(family!)'. Use \"ipv4\", \"ipv6\", or \"both\".")
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                do {
                    let addrs = try await resolveHostnameToStrings(hostname, aiFamily: aiFamily)
                    holder.resolveWith(addrs)
                } catch {
                    holder.rejectWithMessage(error.localizedDescription)
                }
            }
        }
    }

    @objc func ping(_ server: String, _ options: JSValue) -> HSNetworkPing? {
        var count = 5
        var interval = 1.0
        var timeout = 2.0
        var preferFamily: Int32 = AF_UNSPEC
        var callbackValue: JSValue?

        if !options.isUndefined && !options.isNull {
            if options.isFunction {
                callbackValue = options
            } else if options.isObject {
                let c = options.objectForKeyedSubscript("count")
                if c != nil && c!.isNumber { count = max(1, Int(c!.toInt32())) }

                let i = options.objectForKeyedSubscript("interval")
                if i != nil && i!.isNumber { interval = max(0.1, i!.toDouble()) }

                let t = options.objectForKeyedSubscript("timeout")
                if t != nil && t!.isNumber { timeout = max(0.1, t!.toDouble()) }

                let f = options.objectForKeyedSubscript("family")
                if f != nil && f!.isString {
                    switch f!.toString()?.lowercased() {
                    case "ipv4": preferFamily = AF_INET
                    case "ipv6": preferFamily = AF_INET6
                    default:     preferFamily = AF_UNSPEC
                    }
                }

                let cb = options.objectForKeyedSubscript("callback")
                if cb != nil && cb!.isFunction { callbackValue = cb }
            }
        }

        let ping = HSNetworkPing(server: server, count: count, interval: interval,
                                  timeout: timeout, preferFamily: preferFamily,
                                  callbackValue: callbackValue)
        pings.add(ping)
        return ping
    }
}
