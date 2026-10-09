//
//  entrypoint.swift
//  HammerspoonIPCBroker
//
//  A launchd agent that relays messages between Hammerspoon 2 and the hs2 command line tool.
//  See HSIPCShared.swift for an overview.
//

import Foundation
import OSLog
import Synchronization
import XPC

@main
extension HSIPCBroker {
    static func main() {
        let broker = HSIPCBroker()
        do {
            try broker.start()
        } catch {
            HSIPCBroker.logger.fault("Unable to start listeners: \(error, privacy: .public)")
            exit(EXIT_FAILURE)
        }
        withExtendedLifetime(broker) {
            dispatchMain()
        }
    }
}

nonisolated final class HSIPCBroker: Sendable {
    static let logger = Logger(subsystem: HSIPC.brokerSigningIdentifier, category: "broker")

    /// launchd relaunches us on demand, so there's no point lingering once nobody is connected.
    private static let idleExitDelay: DispatchTimeInterval = .seconds(60)

    private struct Client {
        let session: XPCSession
        var minLogLevel = HSIPC.noLogging
    }

    private struct State {
        var host: XPCSession?
        var clients: [ObjectIdentifier: Client] = [:]
        /// The level most recently given to the host, so we only push changes.
        var hostMinLogLevel = HSIPC.noLogging
        /// Bumped on every connect/disconnect, so a pending idle exit can tell it's stale.
        var activityGeneration = 0

        var minLogLevel: Int {
            clients.values.map(\.minLogLevel).min() ?? HSIPC.noLogging
        }
    }

    private let state = Mutex(State())
    private let listeners = Mutex<[XPCListener]>([])

    /// Every listener and session targets this queue, so messages are handled in order.
    private let queue = DispatchQueue(label: "net.tenshu.Hammerspoon-2.HammerspoonIPCBroker")

    func start() throws {
#if DEBUG
        HSIPCBroker.logger.warning("WARNING: Running without XPC peer checking. This is unsafe and should only be done in development.")
        let hostListener = try XPCListener(service: HSIPC.hostServiceName, targetQueue: queue) { [self] request in
            acceptHost(request)
        }
        let clientListener = try XPCListener(service: HSIPC.clientServiceName, targetQueue: queue) { [self] request in
            acceptClient(request)
        }
#else
        HSIPCBroker.logger.info("Enforcing XPC peer requirements.")
        let hostListener = try XPCListener(service: HSIPC.hostServiceName,
                                           targetQueue: queue,
                                           requirement: .isFromSameTeam(andMatchesSigningIdentifier: HSIPC.appSigningIdentifier)) { [self] request in
            acceptHost(request)
        }
        let clientListener = try XPCListener(service: HSIPC.clientServiceName,
                                             targetQueue: queue,
                                             requirement: .isFromSameTeam()) { [self] request in
            acceptClient(request)
        }
#endif
        listeners.withLock { $0 = [hostListener, clientListener] }
        scheduleIdleExitIfNeeded()
    }

    // MARK: - Host (Hammerspoon 2)

    private struct HostPeer: XPCPeerHandler {
        let broker: HSIPCBroker
        let id: ObjectIdentifier

        func handleIncomingRequest(_ message: XPCReceivedMessage) -> (any Encodable)? {
            broker.handleHostMessage(message, from: id)
        }

        func handleCancellation(error: XPCRichError) {
            broker.removeHost(id: id, error: error)
        }
    }

    private func acceptHost(_ request: XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision {
        request.accept { session in
            // The newest host wins, since a reloading Hammerspoon 2 may connect again before
            // the broker has seen its previous session go away. The previous host is told it
            // was replaced, so that (e.g. if it's another running copy of the app) it doesn't
            // just reconnect and take over again.
            let previous = state.withLock { state in
                defer {
                    state.host = session
                    state.activityGeneration += 1
                }
                return state.host
            }
            if let previous {
                retire(previous)
            }
            HSIPCBroker.logger.info("Hammerspoon 2 connected")
            broadcast(.hostStatus(connected: true))
            return HostPeer(broker: self, id: ObjectIdentifier(session))
        }
    }

    private func retire(_ host: XPCSession) {
        let reason = "Replaced by a newer Hammerspoon 2 connection"
        do {
            // Capturing `host` keeps it alive until it has acknowledged, or failed to.
            try host.send(HSIPCBrokerToHost.replaced) { (_: Result<HSIPCAcknowledgement, any Error>) in
                host.cancel(reason: reason)
            }
        } catch {
            host.cancel(reason: reason)
        }
    }

    private func removeHost(id: ObjectIdentifier, error: XPCRichError) {
        let wasCurrent = state.withLock { state in
            guard let host = state.host, ObjectIdentifier(host) == id else { return false }
            state.host = nil
            state.activityGeneration += 1
            return true
        }
        guard wasCurrent else { return }
        HSIPCBroker.logger.info("Hammerspoon 2 disconnected: \(error, privacy: .public)")
        broadcast(.hostStatus(connected: false))
        scheduleIdleExitIfNeeded()
    }

    private func handleHostMessage(_ message: XPCReceivedMessage, from id: ObjectIdentifier) -> (any Encodable)? {
        guard let decoded = try? message.decode(as: HSIPCHostToBroker.self) else {
            HSIPCBroker.logger.error("Unable to decode message from Hammerspoon 2")
            return nil
        }

        switch decoded {
        case .hello(let version):
            if version != HSIPC.protocolVersion {
                HSIPCBroker.logger.error("Hammerspoon 2 speaks protocol \(version), broker speaks \(HSIPC.protocolVersion)")
            }
            return state.withLock { state in
                state.hostMinLogLevel = state.minLogLevel
                return helloReply(state)
            }

        case .log(let level, let text):
            // A replaced host stays connected until it acknowledges being replaced, so ignore
            // its logs rather than mixing them in with the current host's.
            let recipients = state.withLock { state -> [XPCSession] in
                guard let host = state.host, ObjectIdentifier(host) == id else { return [] }
                return state.clients.values.filter { level >= $0.minLogLevel }.map(\.session)
            }
            for session in recipients {
                try? session.send(HSIPCBrokerToClient.log(level: level, message: text))
            }
            return nil
        }
    }

    // MARK: - Clients (hs2)

    private struct ClientPeer: XPCPeerHandler {
        let broker: HSIPCBroker
        let id: ObjectIdentifier

        func handleIncomingRequest(_ message: XPCReceivedMessage) -> (any Encodable)? {
            broker.handleClientMessage(message, from: id)
        }

        func handleCancellation(error: XPCRichError) {
            broker.removeClient(id: id)
        }
    }

    private func acceptClient(_ request: XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision {
        request.accept { session in
            let id = ObjectIdentifier(session)
            state.withLock { state in
                state.clients[id] = Client(session: session)
                state.activityGeneration += 1
            }
            HSIPCBroker.logger.info("hs2 client connected")
            return ClientPeer(broker: self, id: id)
        }
    }

    private func removeClient(id: ObjectIdentifier) {
        state.withLock { state in
            state.clients[id] = nil
            state.activityGeneration += 1
        }
        HSIPCBroker.logger.info("hs2 client disconnected")
        pushLogLevelToHostIfChanged()
        scheduleIdleExitIfNeeded()
    }

    private func handleClientMessage(_ message: XPCReceivedMessage, from id: ObjectIdentifier) -> (any Encodable)? {
        guard let decoded = try? message.decode(as: HSIPCClientToBroker.self) else {
            HSIPCBroker.logger.error("Unable to decode message from hs2")
            return message.expectsReply ? HSIPCEvaluationReply(result: "Malformed request", isError: true, wasEvaluated: false) : nil
        }

        switch decoded {
        case .hello(_, let minLogLevel):
            // The client checks the protocol version in our reply, so it can explain a mismatch to the user.
            let reply = state.withLock { state in
                state.clients[id]?.minLogLevel = minLogLevel
                return helloReply(state)
            }
            pushLogLevelToHostIfChanged()
            return reply

        case .evaluate(let code):
            guard let host = state.withLock({ $0.host }) else {
                return HSIPCEvaluationReply(result: "Hammerspoon 2 is not connected. Make sure it is running and has called hs.ipc.start()",
                                            isError: true, wasEvaluated: false)
            }
            let pending = PendingReply(message)
            do {
                try host.send(HSIPCBrokerToHost.evaluate(code: code)) { (result: Result<HSIPCEvaluationReply, any Error>) in
                    switch result {
                    case .success(let reply):
                        pending.reply(reply)
                    case .failure(let error):
                        pending.reply(HSIPCEvaluationReply(result: "Hammerspoon 2 did not reply: \(error)",
                                                           isError: true, wasEvaluated: false))
                    }
                }
            } catch {
                return HSIPCEvaluationReply(result: "Unable to send to Hammerspoon 2: \(error)", isError: true,
                                            wasEvaluated: false)
            }
            // The reply is sent later, by the closure above.
            return nil
        }
    }

    // MARK: - Helpers

    private func helloReply(_ state: State) -> HSIPCHelloReply {
        HSIPCHelloReply(protocolVersion: HSIPC.protocolVersion,
                        hostConnected: state.host != nil,
                        minLogLevel: state.minLogLevel,
                        brokerPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }

    private func broadcast(_ message: HSIPCBrokerToClient) {
        let sessions = state.withLock { $0.clients.values.map(\.session) }
        for session in sessions {
            try? session.send(message)
        }
    }

    /// Tell the host to only forward log messages that at least one client wants.
    private func pushLogLevelToHostIfChanged() {
        let update: (XPCSession, Int)? = state.withLock { state in
            let level = state.minLogLevel
            guard let host = state.host, level != state.hostMinLogLevel else { return nil }
            state.hostMinLogLevel = level
            return (host, level)
        }
        guard let (host, level) = update else { return }
        try? host.send(HSIPCBrokerToHost.setMinimumLogLevel(level))
    }

    private func scheduleIdleExitIfNeeded() {
        let generation = state.withLock { state -> Int? in
            state.host == nil && state.clients.isEmpty ? state.activityGeneration : nil
        }
        guard let generation else { return }
        queue.asyncAfter(deadline: .now() + HSIPCBroker.idleExitDelay) { [self] in
            let stillIdle = state.withLock { state in
                state.activityGeneration == generation && state.host == nil && state.clients.isEmpty
            }
            if stillIdle {
                HSIPCBroker.logger.info("Exiting after being idle")
                exit(EXIT_SUCCESS)
            }
        }
    }
}

/// Holds a client's `evaluate` message until the host replies to it.
///
/// `XPCReceivedMessage` isn't annotated `Sendable`, but XPC explicitly supports replying to
/// a message later, from any thread. Each `PendingReply` is replied to exactly once.
private nonisolated struct PendingReply: @unchecked Sendable {
    private let message: XPCReceivedMessage

    init(_ message: XPCReceivedMessage) {
        self.message = message
    }

    func reply(_ reply: HSIPCEvaluationReply) {
        message.reply(reply)
    }
}
