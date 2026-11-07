//
//  HSMQTTClientOptions.swift
//  Hammerspoon 2
//

import Foundation
import Security
import MQTTNIO
import NIOCore

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

    var host: String
    var port: Int?
    var clientID: String
    var username: String?
    var password: String?
    var tls = false
    var websocket = false
    var websocketPath: String?
    var version: MQTTConnectionConfiguration.Version = .v3_1_1
    var keepAlive = 60
    var connectTimeout = 10.0
    var timeout = 30.0
    var cleanSession = true
    var will: Will?
    var reconnectInterval = 0.0
    var trustRoots: [SecCertificate]?
    var clientIdentity: SecIdentity?
    var allowUntrustedCertificates = false

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
            let path = url.path(percentEncoded: true)
            if websocket, !path.isEmpty, path != "/" {
                websocketPath = path
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

        if let value = try reader.integer("port") {
            guard (1...65535).contains(value) else { throw HSMQTTError("port must be between 1 and 65535") }
            port = value
        }
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
            guard value > 0 else { throw HSMQTTError("connectTimeout must be greater than 0") }
            connectTimeout = value
        }
        if let value = try reader.number("timeout") {
            guard value > 0 else { throw HSMQTTError("timeout must be greater than 0") }
            timeout = value
        }
        cleanSession = try reader.bool("cleanSession") ?? cleanSession
        if let value = try reader.number("reconnectInterval") {
            guard value >= 0 else { throw HSMQTTError("reconnectInterval must not be negative") }
            reconnectInterval = value
        }
        if let value = try reader.dictionary("will") {
            will = try Self.parseWill(value)
        }

        allowUntrustedCertificates = try reader.bool("allowUntrustedCertificates") ?? false
        let caCertificate = try reader.string("caCertificate")
        let clientCertificate = try reader.string("clientCertificate")
        let clientCertificatePassword = try reader.string("clientCertificatePassword")
        if !tls, allowUntrustedCertificates || caCertificate != nil || clientCertificate != nil {
            throw HSMQTTError("allowUntrustedCertificates, caCertificate and clientCertificate need a TLS connection (tls: true, or an mqtts:// or wss:// URL)")
        }
        if let caCertificate {
            trustRoots = try Self.loadCertificates(caCertificate)
        }
        if let clientCertificate {
            clientIdentity = try Self.loadIdentity(clientCertificate, password: clientCertificatePassword ?? "")
        } else if clientCertificatePassword != nil {
            throw HSMQTTError("clientCertificatePassword needs a clientCertificate")
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

    /// The mqtt-nio configuration for these options
    var configuration: MQTTConnectionConfiguration {
        let tlsSetting: MQTTConnectionConfiguration.Transport.TLS = tls
            ? .enable(.ts(TSTLSConfiguration(
                minimumTLSVersion: .tlsV12,
                trustRoots: trustRoots,
                clientIdentity: clientIdentity,
                certificateVerification: allowUntrustedCertificates ? .none : .fullVerification)), tlsServerName: nil)
            : .disable
        let transport: MQTTConnectionConfiguration.Transport = websocket
            ? .webSocket(.init(urlPath: websocketPath ?? "/mqtt"), tls: tlsSetting)
            : .tcp(tls: tlsSetting)
        let versionConfiguration: MQTTConnectionConfiguration.VersionConfiguration
        switch version {
        case .v3_1_1:
            versionConfiguration = .v3_1_1(will: will.map {
                .init(topicName: $0.topic, payload: ByteBuffer(string: $0.payload), qos: $0.qos, retain: $0.retain)
            })
        case .v5_0:
            versionConfiguration = .v5_0(will: will.map {
                .init(topicName: $0.topic, payload: ByteBuffer(string: $0.payload), qos: $0.qos, retain: $0.retain)
            })
        }
        return MQTTConnectionConfiguration(
            versionConfiguration: versionConfiguration,
            keepAliveInterval: .seconds(keepAlive),
            connectTimeout: Self.duration(connectTimeout),
            timeout: Self.duration(timeout),
            userName: username,
            password: password,
            transport: transport
        )
    }

    private static func duration(_ seconds: Double) -> Duration {
        .milliseconds(Int64((seconds * 1000).rounded()))
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

    // MARK: - TLS material

    private static func readFile(_ path: String, _ what: String) throws -> Data {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            return try Data(contentsOf: URL(fileURLWithPath: expanded))
        } catch {
            throw HSMQTTError("unable to read \(what) '\(path)': \(error.localizedDescription)")
        }
    }

    /// Loads the certificates in a PEM file (one or more certificates) or a DER file (one)
    static func loadCertificates(_ path: String) throws -> [SecCertificate] {
        let data = try readFile(path, "caCertificate")
        var derBlobs: [Data] = []
        if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") {
            for block in text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst() {
                guard let body = block.components(separatedBy: "-----END CERTIFICATE-----").first,
                      let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
                    throw HSMQTTError("caCertificate '\(path)' contains a malformed PEM certificate")
                }
                derBlobs.append(der)
            }
        } else {
            derBlobs = [data]
        }
        return try derBlobs.map { der in
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                throw HSMQTTError("caCertificate '\(path)' is not a PEM or DER certificate")
            }
            return certificate
        }
    }

    /// Loads the identity (certificate and private key) in a PKCS#12 (.p12) file
    static func loadIdentity(_ path: String, password: String) throws -> SecIdentity {
        let data = try readFile(path, "clientCertificate")
        let importOptions = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = unsafe SecPKCS12Import(data as CFData, importOptions, &items)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw HSMQTTError("unable to import clientCertificate '\(path)': \(reason)")
        }
        guard let first = (items as? [[String: Any]])?.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw HSMQTTError("clientCertificate '\(path)' contains no identity")
        }
        // CFTypeRefs bridge to Any as the CF type, so this cast always succeeds
        return identity as! SecIdentity
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
