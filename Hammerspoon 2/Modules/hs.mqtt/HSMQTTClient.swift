//
//  HSMQTTClient.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import MQTTNIO
import NIOCore
import NIOTransportServices

// MARK: - JavaScript API

/// A connection to an MQTT broker, created by `hs.mqtt.create()`.
///
/// The client does nothing until you call `connect()`. Messages for the topics you `subscribe()`
/// to arrive as `"message"` events (see `on()`).
///
/// A connected client keeps working after you drop your reference to it, until you call
/// `disconnect()` or `destroy()`, or Hammerspoon reloads its configuration. So does a client
/// with listeners registered by `on()`.
/// - Example:
/// ```js
/// const client = hs.mqtt.create("mqtt://broker.local")
/// client.on("message", msg => console.log(msg.topic + ": " + msg.payload))
/// await client.connect()
/// await client.subscribe("home/+/temperature")
/// await client.publish("home/office/light", "on")
/// ```
@objc protocol HSMQTTClientAPI: HSTypeAPI, JSExport {
    /// The unique identifier of this client object.
    /// - Example:
    /// ```js
    /// console.log(client.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The MQTT client identifier sent to the broker. Unless you chose one with the `clientID` option, it is `"hammerspoon-"` followed by eight random characters. An MQTT 5 broker may assign a different one when you connect.
    /// - Example:
    /// ```js
    /// console.log(client.clientID)
    /// ```
    @objc var clientID: String { get }

    /// The host name of the broker.
    /// - Example:
    /// ```js
    /// console.log(client.host)
    /// ```
    @objc var host: String { get }

    /// The port of the broker.
    /// - Example:
    /// ```js
    /// console.log(client.port)
    /// ```
    @objc var port: Int { get }

    /// The client's connection state: `"disconnected"`, `"connecting"`, `"connected"`, `"reconnecting"` (the connection was lost and the client is trying to restore it, see the `reconnectInterval` option) or `"disconnecting"`.
    /// - Example:
    /// ```js
    /// if (client.state === "disconnected") await client.connect()
    /// ```
    @objc var state: String { get }

    /// Whether the client is connected to the broker.
    /// - Example:
    /// ```js
    /// console.log(client.isConnected)
    /// ```
    @objc var isConnected: Bool { get }

    /// The topic filters this client has subscribed to, and the QoS level requested for each. These are restored automatically when the client reconnects.
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(client.subscriptions))
    /// ```
    @objc var subscriptions: [String: Int] { get }

    /// Connects to the broker.
    /// - Returns: {Promise<boolean>} A Promise resolving once the broker has accepted the connection, to `true` if the broker resumed a previous session for this client (see the `cleanSession` option), or `false` if it started a new one
    /// - Example:
    /// ```js
    /// try {
    ///     await client.connect()
    /// } catch (err) {
    ///     console.error("Unable to connect: " + err)
    /// }
    /// ```
    @objc func connect() -> JSPromise?

    /// Disconnects from the broker. This also stops a client that is reconnecting from trying again.
    /// - Returns: {Promise<void>} A Promise resolving once the client has disconnected
    /// - Example:
    /// ```js
    /// await client.disconnect()
    /// ```
    @objc func disconnect() -> JSPromise?

    /// Publishes a message.
    /// - Parameters:
    ///   - topic: The topic to publish to
    ///   - payload: The message, sent as UTF-8. Use `JSON.stringify()` to send an object
    ///   - options?: {{qos?: 0 | 1 | 2, retain?: boolean}} The QoS level to send the message with (default `0`), and whether the broker should keep it as the topic's retained message (default `false`)
    /// - Returns: {Promise<void>} A Promise resolving once the message has been sent (QoS 0) or the broker has acknowledged it (QoS 1 and 2)
    /// - Example:
    /// ```js
    /// await client.publish("home/office/light", "on")
    /// await client.publish("home/status", JSON.stringify({ away: true }), { qos: 1, retain: true })
    /// ```
    @objc func publish(_ topic: String, _ payload: String, _ options: [String: Any]?) -> JSPromise?

    /// Subscribes to a topic filter, so messages published to matching topics arrive as `"message"` events.
    /// - Parameters:
    ///   - topicFilter: The topic, which may contain the wildcards `+` (one level) and `#` (all remaining levels)
    ///   - qos?: {0 | 1 | 2} The highest QoS level to receive messages with. Defaults to `0`
    /// - Returns: {Promise<number>} A Promise resolving to the QoS level the broker granted, or rejecting if the broker refused the subscription
    /// - Example:
    /// ```js
    /// await client.subscribe("home/#")
    /// await client.subscribe("alerts/critical", 1)
    /// ```
    @objc func subscribe(_ topicFilter: String, _ qos: Int) -> JSPromise?

    /// Unsubscribes from a topic filter.
    /// - Parameter topicFilter: The topic filter originally passed to `subscribe()`
    /// - Returns: {Promise<void>} A Promise resolving once the broker has acknowledged the request
    /// - Example:
    /// ```js
    /// await client.unsubscribe("home/#")
    /// ```
    @objc func unsubscribe(_ topicFilter: String) -> JSPromise?

    /// Sends a ping to the broker. The client already pings the broker regularly to keep the connection alive (see the `keepAlive` option), so you rarely need this.
    /// - Returns: {Promise<void>} A Promise resolving when the broker responds
    /// - Example:
    /// ```js
    /// await client.ping()
    /// ```
    @objc func ping() -> JSPromise?

    /// Register a listener for this client's events.
    ///
    /// Listeners receive:
    ///  - `"connected"`: `(sessionPresent)`, whether the broker resumed a previous session, each time the client connects, including when it reconnects by itself
    ///  - `"disconnected"`: `(reason)`, `null` when you called `disconnect()`, otherwise a description of why the connection was lost
    ///  - `"message"`: `(message)`, an object with the message's `topic`, its `payload` decoded as UTF-8, its raw `bytes` (a Uint8Array), its `qos`, and whether it is `retain`ed and a `duplicate`
    ///
    /// A client with listeners stays alive until you remove them or call `destroy()`.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "message"} The event to listen for
    ///   - listener: {(arg: boolean | string | null | {topic: string, payload: string, bytes: Uint8Array, qos: number, retain: boolean, duplicate: boolean}) => void} Called when the event occurs
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     client.on("message", msg => console.log(msg.topic + ": " + msg.payload))
    ///     client.on("disconnected", reason => console.log("Disconnected: " + reason))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func on(_ event: String, _ listener: JSFunction)

    /// Remove a previously registered listener for this client's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "message"} The event the listener was registered for
    ///   - listener: The function originally passed to `on`
    /// - Example:
    /// ```js
    /// client.off("message", myListener)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Register a listener that fires at most once for one of this client's events.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "message"} The event to listen for
    ///   - listener: {(arg: boolean | string | null | {topic: string, payload: string, bytes: Uint8Array, qos: number, retain: boolean, duplicate: boolean}) => void} Called once, then automatically removed
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     client.once("connected", () => console.log("Connected to " + client.host))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func once(_ event: String, _ listener: JSFunction)

    /// Disconnects from the broker, removes all listeners and releases the client. It can't be used again afterwards. Called automatically when Hammerspoon reloads its configuration.
    /// - Example:
    /// ```js
    /// client.destroy()
    /// ```
    @objc func destroy()

    // NOTE: Private API consumed only by hs.mqtt.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc(_removeWatcher) func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSMQTTClientEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }
}

// MARK: - Implementation

/// Events emitted by an HSMQTTClient's watcher
nonisolated enum HSMQTTClientEvent: String, HSEventName {
    case connected, disconnected, message
}

@_documentation(visibility: private)
@MainActor
@objc class HSMQTTClient: NSObject, HSMQTTClientAPI, HSTrackedObject {
    @objc var typeName = "HSMQTTClient"
    @objc let identifier = UUID().uuidString

    private enum State: String {
        case disconnected, connecting, connected, reconnecting, disconnecting
    }

    private weak var module: HSMQTTModule?
    private weak var tracker: HSObjectTracker<HSMQTTClient>?
    private let options: HSMQTTClientOptions
    private let client: MQTTClient

    /// The connection state. A connected or reconnecting client is active until disconnect(),
    /// even if the user drops their reference to it; connecting and disconnecting finish on their own.
    private var connectionState: State = .disconnected {
        didSet { updateActivity() }
    }

    private var watcherCallback: JSCallback? {
        didSet { updateActivity() }
    }
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSMQTTClientEvent.allNames }

    /// Topic filters subscribed to, with the requested QoS, restored on reconnection
    private var subscribedFilters: [String: MQTTQoS] = [:]

    /// The connection attempt in progress, if any, which disconnect() waits for
    private var connectTask: Task<Bool, Error>?
    /// The disconnection in progress, if any, which a second disconnect() waits for
    private var disconnectTask: Task<Void, Never>?
    /// Waits and retries after the connection was lost, while `connectionState` is `.reconnecting`
    private var reconnectTask: Task<Void, Never>?

    /// Set by destroy(), after which no Promise is settled: the JSContext is going away
    private var isDestroyed = false

    init(module: HSMQTTModule, options: HSMQTTClientOptions, tracker: HSObjectTracker<HSMQTTClient>) {
        self.module = module
        self.tracker = tracker
        self.options = options
        client = MQTTClient(
            host: options.host,
            port: options.port,
            identifier: options.clientID,
            // Network.framework's event loops, which TSTLSConfiguration (see HSMQTTClientOptions) needs
            eventLoopGroupProvider: .shared(NIOTSEventLoopGroup.singleton),
            configuration: options.configuration
        )
        super.init()
        Self.installListeners(on: client, for: self)
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of HSMQTTClient: \(identifier)")
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        reconnectTask?.cancel()
        reconnectTask = nil
        _removeWatcher()
        connectionState = .disconnected

        // mqtt-nio traps if an MQTTClient is deallocated before it's shut down, and shutdown()
        // keeps it alive until it's done. Disconnect first, so the broker doesn't publish the
        // client's will message as if the connection had failed.
        Self.disconnectAndShutDown(client)
    }

    /// Nonisolated so its closures aren't main-actor isolated: mqtt-nio calls them on its own queues
    nonisolated private static func disconnectAndShutDown(_ client: MQTTClient) {
        // Removed first, so closing the connection doesn't notify (and briefly retain) the
        // HSMQTTClient that's being destroyed
        client.removePublishListener(named: listenerName)
        client.removeCloseListener(named: listenerName)
        if client.isActive() {
            client.disconnect().whenComplete { _ in
                client.shutdown { _ in }
            }
        } else {
            client.shutdown { _ in }
        }
    }

    private func updateActivity() {
        let held = connectionState == .connected || connectionState == .reconnecting || watcherCallback != nil
        let transient = connectionState == .connecting || connectionState == .disconnecting
        tracker?.setActive(self, held || transient, finishesOnItsOwn: !held)
    }

    @objc func toString() -> String {
        "<\(typeName): \(clientID)@\(host):\(port), \(state)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Properties

    @objc var clientID: String { client.identifier }
    @objc var host: String { client.host }
    @objc var port: Int { client.port }
    @objc var state: String { connectionState.rawValue }
    @objc var isConnected: Bool { connectionState == .connected }
    @objc var subscriptions: [String: Int] { subscribedFilters.mapValues { Int($0.rawValue) } }

    // MARK: - Operations

    /// Runs a JS-facing asynchronous operation, settling its Promise with the result
    private func perform(_ method: String, _ body: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard !isDestroyed else {
            return context.createRejectedPromise(with: "hs.mqtt client.\(method)(): the client has been destroyed")
        }
        return wrapAsyncInJSPromise(in: context) { [self] holder in
            Task {
                do {
                    let result = try await body()
                    if !isDestroyed { holder.resolveWith(result) }
                } catch {
                    if !isDestroyed { holder.rejectWithMessage("hs.mqtt client.\(method)(): \(Self.describe(error))") }
                }
            }
        }
    }

    private func reject(_ method: String, _ message: String) -> JSPromise? {
        JSContext.current()?.createRejectedPromise(with: "hs.mqtt client.\(method)(): \(message)")
    }

    private func requireConnection() throws {
        guard connectionState == .connected else {
            throw HSMQTTError("the client is not connected (it is \(state))")
        }
    }

    @objc func connect() -> JSPromise? {
        perform("connect") {
            guard self.connectionState == .disconnected else {
                throw HSMQTTError("the client is already \(self.state)")
            }
            self.connectionState = .connecting
            do {
                let sessionPresent = try await self.establishConnection()
                guard self.connectionState == .connecting else {
                    throw HSMQTTError("disconnect() was called before the connection was established")
                }
                guard self.client.isActive() else {
                    throw HSMQTTError("the broker closed the connection")
                }
                self.connectionState = .connected
                self.fire(.connected, [sessionPresent])
                return sessionPresent
            } catch {
                if self.connectionState == .connecting {
                    self.connectionState = .disconnected
                }
                throw error
            }
        }
    }

    @objc func disconnect() -> JSPromise? {
        perform("disconnect") {
            if let pending = self.disconnectTask {
                await pending.value
                return nil
            }
            guard self.connectionState != .disconnected else { return nil }

            let task = Task {
                let wasConnected = self.connectionState == .connected
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.connectionState = .disconnecting
                // Let a connection attempt in progress finish, so there's a connection to close
                if let pending = self.connectTask {
                    _ = try? await pending.value
                }
                if self.client.isActive() {
                    do {
                        try await self.client.disconnect()
                    } catch {
                        AKWarning("hs.mqtt client.disconnect(): \(Self.describe(error))")
                    }
                }
                self.connectionState = .disconnected
                if wasConnected {
                    self.fire(.disconnected, [NSNull()])
                }
            }
            self.disconnectTask = task
            await task.value
            self.disconnectTask = nil
            return nil
        }
    }

    @objc func publish(_ topic: String, _ payload: String, _ options: [String: Any]?) -> JSPromise? {
        guard !topic.isEmpty, topic != "undefined" else { return reject("publish", "a topic is required") }
        let qos: MQTTQoS
        let retain: Bool
        do {
            qos = try Self.parseQoS(options?["qos"], name: "options.qos")
            if let value = options?["retain"], !(value is NSNull) {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw HSMQTTError("options.retain must be true or false")
                }
                retain = number.boolValue
            } else {
                retain = false
            }
        } catch {
            return reject("publish", Self.describe(error))
        }
        return perform("publish") {
            try self.requireConnection()
            try await self.client.publish(to: topic, payload: ByteBuffer(string: payload), qos: qos, retain: retain)
            return nil
        }
    }

    @objc func subscribe(_ topicFilter: String, _ qos: Int) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("subscribe", "a topic filter is required") }
        guard let level = MQTTQoS(rawValue: UInt8(clamping: qos)), (0...2).contains(qos) else {
            return reject("subscribe", "qos must be 0, 1 or 2")
        }
        return perform("subscribe") {
            try self.requireConnection()
            let granted = try await self.subscribe(to: topicFilter, qos: level)
            return Int(granted.rawValue)
        }
    }

    @objc func unsubscribe(_ topicFilter: String) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("unsubscribe", "a topic filter is required") }
        return perform("unsubscribe") {
            try self.requireConnection()
            try await self.client.unsubscribe(from: [topicFilter])
            self.subscribedFilters[topicFilter] = nil
            return nil
        }
    }

    @objc func ping() -> JSPromise? {
        perform("ping") {
            try self.requireConnection()
            try await self.client.ping()
            return nil
        }
    }

    // MARK: - Connection

    /// Connects the underlying MQTTClient, returning whether the broker resumed a session
    private func establishConnection() async throws -> Bool {
        let client = client
        let cleanSession = options.cleanSession
        let will = options.willMessage
        let task = Task {
            try await client.connect(cleanSession: cleanSession, will: will)
        }
        connectTask = task
        defer { connectTask = nil }
        return try await task.value
    }

    /// Subscribes to one topic filter, remembering it for reconnection
    private func subscribe(to topicFilter: String, qos: MQTTQoS) async throws -> MQTTQoS {
        let suback = try await client.subscribe(to: [MQTTSubscribeInfo(topicFilter: topicFilter, qos: qos)])
        guard let code = suback.returnCodes.first, code != .failure, let granted = MQTTQoS(rawValue: code.rawValue) else {
            throw HSMQTTError("the broker refused the subscription to '\(topicFilter)'")
        }
        subscribedFilters[topicFilter] = qos
        return granted
    }

    /// Called on the main thread when mqtt-nio reports that a connection closed
    private func connectionDidClose(_ reason: String?) {
        // Only an established connection being lost matters here: connect() and disconnect()
        // handle their own connections closing. If the client is active, this is a stale
        // notification for a connection that has since been replaced.
        guard !isDestroyed, connectionState == .connected, !client.isActive() else { return }
        AKDebug("hs.mqtt: \(toString()) lost its connection: \(reason ?? "closed by the broker")")
        if options.reconnectInterval > 0 {
            connectionState = .reconnecting
            startReconnecting()
        } else {
            connectionState = .disconnected
        }
        fire(.disconnected, [reason ?? "The broker closed the connection"])
    }

    private func startReconnecting() {
        let interval = options.reconnectInterval
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled, self.connectionState == .reconnecting else { return }
                if await self.attemptReconnection() { return }
            }
        }
    }

    /// Makes one attempt to restore a lost connection and its subscriptions. Returns true when
    /// there's nothing more to do, either because it worked or because disconnect() took over.
    private func attemptReconnection() async -> Bool {
        do {
            let sessionPresent = try await establishConnection()
            guard connectionState == .reconnecting else { return true }
            if !sessionPresent {
                for (filter, qos) in subscribedFilters {
                    do {
                        _ = try await subscribe(to: filter, qos: qos)
                    } catch {
                        AKWarning("hs.mqtt: \(toString()) couldn't restore its subscription to '\(filter)': \(Self.describe(error))")
                    }
                }
            }
            guard connectionState == .reconnecting else { return true }
            guard client.isActive() else { return false }
            reconnectTask = nil
            connectionState = .connected
            AKDebug("hs.mqtt: \(toString()) reconnected")
            fire(.connected, [sessionPresent])
            return true
        } catch {
            AKDebug("hs.mqtt: \(toString()) failed to reconnect: \(Self.describe(error))")
            return false
        }
    }

    /// Called on the main thread for each message the broker sends
    private func didReceive(_ message: MQTTPublishInfo) {
        guard !isDestroyed, let context = watcherCallback?.value?.context else { return }
        let bytes = message.payload.readableBytesView
        fire(.message, [[
            "topic": message.topicName,
            "payload": String(decoding: bytes, as: UTF8.self),
            "bytes": context.makeUint8Array(bytes) ?? NSNull(),
            "qos": Int(message.qos.rawValue),
            "retain": message.retain,
            "duplicate": message.dup,
        ] as [String: Any]])
    }

    /// Registers for mqtt-nio's notifications, which arrive on its event loop. Nonisolated so
    /// the closures aren't main-actor isolated: they hop to the main queue themselves, which
    /// also keeps messages in the order they arrived.
    nonisolated private static let listenerName = "hs.mqtt"

    nonisolated private static func installListeners(on client: MQTTClient, for owner: HSMQTTClient) {
        client.addPublishListener(named: listenerName) { [weak owner] result in
            switch result {
            case .success(let message):
                let owner = owner
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { owner?.didReceive(message) }
                }
            case .failure(let error):
                let reason = describe(error)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AKWarning("hs.mqtt: failed to receive a message: \(reason)") }
                }
            }
        }
        client.addCloseListener(named: listenerName) { [weak owner] result in
            let owner = owner
            var reason: String?
            if case .failure(let error) = result {
                reason = describe(error)
            }
            let closeReason = reason
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner?.connectionDidClose(closeReason) }
            }
        }
    }

    // MARK: - Helpers

    private static func parseQoS(_ value: Any?, name: String) throws -> MQTTQoS {
        guard let value, !(value is NSNull) else { return .atMostOnce }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let qos = MQTTQoS(rawValue: number.uint8Value), Double(number.uint8Value) == number.doubleValue else {
            throw HSMQTTError("\(name) must be 0, 1 or 2")
        }
        return qos
    }

    /// A user-facing description of an error from mqtt-nio, NIO or hs.mqtt itself
    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case let error as HSMQTTError:
            return error.message
        case let error as MQTTError:
            switch error {
            case .connectionError(let code): return "the broker refused the connection (\(code))"
            case .reasonError(let code): return "the broker returned an error (\(code))"
            case .noConnection: return "the client is not connected"
            case .serverClosedConnection: return "the broker closed the connection"
            case .timeout: return "timed out waiting for the broker"
            case .alreadyShutdown: return "the client has been destroyed"
            default: return "\(error)"
            }
        default:
            return "\(error)"
        }
    }

    // MARK: - Watcher

    /// Lazily creates this client's JS watcher emitter. Returns nil, having set
    /// `ctx.exception`, on failure, so on()/once() never return without registering.
    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let module else {
                ctx.exception = JSValue(newErrorFromMessage: "hs.mqtt client: the hs.mqtt module is unavailable", in: ctx)
                return nil
            }
            guard let emitter = module.makeClientEmitter(for: self, in: ctx) else { return nil }
            _watcherEmitter = emitter
        }
        return _watcherEmitter
    }

    @objc func on(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        _ = ctx.callCapturingException { emitter.invokeMethod("on", withArguments: [event, listener]) }
    }

    @objc func off(_ event: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("off", withArguments: [event, listener])
    }

    @objc func once(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        _ = ctx.callCapturingException { emitter.invokeMethod("once", withArguments: [event, listener]) }
    }

    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool {
        guard !isDestroyed else {
            AKWarning("hs.mqtt client._addWatcher(): \(toString()) has been destroyed")
            return false
        }
        guard watcherCallback == nil else {
            AKWarning("hs.mqtt client._addWatcher(): already watching \(toString()), refusing a second subscription")
            return false
        }
        watcherCallback = JSCallback(value: listener, owner: self)
        AKDebug("hs.mqtt client._addWatcher(): started watching \(toString())")
        return watcherCallback != nil
    }

    @objc(_removeWatcher) func _removeWatcher() {
        // Cleared first so the next on() creates a fresh emitter, in the caller's VM
        _watcherEmitter = nil
        guard watcherCallback != nil else { return }
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("hs.mqtt client._removeWatcher(): stopped watching \(toString())")
    }

    /// Delivers one of this client's events to its listeners
    private func fire(_ event: HSMQTTClientEvent, _ arguments: [Any] = []) {
        _ = watcherCallback?.call(withArguments: [event.rawValue] + arguments)
    }
}
