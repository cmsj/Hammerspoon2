//
//  HSSocketIntegrationTests.swift
//  Hammerspoon 2Tests
//
// These tests exercise hs.socket over loopback TCP, Unix domain sockets and loopback UDP. No
// external network access is required.

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

/// A unique Unix domain socket path. Kept short, since socket paths are limited to 104 bytes.
private func temporarySocketPath() -> String {
    "/tmp/hs2-\(UUID().uuidString.prefix(8)).sock"
}

@MainActor
@Suite("hs.socket tests", .serialized)
struct HSSocketTests {

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSSocketModule.self, as: "socket")
        return harness
    }

    // MARK: - API structure

    @MainActor
    @Suite("hs.socket API structure tests")
    struct HSSocketStructureTests {

        @Test("Module functions and properties have the right types")
        func testModuleMembers() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.socket.create") == "function")
            #expect(harness.evalTypeOf("hs.socket.createUDP") == "function")
            #expect(harness.evalTypeOf("hs.socket.decodeText") == "function")
            #expect(harness.evalDouble("hs.socket.timeout") == 0)
        }

        @Test("A new stream socket is idle")
        func testNewStreamSocket() {
            let harness = makeHarness()
            harness.eval("var s = hs.socket.create()")
            #expect(harness.evalString("s.typeName") == "HSSocket")
            #expect(harness.evalBool("s.isConnected") == false)
            #expect(harness.evalBool("s.isListening") == false)
            #expect(harness.evalBool("s.isSecure") == false)
            #expect(harness.evalBool("s.remoteHost === null") == true)
            #expect(harness.evalInt("s.remotePort") == 0)
            #expect(harness.evalInt("s.localPort") == 0)
            #expect(harness.evalBool("s.unixPath === null") == true)
            #expect(harness.evalInt("s.clients.length") == 0)
            harness.expectTrue("hs.socket.create().identifier !== s.identifier")
            #expect(!harness.hasException)
        }

        @Test("New stream sockets take the module's timeout")
        func testDefaultTimeout() {
            let harness = makeHarness()
            harness.eval("hs.socket.timeout = 7")
            #expect(harness.evalDouble("hs.socket.create().timeout") == 7)
        }

        @Test("A new UDP socket has its defaults")
        func testNewUDPSocket() {
            let harness = makeHarness()
            harness.eval("var u = hs.socket.createUDP()")
            #expect(harness.evalString("u.typeName") == "HSUDPSocket")
            #expect(harness.evalBool("u.isBound") == false)
            #expect(harness.evalBool("u.isConnected") == false)
            #expect(harness.evalBool("u.isReceiving") == false)
            #expect(harness.evalInt("u.localPort") == 0)
            #expect(harness.evalBool("u.broadcast") == false)
            #expect(harness.evalBool("u.reusePort") == false)
            #expect(harness.evalBool("u.ipv4Enabled") == true)
            #expect(harness.evalBool("u.ipv6Enabled") == true)
            #expect(!harness.hasException)
        }

        @Test("decodeText decodes UTF-8 and rejects invalid bytes")
        func testDecodeText() {
            let harness = makeHarness()
            #expect(harness.evalString("hs.socket.decodeText(new Uint8Array([104, 195, 169]))") == "hé")
            #expect(harness.evalBool("hs.socket.decodeText(new Uint8Array([0xFF, 0xFE])) === null") == true)
            #expect(harness.evalBool("hs.socket.decodeText('nope') === null") == true)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Stream sockets

    @MainActor
    @Suite("hs.socket stream socket tests", .serialized)
    struct HSSocketStreamTests {

        /// Starts an echo-ish TCP server that logs everything it receives, and returns once it's
        /// listening.
        private func startServer(_ harness: JSTestHarness) async -> Int? {
            harness.eval("""
                var serverLog = [];
                var server = hs.socket.create().setCallback((event, sock, data, tag) => {
                    if (event === "connection") { data.readUntil("\\n", 7); }
                    if (event === "data") {
                        serverLog.push({tag: tag, text: hs.socket.decodeText(data), isBytes: data instanceof Uint8Array});
                        sock.write("echo:" + hs.socket.decodeText(data));
                        sock.readUntil("\\n", 7);
                    }
                    if (event === "error") serverLog.push({error: data});
                }).listen(0);
            """)
            guard await harness.waitForAsync(timeout: 2, condition: { harness.evalInt("server.localPort") ?? 0 > 0 }) else { return nil }
            return harness.evalInt("server.localPort")
        }

        @Test("A client and server exchange delimited lines over TCP")
        func testTCPRoundTrip() async throws {
            let harness = makeHarness()
            let port = try #require(await startServer(harness))
            #expect(harness.evalBool("server.isListening") == true)

            harness.eval("""
                var clientLog = [];
                var client = hs.socket.create().setCallback((event, sock, data, tag) => {
                    if (event === "connected") sock.write("hello\\nwor").write("ld\\n").readUntil("\\n", 1).readUntil("\\n", 2);
                    if (event === "data") clientLog.push(tag + ":" + hs.socket.decodeText(data));
                    if (event === "error") clientLog.push("error:" + data);
                }).connect("127.0.0.1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("clientLog.length") == 2 })
            #expect(harness.evalString("clientLog.join('|')") == "1:echo:hello\n|2:echo:world\n")
            #expect(harness.evalString("serverLog.map(e => e.tag + e.text).join('|')") == "7hello\n|7world\n")
            #expect(harness.evalBool("serverLog.every(e => e.isBytes)") == true)
            #expect(harness.evalBool("client.isConnected") == true)
            #expect(harness.evalString("client.remoteHost") == "127.0.0.1")
            #expect(harness.evalInt("client.remotePort") == port)
            #expect(harness.evalBool("client.localPort > 0") == true)
            #expect(harness.evalInt("server.clients.length") == 1)
            #expect(!harness.hasException)
        }

        @Test("readBytes and readAvailable read exact and whatever-is-there amounts")
        func testLengthAndAvailableReads() async throws {
            let harness = makeHarness()
            harness.eval("""
                var received = [];
                var server = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "connection") data.writeBytes(new Uint8Array([1, 2, 3, 4, 5, 6]));
                }).listen(0);
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("server.localPort") ?? 0 > 0 })
            let port = try #require(harness.evalInt("server.localPort"))
            harness.eval("""
                var client = hs.socket.create().setCallback((event, sock, data, tag) => {
                    if (event === "data") received.push(tag + ":" + Array.from(data).join(","));
                }).readBytes(2, 1).readAvailable(2).connect("127.0.0.1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("received.length") == 2 })
            // The first read takes exactly 2 bytes; the second takes everything else that has
            // arrived, which may not yet be all of it
            #expect(harness.evalString("received[0]") == "1:1,2")
            harness.expectTrue("received[1].startsWith('2:3')")
            #expect(!harness.hasException)
        }

        @Test("Closing the server end delivers disconnected to the client")
        func testPeerDisconnect() async throws {
            let harness = makeHarness()
            harness.eval("""
                var events = [];
                var server = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "connection") data.write("bye\\n").disconnect();
                }).listen(0);
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("server.localPort") ?? 0 > 0 })
            let port = try #require(harness.evalInt("server.localPort"))
            harness.eval("""
                var client = hs.socket.create().setCallback((event, sock, data) => {
                    events.push(event === "data" ? hs.socket.decodeText(data) : event);
                }).readUntil("\\n").connect("127.0.0.1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalBool("events.includes('disconnected')") == true })
            #expect(harness.evalString("events.join('|')") == "connected|bye\n|disconnected")
            #expect(harness.evalBool("client.isConnected") == false)
            #expect(!harness.hasException)
        }

        @Test("An accepted socket reconnected from the listener's disconnected callback keeps its new connection")
        func testReconnectedClientSurvivesListenerTeardown() async throws {
            let harness = makeHarness()
            let port = try #require(await startServer(harness))
            harness.eval("""
                var accepted = null;
                var acceptedEvents = [];
                var listener = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "connection") {
                        accepted = data;
                        accepted.setCallback((e) => acceptedEvents.push(e));
                    }
                    if (event === "disconnected" && accepted) {
                        accepted.disconnect();
                        accepted.connect("127.0.0.1", \(port));
                    }
                }).listen(0);
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("listener.localPort") ?? 0 > 0 })
            let listenerPort = try #require(harness.evalInt("listener.localPort"))
            harness.eval("var client = hs.socket.create().connect('127.0.0.1', \(listenerPort))")
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalBool("accepted !== null && accepted.isConnected") == true })

            harness.eval("listener.disconnect()")
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalBool("acceptedEvents.includes('connected')") == true })
            #expect(harness.evalBool("accepted.isConnected") == true)
            #expect(harness.evalInt("accepted.remotePort") == port)
            #expect(!harness.hasException)
        }

        @Test("A refused connection reports an error, then disconnected")
        func testConnectionRefused() async throws {
            let harness = makeHarness()
            // Find a free port by listening on it, then stop listening
            harness.eval("var probe = hs.socket.create().listen(0)")
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("probe.localPort") ?? 0 > 0 })
            let port = try #require(harness.evalInt("probe.localPort"))
            harness.eval("probe.disconnect()")

            harness.eval("""
                var events = [];
                var client = hs.socket.create().setCallback((event, sock, data) => {
                    events.push(event);
                }).connect("127.0.0.1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalBool("events.includes('disconnected')") == true })
            #expect(harness.evalString("events.join('|')") == "error|disconnected")
            #expect(!harness.hasException)
        }

        @Test("A read times out when no data arrives")
        func testReadTimeout() async throws {
            let harness = makeHarness()
            let port = try #require(await startServer(harness))
            harness.eval("""
                var events = [];
                var client = hs.socket.create().setCallback((event, sock, data) => {
                    events.push(event === "error" ? data : event);
                });
                client.timeout = 0.1;
                client.readUntil("never").connect("127.0.0.1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalBool("events.includes('disconnected')") == true })
            #expect(harness.evalString("events.join('|')") == "connected|Read timed out|disconnected")
        }

        @Test("A client and server exchange data over a Unix domain socket")
        func testUnixRoundTrip() async {
            let harness = makeHarness()
            let path = temporarySocketPath()
            harness.eval("""
                var log = [];
                var server = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "listening") log.push("listening");
                    if (event === "connection") data.readUntil("\\n");
                    if (event === "data") sock.write("got " + hs.socket.decodeText(data));
                }).listenUnix("\(path)");
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalBool("log.includes('listening')") == true })
            #expect(FileManager.default.fileExists(atPath: path))
            #expect(harness.evalString("server.unixPath") == path)

            harness.eval("""
                var client = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "connected") sock.write("ping\\n").readUntil("\\n");
                    if (event === "data") log.push(hs.socket.decodeText(data));
                }).connectUnix("\(path)");
            """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("log.length") == 2 })
            #expect(harness.evalString("log[1]") == "got ping\n")
            #expect(harness.evalString("client.unixPath") == path)

            // A second listener mustn't take over a path something is still listening on
            harness.eval("""
                var secondErrors = [];
                var second = hs.socket.create().setCallback((event, sock, data) => {
                    if (event === "error") secondErrors.push(data);
                }).listenUnix("\(path)");
            """)
            #expect(harness.evalInt("secondErrors.length") == 1)
            #expect(harness.evalBool("second.isListening") == false)
            #expect(FileManager.default.fileExists(atPath: path))

            harness.eval("server.disconnect()")
            #expect(!FileManager.default.fileExists(atPath: path))
            #expect(!harness.hasException)
        }

        @Test("Invalid arguments report errors without throwing")
        func testInvalidArguments() {
            let harness = makeHarness()
            harness.eval("""
                var errors = [];
                var s = hs.socket.create().setCallback((event, sock, data) => { if (event === "error") errors.push(data); });
                s.connect("127.0.0.1", 0);
                s.connect("", 80);
                s.write("not connected");
                s.writeBytes("not bytes");
                s.listen(70000);
            """)
            #expect(harness.evalInt("errors.length") == 5)
            #expect(harness.evalBool("s.isConnected || s.isListening") == false)
            #expect(!harness.hasException)
        }
    }

    // MARK: - UDP sockets

    @MainActor
    @Suite("hs.socket UDP tests", .serialized)
    struct HSSocketUDPTests {

        @Test("Datagrams sent to a bound socket arrive with the sender's address")
        func testUDPRoundTrip() async throws {
            let harness = makeHarness()
            harness.eval("""
                var received = [];
                var receiver = hs.socket.createUDP().setCallback((event, sock, data, address) => {
                    if (event === "data") received.push({text: hs.socket.decodeText(data), address: address, isBytes: data instanceof Uint8Array});
                }).bind(0).receive();
                var sender = hs.socket.createUDP();
            """)
            let port = try #require(harness.evalInt("receiver.localPort"))
            #expect(port > 0)
            #expect(harness.evalBool("receiver.isBound && receiver.isReceiving") == true)

            harness.eval("""
                sender.send("one", "127.0.0.1", \(port));
                sender.sendBytes(new Uint8Array([116, 119, 111]), "::1", \(port));
            """)
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("received.length") == 2 })
            #expect(harness.evalString("received.map(r => r.text).sort().join('|')") == "one|two")
            #expect(harness.evalBool("received.every(r => r.isBytes)") == true)
            let v4 = "received.find(r => r.text === 'one').address"
            #expect(harness.evalString("\(v4).host") == "127.0.0.1")
            #expect(harness.evalString("\(v4).family") == "ipv4")
            #expect(harness.evalBool("\(v4).port > 0") == true)
            #expect(harness.evalString("received.find(r => r.text === 'two').address.family") == "ipv6")
            #expect(!harness.hasException)
        }

        @Test("A connected socket sends without an address, and receiveOne stops after one datagram")
        func testConnectedAndReceiveOne() async throws {
            let harness = makeHarness()
            harness.eval("""
                var events = [];
                var received = [];
                var receiver = hs.socket.createUDP().setCallback((event, sock, data) => {
                    if (event === "data") received.push(hs.socket.decodeText(data));
                }).bind(0).receiveOne();
                var sender = hs.socket.createUDP().setCallback((event, sock, data, address) => {
                    events.push(event === "error" ? "error:" + data : event + ":" + address.port);
                });
            """)
            let port = try #require(harness.evalInt("receiver.localPort"))
            harness.eval("sender.connect('127.0.0.1', \(port)).send('first').send('second')")
            #expect(harness.evalString("events.join('|')") == "connected:\(port)")
            #expect(harness.evalBool("sender.isConnected") == true)

            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("received.length") == 1 })
            #expect(harness.evalBool("receiver.isReceiving") == false)
            try await Task.sleep(for: .milliseconds(100))
            #expect(harness.evalString("received.join('|')") == "first")

            // The second datagram was queued by the system meanwhile
            harness.eval("receiver.receiveOne()")
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("received.length") == 2 })
            #expect(harness.evalString("received[1]") == "second")
            #expect(!harness.hasException)
        }

        @Test("A socket can receive replies on the port it sent from")
        func testReceiveAfterSend() async throws {
            let harness = makeHarness()
            harness.eval("""
                var replies = [];
                var server = hs.socket.createUDP().setCallback((event, sock, data, address) => {
                    if (event === "data") sock.send("pong", address.host, address.port);
                }).bind(0).receive();
                var client = hs.socket.createUDP().setCallback((event, sock, data) => {
                    if (event === "data") replies.push(hs.socket.decodeText(data));
                });
            """)
            let port = try #require(harness.evalInt("server.localPort"))
            harness.eval("client.send('ping', '127.0.0.1', \(port)).receive()")
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("replies.length") == 1 })
            #expect(harness.evalString("replies[0]") == "pong")
            #expect(!harness.hasException)
        }

        @Test("Receiving without a local port, or sending without an address, reports errors")
        func testUDPErrors() {
            let harness = makeHarness()
            harness.eval("""
                var errors = [];
                var u = hs.socket.createUDP().setCallback((event, sock, data) => { if (event === "error") errors.push(data); });
                u.receive();
                u.send("nowhere");
                u.sendBytes("not bytes", "127.0.0.1", 9);
                u.bind(-1);
            """)
            #expect(harness.evalInt("errors.length") == 4)
            #expect(harness.evalBool("u.isReceiving") == false)
            #expect(!harness.hasException)
        }

        @Test("close() lets the socket bind again")
        func testCloseAndRebind() {
            let harness = makeHarness()
            harness.eval("var u = hs.socket.createUDP().bind(0).receive()")
            #expect(harness.evalBool("u.isBound") == true)
            harness.eval("u.close()")
            #expect(harness.evalBool("u.isBound || u.isReceiving") == false)
            #expect(harness.evalInt("u.localPort") == 0)
            harness.eval("u.bind(0)")
            #expect(harness.evalBool("u.isBound") == true)
            #expect(!harness.hasException)
        }

        @Test("A closed socket's port is free as soon as close() returns")
        func testPortFreedOnClose() {
            let harness = makeHarness()
            harness.eval("""
                var errors = [];
                var u = hs.socket.createUDP().setCallback((event, sock, data) => { if (event === "error") errors.push(data); }).bind(0).receive();
                var port = u.localPort;
                u.close();
                u.bind(port);
            """)
            #expect(harness.evalString("errors.join('|')") == "")
            #expect(harness.evalBool("u.isBound && u.localPort === port") == true)
            #expect(!harness.hasException)
        }

        @Test("A send from a hostname connection's callback doesn't repeat the connection")
        func testHostnameConnectRunsOnce() async throws {
            let harness = makeHarness()
            harness.eval("""
                var received = [];
                var connects = 0;
                var receiver = hs.socket.createUDP().setCallback((event, sock, data) => {
                    if (event === "data") received.push(hs.socket.decodeText(data));
                }).bind(0).receive();
                var sender = hs.socket.createUDP().setCallback((event, sock) => {
                    if (event === "connected") { connects++; sock.send("hello"); }
                });
            """)
            let port = try #require(harness.evalInt("receiver.localPort"))
            harness.eval("sender.connect('localhost', \(port))")
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("received.length") == 1 })
            try await Task.sleep(for: .milliseconds(200))
            #expect(harness.evalInt("connects") == 1)
            #expect(harness.evalInt("received.length") == 1)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Object lifetime

    @MainActor
    @Suite("hs.socket object lifetime tests", .serialized)
    struct HSSocketLifetimeTests {

        @Test("A listening socket the caller didn't keep still accepts connections after garbage collection")
        func testUnreferencedListenerSurvivesGC() async throws {
            let harness = makeHarness()
            harness.eval("var accepted = 0; var port = 0;")
            autoreleasepool {
                _ = harness.eval("""
                    void hs.socket.create().setCallback((event, sock) => {
                        if (event === "listening") port = sock.localPort;
                        if (event === "connection") accepted++;
                    }).listen(0)
                """)
            }
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("port") ?? 0 > 0 })
            harness.collectGarbage()
            let port = try #require(harness.evalInt("port"))
            harness.eval("var client = hs.socket.create().connect('127.0.0.1', \(port))")
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("accepted") == 1 })
        }

        @Test("A disconnected socket the caller didn't keep is garbage collected")
        func testDisconnectedSocketIsCollected() {
            let harness = makeHarness()
            weak var socket: HSSocket?
            autoreleasepool {
                harness.eval("var s = hs.socket.create().listen(0)")
                socket = harness.evalValue("s")?.toObjectOf(HSSocket.self) as? HSSocket
                harness.eval("s.disconnect(); s = null")
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            harness.collectGarbage()
            #expect(socket == nil)
        }

        @Test("A receiving UDP socket the caller didn't keep still delivers datagrams after garbage collection")
        func testUnreferencedUDPReceiverSurvivesGC() async throws {
            let harness = makeHarness()
            harness.eval("var received = 0; var port = 0;")
            autoreleasepool {
                _ = harness.eval("""
                    void (port = hs.socket.createUDP().setCallback((event) => {
                        if (event === "data") received++;
                    }).bind(0).receive().localPort)
                """)
            }
            harness.collectGarbage()
            let port = try #require(harness.evalInt("port"))
            harness.eval("hs.socket.createUDP().send('hi', '127.0.0.1', \(port))")
            #expect(await harness.waitForAsync(timeout: 2) { harness.evalInt("received") == 1 })
        }

        @Test("A closed UDP socket the caller didn't keep is garbage collected")
        func testClosedUDPSocketIsCollected() {
            let harness = makeHarness()
            weak var socket: HSUDPSocket?
            autoreleasepool {
                harness.eval("var u = hs.socket.createUDP().bind(0).receive()")
                socket = harness.evalValue("u")?.toObjectOf(HSUDPSocket.self) as? HSUDPSocket
                harness.eval("u.close(); u = null")
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            harness.collectGarbage()
            #expect(socket == nil)
        }

        @Test("Connecting, listening and receiving sockets are released after shutdown")
        func testSocketsDoNotLeakAfterReload() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = makeHarness()
                // All three are active as soon as these calls return, without waiting for events
                harness.eval("""
                    var server = hs.socket.create().setCallback(() => {}).listen(0);
                    var client = hs.socket.create().setCallback(() => {}).readUntil("\\n").connect("127.0.0.1", 9);
                    var udp = hs.socket.createUDP().setCallback(() => {}).bind(0).receive();
                """)
                for name in ["server", "client"] {
                    if let socket = harness.evalValue(name)?.toObjectOf(HSSocket.self) as? HSSocket {
                        tracker.track(socket)
                    }
                }
                if let udp = harness.evalValue("udp")?.toObjectOf(HSUDPSocket.self) as? HSUDPSocket {
                    tracker.track(udp)
                }
                harness.eval("server = null; client = null; udp = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
