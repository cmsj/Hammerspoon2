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
    /// Expects a reply: `HSIPCHelloReply`.
    case hello(protocolVersion: Int)
    /// No reply.
    case log(level: Int, message: String)
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
}

nonisolated struct HSIPCAcknowledgement: Codable {}

nonisolated struct HSIPCEvaluationReply: Codable {
    let result: String
    let isError: Bool
}
