//
//  HSMQTTClientOptions.swift
//  Hammerspoon 2
//

import Foundation
import MQTT

/// An error from hs.mqtt, whose message is shown to the user as-is
nonisolated struct HSMQTTError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// The settings an HSMQTTClient is created with: the broker's address from `hs.mqtt.create()`'s
/// `server` argument, overridden by its `options` object, all validated up front so a mistake
/// is reported by `create()` rather than by a later `connect()`.
struct HSMQTTClientOptions {
    struct Will {
        let topic: String
        let payload: String
        let qos: MQTTQoS
        let retain: Bool
    }

    static let knownKeys: Set<String> = [
        "port", "clientID", "username", "password", "tls", "websocket", "websocketPath", "version",
        "keepAlive", "connectTimeout", "timeout", "cleanSession", "will", "reconnectInterval",
        "caCertificate", "clientCertificate", "clientCertificatePassword", "allowUntrustedCertificates",
    ]

    /// The longest timeout or interval accepted
    static let maximumSeconds = 86_400.0

    var host: String
    var port: Int?
    var clientID: String
    var username: String?
    var password: String?
    var tls = false
    var websocket = false
    var websocketPath: String?
    var version = Version.v3_1_1
    var keepAlive = 60
    var connectTimeout = 10.0
    var timeout = 5.0
    var cleanSession = true
    var will: Will?
    var reconnectInterval = 0.0
    var trust: TLSOptions.ServerTrust?
    var credential: TLSOptions.Credential?

    init(server: String, options: [String: Any]) throws {
        let server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, server != "undefined", server != "null" else {
            throw HSMQTTError("a server is required, e.g. \"broker.local\" or \"mqtts://broker.local:8883\"")
        }

        if server.contains("://") {
            guard let url = URL(string: server), let scheme = url.scheme?.lowercased() else {
                throw HSMQTTError("'\(server)' is not a valid URL")
            }
            switch scheme {
            case "mqtt", "tcp": break
            case "mqtts", "ssl", "tls": tls = true
            case "ws": websocket = true
            case "wss": websocket = true; tls = true
            default:
                throw HSMQTTError("unsupported URL scheme '\(scheme)' (use mqtt, mqtts, ws or wss)")
            }
            guard let host = url.host(percentEncoded: false), !host.isEmpty else {
                throw HSMQTTError("'\(server)' has no host")
            }
            self.host = host
            port = url.port
            username = url.user(percentEncoded: false)
            password = url.password(percentEncoded: false)
            // Kept as given, query included, since brokers may route or authorize on it
            let path = url.path(percentEncoded: true)
            if websocket, !path.isEmpty || url.query != nil {
                websocketPath = (path.isEmpty ? "/" : path) + (url.query(percentEncoded: true).map { "?" + $0 } ?? "")
            }
        } else {
            host = server
        }

        clientID = "hammerspoon-" + UUID().uuidString.prefix(8).lowercased()

        let unknown = Set(options.keys).subtracting(Self.knownKeys)
        guard unknown.isEmpty else {
            throw HSMQTTError("unknown option(s): \(unknown.sorted().joined(separator: ", "))")
        }
        let reader = OptionReader(options)

        port = try reader.integer("port") ?? port
        if let value = try reader.string("clientID") {
            guard !value.isEmpty else { throw HSMQTTError("clientID must not be empty") }
            clientID = value
        }
        username = try reader.string("username") ?? username
        password = try reader.string("password") ?? password
        tls = try reader.bool("tls") ?? tls
        websocket = try reader.bool("websocket") ?? websocket
        if let value = try reader.string("websocketPath") {
            websocketPath = value.hasPrefix("/") ? value : "/" + value
        }
        if let value = try reader.versionString("version") {
            switch value {
            case "3", "3.1.1": version = .v3_1_1
            case "5", "5.0": version = .v5_0
            default: throw HSMQTTError("version must be \"3.1.1\" or \"5\"")
            }
        }
        if let value = try reader.integer("keepAlive") {
            guard (1...65535).contains(value) else { throw HSMQTTError("keepAlive must be between 1 and 65535 seconds") }
            keepAlive = value
        }
        if let value = try reader.number("connectTimeout") {
            guard value > 0, value <= Self.maximumSeconds else { throw HSMQTTError("connectTimeout must be between 0 and \(Int(Self.maximumSeconds)) seconds") }
            connectTimeout = value
        }
        if let value = try reader.number("timeout") {
            guard value > 0, value <= Self.maximumSeconds else { throw HSMQTTError("timeout must be between 0 and \(Int(Self.maximumSeconds)) seconds") }
            timeout = value
        }
        cleanSession = try reader.bool("cleanSession") ?? cleanSession
        if let value = try reader.number("reconnectInterval") {
            guard value >= 0, value <= Self.maximumSeconds else { throw HSMQTTError("reconnectInterval must be between 0 and \(Int(Self.maximumSeconds)) seconds") }
            reconnectInterval = value
        }
        if let value = try reader.dictionary("will") {
            will = try Self.parseWill(value)
        }

        let allowUntrustedCertificates = try reader.bool("allowUntrustedCertificates") ?? false
        let caCertificate = try reader.string("caCertificate")
        let clientCertificate = try reader.string("clientCertificate")
        let clientCertificatePassword = try reader.string("clientCertificatePassword")
        if !tls, allowUntrustedCertificates || caCertificate != nil || clientCertificate != nil {
            throw HSMQTTError("allowUntrustedCertificates, caCertificate and clientCertificate need a TLS connection (tls: true, or an mqtts:// or wss:// URL)")
        }
        if let caCertificate {
            trust = .trustRoots(try Self.certificates(from: caCertificate))
        }
        if allowUntrustedCertificates {
            trust = .trustAll
        }
        if let clientCertificate {
            do {
                credential = try TLSOptions.Credential.create(from: Self.expandedPath(clientCertificate), passwd: clientCertificatePassword ?? "")
            } catch {
                throw HSMQTTError("unable to load clientCertificate '\(clientCertificate)': \(Self.describe(error))")
            }
        } else if clientCertificatePassword != nil {
            throw HSMQTTError("clientCertificatePassword needs a clientCertificate")
        }

        // swift-mqtt crashes on a port or WebSocket URL it can't use, so they're checked here
        guard (1...65535).contains(resolvedPort) else { throw HSMQTTError("port must be between 1 and 65535") }
        if websocket, URL(string: "ws://\(host):\(resolvedPort)\(websocketPath ?? "/mqtt")") == nil {
            throw HSMQTTError("'\(host)' and '\(websocketPath ?? "/mqtt")' don't make a valid WebSocket URL")
        }
    }

    /// The port to connect to: the one given, or the default for the transport
    var resolvedPort: Int {
        if let port { return port }
        switch (tls, websocket) {
        case (false, false): return 1883
        case (true, false): return 8883
        case (false, true): return 80
        case (true, true): return 443
        }
    }

    /// A swift-mqtt client for these options
    func makeClient() -> MQTTClient {
        let port = UInt16(resolvedPort)
        let path = websocketPath ?? "/mqtt"
        let tlsOptions = TLSOptions(trust: trust, credential: credential, minVersion: .v1_2)
        let endpoint: Endpoint
        switch (tls, websocket) {
        case (false, false): endpoint = .tcp(host: host, port: port)
        case (true, false): endpoint = .tls(host: host, port: port, tls: tlsOptions)
        case (false, true): endpoint = .ws(host: host, port: port, path: path)
        case (true, true): endpoint = .wss(host: host, port: port, path: path, tls: tlsOptions)
        }
        var config = MQTT.Config()
        config.keepAlive = UInt16(keepAlive)
        config.connectTimeout = .seconds(connectTimeout)
        config.requestTimeout = .seconds(timeout)
        if reconnectInterval > 0 {
            config.retrier = Retrier(.equals(interval: reconnectInterval), limits: .max)
            config.monitorsNetwork = true
        }
        return MQTTClient(endpoint, version: version, config: config)
    }

    var identity: Identity {
        Identity(clientID, username: username, password: password)
    }

    var mqttWill: MQTT.Will? {
        will.map { MQTT.Will(topic: $0.topic, payload: Data($0.payload.utf8), qos: $0.qos, retain: $0.retain) }
    }

    private static func parseWill(_ will: [String: Any]) throws -> Will {
        let reader = OptionReader(will, prefix: "will.")
        let unknown = Set(will.keys).subtracting(["topic", "payload", "qos", "retain"])
        guard unknown.isEmpty else {
            throw HSMQTTError("unknown will option(s): \(unknown.sorted().joined(separator: ", "))")
        }
        guard let topic = try reader.string("topic"), !topic.isEmpty else {
            throw HSMQTTError("will.topic is required")
        }
        var qos = MQTTQoS.atMostOnce
        if let value = try reader.integer("qos") {
            guard let level = MQTTQoS(rawValue: UInt8(clamping: value)), (0...2).contains(value) else {
                throw HSMQTTError("will.qos must be 0, 1 or 2")
            }
            qos = level
        }
        return Will(topic: topic, payload: try reader.string("payload") ?? "", qos: qos, retain: try reader.bool("retain") ?? false)
    }

    /// The certificates `caCertificate` names: those in a DER or PEM file, or, for "keychain:<name>",
    /// the keychain's certificates with that name
    private static func certificates(from caCertificate: String) throws -> [SecCertificate] {
        if caCertificate.hasPrefix("keychain:") {
            let name = String(caCertificate.dropFirst("keychain:".count))
            let query: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecAttrLabel: name,
                kSecReturnRef: true,
                kSecMatchLimit: kSecMatchLimitAll,
            ]
            var result: CFTypeRef?
            guard unsafe SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let certificates = result as? [SecCertificate], !certificates.isEmpty else {
                throw HSMQTTError("caCertificate: there's no certificate named '\(name)' in the keychain")
            }
            return certificates
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: expandedPath(caCertificate)))
        } catch {
            throw HSMQTTError("unable to read caCertificate '\(caCertificate)': \(error.localizedDescription)")
        }
        // A PEM file may hold several certificates; anything else is taken to be one DER certificate
        let blocks = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "-----BEGIN CERTIFICATE-----")
            .dropFirst()
            .map { $0.components(separatedBy: "-----END CERTIFICATE-----")[0] }
        let ders = blocks.isEmpty ? [data] : blocks.map { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) ?? Data() }
        let certificates = ders.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty, certificates.count == ders.count else {
            throw HSMQTTError("caCertificate '\(caCertificate)' isn't a DER or PEM certificate file")
        }
        return certificates
    }

    private static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func describe(_ error: Error) -> String {
        (error as? MQTTError).map { "\($0)" } ?? error.localizedDescription
    }
}

/// Typed access to a JS options object, naming the offending key when a value has the wrong type
private struct OptionReader {
    let options: [String: Any]
    var prefix = ""

    init(_ options: [String: Any], prefix: String = "") {
        self.options = options
        self.prefix = prefix
    }

    private func value(_ key: String) -> Any? {
        guard let value = options[key], !(value is NSNull) else { return nil }
        return value
    }

    func string(_ key: String) throws -> String? {
        guard let value = value(key) else { return nil }
        guard let string = value as? String else { throw HSMQTTError("\(prefix)\(key) must be a string") }
        return string
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = value(key) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw HSMQTTError("\(prefix)\(key) must be true or false")
        }
        return number.boolValue
    }

    func number(_ key: String) throws -> Double? {
        guard let value = value(key) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw HSMQTTError("\(prefix)\(key) must be a number")
        }
        return number.doubleValue
    }

    func integer(_ key: String) throws -> Int? {
        guard let number = try number(key) else { return nil }
        guard number == number.rounded(), abs(number) < Double(Int32.max) else {
            throw HSMQTTError("\(prefix)\(key) must be a whole number")
        }
        return Int(number)
    }

    func dictionary(_ key: String) throws -> [String: Any]? {
        guard let value = value(key) else { return nil }
        guard let dictionary = value as? [String: Any] else { throw HSMQTTError("\(prefix)\(key) must be an object") }
        return dictionary
    }

    /// A version given as either a string ("3.1.1", "5") or a number (5)
    func versionString(_ key: String) throws -> String? {
        guard let value = value(key) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        throw HSMQTTError("\(prefix)\(key) must be \"3.1.1\" or \"5\"")
    }
}
