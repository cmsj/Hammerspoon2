//
//  HSMQTTModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - JavaScript API

/// Connect to MQTT brokers to publish messages and subscribe to topics.
///
/// MQTT is a lightweight publish/subscribe protocol, widely used for home automation (e.g. Home
/// Assistant, Zigbee2MQTT, Tasmota) and IoT devices. Create a client with `create()`, then
/// `connect()` it, and listen for messages with its `on()` method.
///
/// Both MQTT 3.1.1 and MQTT 5 brokers are supported, over plain TCP, TLS, and WebSockets.
///
/// **Note:** this module is new and has not yet been well tested. It has only been tested against a
/// simple MQTT 3.1.1 test broker, not against real brokers, MQTT 5, TLS or WebSockets. Please report
/// any problems you find.
///
/// - Example:
/// ```js
/// const client = hs.mqtt.create("mqtt://homeassistant.local", {
///     username: "hammerspoon",
///     password: "secret",
///     reconnectInterval: 5
/// })
/// client.on("message", msg => {
///     if (msg.topic === "home/doorbell" && msg.payload === "pressed") {
///         hs.notify.show("Doorbell", "Someone is at the door")
///     }
/// })
/// async function start() {
///     await client.connect()
///     await client.subscribe("home/doorbell")
///     await client.publish("home/mac/status", "online", { retain: true })
/// }
/// start()
/// ```
@objc protocol HSMQTTModuleAPI: JSExport {
    /// Creates an MQTT client. The client doesn't connect until you call its `connect()` method.
    ///
    /// The `server` is either a host name, or a URL whose scheme chooses the transport:
    /// `mqtt://` (TCP, port 1883), `mqtts://` (TLS, port 8883), `ws://` (WebSocket, port 80) or
    /// `wss://` (WebSocket over TLS, port 443). A URL may include a port, a username and password
    /// (`mqtt://user:pass@host`), and for WebSockets a path (defaults to `/mqtt`).
    ///
    /// - Parameters:
    ///   - server: The broker's host name or URL
    ///   - options?: Connection options, which override anything given in the URL
    ///     - port?: {number} The broker's port
    ///     - clientID?: {string} The MQTT client identifier. Defaults to `"hammerspoon-"` followed by eight random characters. Brokers disconnect an existing client when another connects with the same identifier
    ///     - username?: {string} The username for the broker
    ///     - password?: {string} The password for the broker
    ///     - tls?: {boolean} `true` to connect with TLS
    ///     - websocket?: {boolean} `true` to connect over a WebSocket
    ///     - websocketPath?: {string} The WebSocket's path. Defaults to `/mqtt`
    ///     - version?: {"3.1.1" | "5"} The MQTT version. Defaults to `"3.1.1"`
    ///     - keepAlive?: {number} Seconds between keep-alive pings. Defaults to `60`
    ///     - connectTimeout?: {number} Seconds to wait for the broker to accept the connection. Defaults to `10`
    ///     - timeout?: {number} Seconds to wait for the broker to acknowledge a `subscribe()`, an `unsubscribe()`, or a `publish()` with QoS 1 or 2, before its Promise rejects. Defaults to `5`
    ///     - cleanSession?: {boolean} `false` to ask the broker to keep the client's subscriptions and queued messages while it's disconnected. Defaults to `true`
    ///     - will?: A message the broker publishes if the client disconnects without calling `disconnect()`
    ///       - topic: {string} The topic to publish it to
    ///       - payload?: {string} The message. Defaults to an empty one
    ///       - qos?: {0 | 1 | 2} Its quality of service. Defaults to `0`
    ///       - retain?: {boolean} `true` for the broker to retain it. Defaults to `false`
    ///     - reconnectInterval?: {number} Seconds to wait before trying to reconnect when the connection is lost, retrying until `disconnect()` is called. While the network is unavailable, the client waits for it to return instead. Defaults to `0`, which doesn't reconnect
    ///     - caCertificate?: {string} The CA certificate to trust for the broker instead of the system's, e.g. for a self-signed certificate: the path of a DER or PEM file, or `"keychain:<name>"` for the certificates with that name in your keychain. Without it, the broker's certificate must be trusted by macOS, which includes CA certificates you've added to your keychain and marked as trusted
    ///     - clientCertificate?: {string} The path of a PKCS#12 (.p12) file with a certificate and private key to identify the client
    ///     - clientCertificatePassword?: {string} The password for `clientCertificate`
    ///     - allowUntrustedCertificates?: {boolean} `true` to accept any certificate from the broker. This makes the connection insecure, so use `caCertificate` instead if you can
    /// - Returns: A new `HSMQTTClient`, or `null` if the server or options are invalid (the reason is logged to the Console)
    /// - Example:
    /// ```js
    /// const local = hs.mqtt.create("broker.local")
    /// const secure = hs.mqtt.create("mqtts://broker.example.com", { username: "me", password: "secret" })
    /// const custom = hs.mqtt.create("broker.local", { tls: true, caCertificate: "~/certs/ca.der", version: "5" })
    /// ```
    @objc func create(_ server: String, _ options: [String: Any]?) -> HSMQTTClient?

    // NOTE: Private API consumed only by hs.mqtt.js
    // Set by hs.mqtt.js. Must be a pre-declared property, or JSC drops it on GC (issue #185).
    /// SKIP_DOCS
    @objc var _makeClientEmitter: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSMQTTModule: NSObject, HSModuleAPI, HSMQTTModuleAPI {
    var moduleName = "hs.mqtt"
    let engineID: UUID
    private var clients = HSObjectTracker<HSMQTTClient>()

    @objc var _makeClientEmitter: JSFunction?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        clients.shutdown()
        _makeClientEmitter = nil
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = clients.activeCount
        return "<\(moduleName): \(n) active client\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func create(_ server: String, _ options: [String: Any]?) -> HSMQTTClient? {
        let parsed: HSMQTTClientOptions
        do {
            parsed = try HSMQTTClientOptions(server: server, options: options ?? [:])
        } catch {
            AKError("hs.mqtt.create(): \(HSMQTTClient.describe(error))")
            return nil
        }
        let client = HSMQTTClient(module: self, options: parsed, tracker: clients)
        clients.add(client)
        return client
    }

    /// Makes the JS emitter for a client's on()/once(), via the factory in hs.mqtt.js. Returns
    /// nil, having set `ctx.exception`, on failure.
    func makeClientEmitter(for client: HSMQTTClient, in ctx: JSContext) -> JSValue? {
        guard let factory = _makeClientEmitter, factory.isFunction else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.mqtt: the watcher emitter factory is unavailable", in: ctx)
            return nil
        }
        let emitter = ctx.callCapturingException { factory.call(withArguments: [client]) }
        guard ctx.exception == nil, let emitter, emitter.isObject else {
            if ctx.exception == nil {
                ctx.exception = JSValue(newErrorFromMessage: "hs.mqtt: failed to create a watcher emitter", in: ctx)
            }
            return nil
        }
        return emitter
    }
}
