//
//  HSNetworkDNS.swift
//  Hammerspoon 2
//
//  Shared DNS resolution using CFHost for hs.network.resolve() and hs.network.ping().
//  CFHost is more deeply integrated with macOS networking (VPN, proxy, system cache)
//  than raw POSIX getaddrinfo.
//

import Foundation
import CFNetwork
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

// MARK: - CFHost DNS resolution

/// Resolves `hostname` asynchronously using CFHost on a background thread.
/// Returns sockaddr Data objects filtered by `aiFamily` (AF_INET, AF_INET6, or AF_UNSPEC for both).
/// Throws an NSError on lookup failure (NXDOMAIN, unreachable, etc.).
nonisolated func resolveHostnameToAddresses(_ hostname: String, aiFamily: Int32) async throws -> [Data] {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let hostRef = unsafe CFHostCreateWithName(kCFAllocatorDefault, hostname as CFString).takeRetainedValue()
            var streamError = CFStreamError()

            guard unsafe CFHostStartInfoResolution(hostRef, .addresses, &streamError) else {
                continuation.resume(throwing: NSError(
                    domain: "hs.network.resolve",
                    code: Int(streamError.error),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to resolve hostname '\(hostname)' (error \(streamError.error))"]
                ))
                return
            }

            var resolved: DarwinBoolean = false
            guard let cfResult = unsafe CFHostGetAddressing(hostRef, &resolved) else {
                continuation.resume(returning: [])
                return
            }
            let nsAddresses = unsafe cfResult.takeUnretainedValue() as NSArray

            var seen = Set<String>()
            var result: [Data] = []
            for item in nsAddresses {
                guard let data = item as? Data else { continue }
                let family = networkAddressFamily(from: data)
                guard family == AF_INET || family == AF_INET6 else { continue }
                guard aiFamily == AF_UNSPEC || family == aiFamily else { continue }
                if let str = networkAddressString(from: data), seen.insert(str).inserted {
                    result.append(data)
                }
            }
            continuation.resume(returning: result)
        }
    }
}

/// Convenience wrapper: resolves `hostname` and returns numeric IP address strings.
nonisolated func resolveHostnameToStrings(_ hostname: String, aiFamily: Int32) async throws -> [String] {
    let addresses = try await resolveHostnameToAddresses(hostname, aiFamily: aiFamily)
    return addresses.compactMap { networkAddressString(from: $0) }
}
