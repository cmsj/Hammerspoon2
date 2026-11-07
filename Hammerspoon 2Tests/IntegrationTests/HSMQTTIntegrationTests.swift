//
//  HSMQTTIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// A harness with hs.mqtt loaded and a FakeMQTTBroker listening on loopback, plus helpers to
/// wait for the Promises hs.mqtt returns. The broker is stopped when this goes away.
@MainActor
private final class MQTTFixture {
    let harness = JSTestHarness()
    let broker = FakeMQTTBroker()
    private(set) var port: UInt16 = 0

    init() {
        harness.loadModule(HSMQTTModule.self, as: "mqtt")
    }

    /// Starts the broker and puts a client for it, created with `options` (a JS object
    /// literal), in the global `client`
    func start(options: String = "{}") async throws {
        port = try await broker.start()
        harness.eval("var client = hs.mqtt.create('mqtt://127.0.0.1:\(port)', \(options))")
        #expect(harness.evalTypeOf("client") == "object")
    }

    isolated deinit {
        broker.stop()
    }

    /// Evaluates `expression`, a Promise, and waits for it to settle
    /// - Returns: The value it resolved with, and the reason it rejected with
    @discardableResult
    func settle(_ expression: String, timeout: TimeInterval = 5) async -> (value: JSValue?, error: String?) {
        harness.eval("""
            globalThis.__settled = false; globalThis.__value = undefined; globalThis.__error = undefined;
            (\(expression)).then(
                v => { __value = v; __settled = true; },
                e => { __error = String(e); __settled = true; }
            );
            """)
        let settled = await harness.waitForAsync(timeout: timeout) { [harness] in harness.evalBool("__settled") == true }
        #expect(settled, "\(expression) didn't settle")
        return (harness.evalValue("__value"), harness.evalString("__error === undefined ? null : __error"))
    }

    /// Records the client's events in the global `events` array, as `[name, argument]` pairs
    func recordEvents() {
        harness.eval("""
            var events = [];
            ['connected', 'disconnected', 'message'].forEach(name => client.on(name, arg => events.push([name, arg])));
            """)
    }

    func waitFor(_ condition: String, timeout: TimeInterval = 5) async -> Bool {
        await harness.waitForAsync(timeout: timeout) { [harness] in harness.evalBool(condition) == true }
    }

    func connect() async {
        let result = await settle("client.connect()")
        #expect(result.error == nil)
    }

    func disconnect() async {
        let result = await settle("client.disconnect()")
        #expect(result.error == nil)
    }
}

@Suite("hs.mqtt tests")
struct HSMQTTTests {

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSMQTTModule.self, as: "mqtt")
        return harness
    }

    // MARK: - Suite 1: API structure

    @Suite("hs.mqtt API structure tests")
    struct HSMQTTStructureTests {

        @Test("create is a function")
        func testCreateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.mqtt.create") == "function")
        }

        @Test("hs.mqtt.js installs the client emitter factory")
        func testEmitterFactoryInstalled() {
            #expect(makeHarness().evalTypeOf("hs.mqtt._makeClientEmitter") == "function")
        }

        @Test("Client methods are functions", arguments: [
            "connect", "disconnect", "publish", "subscribe", "unsubscribe", "ping", "on", "off", "once", "destroy",
        ])
        func testClientMethodIsFunction(_ method: String) {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('broker.local')")
            #expect(harness.evalTypeOf("c.\(method)") == "function")
        }

        @Test("A new client is disconnected and has no subscriptions")
        func testNewClientDefaults() {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('broker.local')")
            #expect(harness.evalString("c.typeName") == "HSMQTTClient")
            #expect(harness.evalString("c.state") == "disconnected")
            #expect(harness.evalBool("c.isConnected") == false)
            #expect(harness.evalString("JSON.stringify(c.subscriptions)") == "{}")
            #expect(harness.evalString("c.host") == "broker.local")
            #expect(harness.evalInt("c.port") == 1883)
            harness.expectTrue("/^hammerspoon-[0-9a-f]{8}$/.test(c.clientID)")
            harness.expectTrue("c.identifier.length > 0")
            #expect(!harness.hasException)
        }

        @Test("Two clients have different identifiers and client IDs")
        func testUniqueIdentifiers() {
            let harness = makeHarness()
            harness.eval("var a = hs.mqtt.create('broker.local'); var b = hs.mqtt.create('broker.local')")
            harness.expectTrue("a.identifier !== b.identifier")
            harness.expectTrue("a.clientID !== b.clientID")
        }

        @Test("toString describes the client")
        func testToString() {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('broker.local', { clientID: 'me' })")
            #expect(harness.evalString("String(c)") == "<HSMQTTClient: me@broker.local:1883, disconnected>")
        }

        @Test("on() rejects an unknown event name")
        func testUnknownEventThrows() {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('broker.local'); var threw = false; try { c.on('messages', () => {}) } catch (e) { threw = true }")
            #expect(harness.evalBool("threw") == true)
        }
    }

    // MARK: - Suite 2: create() options

    @Suite("hs.mqtt create() options")
    struct HSMQTTOptionsTests {

        @Test("A URL's scheme chooses the default port", arguments: [
            ("mqtt://broker.local", 1883),
            ("tcp://broker.local", 1883),
            ("mqtts://broker.local", 8883),
            ("ws://broker.local", 80),
            ("wss://broker.local", 443),
            ("mqtt://broker.local:1999", 1999),
        ])
        func testSchemePorts(_ server: String, _ port: Int) {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('\(server)')")
            #expect(harness.evalString("c.host") == "broker.local")
            #expect(harness.evalInt("c.port") == port)
        }

        @Test("Options override the URL")
        func testOptionsOverrideURL() {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create('mqtt://broker.local:1999', { port: 2000, clientID: 'kitchen' })")
            #expect(harness.evalInt("c.port") == 2000)
            #expect(harness.evalString("c.clientID") == "kitchen")
        }

        @Test("Invalid servers and options return null", arguments: [
            "''",
            "'ftp://broker.local'",
            "'mqtt://'",
            "'broker.local', { prot: 1883 }",
            "'broker.local', { port: 70000 }",
            "'broker.local', { port: 18.5 }",
            "'broker.local', { port: '1883' }",
            "'broker.local', { tls: 'yes' }",
            "'broker.local', { clientID: '' }",
            "'broker.local', { version: '4' }",
            "'broker.local', { keepAlive: 0 }",
            "'broker.local', { connectTimeout: -1 }",
            "'broker.local', { reconnectInterval: -1 }",
            "'broker.local', { will: { payload: 'gone' } }",
            "'broker.local', { will: { topic: 't', qos: 3 } }",
            "'broker.local', { will: { topic: 't', delay: 1 } }",
            "'broker.local', { allowUntrustedCertificates: true }",
            "'broker.local', { caCertificate: '/tmp/ca.pem' }",
            "'mqtts://broker.local', { caCertificate: '/nonexistent/ca.pem' }",
            "'mqtts://broker.local', { clientCertificatePassword: 'secret' }",
        ])
        func testInvalidReturnsNull(_ arguments: String) {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create(\(arguments))")
            #expect(harness.evalBool("c === null") == true)
            #expect(!harness.hasException)
        }

        @Test("Valid option combinations create a client", arguments: [
            "'broker.local', { version: '5' }",
            "'broker.local', { version: 5 }",
            "'broker.local', { tls: true, allowUntrustedCertificates: true }",
            "'broker.local', { websocket: true, websocketPath: 'mqtt' }",
            "'broker.local', { username: 'u', password: 'p', keepAlive: 30, connectTimeout: 2.5, timeout: 5 }",
            "'broker.local', { cleanSession: false, reconnectInterval: 1, will: { topic: 't', payload: 'gone', qos: 2, retain: true } }",
            "'broker.local', { port: null, clientID: undefined }",
        ])
        func testValidCreatesClient(_ arguments: String) {
            let harness = makeHarness()
            harness.eval("var c = hs.mqtt.create(\(arguments))")
            #expect(harness.evalString("c && c.typeName") == "HSMQTTClient")
        }

        @Test("Credentials and a WebSocket path are read from the URL")
        func testURLComponents() throws {
            let options = try HSMQTTClientOptions(server: "wss://some%20user:p%40ss@broker.local:9001/ws/mqtt", options: [:])
            #expect(options.host == "broker.local")
            #expect(options.port == 9001)
            #expect(options.username == "some user")
            #expect(options.password == "p@ss")
            #expect(options.tls)
            #expect(options.websocket)
            #expect(options.websocketPath == "/ws/mqtt")
        }

        @Test("Option credentials replace the URL's")
        func testOptionCredentials() throws {
            let options = try HSMQTTClientOptions(server: "mqtt://a:b@broker.local", options: ["username": "c", "password": "d"])
            #expect(options.username == "c")
            #expect(options.password == "d")
        }

        @Test("A file that isn't a certificate is rejected")
        func testInvalidCertificateFile() throws {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("hs_mqtt_\(UUID().uuidString).pem")
            try Data("-----BEGIN CERTIFICATE-----\nnot base64!\n-----END CERTIFICATE-----\n".utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            #expect(throws: HSMQTTError.self) {
                _ = try HSMQTTClientOptions.loadCertificates(file.path)
            }
        }
    }

    // MARK: - Suite 3: talking to a broker

    @Suite("hs.mqtt client behaviour", .serialized)
    struct HSMQTTClientBehaviourTests {
        init() async {
            await JSTestHarness.drainMainActorQueue()
        }

        @Test("connect() connects with the client's identity and fires 'connected'")
        func testConnect() async throws {
            let fixture = MQTTFixture()
            try await fixture.start(options: "{ clientID: 'office', username: 'hs', password: 'pw', cleanSession: false }")
            fixture.recordEvents()

            let result = await fixture.settle("client.connect()")
            #expect(result.error == nil)
            #expect(result.value?.toBool() == false)
            #expect(fixture.harness.evalString("client.state") == "connected")
            #expect(fixture.harness.evalBool("client.isConnected") == true)
            #expect(fixture.harness.evalString("JSON.stringify(events)") == "[[\"connected\",false]]")
            #expect(fixture.broker.connects == [
                FakeMQTTBroker.Connect(clientID: "office", username: "hs", password: "pw", cleanSession: false),
            ])

            await fixture.disconnect()
        }

        @Test("connect() sends the will message")
        func testWill() async throws {
            let fixture = MQTTFixture()
            try await fixture.start(options: "{ will: { topic: 'status/mac', payload: 'offline', qos: 1, retain: true } }")
            await fixture.connect()
            let connect = try #require(fixture.broker.connects.first)
            #expect(connect.willTopic == "status/mac")
            #expect(connect.willPayload == "offline")
            #expect(connect.willQoS == 1)
            #expect(connect.willRetain)
            await fixture.disconnect()
        }

        @Test("connect() rejects when the broker refuses the connection")
        func testConnectRefused() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.broker.connackReturnCode = 5
            let result = await fixture.settle("client.connect()")
            #expect(result.error?.contains("refused the connection") == true, "rejected with \(result.error ?? "nothing")")
            #expect(fixture.harness.evalString("client.state") == "disconnected")
        }

        @Test("connect() rejects when nothing is listening")
        func testConnectNoBroker() async throws {
            let fixture = MQTTFixture()
            let port = try await fixture.broker.start()
            fixture.broker.stop()
            fixture.harness.eval("var client = hs.mqtt.create('127.0.0.1', { port: \(port), connectTimeout: 2 })")
            let result = await fixture.settle("client.connect()")
            #expect(result.error != nil)
            #expect(fixture.harness.evalString("client.state") == "disconnected")
        }

        @Test("connect() rejects while already connected")
        func testConnectTwice() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            let result = await fixture.settle("client.connect()")
            #expect(result.error?.contains("already connected") == true)
            await fixture.disconnect()
        }

        @Test("disconnect() disconnects cleanly and fires 'disconnected' with null")
        func testDisconnect() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.recordEvents()
            await fixture.connect()
            await fixture.disconnect()
            #expect(fixture.harness.evalString("client.state") == "disconnected")
            #expect(fixture.harness.evalString("JSON.stringify(events)") == "[[\"connected\",false],[\"disconnected\",null]]")
            #expect(await fixture.harness.waitForAsync { fixture.broker.disconnects == 1 })

            // A second disconnect() has nothing to do
            let again = await fixture.settle("client.disconnect()")
            #expect(again.error == nil)
        }

        @Test("publish() sends the topic, payload, QoS and retain flag", arguments: [
            ("{}", 0, false),
            ("{ qos: 1 }", 1, false),
            ("{ qos: 2, retain: true }", 2, true),
        ])
        func testPublish(_ options: String, _ qos: Int, _ retain: Bool) async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            let result = await fixture.settle("client.publish('home/light', 'on ✓', \(options))")
            #expect(result.error == nil)
            #expect(await fixture.harness.waitForAsync { !fixture.broker.publishes.isEmpty })
            #expect(fixture.broker.publishes == [
                FakeMQTTBroker.Publish(topic: "home/light", payload: Data("on ✓".utf8), qos: qos, retain: retain),
            ])
            await fixture.disconnect()
        }

        @Test("publish() rejects invalid arguments", arguments: [
            "client.publish('', 'x')",
            "client.publish('t', 'x', { qos: 3 })",
            "client.publish('t', 'x', { qos: 'one' })",
            "client.publish('t', 'x', { retain: 1 })",
        ])
        func testPublishInvalid(_ expression: String) async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            let result = await fixture.settle(expression)
            #expect(result.error != nil)
            #expect(fixture.broker.publishes.isEmpty)
            await fixture.disconnect()
        }

        @Test("Operations reject while disconnected", arguments: [
            "client.publish('t', 'x')", "client.subscribe('t')", "client.unsubscribe('t')", "client.ping()",
        ])
        func testRejectWhileDisconnected(_ expression: String) async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            let result = await fixture.settle(expression)
            #expect(result.error?.contains("not connected") == true)
        }

        @Test("Subscribed messages arrive as 'message' events")
        func testSubscribeAndReceive() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.recordEvents()
            await fixture.connect()

            let result = await fixture.settle("client.subscribe('home/+/temperature', 1)")
            #expect(result.value?.toInt32() == 1)
            #expect(fixture.harness.evalString("JSON.stringify(client.subscriptions)") == "{\"home/+/temperature\":1}")
            #expect(fixture.broker.subscribes == ["home/+/temperature"])

            fixture.broker.send(topic: "home/office/humidity", payload: "40")
            fixture.broker.send(topic: "home/office/temperature", payload: "21.5", retain: true)
            #expect(await fixture.waitFor("events.some(e => e[0] === 'message')"))
            fixture.harness.eval("var msg = events.find(e => e[0] === 'message')[1]")
            #expect(fixture.harness.evalString("msg.topic") == "home/office/temperature")
            #expect(fixture.harness.evalString("msg.payload") == "21.5")
            #expect(fixture.harness.evalString("Array.from(msg.bytes).join(',')") == "50,49,46,53")
            harnessExpectTrue(fixture, "msg.bytes instanceof Uint8Array")
            #expect(fixture.harness.evalInt("msg.qos") == 0)
            #expect(fixture.harness.evalBool("msg.retain") == true)
            #expect(fixture.harness.evalBool("msg.duplicate") == false)
            #expect(fixture.harness.evalInt("events.filter(e => e[0] === 'message').length") == 1)

            await fixture.disconnect()
        }

        @Test("Messages published by the client itself are delivered back to its subscription")
        func testRoundTrip() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.harness.eval("var received = []; client.on('message', m => received.push(m.payload))")
            await fixture.connect()
            await fixture.settle("client.subscribe('echo/#')")
            await fixture.settle("client.publish('echo/1', 'first').then(() => client.publish('echo/2', 'second'))")
            #expect(await fixture.waitFor("received.length === 2"))
            #expect(fixture.harness.evalString("received.join(',')") == "first,second")
            await fixture.disconnect()
        }

        @Test("subscribe() rejects an invalid QoS")
        func testSubscribeInvalidQoS() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            let badQoS = await fixture.settle("client.subscribe('t', 3)")
            #expect(badQoS.error?.contains("qos") == true)
            #expect(fixture.harness.evalString("JSON.stringify(client.subscriptions)") == "{}")
            await fixture.disconnect()
        }

        @Test("subscribe() can't tell when the broker refuses a subscription")
        func testSubscribeRefused() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.broker.refusedFilters = ["secret/#"]
            await fixture.connect()
            let refused = await fixture.settle("client.subscribe('secret/#')")
            withKnownIssue("mqtt-nio 3.0.0-rc.1 ignores the return codes in SUBACK") {
                #expect(refused.error?.contains("refused") == true)
            }
            await fixture.disconnect()
        }

        @Test("A message matching overlapping subscriptions is delivered once")
        func testOverlappingSubscriptions() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.harness.eval("var received = []; client.on('message', m => received.push(m.topic))")
            await fixture.connect()
            await fixture.settle("client.subscribe('home/#')")
            await fixture.settle("client.subscribe('home/+/temperature')")
            fixture.broker.send(topic: "home/office/temperature", payload: "21")
            fixture.broker.send(topic: "home/office/humidity", payload: "40")
            #expect(await fixture.waitFor("received.length >= 2"))
            try await Task.sleep(for: .milliseconds(100))
            #expect(fixture.harness.evalString("received.join(',')") == "home/office/temperature,home/office/humidity")
            await fixture.disconnect()
        }

        @Test("Topic filters match MQTT's wildcard rules", arguments: [
            ("a/b", "a/b", true), ("a/b", "a/c", false), ("a/b/c", "a/+/c", true), ("a/b", "a/+/c", false),
            ("a/b/c", "a/#", true), ("a", "a/#", true), ("a/b", "#", true), ("$SYS/x", "#", false),
            ("$SYS/x", "$SYS/#", true), ("a/b", "+", false),
        ])
        func testTopicMatching(_ topic: String, _ filter: String, _ matches: Bool) {
            #expect(HSMQTTClient.topic(topic, matches: filter) == matches)
        }

        @Test("unsubscribe() removes the subscription")
        func testUnsubscribe() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            await fixture.settle("client.subscribe('a/b')")
            let result = await fixture.settle("client.unsubscribe('a/b')")
            #expect(result.error == nil)
            #expect(fixture.broker.unsubscribes == ["a/b"])
            #expect(fixture.harness.evalString("JSON.stringify(client.subscriptions)") == "{}")
            await fixture.disconnect()
        }

        @Test("ping() is answered by the broker")
        func testPing() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            let result = await fixture.settle("client.ping()")
            #expect(result.error == nil)
            #expect(fixture.broker.pings >= 1)
            await fixture.disconnect()
        }

        @Test("A lost connection fires 'disconnected' with a reason")
        func testConnectionLost() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.recordEvents()
            await fixture.connect()
            fixture.broker.dropConnections()
            #expect(await fixture.waitFor("events.some(e => e[0] === 'disconnected')"))
            #expect(fixture.harness.evalString("client.state") == "disconnected")
            harnessExpectTrue(fixture, "typeof events.find(e => e[0] === 'disconnected')[1] === 'string'")
        }

        @Test("With reconnectInterval, a lost connection is restored along with its subscriptions")
        func testReconnect() async throws {
            let fixture = MQTTFixture()
            try await fixture.start(options: "{ reconnectInterval: 0.1 }")
            fixture.recordEvents()
            await fixture.connect()
            await fixture.settle("client.subscribe('home/#', 1)")

            fixture.broker.dropConnections()
            #expect(await fixture.waitFor("events.filter(e => e[0] === 'connected').length === 2"))
            #expect(fixture.harness.evalString("client.state") == "connected")
            #expect(fixture.harness.evalString("events.map(e => e[0]).join(',')") == "connected,disconnected,connected")
            #expect(fixture.broker.connects.count == 2)
            #expect(fixture.broker.subscribes == ["home/#", "home/#"])

            // The restored subscription delivers messages
            fixture.broker.send(topic: "home/door", payload: "open")
            #expect(await fixture.waitFor("events.some(e => e[0] === 'message' && e[1].payload === 'open')"))

            await fixture.disconnect()
        }

        @Test("disconnect() stops a reconnecting client from trying again")
        func testDisconnectWhileReconnecting() async throws {
            let fixture = MQTTFixture()
            try await fixture.start(options: "{ reconnectInterval: 0.3 }")
            await fixture.connect()
            fixture.broker.connackReturnCode = 5    // reconnection attempts fail
            fixture.broker.dropConnections()
            #expect(await fixture.waitFor("client.state === 'reconnecting'"))
            await fixture.disconnect()
            #expect(fixture.harness.evalString("client.state") == "disconnected")
            let attempts = fixture.broker.connects.count
            try await Task.sleep(for: .milliseconds(700))
            #expect(fixture.broker.connects.count == attempts)
        }

        @Test("disconnect() during connect() leaves the client disconnected")
        func testDisconnectWhileConnecting() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            fixture.harness.eval("var connectResult = null; client.connect().then(v => connectResult = 'ok', e => connectResult = String(e))")
            let result = await fixture.settle("client.disconnect()")
            #expect(result.error == nil)
            #expect(await fixture.waitFor("connectResult !== null"))
            #expect(fixture.harness.evalString("client.state") == "disconnected")
        }

        @Test("A destroyed client rejects connect() and disconnects from the broker")
        func testDestroy() async throws {
            let fixture = MQTTFixture()
            try await fixture.start()
            await fixture.connect()
            fixture.harness.eval("client.destroy()")
            #expect(fixture.harness.evalString("client.state") == "disconnected")
            #expect(await fixture.harness.waitForAsync { fixture.broker.disconnects == 1 })
            let result = await fixture.settle("client.connect()")
            #expect(result.error?.contains("destroyed") == true)
        }

        private func harnessExpectTrue(_ fixture: MQTTFixture, _ expression: String, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(fixture.harness.evalBool(expression) == true, "\(expression)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Suite 4: object lifetime

    @Suite("hs.mqtt object lifetime", .serialized)
    struct HSMQTTLifetimeTests {
        init() async {
            await JSTestHarness.drainMainActorQueue()
        }

        @Test("A connected HSMQTTClient is released after shutdown")
        func testClientDoesNotLeakAfterReload() async throws {
            let tracker = WeakLeakTracker()
            let broker = FakeMQTTBroker()
            let port = try await broker.start()
            defer { broker.stop() }

            let harness = JSTestHarness()
            harness.loadModule(HSMQTTModule.self, as: "mqtt")
            var client: HSMQTTClient?
            autoreleasepool {
                harness.eval("""
                    var client = hs.mqtt.create('127.0.0.1', { port: \(port) });
                    client.on('message', () => {});
                    client.connect().then(() => client.subscribe('a/#'));
                    """)
                client = harness.evalValue("client")?.toObjectOf(HSMQTTClient.self) as? HSMQTTClient
            }
            tracker.track(try #require(client))

            // Polls the Swift object rather than eval(), whose JSValues would be autoreleased
            // outside any pool that closes before assertNoLeaks() (see HSUIWebViewTests)
            #expect(await harness.waitForAsync(timeout: 5) { client?.subscriptions.isEmpty == false })
            autoreleasepool {
                harness.eval("client = null")
                harness.shutdownForLeakTest()
            }
            client = nil
            tracker.assertNoLeaks()
        }

        @Test("A connected client the caller didn't keep stays connected after garbage collection")
        func testUnreferencedConnectedClientSurvivesGC() async throws {
            let fixture = MQTTFixture()
            let port = try await fixture.broker.start()
            weak var client: HSMQTTClient?

            // autoreleasepool: otherwise the JSValues eval returns hold the client's wrapper,
            // which pins it and makes the test pass even without the fix
            autoreleasepool {
                fixture.harness.eval("var connected = false; var c = hs.mqtt.create('127.0.0.1', { port: \(port) }); c.connect().then(() => { connected = true; })")
                client = fixture.harness.evalValue("c")?.toObjectOf(HSMQTTClient.self) as? HSMQTTClient
                fixture.harness.eval("c = null")
            }
            #expect(await fixture.waitFor("connected"))
            await JSTestHarness.drainMainActorQueue()
            fixture.harness.collectGarbage()

            #expect(client != nil)
            #expect(client?.isConnected == true)
            #expect(fixture.broker.connectionCount == 1)
        }

        // Unlike the test above, this passes even without the client pinning itself: its
        // emitter (held by Swift) closes over its wrapper. It checks the listener survives.
        @Test("A connected client with a listener keeps calling it after garbage collection")
        func testUnreferencedClientListenerSurvivesGC() async throws {
            let fixture = MQTTFixture()
            let port = try await fixture.broker.start()
            var received: String?
            fixture.harness.registerCallback("onMessage") { (payload: String) in received = payload }

            autoreleasepool {
                _ = fixture.harness.eval("""
                    var subscribed = false;
                    void (function() {
                        const c = hs.mqtt.create('127.0.0.1', { port: \(port) });
                        c.on('message', m => onMessage(m.payload));
                        c.connect().then(() => c.subscribe('t')).then(() => { subscribed = true; });
                    })()
                    """)
            }
            #expect(await fixture.waitFor("subscribed"))
            fixture.harness.collectGarbage()

            fixture.broker.send(topic: "t", payload: "still here")
            #expect(await fixture.harness.waitForAsync(timeout: 5) { received == "still here" })
        }

        @Test("A disconnected client the caller didn't keep is garbage collected")
        func testDisconnectedClientIsCollected() async throws {
            let fixture = MQTTFixture()
            let port = try await fixture.broker.start()
            weak var client: HSMQTTClient?
            autoreleasepool {
                fixture.harness.eval("var c = hs.mqtt.create('127.0.0.1', { port: \(port) })")
                client = fixture.harness.evalValue("c")?.toObjectOf(HSMQTTClient.self) as? HSMQTTClient
            }
            await fixture.settle("c.connect().then(() => c.disconnect())")
            autoreleasepool {
                _ = fixture.harness.eval("void (c = null, __value = undefined)")
            }
            await JSTestHarness.drainMainActorQueue()
            fixture.harness.collectGarbage()
            #expect(client == nil)
        }

        @Test("A client whose listeners are removed is garbage collected")
        func testClientWithoutListenersIsCollected() async {
            let fixture = MQTTFixture()
            weak var client: HSMQTTClient?
            autoreleasepool {
                fixture.harness.eval("var c = hs.mqtt.create('broker.local'); var f = () => {}; c.on('message', f)")
                client = fixture.harness.evalValue("c")?.toObjectOf(HSMQTTClient.self) as? HSMQTTClient
                fixture.harness.eval("c.off('message', f); c = null")
            }
            fixture.harness.collectGarbage()
            #expect(client == nil)
        }
    }
}
