//
//  HSIPCBrokerConnection.swift
//  Hammerspoon 2
//

import Foundation
import Observation
import ServiceManagement
import XPC

/// Hammerspoon 2's connection to the HammerspoonIPCBroker launch agent.
///
/// Hammerspoon 2 can't vend a Mach service itself, so the broker (registered here via
/// `SMAppService`) owns the services, and relays JavaScript from hs2 to us, and our log
/// messages back to hs2. See `HSIPCShared.swift`.
@safe @MainActor
final class HSIPCBrokerConnection {
    private(set) var isConnected = false

    private var session: XPCSession?

    /// Whether the user wants us connected, i.e. `start()` was called without a matching `stop()`.
    private var isWanted = false
    private var reconnectAttempts = 0
    private static let maxReconnectAttempts = 5

    /// The lowest log level any connected hs2 wants, as told to us by the broker.
    private var minLogLevel = HSIPC.noLogging
    /// Sequence number of the newest log entry we've already considered for forwarding.
    private var lastForwardedSequence: UInt64 = 0
    private var observationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        guard !isWanted else {
            AKWarning("hs.ipc: Already started")
            return
        }
        guard registerBroker() else { return }
        isWanted = true
        reconnectAttempts = 0
        connect()
    }

    func stop() {
        isWanted = false
        disconnect(reason: "hs.ipc stopped")
        AKDebug("hs.ipc: Stopped")
    }

    isolated deinit {
        // An XPCSession released while still active is a fatal API misuse.
        session?.cancel(reason: "HSIPCBrokerConnection deinit")
    }

    // MARK: - Broker registration

    /// Make sure launchd knows about the broker, so that it can launch it on demand.
    private func registerBroker() -> Bool {
        let service = SMAppService.agent(plistName: HSIPC.launchAgentPlistName)

        if service.status != .enabled {
            do {
                try service.register()
            } catch {
                // Registration can fail while still leaving the service awaiting approval,
                // which is reported below.
                AKDebug("hs.ipc: Registering the IPC broker failed: \(error.localizedDescription)")
            }
        }

        switch service.status {
        case .enabled:
            return true
        case .requiresApproval:
            AKError("hs.ipc: The Hammerspoon 2 IPC broker needs to be allowed to run in the background. Enable Hammerspoon 2 in System Settings → General → Login Items & Extensions, then call hs.ipc.start() again.")
        case .notFound:
            AKError("hs.ipc: The IPC broker's launchd plist (\(HSIPC.launchAgentPlistName)) is missing from the app bundle.")
        default:
            AKError("hs.ipc: Unable to register the IPC broker with launchd.")
        }
        return false
    }

    // MARK: - Session management

    private func connect() {
        // The session targets the main queue, so this is always called on the main thread.
        let messageHandler: @Sendable (XPCReceivedMessage) -> (any Encodable)? = { [weak self] message in
            let decoded = try? message.decode(as: HSIPCBrokerToHost.self)
            let expectsReply = message.expectsReply
            return MainActor.assumeIsolated { () -> (any Encodable & Sendable)? in
                guard let decoded else {
                    AKError("hs.ipc: Unable to decode message from the IPC broker")
                    return expectsReply ? HSIPCEvaluationReply(result: "Malformed request", isError: true) : nil
                }
                return self?.handle(decoded)
            }
        }

        let session: XPCSession
        do {
#if DEBUG
            AKWarning("hs.ipc: DEBUG build — peer code-signing check disabled")
            session = try XPCSession(machService: HSIPC.hostServiceName,
                                     targetQueue: .main,
                                     options: .inactive,
                                     incomingMessageHandler: messageHandler)
#else
            session = try XPCSession(machService: HSIPC.hostServiceName,
                                     targetQueue: .main,
                                     options: .inactive,
                                     requirement: HSIPC.brokerRequirement,
                                     incomingMessageHandler: messageHandler)
#endif
            // Weakly capture `session` so a late cancellation of a session that has
            // already been replaced doesn't tear down its successor.
            session.setCancellationHandler { [weak self, weak session] error in
                Task { @MainActor in
                    guard let self, let session, self.session === session else { return }
                    self.sessionCancelled(error)
                }
            }
            try session.activate()
        } catch {
            AKError("hs.ipc: Unable to connect to the IPC broker: \(error)")
            isWanted = false
            return
        }
        self.session = session

        do {
            try session.send(HSIPCHostToBroker.hello(protocolVersion: HSIPC.protocolVersion)) { [weak self, weak session] (result: Result<HSIPCHelloReply, any Error>) in
                Task { @MainActor in
                    guard let self, let session, self.session === session else { return }
                    self.helloReplied(result)
                }
            }
        } catch {
            AKError("hs.ipc: Unable to send to the IPC broker: \(error)")
            stop()
        }
    }

    private func helloReplied(_ result: Result<HSIPCHelloReply, any Error>) {
        switch result {
        case .failure(let error):
            // The session's cancellation handler deals with reconnecting.
            AKError("hs.ipc: The IPC broker did not respond: \(error)")
        case .success(let reply):
            guard reply.protocolVersion == HSIPC.protocolVersion else {
                AKError("hs.ipc: The running IPC broker (\(reply.brokerPath)) speaks protocol version \(reply.protocolVersion), but this Hammerspoon 2 speaks \(HSIPC.protocolVersion).")
                stop()
                return
            }
            if !reply.brokerPath.hasPrefix(Bundle.main.bundlePath + "/") {
                AKWarning("hs.ipc: launchd is running the IPC broker from another copy of Hammerspoon 2 (\(reply.brokerPath))")
            }
            isConnected = true
            reconnectAttempts = 0
            setMinLogLevel(reply.minLogLevel)
            AKInfo("hs.ipc: Connected to the IPC broker")
        }
    }

    private func sessionCancelled(_ error: XPCRichError) {
        let wasConnected = isConnected
        disconnect(reason: nil)

        guard isWanted else { return }
        guard error.canRetry || wasConnected, reconnectAttempts < Self.maxReconnectAttempts else {
            AKError("hs.ipc: Lost connection to the IPC broker: \(error)")
            isWanted = false
            return
        }

        reconnectAttempts += 1
        AKWarning("hs.ipc: Lost connection to the IPC broker, reconnecting (attempt \(reconnectAttempts) of \(Self.maxReconnectAttempts))")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.isWanted, self.session == nil else { return }
            self.connect()
        }
    }

    /// Tear down the session and log forwarding. `reason` is nil when the session is already cancelled.
    private func disconnect(reason: String?) {
        if let reason {
            session?.cancel(reason: reason)
        }
        session = nil
        isConnected = false
        setMinLogLevel(HSIPC.noLogging)
    }

    // MARK: - Messages from the broker

    private func handle(_ message: HSIPCBrokerToHost) -> (any Encodable & Sendable)? {
        switch message {
        case .evaluate(let code):
            let (result, isError) = Self.evalJS(code)
            return HSIPCEvaluationReply(result: result, isError: isError)
        case .setMinimumLogLevel(let level):
            setMinLogLevel(level)
            return nil
        case .replaced:
            // Most likely another running copy of Hammerspoon 2 called hs.ipc.start(). Reconnecting
            // would just take over from it again, so stop. The broker cancels our session once we've
            // acknowledged, and sessionCancelled() won't reconnect because we're no longer wanted.
            if isWanted {
                isWanted = false
                AKWarning("hs.ipc: Another Hammerspoon 2 connection has taken over IPC, so hs.ipc has stopped. Call hs.ipc.start() to take it back.")
            }
            return HSIPCAcknowledgement()
        }
    }

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

    // MARK: - Log forwarding

    private func setMinLogLevel(_ level: Int) {
        minLogLevel = level
        if level == HSIPC.noLogging {
            observationTask?.cancel()
            observationTask = nil
        } else if observationTask == nil {
            // Only forward entries logged from now on, not the existing history.
            lastForwardedSequence = HammerspoonLog.shared.latestSequence
            observationTask = Task { [weak self] in
                // Watch the cheap sequence counter rather than the full merged/filtered
                // `entries(minimumLevel:)`, so this doesn't pay for a flatten+filter+sort
                // of every per-level buffer on every single log call.
                let changes = Observations {
                    HammerspoonLog.shared.latestSequence
                }
                for await _ in changes {
                    self?.forwardNewEntries()
                }
            }
        }
    }

    private func forwardNewEntries() {
        guard let session,
              let minimumType = HammerspoonLogType.allCases.first(where: { $0.rawValue >= minLogLevel }) else { return }

        let newEntries = HammerspoonLog.shared.entries(minimumLevel: minimumType)
            .filter { $0.sequence > lastForwardedSequence }
        lastForwardedSequence = HammerspoonLog.shared.latestSequence

        for entry in newEntries {
            try? session.send(HSIPCHostToBroker.log(level: entry.logType.rawValue, message: entry.msg))
        }
    }
}
