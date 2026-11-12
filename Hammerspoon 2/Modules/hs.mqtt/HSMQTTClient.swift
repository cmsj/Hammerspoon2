//
//  HSMQTTClient.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import MQTT
import Network

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

    /// The MQTT client identifier sent to the broker. Unless you chose one with the `clientID` option, it is `"hammerspoon-"` followed by eight random characters.
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
    /// - Returns: {Promise<number>} A Promise resolving to the QoS level the broker granted, which may be lower than requested. It rejects if the broker refuses the subscription
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

    /// Register a listener for this client's events.
    ///
    /// Listeners receive:
    ///  - `"connected"`: `()`, each time the client connects, including when it reconnects by itself
    ///  - `"disconnected"`: `(reason)`, `null` when you called `disconnect()`, otherwise a description of why the connection was lost
    ///  - `"message"`: `(message)`, an object with the message's `topic`, its `payload` decoded as UTF-8, its raw `bytes` (a Uint8Array), its `qos`, and whether it is `retain`ed and a `duplicate`
    ///
    /// A client with listeners stays alive until you remove them or call `destroy()`.
    /// - Parameters:
    ///   - event: {"connected" | "disconnected" | "message"} The event to listen for
    ///   - listener: {(arg?: string | null | {topic: string, payload: string, bytes: Uint8Array, qos: number, retain: boolean, duplicate: boolean}) => void} Called when the event occurs
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
    ///   - listener: {(arg?: string | null | {topic: string, payload: string, bytes: Uint8Array, qos: number, retain: boolean, duplicate: boolean}) => void} Called once, then automatically removed
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

    private let connection: MQTTClient

    /// Handles `connection`'s status changes and messages, in order
    private var eventsTask: Task<Void, Never>?

    /// The disconnect() in progress, which every overlapping disconnect() waits for
    private var closing: Task<Void, Never>?

    /// Topic filters subscribed to, restored on reconnection, with the requested QoS and the
    /// subscribe() that requested it
    private var subscribedFilters: [String: (qos: MQTTQoS, request: UUID)] = [:]

    /// Set by destroy(), after which no Promise is settled: the JSContext is going away
    private var isDestroyed = false

    init(module: HSMQTTModule, options: HSMQTTClientOptions, tracker: HSObjectTracker<HSMQTTClient>) {
        self.module = module
        self.tracker = tracker
        self.options = options
        connection = options.makeClient()
        super.init()
        let events = connection.events()
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .status(let status, let previous): connectionDidUpdate(status, previous: previous)
                case .message(let message): didReceive(message)
                case .error: break
                }
            }
        }
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of HSMQTTClient: \(identifier)")
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        _removeWatcher()
        eventsTask?.cancel()
        eventsTask = nil
        connectionState = .disconnected
        // Sends DISCONNECT, so the broker doesn't publish the will message
        Task { [connection] in try? await connection.close() }
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

    @objc var clientID: String { options.clientID }
    @objc var host: String { options.host }
    @objc var port: Int { options.resolvedPort }
    @objc var state: String { connectionState.rawValue }
    @objc var isConnected: Bool { connectionState == .connected }
    @objc var subscriptions: [String: Int] { subscribedFilters.mapValues { Int($0.qos.rawValue) } }

    // MARK: - Operations

    /// Runs a JS-facing asynchronous operation, settling its Promise with the result
    private func perform(_ method: String, _ body: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard !isDestroyed else {
            return context.createRejectedPromise(with: "hs.mqtt client.\(method)(): the client has been destroyed")
        }
        return wrapAsyncInJSPromise(in: context) { [self] holder in
            Task {
                // destroy() may have run since this was called, in the same JavaScript turn
                guard !isDestroyed else { return }
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

    private func requireConnected() throws {
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
                let connack = try await self.connection.open(self.options.identity, will: self.options.mqttWill, cleanStart: self.options.cleanSession)
                guard self.connectionState == .connecting else { throw MQTTError.clientClose(.normal) }
                await self.restoreSubscriptions()
                guard self.connectionState == .connecting else { throw MQTTError.clientClose(.normal) }
                guard await self.connection.status == .opened else { throw HSMQTTError("the broker closed the connection") }
                self.connectionState = .connected
                self.fire(.connected)
                return connack.sessionPresent
            } catch {
                if self.connectionState == .connecting {
                    // Also stops swift-mqtt retrying a first connection that failed
                    try? await self.connection.close()
                    self.connectionState = .disconnected
                }
                throw error
            }
        }
    }

    @objc func disconnect() -> JSPromise? {
        perform("disconnect") {
            if self.connectionState != .disconnected, self.connectionState != .disconnecting {
                let wasConnected = self.connectionState == .connected
                self.connectionState = .disconnecting
                self.closing = Task {
                    // Also cancels a reconnection that's waiting to happen
                    try? await self.connection.close()
                    self.closing = nil
                    self.connectionState = .disconnected
                    if wasConnected {
                        self.fire(.disconnected, [NSNull()])
                    }
                }
            }
            await self.closing?.value
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
            try self.requireConnected()
            try await self.connection.publish(to: topic, payload: payload, qos: qos, retain: retain)
            return nil
        }
    }

    @objc func subscribe(_ topicFilter: String, _ qos: Int) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("subscribe", "a topic filter is required") }
        guard let level = MQTTQoS(rawValue: UInt8(clamping: qos)), (0...2).contains(qos) else {
            return reject("subscribe", "qos must be 0, 1 or 2")
        }
        return perform("subscribe") {
            try self.requireConnected()
            // Recorded in the order of the calls, since the broker's answers may arrive in any order
            let request = UUID()
            self.subscribedFilters[topicFilter] = (level, request)
            do {
                return try await self.subscribe(to: topicFilter, qos: level)
            } catch {
                // Unless a newer subscribe() or unsubscribe() has replaced this request
                if self.subscribedFilters[topicFilter]?.request == request {
                    self.subscribedFilters[topicFilter] = nil
                }
                throw error
            }
        }
    }

    @objc func unsubscribe(_ topicFilter: String) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("unsubscribe", "a topic filter is required") }
        return perform("unsubscribe") {
            try self.requireConnected()
            self.subscribedFilters[topicFilter] = nil
            try await self.connection.unsubscribe(from: topicFilter)
            return nil
        }
    }

    // MARK: - Connection

    /// Subscribes to a topic filter, returning the QoS level the broker granted
    private func subscribe(to topicFilter: String, qos: MQTTQoS) async throws -> Int {
        let suback = try await connection.subscribe(to: topicFilter, qos: qos)
        guard let code = suback.codes.first, code.rawValue <= 2 else {
            throw HSMQTTError("the broker refused the subscription to '\(topicFilter)'")
        }
        return Int(code.rawValue)
    }

    /// Re-subscribes a new connection to the topic filters subscribed to on earlier ones,
    /// which swift-mqtt doesn't do by itself
    private func restoreSubscriptions() async {
        for (filter, subscription) in subscribedFilters {
            do {
                _ = try await subscribe(to: filter, qos: subscription.qos)
            } catch {
                AKWarning("hs.mqtt: \(toString()) couldn't restore its subscription to '\(filter)': \(Self.describe(error))")
            }
        }
    }

    private func finishReconnecting() async {
        await restoreSubscriptions()
        guard await connection.status == .opened, connectionState == .reconnecting else { return }
        connectionState = .connected
        AKDebug("hs.mqtt: \(toString()) reconnected")
        fire(.connected)
    }

    // connect() and disconnect() handle the status changes they cause themselves
    // Internal so tests can simulate the network going away, which they can't do for real
    func connectionDidUpdate(_ status: Status, previous: Status) {
        switch (status, previous, connectionState) {
        case (.opening, .opened, .connected):
            connectionState = .reconnecting
            fire(.disconnected, ["the connection was lost, and the client is reconnecting"])
        case (.opened, _, .reconnecting):
            Task { await finishReconnecting() }
        // swift-mqtt reconnects when the network returns
        case (.closed(let reason), _, .connected) where waitsForNetwork(reason):
            connectionState = .reconnecting
            fire(.disconnected, ["the network is unavailable, and the client will reconnect when it returns"])
        case (.closed(let reason), _, .reconnecting) where waitsForNetwork(reason):
            AKDebug("hs.mqtt: \(toString()) is waiting for the network to return")
        case (.closed(let reason), _, .connected), (.closed(let reason), _, .reconnecting):
            let description = Self.describe(reason)
            AKDebug("hs.mqtt: \(toString()) lost its connection: \(description)")
            connectionState = .disconnected
            fire(.disconnected, [description])
        default:
            break
        }
    }

    /// Whether a connection closed by `reason` is reopened by swift-mqtt once the network returns
    private func waitsForNetwork(_ reason: CloseReason?) -> Bool {
        guard options.reconnectInterval > 0 else { return false }
        switch reason {
        case .unsatisfied, .networkError(.posix(.ENETUNREACH)), .networkError(.posix(.ENETDOWN)): return true
        default: return false
        }
    }

    private func didReceive(_ message: Message) {
        guard !isDestroyed, let context = watcherCallback?.value?.context else { return }
        fire(.message, [[
            "topic": message.topic,
            "payload": String(decoding: message.payload, as: UTF8.self),
            "bytes": context.makeUint8Array(message.payload) ?? NSNull(),
            "qos": Int(message.qos.rawValue),
            "retain": message.retain,
            "duplicate": message.dup,
        ] as [String: Any]])
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

    /// A user-facing description of an error from swift-mqtt, Network.framework or hs.mqtt itself
    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case let error as HSMQTTError:
            return error.message
        case let error as MQTTError:
            switch error {
            case .connectFailed(let code?): return "the broker refused the connection (\(code))"
            case .serverClose(let code): return "the broker closed the connection (\(code))"
            case .clientClose: return "disconnect() was called before the operation finished"
            case .decodeError(.streamIsComplete): return "the broker closed the connection"
            case .timeout: return "timed out waiting for the broker"
            case .publishFailed(let code): return "the broker rejected the message (\(code))"
            default: return "\(error)"
            }
        default:
            return "\(error)"
        }
    }

    /// A user-facing description of why a connection closed
    nonisolated private static func describe(_ reason: CloseReason?) -> String {
        switch reason {
        case .mqttError(let error): return describe(error)
        case .serverClose(let code): return describe(MQTTError.serverClose(code))
        case .pingTimeout: return "the broker stopped responding"
        case .some(let reason): return reason.description
        case nil: return "the broker closed the connection"
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
