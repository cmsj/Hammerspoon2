//
//  FakeMQTTBroker.swift
//  Hammerspoon 2Tests
//

import Foundation
import Network

/// A minimal MQTT 3.1.1 broker on the loopback interface, so hs.mqtt can be tested end to end
/// without a real broker or the network. It understands CONNECT, PUBLISH (QoS 0-2), SUBSCRIBE,
/// UNSUBSCRIBE, PINGREQ and DISCONNECT, routes published messages to matching subscriptions,
/// and records what it receives for tests to inspect.
///
/// All state is confined to `queue`; the accessors below read it synchronously.
nonisolated final class FakeMQTTBroker: @unchecked Sendable {
    struct Connect: Equatable {
        var clientID: String
        var username: String?
        var password: String?
        var cleanSession: Bool
        var willTopic: String?
        var willPayload: String?
        var willRetain = false
    }

    struct Publish: Equatable {
        var topic: String
        var payload: Data
        var qos: Int
        var retain: Bool
    }

    // Confined to the broker's queue, like the rest of its state
    private final class Session: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var subscriptions: [String: Int] = [:]

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let queue = DispatchQueue(label: "FakeMQTTBroker")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]

    // Recorded traffic and behaviour switches, all only touched on `queue`
    private var _connects: [Connect] = []
    private var _publishes: [Publish] = []
    private var _subscribes: [String] = []
    private var _unsubscribes: [String] = []
    private var _pings = 0
    private var _disconnects = 0
    private var _connackReturnCode: UInt8 = 0
    private var _refusedFilters: Set<String> = []

    /// The port the broker listens on, once started
    private(set) var port: UInt16 = 0

    var connects: [Connect] { queue.sync { _connects } }
    var publishes: [Publish] { queue.sync { _publishes } }
    var subscribes: [String] { queue.sync { _subscribes } }
    var unsubscribes: [String] { queue.sync { _unsubscribes } }
    var pings: Int { queue.sync { _pings } }
    var disconnects: Int { queue.sync { _disconnects } }
    var connectionCount: Int { queue.sync { sessions.count } }

    /// The CONNACK return code sent to clients; non-zero refuses their connection
    var connackReturnCode: UInt8 {
        get { queue.sync { _connackReturnCode } }
        set { queue.sync { _connackReturnCode = newValue } }
    }

    /// Topic filters whose subscriptions are refused (SUBACK 0x80)
    var refusedFilters: Set<String> {
        get { queue.sync { _refusedFilters } }
        set { queue.sync { _refusedFilters = newValue } }
    }

    /// Starts listening on a free loopback port, returning once it's ready
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            // Cleared on the first ready/failed state, so the continuation is resumed only once
            listener.stateUpdateHandler = { [unowned listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.port = port
        return port
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for session in sessions.values {
                session.connection.cancel()
            }
            sessions.removeAll()
        }
    }

    /// Drops every client connection without a DISCONNECT, as if the network failed
    func dropConnections() {
        queue.sync {
            for session in sessions.values {
                session.connection.cancel()
            }
            sessions.removeAll()
        }
    }

    /// Sends a message to every client subscribed to a matching filter
    func send(topic: String, payload: String, retain: Bool = false) {
        queue.sync {
            deliver(Publish(topic: topic, payload: Data(payload.utf8), qos: 0, retain: retain))
        }
    }

    deinit {
        listener?.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let session = Session(connection: connection)
        sessions[ObjectIdentifier(session)] = session
        connection.stateUpdateHandler = { [weak self, weak session] state in
            guard let self, let session else { return }
            switch state {
            case .failed, .cancelled:
                self.sessions[ObjectIdentifier(session)] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: session)
    }

    private func receive(on session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak session] data, _, isComplete, error in
            guard let self, let session else { return }
            if let data {
                session.buffer.append(data)
                self.processBuffer(of: session)
            }
            if isComplete || error != nil {
                session.connection.cancel()
                self.sessions[ObjectIdentifier(session)] = nil
                return
            }
            if self.sessions[ObjectIdentifier(session)] != nil {
                self.receive(on: session)
            }
        }
    }

    private func processBuffer(of session: Session) {
        while let (header, body, length) = Self.nextPacket(in: session.buffer) {
            session.buffer.removeFirst(length)
            handle(header: header, body: body, from: session)
        }
    }

    /// The first complete packet in `buffer`: its fixed header byte, its body and its total length
    private static func nextPacket(in buffer: Data) -> (UInt8, Data, Int)? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }
        var remaining = 0
        var multiplier = 1
        var index = 1
        while true {
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            remaining += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            index += 1
            if byte & 0x80 == 0 { break }
        }
        guard bytes.count >= index + remaining else { return nil }
        return (bytes[0], Data(bytes[index..<(index + remaining)]), index + remaining)
    }

    // MARK: - Packets

    private func handle(header: UInt8, body: Data, from session: Session) {
        var reader = Reader(bytes: [UInt8](body))
        switch header >> 4 {
        case 1: // CONNECT
            _ = reader.string()        // protocol name
            _ = reader.byte()          // protocol level
            let flags = reader.byte()
            _ = reader.uint16()        // keep alive
            var connect = Connect(clientID: reader.string(), cleanSession: flags & 0x02 != 0)
            if flags & 0x04 != 0 {
                connect.willTopic = reader.string()
                connect.willPayload = String(decoding: reader.binary(), as: UTF8.self)
                connect.willRetain = flags & 0x20 != 0
            }
            if flags & 0x80 != 0 { connect.username = reader.string() }
            if flags & 0x40 != 0 { connect.password = String(decoding: reader.binary(), as: UTF8.self) }
            _connects.append(connect)
            if _connackReturnCode == 0 {
                write([0x20, 0x02, 0x00, 0x00], to: session)
            } else {
                // Closed once the refusal has been sent, as a real broker does
                let connection = session.connection
                connection.send(content: Data([0x20, 0x02, 0x00, _connackReturnCode]), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        case 3: // PUBLISH
            let qos = Int((header >> 1) & 0x03)
            let topic = reader.string()
            let packetID = qos > 0 ? reader.uint16() : 0
            let publish = Publish(topic: topic, payload: Data(reader.rest()), qos: qos, retain: header & 0x01 != 0)
            _publishes.append(publish)
            if qos == 1 {
                write([0x40, 0x02] + Self.encode(packetID), to: session)
            } else if qos == 2 {
                write([0x50, 0x02] + Self.encode(packetID), to: session)
            }
            deliver(Publish(topic: publish.topic, payload: publish.payload, qos: 0, retain: false))
        case 6: // PUBREL
            write([0x70, 0x02] + Self.encode(reader.uint16()), to: session)
        case 8: // SUBSCRIBE
            let packetID = reader.uint16()
            var codes: [UInt8] = []
            while !reader.isAtEnd {
                let filter = reader.string()
                let qos = Int(reader.byte())
                _subscribes.append(filter)
                if _refusedFilters.contains(filter) {
                    codes.append(0x80)
                } else {
                    session.subscriptions[filter] = qos
                    codes.append(UInt8(qos))
                }
            }
            write([0x90, UInt8(2 + codes.count)] + Self.encode(packetID) + codes, to: session)
        case 10: // UNSUBSCRIBE
            let packetID = reader.uint16()
            while !reader.isAtEnd {
                let filter = reader.string()
                _unsubscribes.append(filter)
                session.subscriptions[filter] = nil
            }
            write([0xB0, 0x02] + Self.encode(packetID), to: session)
        case 12: // PINGREQ
            _pings += 1
            write([0xD0, 0x00], to: session)
        case 14: // DISCONNECT
            _disconnects += 1
            session.connection.cancel()
            sessions[ObjectIdentifier(session)] = nil
        default:
            break
        }
    }

    private func deliver(_ publish: Publish) {
        for session in sessions.values where session.subscriptions.keys.contains(where: { Self.matches(filter: $0, topic: publish.topic) }) {
            let topic = Array(publish.topic.utf8)
            let body = Self.encode(UInt16(topic.count)) + topic + [UInt8](publish.payload)
            write([0x30 | (publish.retain ? 0x01 : 0x00)] + Self.encodeLength(body.count) + body, to: session)
        }
    }

    private func write(_ bytes: [UInt8], to session: Session) {
        session.connection.send(content: Data(bytes), completion: .idempotent)
    }

    // MARK: - Encoding

    private static func encode(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func encodeLength(_ length: Int) -> [UInt8] {
        var length = length
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while length > 0
        return bytes
    }

    /// MQTT topic matching, with `+` (one level) and `#` (the remaining levels)
    static func matches(filter: String, topic: String) -> Bool {
        let filterLevels = filter.split(separator: "/", omittingEmptySubsequences: false)
        let topicLevels = topic.split(separator: "/", omittingEmptySubsequences: false)
        for (index, level) in filterLevels.enumerated() {
            if level == "#" { return true }
            guard index < topicLevels.count else { return false }
            if level != "+" && level != topicLevels[index] { return false }
        }
        return filterLevels.count == topicLevels.count
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index >= bytes.count }

        mutating func byte() -> UInt8 {
            guard index < bytes.count else { return 0 }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func uint16() -> UInt16 {
            UInt16(byte()) << 8 | UInt16(byte())
        }

        mutating func binary() -> [UInt8] {
            let length = Int(uint16())
            let end = min(index + length, bytes.count)
            defer { index = end }
            return Array(bytes[index..<end])
        }

        mutating func string() -> String {
            String(decoding: binary(), as: UTF8.self)
        }

        mutating func rest() -> [UInt8] {
            defer { index = bytes.count }
            return Array(bytes[index...])
        }
    }
}
