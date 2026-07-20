//
//  HSNetworkReachability.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Network

// MARK: - Flag constants (matching SCNetworkReachabilityFlags raw values for API compatibility)

// These numeric values are deliberately kept identical to the deprecated SCNetworkReachabilityFlags
// so that JS code checking specific bits against hs.network.reachabilityFlags constants continues
// to work correctly after migration from the v1 API.
let kFlagTransientConnection: UInt32  = 1 << 0    // path.isExpensive (cellular, VPN)
let kFlagReachable: UInt32            = 1 << 1    // path.status == .satisfied
let kFlagConnectionRequired: UInt32   = 1 << 2    // path.status == .requiresConnection
let kFlagConnectionOnTraffic: UInt32  = 1 << 3    // (not determinable via NWPathMonitor)
let kFlagInterventionRequired: UInt32 = 1 << 4    // path.isConstrained (Low Data Mode)
let kFlagConnectionOnDemand: UInt32   = 1 << 5    // (not determinable via NWPathMonitor)
let kFlagIsLocalAddress: UInt32       = 1 << 16   // (not determinable via NWPathMonitor)
let kFlagIsDirect: UInt32             = 1 << 17   // !path.isExpensive when satisfied

// MARK: - File-scope helpers

/// Returns true if `string` is a valid IPv4 or IPv6 address literal.
nonisolated func isValidIPAddress(_ string: String) -> Bool {
    IPv4Address(string) != nil || IPv6Address(string) != nil
}

private func pathToFlags(_ path: NWPath) -> Int {
    var flags: UInt32 = 0
    switch path.status {
    case .satisfied:
        flags |= kFlagReachable
        if path.isExpensive {
            flags |= kFlagTransientConnection
        } else {
            flags |= kFlagIsDirect
        }
    case .requiresConnection:
        flags |= kFlagConnectionRequired
    case .unsatisfied:
        break
    @unknown default:
        break
    }
    if path.isConstrained {
        flags |= kFlagInterventionRequired
    }
    return Int(flags)
}

private func pathToString(_ path: NWPath) -> String {
    let satisfied = path.status == .satisfied
    var s = ""
    s += path.isExpensive                         ? "t" : "-"
    s += satisfied                                 ? "R" : "-"
    s += path.status == .requiresConnection        ? "c" : "-"
    s += "-"                                       // connectionOnTraffic — not determinable
    s += path.isConstrained                        ? "i" : "-"
    s += "-"                                       // connectionOnDemand — not determinable
    s += "-"                                       // isLocalAddress — not determinable per-address
    s += satisfied && !path.isExpensive            ? "d" : "-"
    return s
}

// MARK: - Instance protocol

/// An active or inactive network reachability monitor. Create with `hs.network.reachability*()`.
@objc protocol HSNetworkReachabilityAPI: HSTypeAPI, JSExport {

    /// Always `"HSNetworkReachability"`.
    @objc var typeName: String { get }

    /// Returns the current reachability flags as a numeric bitmask.
    ///
    /// Compare against constants in `hs.network.reachabilityFlags`. Returns `0` if the
    /// network is currently unreachable.
    /// - Returns: A number representing the current reachability bitmask.
    /// - Example:
    /// ```js
    /// const r = hs.network.reachabilityInternet()
    /// const f = hs.network.reachabilityFlags
    /// console.log("Reachable: " + ((r.status() & f.reachable) !== 0))
    /// ```
    @objc func status() -> Int

    /// Returns a human-readable summary of the current reachability flags.
    ///
    /// The string contains 8 characters in order: `t` (transient/expensive), `R` (reachable),
    /// `c` (connectionRequired), `C` (connectionOnTraffic — always `-`), `i` (interventionRequired/constrained),
    /// `D` (connectionOnDemand — always `-`), `l` (isLocalAddress — always `-`), `d` (isDirect).
    /// A letter appears when that flag is set; `-` appears when it is clear.
    /// - Returns: An 8-character flag string such as `"-R-----d"`.
    /// - Example:
    /// ```js
    /// const r = hs.network.reachabilityInternet()
    /// console.log(r.statusString())  // e.g. "-R-----d"
    /// ```
    @objc func statusString() -> String

    /// Replaces the callback invoked when reachability changes.
    ///
    /// The callback receives `(reachability, flags)` where `flags` is the same numeric
    /// bitmask as returned by `status()`. Call `start()` after `setCallback()` to begin
    /// monitoring.
    /// - Parameter callback: {(reachability: HSNetworkReachability, flags: number) => void} Called on each reachability status change.
    /// - Returns: This reachability object for chaining.
    /// - Example:
    /// ```js
    /// hs.network.reachabilityInternet()
    ///   .setCallback((r, flags) => console.log(r.statusString()))
    ///   .start()
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkReachability

    /// Starts monitoring for reachability changes.
    ///
    /// After calling `start()`, the callback registered with `setCallback()` is invoked
    /// whenever the reachability status changes.
    /// - Returns: This reachability object for chaining.
    /// - Example:
    /// ```js
    /// hs.network.reachabilityInternet()
    ///   .setCallback((r, flags) => console.log(r.statusString()))
    ///   .start()
    /// ```
    @objc @discardableResult func start() -> HSNetworkReachability

    /// Stops monitoring for reachability changes.
    ///
    /// The callback will no longer be invoked. Call `start()` again to resume monitoring.
    /// - Returns: This reachability object for chaining.
    /// - Example:
    /// ```js
    /// r.stop()
    /// ```
    @objc @discardableResult func stop() -> HSNetworkReachability
}

// MARK: - Instance class

@_documentation(visibility: private)
@MainActor
@objc final class HSNetworkReachability: NSObject, HSNetworkReachabilityAPI {
    @objc var typeName = "HSNetworkReachability"

    private let monitor = NWPathMonitor()
    private var lastKnownPath: NWPath?
    private var _callback: JSCallback?
    private var _isWatching = false
    private var selfRetain: HSNetworkReachability?   // keeps self alive while watching

    override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated {
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: .main)
    }

    isolated deinit {
        destroy()
        AKDebug("deinit HSNetworkReachability")
    }

    // MARK: - HSNetworkReachabilityAPI

    @objc func status() -> Int {
        pathToFlags(lastKnownPath ?? monitor.currentPath)
    }

    @objc func statusString() -> String {
        pathToString(lastKnownPath ?? monitor.currentPath)
    }

    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkReachability {
        _callback?.detach(from: self)
        _callback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc @discardableResult func start() -> HSNetworkReachability {
        guard !_isWatching else { return self }
        _isWatching = true
        selfRetain = self
        AKTrace("HSNetworkReachability.start()")
        return self
    }

    @objc @discardableResult func stop() -> HSNetworkReachability {
        stopWatching()
        return self
    }

    // MARK: - Internal

    func destroy() {
        stopWatching()
        monitor.cancel()
        _callback?.detach(from: self)
        _callback = nil
    }

    // MARK: - Private

    private func handlePathUpdate(_ path: NWPath) {
        lastKnownPath = path
        guard _isWatching else { return }
        _ = _callback?.call(withArguments: [self, pathToFlags(path)])
    }

    private func stopWatching() {
        guard _isWatching else { return }
        _isWatching = false
        selfRetain = nil
        AKTrace("HSNetworkReachability.stop()")
    }
}
