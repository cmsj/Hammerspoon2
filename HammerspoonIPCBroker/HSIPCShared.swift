//
//  HSIPCShared.swift
//  HammerspoonIPCBroker
//
//  This is for data that needs to be shared between the HammerspoonIPCBroker launch agent,
//  Hammerspoon 2 itself (the "host"), and the hs2 command line tool (a "client").
//  This file is compiled into all three binaries.
//
//  Hammerspoon 2 cannot listen on a Mach service itself - only launchd can vend those - so
//  the broker is a launchd agent (registered by the app via SMAppService) that owns two Mach
//  services and relays messages between them:
//
//      hs2  --(clientServiceName)-->  HammerspoonIPCBroker  <--(hostServiceName)--  Hammerspoon 2
//

import Foundation
import MachO
import XPC

nonisolated enum HSIPC {
    /// Bumped whenever any of the message types below change shape, so mismatched
    /// binaries (e.g. an hs2 symlink pointing at an older app bundle) fail clearly.
    static let protocolVersion = 1

    /// Mach service that hs2 connects to.
    static let clientServiceName = "net.tenshu.Hammerspoon-2.ipc"

    /// Mach service that Hammerspoon 2 connects to.
    static let hostServiceName = "net.tenshu.Hammerspoon-2.ipc.host"

    /// Name of the launchd plist in Contents/Library/LaunchAgents, as passed to SMAppService.
    static let launchAgentPlistName = "net.tenshu.Hammerspoon-2.HammerspoonIPCBroker.plist"

    static let appSigningIdentifier = "net.tenshu.Hammerspoon-2"
    static let brokerSigningIdentifier = "net.tenshu.Hammerspoon-2.HammerspoonIPCBroker"

    /// Sentinel log level meaning "send no log messages".
    static let noLogging = Int.max

    /// What Hammerspoon 2 and hs2 require of the broker they connect to.
    static let brokerRequirement = XPCPeerRequirement.isFromSameTeam(andMatchesSigningIdentifier: brokerSigningIdentifier)

    /// This binary's CFBundleShortVersionString and CFBundleVersion. Every target shares the
    /// project's version settings, so these only differ between binaries from different builds.
    static let marketingVersion = ownInfoDictionary()["CFBundleShortVersionString"] as? String
    static let buildVersion = ownInfoDictionary()["CFBundleVersion"] as? String

    /// The broker and hs2 are built with CREATE_INFOPLIST_SECTION_IN_BINARY, so their Info.plist is
    /// in their own image. Reading it from there rather than from disk means a broker that was left
    /// running while Hammerspoon 2 was updated still reports the build it was launched from.
    /// Hammerspoon 2 itself has no such section, so falls back to its bundle's Info.plist.
    private static func ownInfoDictionary() -> [String: Any] {
        var size: UInt = 0
        let header = unsafe #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        if let bytes = unsafe getsectiondata(header, "__TEXT", "__info_plist", &size), size > 0,
           let info = try? unsafe PropertyListSerialization.propertyList(from: unsafe Data(bytes: bytes, count: Int(size)),
                                                                  format: nil) as? [String: Any] {
            return info
        }
        return Bundle.main.infoDictionary ?? [:]
    }
}

// MARK: - hs2 <-> broker

/// Sent by hs2 to the broker. Both cases expect a reply.
nonisolated enum HSIPCClientToBroker: Codable {
    /// Replied to with `HSIPCHelloReply`.
    case hello(protocolVersion: Int, minLogLevel: Int)
    /// Replied to with `HSIPCEvaluationReply`.
    case evaluate(code: String)
}

/// Pushed by the broker to hs2. No reply is expected.
nonisolated enum HSIPCBrokerToClient: Codable {
    case log(level: Int, message: String)
    case hostStatus(connected: Bool)
}

// MARK: - Hammerspoon 2 <-> broker

/// Sent by Hammerspoon 2 to the broker.
nonisolated enum HSIPCHostToBroker: Codable {
    /// Expects a reply: `HSIPCHelloReply`. `buildVersion` is nil from builds that predate it.
    case hello(protocolVersion: Int, buildVersion: String?)
    /// No reply.
    case log(level: Int, message: String)
    /// Expects a reply: `HSIPCAcknowledgement`. Hammerspoon 2 is about to disconnect (hs.ipc.stop(),
    /// a reload, or quitting), so if no hs2 is connected, the broker exits soon after rather than
    /// lingering until its idle timeout. Only sent to brokers whose hello reply had a `buildVersion`.
    case goodbye
    /// No reply. The broker is from a different build of this copy of Hammerspoon 2 (it was left
    /// running while the app was updated), so it disconnects everyone and exits, and launchd starts
    /// the current one on the next connection. Only sent to brokers whose hello reply had a `buildVersion`.
    case exitStaleBroker
}

/// Sent by the broker to Hammerspoon 2.
nonisolated enum HSIPCBrokerToHost: Codable {
    /// Expects a reply: `HSIPCEvaluationReply`.
    case evaluate(code: String)
    /// No reply. The lowest log level any connected hs2 wants, or `HSIPC.noLogging`.
    case setMinimumLogLevel(Int)
    /// Expects a reply: `HSIPCAcknowledgement`. Another Hammerspoon 2 connection has taken over,
    /// so this one must not reconnect. The broker cancels the session once acknowledged.
    case replaced
}

// MARK: - Replies

nonisolated struct HSIPCHelloReply: Codable {
    let protocolVersion: Int
    /// Whether Hammerspoon 2 is currently connected to the broker.
    let hostConnected: Bool
    /// The lowest log level any connected hs2 wants, or `HSIPC.noLogging`.
    let minLogLevel: Int
    /// Path of the running broker executable, so the host can spot a broker that
    /// launchd is running from a different copy of the app.
    let brokerPath: String
    /// The broker's CFBundleVersion, so the host can spot a broker left running from before an
    /// update. Nil from brokers that predate it, which also don't understand `goodbye` or `exitStaleBroker`.
    let buildVersion: String?
    /// The connected Hammerspoon 2's CFBundleVersion, so hs2 can spot that it's from another build.
    /// Nil when Hammerspoon 2 isn't connected, or it or the broker predate it.
    let hostBuildVersion: String?
}

nonisolated struct HSIPCAcknowledgement: Codable {}

nonisolated struct HSIPCEvaluationReply: Codable {
    let result: String
    let isError: Bool
    /// False when the code never ran in Hammerspoon 2's JavaScript engine (it isn't connected,
    /// didn't reply, or couldn't decode the request), in which case `isError` reports that
    /// failure rather than a JavaScript error.
    let wasEvaluated: Bool

    init(result: String, isError: Bool, wasEvaluated: Bool = true) {
        self.result = result
        self.isError = isError
        self.wasEvaluated = wasEvaluated
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decode(String.self, forKey: .result)
        isError = try container.decode(Bool.self, forKey: .isError)
        // Replies from a broker or host that predates this field only ever came from evaluating.
        wasEvaluated = try container.decodeIfPresent(Bool.self, forKey: .wasEvaluated) ?? true
    }
}
