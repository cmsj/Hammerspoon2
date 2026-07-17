//
//  HSIPCServer.swift
//  Hammerspoon 2
//

import Foundation
import Network
import Observation

// MARK: - Helpers

private func jsonLine(_ dict: [String: Any]) -> Data? {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
    var line = data
    line.append(0x0A) // '\n'
    return line
}

// MARK: - Single client connection

@safe @MainActor
private final class HSIPCConnection {
    let id = UUID()
    let nwConnection: NWConnection

    // Minimum log type raw value to forward; Int.max means suppress all logs.
    var minLogLevel: Int = Int.max

    private var receiveBuffer = Data()
    private var isActive = false

    weak var server: HSIPCServer?

    init(_ nwConn: NWConnection, server: HSIPCServer) {
        self.nwConnection = nwConn
        self.server = server
    }

    func start() {
        isActive = true
        nwConnection.start(queue: .main)
        sendRaw(["type": "connected", "port": server?.currentPort ?? 0])
        scheduleReceive()
        AKTrace("hs.ipc: Client \(id) connected")
    }

    func cancel() {
        isActive = false
        nwConnection.cancel()
    }

    func sendLogEntry(_ entry: HammerspoonLogEntry) {
        guard entry.logType.rawValue >= minLogLevel else { return }
        sendRaw([
            "type": "log",
            "level": entry.logType.asString,
            "message": entry.msg,
            "timestamp": entry.date.timeIntervalSince1970
        ])
    }

    // MARK: - Private networking

    private func sendRaw(_ dict: [String: Any]) {
        guard isActive, let data = jsonLine(dict) else { return }
        nwConnection.send(content: data, completion: .idempotent)
    }

    private func scheduleReceive() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }
                if isComplete || error != nil {
                    self.isActive = false
                    AKTrace("hs.ipc: Client \(self.id) disconnected")
                    self.server?.connectionClosed(self)
                } else {
                    self.scheduleReceive()
                }
            }
        }
    }

    private func processBuffer() {
        while let nl = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(receiveBuffer[receiveBuffer.startIndex..<nl])
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...nl)
            if !lineData.isEmpty { handleMessage(lineData) }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "hello":
            if let level = json["minLogLevel"] as? Int, level >= 0 {
                minLogLevel = level
            }

        case "eval":
            guard let evalID = json["id"] as? String,
                  let code = json["code"] as? String else { return }
            let (result, isError) = evaluateJS(code)
            sendRaw(["type": "result", "id": evalID, "result": result, "isError": isError])

        default:
            AKWarning("hs.ipc: Unknown message type '\(type)' from client \(id)")
        }
    }

    // MARK: - JS evaluation

    private func evaluateJS(_ code: String) -> (String, Bool) {
        // Pass the code via a temporary JS global to avoid any string-escaping problems.
        // The wrapper immediately captures and clears it before calling eval().
        JSEngine.shared["__hs_ipc_eval"] = code
        let wrapper = """
        (function() {
            var __code = __hs_ipc_eval;
            __hs_ipc_eval = undefined;
            try {
                var result = eval(__code);
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

// MARK: - Listener / server

@safe @MainActor
final class HSIPCServer {
    private(set) var isListening = false
    private(set) var currentPort: Int32 = 0

    private var listener: NWListener?
    private var connections: [UUID: HSIPCConnection] = [:]

    // UUIDs of log entries we have already forwarded to clients.
    // Tracked by UUID so trim-and-add cycles in the ring buffer don't cause duplicates.
    private var broadcastedEntryIDs = Set<UUID>()
    private var observationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start(port: UInt16) throws {
        let lnr = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port) ?? .any)
        listener = lnr

        lnr.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }

        lnr.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if let p = self.listener?.port?.rawValue {
                        self.currentPort = Int32(p)
                        self.isListening = true
                        AKInfo("hs.ipc: Listening on port \(p)")
                        self.startObservingLog()
                    }
                case .failed(let error):
                    AKError("hs.ipc: Listener failed: \(error.localizedDescription)")
                    self.isListening = false
                case .cancelled:
                    self.isListening = false
                default:
                    break
                }
            }
        }

        lnr.start(queue: .main)
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        isListening = false
        currentPort = 0
        broadcastedEntryIDs.removeAll()
        AKTrace("hs.ipc: Server stopped")
    }

    fileprivate func connectionClosed(_ conn: HSIPCConnection) {
        connections.removeValue(forKey: conn.id)
        AKTrace("hs.ipc: Active connections: \(connections.count)")
    }

    // MARK: - Incoming connections

    private func accept(_ nwConn: NWConnection) {
        // Restrict to localhost for security
        if case .hostPort(let host, _) = nwConn.endpoint {
            let h = "\(host)"
            guard h.hasPrefix("127.") || h == "::1" || h == "localhost" else {
                AKWarning("hs.ipc: Rejecting non-localhost connection from \(h)")
                nwConn.cancel()
                return
            }
        }
        let conn = HSIPCConnection(nwConn, server: self)
        connections[conn.id] = conn
        conn.start()
        AKTrace("hs.ipc: Active connections: \(connections.count)")
    }

    // MARK: - Log observation

    private func startObservingLog() {
        // Seed with existing entries so clients only see new messages going forward.
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

        // Prune IDs for entries that were trimmed from the ring buffer.
        let currentIDs = Set(entries.map { $0.id })
        broadcastedEntryIDs = broadcastedEntryIDs.intersection(currentIDs)

        for entry in toSend {
            for conn in connections.values {
                conn.sendLogEntry(entry)
            }
        }
    }
}
