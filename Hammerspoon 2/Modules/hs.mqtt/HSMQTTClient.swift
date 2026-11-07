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
    /// - Returns: {Promise<number>} A Promise resolving to the requested QoS level once the broker has acknowledged the subscription. The broker may grant a lower level, or refuse the subscription, which this can't currently detect
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
    /// Session state (e.g. QoS 1/2 messages in flight) kept across connections. Only used when
    /// the cleanSession option is false; mqtt-nio connects with a clean session otherwise.
    private let session: MQTTSession?

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

    /// The open connection. mqtt-nio scopes a connection to a closure, which `connectionTask`
    /// runs until the connection closes.
    private var connection: MQTTConnection?
    private var connectionTask: Task<Void, Never>?
    /// Counts connections, so a closing connection's late notification can't affect a newer one
    private var connectionGeneration = 0

    /// Topic filters subscribed to, with the requested QoS, restored on reconnection
    private var subscribedFilters: [String: MQTTQoS] = [:]
    /// The task iterating each subscription's messages. mqtt-nio scopes a subscription to a
    /// closure too, so cancelling its task unsubscribes.
    private var subscriptionTasks: [String: Task<Void, Never>] = [:]
    /// The filters whose subscriptions are currently delivering messages (see didReceive)
    private var activeFilters: Set<String> = []
    /// The last subscription change queued for each filter (see changeSubscription)
    private var filterChanges: [String: Task<Void, Never>] = [:]

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
        session = options.cleanSession ? nil : MQTTSession(clientID: options.clientID)
        super.init()
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
        // Sends DISCONNECT, so the broker doesn't publish the will message, then closes. The
        // connection and subscription tasks finish by themselves once it has closed.
        connection?.close()
        connection = nil
        subscriptionTasks.removeAll()
        activeFilters.removeAll()
        filterChanges.removeAll()
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

    private func requireConnection() throws -> MQTTConnection {
        guard connectionState == .connected, let connection else {
            throw HSMQTTError("the client is not connected (it is \(state))")
        }
        return connection
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
                guard let connection = self.connection else {
                    throw HSMQTTError("the broker closed the connection")
                }
                await self.restoreSubscriptions(on: connection)
                guard self.connectionState == .connecting else {
                    throw HSMQTTError("disconnect() was called before the connection was established")
                }
                guard self.connection === connection else {
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
                if let connection = self.connection {
                    connection.close()
                    await self.connectionTask?.value
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
            let connection = try self.requireConnection()
            try await connection.publish(to: topic, payload: ByteBuffer(string: payload), qos: qos, retain: retain)
            return nil
        }
    }

    @objc func subscribe(_ topicFilter: String, _ qos: Int) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("subscribe", "a topic filter is required") }
        guard let level = MQTTQoS(rawValue: UInt8(clamping: qos)), (0...2).contains(qos) else {
            return reject("subscribe", "qos must be 0, 1 or 2")
        }
        return perform("subscribe") {
            let connection = try self.requireConnection()
            try await self.subscribe(to: topicFilter, qos: level, on: connection)
            // mqtt-nio 3 doesn't report the QoS the broker granted
            return Int(level.rawValue)
        }
    }

    @objc func unsubscribe(_ topicFilter: String) -> JSPromise? {
        guard !topicFilter.isEmpty, topicFilter != "undefined" else { return reject("unsubscribe", "a topic filter is required") }
        return perform("unsubscribe") {
            _ = try self.requireConnection()
            try await self.changeSubscription(for: topicFilter) {
                self.subscribedFilters[topicFilter] = nil
                await self.endSubscription(to: topicFilter)
            }
            return nil
        }
    }

    @objc func ping() -> JSPromise? {
        perform("ping") {
            let connection = try self.requireConnection()
            try await connection.ping()
            return nil
        }
    }

    // MARK: - Connection

    /// Opens a connection, returning whether the broker resumed a session
    private func establishConnection() async throws -> Bool {
        let task = Task { try await self.openConnection() }
        connectTask = task
        defer { connectTask = nil }
        return try await task.value
    }

    /// Starts `connectionTask`, which connects and then holds the connection open until it
    /// closes. Returns once the broker has accepted the connection.
    private func openConnection() async throws -> Bool {
        connectionGeneration += 1
        let generation = connectionGeneration
        let address = MQTTServerAddress.hostname(options.host, port: options.resolvedPort)
        let configuration = options.configuration
        let clientID = options.clientID
        let session = session
        // Network.framework's event loops, which TSTLSConfiguration (see HSMQTTClientOptions) needs
        let eventLoop = NIOTSEventLoopGroup.singleton.any()

        return try await withCheckedThrowingContinuation { continuation in
            connectionTask = Task { [weak self] in
                var pending: CheckedContinuation<Bool, any Error>? = continuation
                var failure: (any Error)?
                let operation: (MQTTConnection, Bool) async -> Void = { connection, sessionPresent in
                    // A connection that completes after destroy() is closed straight away. self is
                    // only borrowed here, not kept for the connection's lifetime (which would keep
                    // the client alive past destroy() until the connection had closed).
                    guard self?.isDestroyed == false else {
                        connection.close()
                        pending?.resume(throwing: HSMQTTError("the client has been destroyed"))
                        pending = nil
                        return
                    }
                    self?.connection = connection
                    pending?.resume(returning: sessionPresent)
                    pending = nil
                    await connection.waitOnClose()
                }
                do {
                    if let session {
                        try await MQTTConnection.withConnection(address: address, configuration: configuration, session: session, eventLoop: eventLoop, operation: operation)
                    } else {
                        try await MQTTConnection.withConnection(address: address, configuration: configuration, identifier: clientID, eventLoop: eventLoop) { connection in
                            await operation(connection, false)
                        }
                    }
                } catch {
                    failure = error
                }
                if let pending {
                    pending.resume(throwing: failure ?? HSMQTTError("the broker closed the connection"))
                }
                guard let self, self.connectionGeneration == generation else { return }
                self.connection = nil
                self.connectionTask = nil
                self.subscriptionTasks.removeAll()
                self.activeFilters.removeAll()
                self.connectionDidClose(failure)
            }
        }
    }

    /// Runs changes to one topic filter's subscription one at a time, in the order they're made.
    /// Each waits for the subscription before it to be replaced or removed, so two changes can't
    /// both see no subscription and start one each, and a SUBSCRIBE can't overtake an UNSUBSCRIBE.
    private func changeSubscription(for topicFilter: String, _ change: @escaping @MainActor () async throws -> Void) async throws {
        let previous = filterChanges[topicFilter]
        let task = Task {
            await previous?.value
            try await change()
        }
        let done = Task { _ = try? await task.value }
        filterChanges[topicFilter] = done
        defer {
            if filterChanges[topicFilter] == done { filterChanges[topicFilter] = nil }
        }
        try await task.value
    }

    /// Ends the subscription to a filter, if there is one, waiting for mqtt-nio to unsubscribe
    private func endSubscription(to topicFilter: String) async {
        guard let task = subscriptionTasks.removeValue(forKey: topicFilter) else { return }
        // Ending the subscription's closure makes mqtt-nio unsubscribe, which the task waits for
        task.cancel()
        await task.value
    }

    /// Subscribes to one topic filter on a connection, remembering it for reconnection.
    /// Returns once the broker has acknowledged the subscription.
    private func subscribe(to topicFilter: String, qos: MQTTQoS, on connection: MQTTConnection) async throws {
        try await changeSubscription(for: topicFilter) {
            // Replaces any existing subscription, which must have unsubscribed first, or its
            // UNSUBSCRIBE would remove the new one too
            await self.endSubscription(to: topicFilter)
            try await self.startSubscription(to: topicFilter, qos: qos, on: connection)
        }
    }

    private func startSubscription(to topicFilter: String, qos: MQTTQoS, on connection: MQTTConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            subscriptionTasks[topicFilter] = Task { [weak self] in
                var pending: CheckedContinuation<Void, any Error>? = continuation
                do {
                    try await connection.subscribe(to: [MQTTSubscribeInfo(topicFilter: topicFilter, qos: qos)]) { messages in
                        // Recorded before any message (e.g. a retained one) is delivered
                        self?.subscribedFilters[topicFilter] = qos
                        self?.activeFilters.insert(topicFilter)
                        pending?.resume()
                        pending = nil
                        for try await message in messages {
                            self?.didReceive(message, via: topicFilter)
                        }
                    }
                } catch {
                    pending?.resume(throwing: error)
                    pending = nil
                }
                self?.activeFilters.remove(topicFilter)
            }
        }
    }

    /// Re-subscribes a new connection to the topic filters subscribed to on earlier ones
    private func restoreSubscriptions(on connection: MQTTConnection) async {
        for (filter, qos) in subscribedFilters {
            do {
                try await subscribe(to: filter, qos: qos, on: connection)
            } catch {
                AKWarning("hs.mqtt: \(toString()) couldn't restore its subscription to '\(filter)': \(Self.describe(error))")
            }
        }
    }

    /// Called when a connection closes, unless the client is being disconnected or destroyed
    private func connectionDidClose(_ error: (any Error)?) {
        // Only an established connection being lost matters here: connect() and disconnect()
        // handle their own connections closing
        guard !isDestroyed, connectionState == .connected else { return }
        let reason = error.map(Self.describe)
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
            guard let connection else { return false }
            await restoreSubscriptions(on: connection)
            guard connectionState == .reconnecting else { return true }
            guard self.connection === connection else { return false }
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

    /// Called for each message delivered to the subscription for `topicFilter`
    private func didReceive(_ message: MQTTPublishInfo, via topicFilter: String) {
        // mqtt-nio delivers a message to every subscription whose filter matches its topic, so
        // with overlapping filters (e.g. "home/#" and "home/+/temperature") only the first
        // matching filter's subscription passes it on, so it's delivered once
        let deliveringFilter = activeFilters.sorted().first { Self.topic(message.topicName, matches: $0) }
        guard deliveringFilter == topicFilter else { return }
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

    /// MQTT topic filter matching: `+` matches one level and `#` all remaining levels, and
    /// neither matches a first level starting with `$` (e.g. `$SYS`)
    static func topic(_ topic: String, matches filter: String) -> Bool {
        let topicLevels = topic.split(separator: "/", omittingEmptySubsequences: false)
        let filterLevels = filter.split(separator: "/", omittingEmptySubsequences: false)
        if topic.hasPrefix("$"), filter.first == "+" || filter.first == "#" { return false }
        for (index, level) in filterLevels.enumerated() {
            if level == "#" { return true }
            guard index < topicLevels.count else { return false }
            if level != "+" && level != topicLevels[index] { return false }
        }
        return filterLevels.count == topicLevels.count
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
            case .connectionClosed: return "the connection is closed"
            case .serverClosedConnection: return "the broker closed the connection"
            case .timeout: return "timed out waiting for the broker"
            case .invalidTopicFilter(let filter): return "'\(filter)' is not a valid topic filter"
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
