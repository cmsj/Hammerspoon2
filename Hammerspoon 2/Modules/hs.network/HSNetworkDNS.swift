//
//  HSNetworkDNS.swift
//  Hammerspoon 2
//
//  Shared DNS resolution using getaddrinfo for hs.network.resolve() and hs.network.ping().
//
//  Apple's deprecation notice for CFHost (effective macOS 27) says to use Network.framework,
//  meaning NWConnection for establishing connections. NWConnection only exposes the single
//  address it chose via Happy Eyeballs, so it cannot replace hs.network.resolve() which must
//  return ALL records, nor ping() which needs raw sockaddr bytes for the ICMP socket.
//
//  getaddrinfo is the correct POSIX replacement. On macOS it goes through mDNSResponder —
//  the same system daemon that CFHost and NWConnection use internally — so VPN split-DNS,
//  proxy settings, /etc/hosts, mDNS, and the system cache all apply identically.
//

import Foundation
import Darwin

// MARK: - sockaddr helpers

// nonisolated: these pure helpers are called from background DispatchQueue closures
// as well as from @MainActor contexts, so they must be reachable without hopping.

/// Converts a Data object containing a sockaddr struct to a numeric IP address string.
nonisolated func networkAddressString(from data: Data) -> String? {
    unsafe data.withUnsafeBytes { raw -> String? in
        guard let base = raw.baseAddress else { return nil }
        let sa = unsafe base.assumingMemoryBound(to: sockaddr.self)
        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = unsafe getnameinfo(sa, socklen_t(data.count),
                                    &hostBuf, socklen_t(hostBuf.count),
                                    nil, 0, NI_NUMERICHOST)
        guard rc == 0 else { return nil }
        return String(utf8String: hostBuf)
    }
}

/// Returns AF_INET, AF_INET6, or AF_UNSPEC for a Data-encoded sockaddr.
nonisolated func networkAddressFamily(from data: Data) -> Int32 {
    unsafe data.withUnsafeBytes { raw -> Int32 in
        guard let base = raw.baseAddress else { return AF_UNSPEC }
        let sa = unsafe base.assumingMemoryBound(to: sockaddr.self)
        return Int32(unsafe sa.pointee.sa_family)
    }
}

// MARK: - DNS resolution

/// Resolves `hostname` asynchronously using getaddrinfo on a background thread.
/// Returns sockaddr Data objects filtered by `aiFamily` (AF_INET, AF_INET6, or AF_UNSPEC for both).
/// Throws an NSError on lookup failure (NXDOMAIN, unreachable, etc.).
nonisolated func resolveHostnameToAddresses(_ hostname: String, aiFamily: Int32) async throws -> [Data] {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            var hints = unsafe addrinfo()
            unsafe hints.ai_family = aiFamily

            var resultPtr: UnsafeMutablePointer<addrinfo>?
            let rc = unsafe getaddrinfo(hostname, nil, &hints, &resultPtr)
            defer { if let p = unsafe resultPtr { unsafe freeaddrinfo(p) } }

            guard rc == 0 else {
                continuation.resume(throwing: NSError(
                    domain: "hs.network.resolve",
                    code: Int(rc),
                    userInfo: [NSLocalizedDescriptionKey: unsafe "Failed to resolve '\(hostname)': \(String(utf8String: gai_strerror(rc)) ?? "unknown")"]
                ))
                return
            }

            var seen = Set<String>()
            var addresses: [Data] = []
            var current: UnsafeMutablePointer<addrinfo>? = unsafe resultPtr
            while let ai = unsafe current {
                defer { unsafe current = unsafe ai.pointee.ai_next }
                let family = Int32(unsafe ai.pointee.ai_family)
                guard family == AF_INET || family == AF_INET6 else { continue }
                guard aiFamily == AF_UNSPEC || family == aiFamily else { continue }
                guard let addrPtr = unsafe ai.pointee.ai_addr else { continue }
                let len = Int(unsafe ai.pointee.ai_addrlen)
                let data = unsafe Data(bytes: addrPtr, count: len)
                if let str = networkAddressString(from: data), seen.insert(str).inserted {
                    addresses.append(data)
                }
            }
            continuation.resume(returning: addresses)
        }
    }
}

/// Convenience wrapper: resolves `hostname` and returns numeric IP address strings.
nonisolated func resolveHostnameToStrings(_ hostname: String, aiFamily: Int32) async throws -> [String] {
    let addresses = try await resolveHostnameToAddresses(hostname, aiFamily: aiFamily)
    return addresses.compactMap { networkAddressString(from: $0) }
}
