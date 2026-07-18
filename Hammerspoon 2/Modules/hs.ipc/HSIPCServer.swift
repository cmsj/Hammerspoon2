//
//  HSIPCServer.swift
//  Hammerspoon 2
//

import Foundation
import Observation
import Security

// MARK: - Server

@safe @MainActor
final class HSIPCServer: NSObject {
    static let serviceName = "net.tenshu.Hammerspoon-2.ipc"

    private(set) var isListening = false

    private var listener: NSXPCListener?

    // Per-connection state, keyed by ObjectIdentifier for O(1) add/remove.
    private var connections: [ObjectIdentifier: ConnectionEntry] = [:]

    private struct ConnectionEntry {
        let connection: NSXPCConnection
        var minLogLevel: Int = Int.max
    }

    // UUIDs of log entries already forwarded; seeded at start to skip history.
    private var broadcastedEntryIDs = Set<UUID>()
    private var observationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        guard !isListening else {
            AKWarning("hs.ipc: Already listening")
            return
        }
        let lnr = NSXPCListener(machServiceName: Self.serviceName)
        lnr.delegate = self
        #if !DEBUG
        guard let req = peerSigningRequirement() else {
            AKError("hs.ipc: Cannot determine signing Team ID — refusing to start without peer authentication")
            return
        }
        lnr.setConnectionCodeSigningRequirement(req)
        #else
        AKWarning("hs.ipc: DEBUG build — peer code-signing check disabled")
        #endif
        lnr.resume()
        listener = lnr
        isListening = true
        startObservingLog()
        AKInfo("hs.ipc: Listening on \(Self.serviceName)")
    }

    // Returns a code-signing requirement string that matches any binary signed with
    // the same Team ID as this process. Used with setConnectionCodeSigningRequirement.
    private func peerSigningRequirement() -> String? {
        var selfCode: SecCode?
        guard unsafe SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }

        var selfStatic: SecStaticCode?
        guard unsafe SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess,
              let selfStatic else { return nil }

        var info: CFDictionary?
        guard unsafe SecCodeCopySigningInformation(selfStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let teamID = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else { return nil }

        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        for entry in connections.values { entry.connection.invalidate() }
        connections.removeAll()
        listener?.invalidate()
        listener = nil
        isListening = false
        broadcastedEntryIDs.removeAll()
        AKTrace("hs.ipc: Server stopped")
    }

    // MARK: - Connection management (called via Task { @MainActor } from nonisolated delegate)

    fileprivate func addConnection(_ box: XPCConnectionBox) {
        let conn = unsafe box.connection
        connections[ObjectIdentifier(conn)] = ConnectionEntry(connection: conn)
        AKTrace("hs.ipc: Client connected. Active: \(connections.count)")
    }

    fileprivate func removeConnection(id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
        AKTrace("hs.ipc: Client disconnected. Active: \(connections.count)")
    }

    fileprivate func setMinLogLevel(_ level: Int, connectionID: ObjectIdentifier) {
        connections[connectionID]?.minLogLevel = level
    }

    // MARK: - Log broadcasting

    private func startObservingLog() {
        broadcastedEntryIDs = Set(HammerspoonLog.shared.entries.map { $0.id })
        observationTask = Task { [weak self] in
            let changes = Observations {
                HammerspoonLog.shared.entries.count
            }
            for await _ in changes {
                self?.broadcastNewEntries()
            }
        }
    }

    private func broadcastNewEntries() {
        guard !connections.isEmpty else { return }
        let entries = HammerspoonLog.shared.entries
        var toSend: [HammerspoonLogEntry] = []

        for entry in entries where !broadcastedEntryIDs.contains(entry.id) {
            toSend.append(entry)
            broadcastedEntryIDs.insert(entry.id)
        }

        let currentIDs = Set(entries.map { $0.id })
        broadcastedEntryIDs = broadcastedEntryIDs.intersection(currentIDs)

        for entry in toSend {
            for connEntry in connections.values {
                guard entry.logType.rawValue >= connEntry.minLogLevel else { continue }
                let proxy = connEntry.connection.remoteObjectProxy as? HSIPCClientProtocol
                proxy?.logEntry(level: entry.logType.asString, message: entry.msg)
            }
        }
    }
}

// MARK: - Sendable wrapper for NSXPCConnection
//
// NSXPCConnection is internally thread-safe but not annotated as Sendable in the
// Swift overlay. This thin wrapper carries the @unchecked Sendable annotation so
// that we can pass the connection from the NSXPCListenerDelegate queue to @MainActor.

// A thin Sendable box around NSXPCConnection.
// NSXPCConnection is internally thread-safe but not annotated Sendable in the SDK.
// We use nonisolated(unsafe) so that the stored property is not @MainActor-isolated;
// @unchecked Sendable signals that we take manual responsibility for thread safety.
private final class XPCConnectionBox: NSObject, @unchecked Sendable {
    nonisolated(unsafe) let connection: NSXPCConnection
    nonisolated override init() { fatalError("use init(_:)") }
    nonisolated init(_ conn: NSXPCConnection) {
        unsafe connection = conn
        super.init()
    }
}

// MARK: - NSXPCListenerDelegate

extension HSIPCServer: NSXPCListenerDelegate {
    // Called on NSXPCListener's internal queue — must be nonisolated.
    // Peer authentication is handled by setConnectionCodeSigningRequirement in start().
    nonisolated func listener(_ listener: NSXPCListener,
                               shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HSIPCServerProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: HSIPCClientProtocol.self)
        connection.exportedObject = HSIPCConnectionHandler(server: self, connection: connection)

        // Use ObjectIdentifier (value type, Sendable) to identify the connection in handlers
        // that fire after the connection may have been released.
        let connectionID = ObjectIdentifier(connection)

        connection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in self?.removeConnection(id: connectionID) }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in self?.removeConnection(id: connectionID) }
        }

        // Wrap connection in XPCConnectionBox to cross the isolation boundary safely.
        let box = XPCConnectionBox(connection)
        Task { @MainActor [weak self] in self?.addConnection(box) }

        connection.resume()
        return true
    }

}

// MARK: - Per-connection handler

// nonisolated so NSXPCConnection can dispatch protocol calls from its internal
// queue without crossing into the main actor for every message.
private nonisolated final class HSIPCConnectionHandler: NSObject, HSIPCServerProtocol {
    // Written once at init, read-only thereafter; nonisolated(unsafe) is safe here.
    nonisolated(unsafe) private weak var server: HSIPCServer?
    // ObjectIdentifier is a value type and Sendable; store it directly instead of the
    // non-Sendable NSXPCConnection so we can send it to @MainActor without a wrapper.
    private let connectionID: ObjectIdentifier

    nonisolated init(server: HSIPCServer, connection: NSXPCConnection) {
        unsafe self.server = server
        self.connectionID = ObjectIdentifier(connection)
    }

    func hello(minLogLevel: Int, withReply reply: @escaping (String) -> Void) {
        let level = minLogLevel
        let id = connectionID
        unsafe Task { @MainActor [weak server] in
            server?.setMinLogLevel(level, connectionID: id)
        }
        reply("connected")
    }

    func evaluate(id: String, code: String, withReply reply: @escaping (String, Bool) -> Void) {
        // XPC reply blocks are designed to be called from any thread; wrapping as
        // @unchecked Sendable lets us send the closure to @MainActor for JS evaluation.
        final class ReplyBox: @unchecked Sendable {
            let call: (String, Bool) -> Void
            init(_ fn: @escaping (String, Bool) -> Void) { call = fn }
        }
        let box = ReplyBox(reply)
        Task { @MainActor in
            let (result, isError) = HSIPCConnectionHandler.evalJS(code)
            box.call(result, isError)
        }
    }

    @MainActor
    private static func evalJS(_ code: String) -> (String, Bool) {
        JSEngine.shared["__hs_ipc_eval"] = code
        let wrapper = """
        (function() {
            var __code = __hs_ipc_eval;
            __hs_ipc_eval = undefined;
            try {
                var result = (0, eval)(__code);
                var str;
                if (result === undefined) {
                    str = "undefined";
                } else if (result === null) {
                    str = "null";
                } else if (typeof result === 'string') {
                    str = result;
                } else if (typeof result === 'function') {
                    str = result.toString();
                } else {
                    try { str = JSON.stringify(result, null, 2); } catch(_e) { str = String(result); }
                }
                return JSON.stringify([false, str]);
            } catch(err) {
                return JSON.stringify([true, err.toString()]);
            }
        })()
        """
        defer { JSEngine.shared["__hs_ipc_eval"] = nil }
        guard let raw = JSEngine.shared.eval(wrapper) as? String,
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count == 2,
              let isError = arr[0] as? Bool,
              let resultStr = arr[1] as? String else {
            return ("undefined", false)
        }
        return (resultStr, isError)
    }
}
