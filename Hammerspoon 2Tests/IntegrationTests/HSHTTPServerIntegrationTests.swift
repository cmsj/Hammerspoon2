//
//  HSHTTPServerIntegrationTests.swift
//  Hammerspoon 2Tests
//
// These tests exercise hs.httpserver via the JSTestHarness. The cross-module tests
// start a real local server and use hs.http to make requests to it — no external
// network access is required.

import Testing
import JavaScriptCore
import Network
@testable import Hammerspoon_2

@Suite("hs.http/hs.httpserver tests", .serialized)
struct HSHTTPTests {

    // MARK: - API structure

    @Suite("hs.httpserver API structure tests")
    struct HSHTTPServerStructureTests {

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPServerModule.self, as: "httpserver")
            return h
        }

        @Test("create is a function")
        func testCreateIsFunction() {
            makeHarness().expectTrue("typeof hs.httpserver.create === 'function'")
        }

        @Test("create returns an object")
        func testCreateReturnsObject() {
            makeHarness().expectTrue("typeof hs.httpserver.create() === 'object'")
        }

        @Test("server has identifier")
        func testServerHasIdentifier() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.identifier === 'string'")
            h.expectTrue("s.identifier.length > 0")
            #expect(!h.hasException)
        }

        @Test("two servers have different identifiers")
        func testUniqueIdentifiers() {
            let h = makeHarness()
            h.expectTrue("hs.httpserver.create().identifier !== hs.httpserver.create().identifier")
            #expect(!h.hasException)
        }

        @Test("server has setPort function")
        func testSetPortIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.setPort === 'function'")
        }

        @Test("server has setCallback function")
        func testSetCallbackIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.setCallback === 'function'")
        }

        @Test("server has setDocumentRoot function")
        func testSetDocumentRootIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.setDocumentRoot === 'function'")
        }

        @Test("server has start function")
        func testStartIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.start === 'function'")
        }

        @Test("server has stop function")
        func testStopIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.stop === 'function'")
        }

        @Test("server has getPort function")
        func testGetPortIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.getPort === 'function'")
        }

        @Test("setters return the server for chaining")
        func testChainingReturnsServer() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("s.setPort(0) === s")
            h.expectTrue("s.setName('test') === s")
            h.expectTrue("s.setMaxBodySize(1024) === s")
            h.expectTrue("s.setBonjour(false) === s")
            #expect(!h.hasException)
        }

        @Test("server has setWebSocketCallback function")
        func testSetWebSocketCallbackIsFunction() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("typeof s.setWebSocketCallback === 'function'")
        }

        @Test("setWebSocketCallback returns server for chaining")
        func testSetWebSocketCallbackChaining() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("s.setWebSocketCallback('/ws', null) === s")
            #expect(!h.hasException)
        }
    }

    // MARK: - Server lifecycle

    @Suite("hs.httpserver lifecycle tests", .serialized)
    struct HSHTTPServerLifecycleTests {

        init() async {
            await JSTestHarness.drainMainActorQueue()
        }

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPServerModule.self, as: "httpserver")
            return h
        }

        @Test("server reports port 0 before starting")
        func testPortBeforeStart() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create().setPort(0)")
            h.expectEqual("s.getPort()", 0)
            #expect(!h.hasException)
        }

        @Test("server reports a non-zero port after starting on port 0")
        func testPortAfterStart() async {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create().setPort(0).start()")

            // Wait for the listener to become ready
            let ok = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("s.getPort()") as? Int ?? 0
                return port > 0
            }
            h.eval("s.stop()")

            #expect(ok, "Server should report a non-zero port after start")
        }

        @Test("stop is safe to call when not running")
        func testStopWhenNotRunning() {
            let h = makeHarness()
            h.eval("hs.httpserver.create().stop()")
            #expect(!h.hasException)
        }

        @Test("server can be started and stopped multiple times")
        func testStartStopRepeat() async {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create().setPort(0)")

            for _ in 0..<3 {
                h.eval("s.start()")
                let ok = await h.waitForAsync(timeout: 1.0) {
                    let port = h.eval("s.getPort()") as? Int ?? 0
                    return port > 0
                }
                #expect(ok)
                h.eval("s.stop()")
                // Allow listener to fully cancel
                try? await Task.sleep(for: .milliseconds(50))
            }
            #expect(!h.hasException)
        }

        @Test("getName returns configured name")
        func testGetName() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create().setName('TestServer')")
            h.expectEqual("s.getName()", "TestServer")
            #expect(!h.hasException)
        }

        @Test("getInterface returns null when not configured")
        func testGetInterfaceDefault() {
            let h = makeHarness()
            h.eval("var s = hs.httpserver.create()")
            h.expectTrue("s.getInterface() === null || s.getInterface() === undefined")
            #expect(!h.hasException)
        }
    }

    // MARK: - WebSocket frame parsing (pure Swift)

    @Suite("WebSocket frame parsing tests")
    struct WebSocketFrameParsingTests {

        @Test("parseNextFrame returns nil for empty buffer")
        func testEmptyBuffer() {
            let result = HSWebSocketConnection.parseNextFrame(from: Data())
            #expect(result == nil)
        }

        @Test("parseNextFrame parses a minimal unmasked text frame")
        func testSmallTextFrame() {
            // FIN=1 opcode=1, MASK=0 length=5, payload "Hello"
            var data = Data([0x81, 0x05])
            data.append(contentsOf: "Hello".utf8)
            let result = HSWebSocketConnection.parseNextFrame(from: data)
            #expect(result != nil)
            #expect(result?.frame.opcode == 0x01)
            #expect(result?.frame.isFinal == true)
            #expect(result?.consumed == 7)
            let text = String(data: result!.frame.payload, encoding: .utf8)
            #expect(text == "Hello")
        }

        @Test("parseNextFrame parses a masked client frame")
        func testMaskedFrame() {
            // FIN=1 opcode=1, MASK=1 length=4, mask=[0x01,0x02,0x03,0x04], payload "test" XOR mask
            let mask: [UInt8] = [0x01, 0x02, 0x03, 0x04]
            let plain: [UInt8] = Array("test".utf8)
            let masked = plain.enumerated().map { $0.element ^ mask[$0.offset % 4] }
            var data = Data([0x81, 0x80 | 0x04])
            data.append(contentsOf: mask)
            data.append(contentsOf: masked)
            let result = HSWebSocketConnection.parseNextFrame(from: data)
            #expect(result != nil)
            #expect(result?.frame.isFinal == true)
            let text = String(data: result!.frame.payload, encoding: .utf8)
            #expect(text == "test")
        }

        @Test("parseNextFrame reports FIN=0 for a continuation/first fragment frame")
        func testFragmentFrame() {
            // FIN=0 opcode=1 (first text fragment), MASK=0 length=5, payload "Hello"
            var data = Data([0x01, 0x05])   // byte0: FIN=0, opcode=1
            data.append(contentsOf: "Hello".utf8)
            let result = HSWebSocketConnection.parseNextFrame(from: data)
            #expect(result != nil)
            #expect(result?.frame.opcode == 0x01)
            #expect(result?.frame.isFinal == false)
            let text = String(data: result!.frame.payload, encoding: .utf8)
            #expect(text == "Hello")
        }

        @Test("parseNextFrame returns nil when buffer is incomplete")
        func testIncompleteFrame() {
            // Claims length=10 but only 3 payload bytes present
            var data = Data([0x81, 0x0A])
            data.append(contentsOf: [0x01, 0x02, 0x03])
            let result = HSWebSocketConnection.parseNextFrame(from: data)
            #expect(result == nil)
        }

        @Test("buildFrame produces correct FIN+opcode byte")
        func testBuildFrameHeader() {
            let frame = HSWebSocketConnection.buildFrame(opcode: 0x01, payload: Data("hi".utf8))
            #expect(frame[0] == 0x81)   // FIN=1, opcode=1
            #expect(frame[1] == 0x02)   // MASK=0, length=2
        }

        @Test("webSocketAcceptKey produces correct RFC 6455 value")
        func testAcceptKey() {
            // RFC 6455 §1.3 example: key "dGhlIHNhbXBsZSBub25jZQ==" → "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            let key = "dGhlIHNhbXBsZSBub25jZQ=="
            let accept = HSWebSocketConnection.webSocketAcceptKey(for: key)
            #expect(accept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
        }
    }

    // MARK: - Integration: hs.http client ↔ hs.httpserver

    // These tests start a real local TCP server and verify end-to-end request/response.

    @Suite("hs.http + hs.httpserver integration tests", .serialized)
    struct HSHTTPServerIntegrationTests {

        init() async {
            await JSTestHarness.drainMainActorQueue()
        }

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPServerModule.self, as: "httpserver")
            h.loadModule(HSHTTPModule.self, as: "http")
            return h
        }

        @Test("simple GET request is handled by callback")
        func testSimpleGET() async {
            let h = makeHarness()

            // Start server on a random port with a simple callback
            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setCallback((method, path, headers, body) => {
                    return {body: "Hello from Hammerspoon", status: 200, headers: {"Content-Type": "text/plain"}}
                })
                .start()
        """)

            // Wait for port assignment
            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            #expect(portReady, "Server should be ready")
            guard portReady else { h.eval("server.stop()"); return }

            var gotResponse = false
            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/").then(r => {
                __test_callback(r.status === 200 && r.body === "Hello from Hammerspoon" ? 'ok' : 'fail')
            })
        """)
            h.registerCallback("ok") { gotResponse = true }

            let ok = await h.waitForAsync(timeout: 3.0) { gotResponse }
            h.eval("server.stop()")
            #expect(ok, "Should receive a 200 response from the local server")
        }

        @Test("POST body is delivered to callback")
        func testPOSTBody() async {
            let h = makeHarness()
            var bodyReceived = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setCallback((method, path, headers, body) => {
                    if (body === 'test-payload') __test_callback('gotbody')
                    return {body: "ok", status: 200, headers: {}}
                })
                .start()
        """)
            h.registerCallback("gotbody") { bodyReceived = true }

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.post("http://localhost:" + server.getPort() + "/", "test-payload", null)
        """)

            let ok = await h.waitForAsync(timeout: 3.0) { bodyReceived }
            h.eval("server.stop()")
            #expect(ok, "Server callback should receive the POST body")
        }

        @Test("request method is delivered correctly")
        func testRequestMethod() async {
            let h = makeHarness()
            var sawDelete = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setCallback((method, path, headers, body) => {
                    if (method === 'DELETE') __test_callback('deleteok')
                    return {body: "ok", status: 200, headers: {}}
                })
                .start()
        """)
            h.registerCallback("deleteok") { sawDelete = true }

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("hs.http.doRequest('http://localhost:' + server.getPort() + '/', 'DELETE', null, null)")
            let ok = await h.waitForAsync(timeout: 3.0) { sawDelete }
            h.eval("server.stop()")
            #expect(ok)
        }

        @Test("server returns 401 when password is set and auth header is missing")
        func testBasicAuthRequired() async {
            let h = makeHarness()
            var got401 = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setPassword("secret")
                .setCallback((method, path, headers, body) => {
                    return {body: "private", status: 200, headers: {}}
                })
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/").then(r => {
                if (r.status === 401) __test_callback('auth401')
            })
        """)
            h.registerCallback("auth401") { got401 = true }

            let ok = await h.waitForAsync(timeout: 3.0) { got401 }
            h.eval("server.stop()")
            #expect(ok, "Server should reject unauthenticated request with 401")
        }

        @Test("server accepts request with correct Basic auth password")
        func testBasicAuthSuccess() async {
            let h = makeHarness()
            var got200 = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setPassword("mysecret")
                .setCallback((method, path, headers, body) => {
                    return {body: "ok", status: 200, headers: {}}
                })
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            // btoa("user:mysecret") = "dXNlcjpteXNlY3JldA=="
            h.eval("""
            hs.http.get(
                "http://localhost:" + server.getPort() + "/",
                {"Authorization": "Basic dXNlcjpteXNlY3JldA=="}
            ).then(r => {
                if (r.status === 200) __test_callback('auth200')
            })
        """)
            h.registerCallback("auth200") { got200 = true }

            let ok = await h.waitForAsync(timeout: 3.0) { got200 }
            h.eval("server.stop()")
            #expect(ok, "Server should accept correctly authenticated request")
        }

        @Test("callback returning null produces 404")
        func testCallbackNullGives404() async {
            let h = makeHarness()
            var got404 = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setCallback((method, path, headers, body) => null)
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/").then(r => {
                if (r.status === 404) __test_callback('got404')
            })
        """)
            h.registerCallback("got404") { got404 = true }

            let ok = await h.waitForAsync(timeout: 3.0) { got404 }
            h.eval("server.stop()")
            #expect(ok)
        }

        @Test("async Promise-returning callback is handled correctly")
        func testAsyncCallback() async {
            let h = makeHarness()
            var gotAsyncResponse = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setCallback((method, path, headers, body) => {
                    return new Promise(resolve => {
                        resolve({body: "async-ok", status: 200, headers: {}})
                    })
                })
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/").then(r => {
                if (r.status === 200 && r.body === "async-ok") __test_callback('asyncok')
            })
        """)
            h.registerCallback("asyncok") { gotAsyncResponse = true }

            let ok = await h.waitForAsync(timeout: 3.0) { gotAsyncResponse }
            h.eval("server.stop()")
            #expect(ok, "Server should handle Promise-returning callbacks")
        }

        @Test("callback returning null falls through to static file serving")
        func testCallbackNullFallsThroughToStaticFile() async throws {
            let h = makeHarness()
            var gotStaticFile = false

            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            try "static-content".write(to: tmpDir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setDocumentRoot("\(tmpDir.path)")
                .setCallback((method, path, headers, body) => null)
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/hello.txt").then(r => {
                if (r.status === 200 && r.body === "static-content") __test_callback('gotfile')
            })
        """)
            h.registerCallback("gotfile") { gotStaticFile = true }

            let ok = await h.waitForAsync(timeout: 3.0) { gotStaticFile }
            h.eval("server.stop()")
            #expect(ok, "Callback returning null should fall through to static file serving")
        }

        @Test("async callback resolving to null falls through to static file serving")
        func testAsyncCallbackNullFallsThroughToStaticFile() async throws {
            let h = makeHarness()
            var gotStaticFile = false

            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            try "async-static".write(to: tmpDir.appendingPathComponent("page.txt"), atomically: true, encoding: .utf8)

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setDocumentRoot("\(tmpDir.path)")
                .setCallback((method, path, headers, body) => new Promise(resolve => resolve(null)))
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            hs.http.get("http://localhost:" + server.getPort() + "/page.txt").then(r => {
                if (r.status === 200 && r.body === "async-static") __test_callback('gotfile')
            })
        """)
            h.registerCallback("gotfile") { gotStaticFile = true }

            let ok = await h.waitForAsync(timeout: 3.0) { gotStaticFile }
            h.eval("server.stop()")
            #expect(ok, "Promise-returning callback resolving to null should fall through to static file serving")
        }

        @Test("WebSocket client and server exchange messages end-to-end")
        func testWebSocketEcho() async {
            let h = makeHarness()
            var gotEcho = false

            // Start a server that echoes any WebSocket message back with "echo: " prefix.
            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setWebSocketCallback('/ws', (event, conn, msg) => {
                    if (event === 'message') conn.send('echo: ' + msg)
                })
                .start()
        """)

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            #expect(portReady, "Server should start and assign a port")
            guard portReady else { h.eval("server.stop()"); return }

            // Connect a WebSocket client; send "hello" when open; expect "echo: hello" back.
            h.eval("""
            var ws = hs.http.openWebSocket('ws://localhost:' + server.getPort() + '/ws')
                .setOpenCallback(() => { ws.send('hello') })
                .setMessageCallback(msg => {
                    if (msg === 'echo: hello') __test_callback('gotecho')
                })
        """)
            h.registerCallback("gotecho") { gotEcho = true }

            let ok = await h.waitForAsync(timeout: 5.0) { gotEcho }
            h.eval("ws.close(); server.stop()")
            #expect(ok, "WebSocket client should receive echoed message from server")
        }

        @Test("server reassembles WebSocket message sent as two fragments")
    func testWebSocketFragmentedMessage() async {
        let h = makeHarness()
        var gotFragmented = false

        h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setWebSocketCallback('/ws', (event, conn, msg) => {
                    if (event === 'message' && msg === 'Hello, World!') __test_callback('gotfragmented')
                })
                .start()
        """)
        h.registerCallback("gotfragmented") { gotFragmented = true }

        let portReady = await h.waitForAsync(timeout: 2.0) {
            (h.eval("server.getPort()") as? Int ?? 0) > 0
        }
        guard portReady else { h.eval("server.stop()"); return }
        let port = h.eval("server.getPort()") as? Int ?? 0

        // Open a raw TCP connection and perform the WebSocket handshake manually so we can
        // send frames with FIN=0 — URLSessionWebSocketTask always sends FIN=1 and can't be used.
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        var connState: NWConnection.State = .setup
        conn.stateUpdateHandler = { state in MainActor.assumeIsolated { connState = state } }
        conn.start(queue: .main)

        let tcpReady = await h.waitForAsync(timeout: 2.0) {
            if case .ready = connState { return true }; return false
        }
        guard tcpReady else { conn.cancel(); h.eval("server.stop()"); return }

        let upgradeRequest = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdGtleWhlcmU=\r\nSec-WebSocket-Version: 13\r\n\r\n"
        conn.send(content: Data(upgradeRequest.utf8), completion: .idempotent)

        var httpResponse = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
            MainActor.assumeIsolated { if let data { httpResponse.append(data) } }
        }
        let got101 = await h.waitForAsync(timeout: 2.0) {
            String(data: httpResponse, encoding: .utf8)?.contains("101") == true
        }
        guard got101 else { conn.cancel(); h.eval("server.stop()"); return }

        // Build masked frames: FIN=0 text "Hello, " then FIN=1 continuation "World!".
        func maskedFrame(opcode: UInt8, fin: Bool, text: String) -> Data {
            let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
            let payload = Array(text.utf8)
            var frame = Data([UInt8((fin ? 0x80 : 0x00) | Int(opcode & 0x0F)), UInt8(0x80 | payload.count)])
            frame.append(contentsOf: mask)
            frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
            return frame
        }
        var fragmented = maskedFrame(opcode: 0x01, fin: false, text: "Hello, ")
        fragmented.append(maskedFrame(opcode: 0x00, fin: true, text: "World!"))
        conn.send(content: fragmented, completion: .idempotent)

        let ok = await h.waitForAsync(timeout: 3.0) { gotFragmented }
        conn.cancel()
        h.eval("server.stop()")
        #expect(ok, "Server should reassemble two fragments into 'Hello, World!'")
    }

    @Test("oversized single WebSocket frame closes connection with 1009")
    func testWebSocketFrameBufferLimitClosesWith1009() async {
        let h = makeHarness()

        // maxBodySize=64; a 100-byte-payload frame is ~106 bytes on the wire, exceeding the limit.
        h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setMaxBodySize(64)
                .setWebSocketCallback('/ws', (event, conn, msg) => {})
                .start()
        """)

        let portReady = await h.waitForAsync(timeout: 2.0) {
            (h.eval("server.getPort()") as? Int ?? 0) > 0
        }
        guard portReady else { h.eval("server.stop()"); return }
        let port = h.eval("server.getPort()") as? Int ?? 0

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        var connState: NWConnection.State = .setup
        conn.stateUpdateHandler = { state in MainActor.assumeIsolated { connState = state } }
        conn.start(queue: .main)
        let tcpReady = await h.waitForAsync(timeout: 2.0) {
            if case .ready = connState { return true }; return false
        }
        guard tcpReady else { conn.cancel(); h.eval("server.stop()"); return }

        let upgradeRequest = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdGtleWhlcmU=\r\nSec-WebSocket-Version: 13\r\n\r\n"
        var httpResponse = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
            MainActor.assumeIsolated { if let data { httpResponse.append(data) } }
        }
        conn.send(content: Data(upgradeRequest.utf8), completion: .idempotent)
        let got101 = await h.waitForAsync(timeout: 2.0) {
            String(data: httpResponse, encoding: .utf8)?.contains("101") == true
        }
        guard got101 else { conn.cancel(); h.eval("server.stop()"); return }

        // Build and send a masked frame with a 100-byte payload (well over maxBodySize 64).
        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        var frame = Data([0x81, UInt8(0x80 | 100)])  // FIN=1, text, MASK=1, length=100
        frame.append(contentsOf: mask)
        frame.append(contentsOf: (0..<100).map { UInt8(0x41) ^ mask[$0 % 4] })

        var serverResponse = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
            MainActor.assumeIsolated { if let data { serverResponse.append(data) } }
        }
        conn.send(content: frame, completion: .idempotent)

        let ok = await h.waitForAsync(timeout: 3.0) {
            serverResponse.count >= 4 &&
            serverResponse[0] == 0x88 && serverResponse[1] == 0x02 &&
            serverResponse[2] == 0x03 && serverResponse[3] == 0xF1
        }
        conn.cancel()
        h.eval("server.stop()")
        #expect(ok, "Server should close with code 1009 when frame buffer exceeds maxBodySize")
    }

    @Test("oversized fragmented WebSocket message closes connection with 1009")
    func testWebSocketFragmentBufferLimitClosesWith1009() async {
        let h = makeHarness()

        // maxBodySize=200; each individual frame is ~156 or ~106 bytes (both under the limit),
        // but their combined payload (250 bytes) exceeds it, triggering the fragmentBuffer check.
        h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setMaxBodySize(200)
                .setWebSocketCallback('/ws', (event, conn, msg) => {})
                .start()
        """)

        let portReady = await h.waitForAsync(timeout: 2.0) {
            (h.eval("server.getPort()") as? Int ?? 0) > 0
        }
        guard portReady else { h.eval("server.stop()"); return }
        let port = h.eval("server.getPort()") as? Int ?? 0

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        var connState: NWConnection.State = .setup
        conn.stateUpdateHandler = { state in MainActor.assumeIsolated { connState = state } }
        conn.start(queue: .main)
        let tcpReady = await h.waitForAsync(timeout: 2.0) {
            if case .ready = connState { return true }; return false
        }
        guard tcpReady else { conn.cancel(); h.eval("server.stop()"); return }

        let upgradeRequest = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdGtleWhlcmU=\r\nSec-WebSocket-Version: 13\r\n\r\n"
        var httpResponse = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
            MainActor.assumeIsolated { if let data { httpResponse.append(data) } }
        }
        conn.send(content: Data(upgradeRequest.utf8), completion: .idempotent)
        let got101 = await h.waitForAsync(timeout: 2.0) {
            String(data: httpResponse, encoding: .utf8)?.contains("101") == true
        }
        guard got101 else { conn.cancel(); h.eval("server.stop()"); return }

        // Build two masked frames: FIN=0 with 150-byte payload, then FIN=0 continuation with
        // 100-byte payload. Each frame is under maxBodySize (200) individually, but the combined
        // fragment payload (250) exceeds it. Sent via .contentProcessed to ensure they arrive
        // in separate TCP receives so the fragmentBuffer check fires rather than the buf check.
        // Frame wire sizes: ~158 bytes (2-byte header + 2-byte extended length + 4-byte mask + 150)
        // and ~106 bytes (2-byte header + 4-byte mask + 100) — both under maxBodySize (200).
        func maskedFrame(opcode: UInt8, fin: Bool, size: Int) -> Data {
            let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
            var f = Data()
            f.append(UInt8((fin ? 0x80 : 0x00) | (opcode & 0x0F)))
            // RFC 6455: payloads >= 126 require extended 16-bit length encoding.
            if size < 126 {
                f.append(UInt8(0x80 | size))
            } else {
                f.append(0xFE)  // MASK=1, length indicator=126 (16-bit extended)
                f.append(UInt8((size >> 8) & 0xFF))
                f.append(UInt8(size & 0xFF))
            }
            f.append(contentsOf: mask)
            f.append(contentsOf: (0..<size).map { UInt8(0x41) ^ mask[$0 % 4] })
            return f
        }
        let frame1 = maskedFrame(opcode: 0x01, fin: false, size: 150)
        let frame2 = maskedFrame(opcode: 0x00, fin: false, size: 100)

        var serverResponse = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
            MainActor.assumeIsolated { if let data { serverResponse.append(data) } }
        }
        conn.send(content: frame1, completion: .contentProcessed { _ in
            conn.send(content: frame2, completion: .idempotent)
        })

        let ok = await h.waitForAsync(timeout: 3.0) {
            serverResponse.count >= 4 &&
            serverResponse[0] == 0x88 && serverResponse[1] == 0x02 &&
            serverResponse[2] == 0x03 && serverResponse[3] == 0xF1
        }
        conn.cancel()
        h.eval("server.stop()")
        #expect(ok, "Server should close with code 1009 when fragment buffer exceeds maxBodySize")
    }

    @Test("WebSocket server fires connected and closed events")
        func testWebSocketConnectedClosedEvents() async {
            let h = makeHarness()
            var gotConnected = false
            var gotClosed = false

            h.eval("""
            var server = hs.httpserver.create()
                .setPort(0)
                .setWebSocketCallback('/events', (event, conn, msg) => {
                    if (event === 'connected') __test_callback('connected')
                    else if (event === 'closed') __test_callback('closed')
                })
                .start()
        """)
            h.registerCallback("connected") { gotConnected = true }
            h.registerCallback("closed") { gotClosed = true }

            let portReady = await h.waitForAsync(timeout: 2.0) {
                let port = h.eval("server.getPort()") as? Int ?? 0
                return port > 0
            }
            guard portReady else { h.eval("server.stop()"); return }

            h.eval("""
            var ws = hs.http.openWebSocket('ws://localhost:' + server.getPort() + '/events')
        """)

            let connected = await h.waitForAsync(timeout: 3.0) { gotConnected }
            #expect(connected, "Server should fire connected event")

            h.eval("ws.close()")
            let closed = await h.waitForAsync(timeout: 3.0) { gotClosed }
            h.eval("server.stop()")
            #expect(closed, "Server should fire closed event when client disconnects")
        }
    }

    // MARK: - Memory Leak Tests

    @Test("Active HSHTTPServer is released after shutdown")
    func testHTTPServerDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSHTTPServerModule.self, as: "httpserver")
            // Create the server, set a request callback (exercising the JSCallback path),
            // then start() it on port 0 (OS-assigned) so it is actively listening.
            // shutdown() → destroy() stops the Network.framework listener and detaches
            // all callbacks.
            harness.eval("""
                var server = hs.httpserver.create()
                server.setPort(0)
                      .setCallback(function(method, path, headers, body) {
                          return { code: 200, body: 'ok', headers: {} }
                      })
                      .start()
            """)
            if let obj = harness.evalValue("server")?.toObjectOf(HSHTTPServer.self) as? HSHTTPServer {
                tracker.track(obj)
            }
            harness.eval("server = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
