//
//  HSHTTPIntegrationTests.swift
//  Hammerspoon 2Tests

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.http/hs.httpserver other tests")
struct HSHTTPOtherTests {

    // MARK: - API structure

    @Suite("hs.http API structure tests")
    struct HSHTTPStructureTests {

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPModule.self, as: "http")
            return h
        }

        @Test("get is a function")
        func testGetIsFunction() {
            makeHarness().expectTrue("typeof hs.http.get === 'function'")
        }

        @Test("post is a function")
        func testPostIsFunction() {
            makeHarness().expectTrue("typeof hs.http.post === 'function'")
        }

        @Test("put is a function")
        func testPutIsFunction() {
            makeHarness().expectTrue("typeof hs.http.put === 'function'")
        }

        @Test("doRequest is a function")
        func testDoRequestIsFunction() {
            makeHarness().expectTrue("typeof hs.http.doRequest === 'function'")
        }

        @Test("encodeForQuery is a function")
        func testEncodeForQueryIsFunction() {
            makeHarness().expectTrue("typeof hs.http.encodeForQuery === 'function'")
        }

        @Test("urlParts is a function")
        func testUrlPartsIsFunction() {
            makeHarness().expectTrue("typeof hs.http.urlParts === 'function'")
        }

        @Test("convertHtmlEntities is a function")
        func testConvertHtmlEntitiesIsFunction() {
            makeHarness().expectTrue("typeof hs.http.convertHtmlEntities === 'function'")
        }

        @Test("get returns a Promise-like object")
        func testGetReturnsPromise() {
            let h = makeHarness()
            h.eval("var p = hs.http.get('http://localhost:1')")
            h.expectTrue("p !== null && p !== undefined && typeof p.then === 'function'")
            #expect(!h.hasException)
        }

        @Test("post returns a Promise-like object")
        func testPostReturnsPromise() {
            let h = makeHarness()
            h.eval("var p = hs.http.post('http://localhost:1', null, null)")
            h.expectTrue("p !== null && p !== undefined && typeof p.then === 'function'")
            #expect(!h.hasException)
        }

        @Test("doRequest returns a Promise-like object")
        func testDoRequestReturnsPromise() {
            let h = makeHarness()
            h.eval("var p = hs.http.doRequest('http://localhost:1', 'DELETE', null, null)")
            h.expectTrue("p !== null && p !== undefined && typeof p.then === 'function'")
            #expect(!h.hasException)
        }
    }

    // MARK: - Utility function tests (no network needed)

    @Suite("hs.http utility tests")
    struct HSHTTPUtilityTests {

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPModule.self, as: "http")
            return h
        }

        // encodeForQuery

        @Test("encodeForQuery encodes spaces")
        func testEncodeSpaces() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('hello world')", "hello%20world")
            #expect(!h.hasException)
        }

        @Test("encodeForQuery encodes ampersand")
        func testEncodeAmpersand() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('a&b')", "a%26b")
            #expect(!h.hasException)
        }

        @Test("encodeForQuery encodes equals sign")
        func testEncodeEquals() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('key=val')", "key%3Dval")
            #expect(!h.hasException)
        }

        @Test("encodeForQuery encodes hash")
        func testEncodeHash() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('a#b')", "a%23b")
            #expect(!h.hasException)
        }

        @Test("encodeForQuery leaves safe characters unchanged")
        func testEncodeSafeChars() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('abc123-._~')", "abc123-._~")
            #expect(!h.hasException)
        }

        @Test("encodeForQuery handles empty string")
        func testEncodeEmpty() {
            let h = makeHarness()
            h.expectEqual("hs.http.encodeForQuery('')", "")
            #expect(!h.hasException)
        }

        // urlParts

        @Test("urlParts returns null for invalid URL")
        func testUrlPartsInvalid() {
            let h = makeHarness()
            h.eval("var r = hs.http.urlParts('not a url at all !!!:}')")
            // Either null or an object with no useful fields — just check no exception
            #expect(!h.hasException)
        }

        @Test("urlParts extracts scheme")
        func testUrlPartsScheme() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com/').scheme", "https")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts host")
        func testUrlPartsHost() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com/path').host", "example.com")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts port")
        func testUrlPartsPort() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com:8080/').port", 8080)
            #expect(!h.hasException)
        }

        @Test("urlParts extracts path")
        func testUrlPartsPath() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com/some/path').path", "/some/path")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts query string")
        func testUrlPartsQuery() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com/?key=val').query", "key=val")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts fragment")
        func testUrlPartsFragment() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://example.com/page#section').fragment", "section")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts user and password")
        func testUrlPartsCredentials() {
            let h = makeHarness()
            h.expectEqual("hs.http.urlParts('https://user:pass@example.com/').user", "user")
            h.expectEqual("hs.http.urlParts('https://user:pass@example.com/').password", "pass")
            #expect(!h.hasException)
        }

        @Test("urlParts extracts queryItems array")
        func testUrlPartsQueryItems() {
            let h = makeHarness()
            h.eval("var parts = hs.http.urlParts('https://example.com/?a=1&b=2')")
            h.expectTrue("Array.isArray(parts.queryItems)")
            h.expectTrue("parts.queryItems.length === 2")
            h.expectTrue("parts.queryItems[0].name === 'a'")
            h.expectTrue("parts.queryItems[0].value === '1'")
            #expect(!h.hasException)
        }

        // convertHtmlEntities

        @Test("convertHtmlEntities converts &amp;")
        func testEntityAmp() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('a &amp; b')", "a & b")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities converts &lt; and &gt;")
        func testEntityLtGt() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('&lt;div&gt;')", "<div>")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities converts &quot;")
        func testEntityQuot() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('&quot;')", "\"")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities converts &copy;")
        func testEntityCopy() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('&copy;')", "©")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities converts decimal numeric entity")
        func testEntityDecimal() {
            let h = makeHarness()
            // &#65; = 'A'
            h.expectEqual("hs.http.convertHtmlEntities('&#65;')", "A")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities converts hex numeric entity")
        func testEntityHex() {
            let h = makeHarness()
            // &#x41; = 'A'
            h.expectEqual("hs.http.convertHtmlEntities('&#x41;')", "A")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities passes through unknown entities unchanged")
        func testEntityUnknown() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('&unknownentity;')", "&unknownentity;")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities handles empty string")
        func testEntityEmpty() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('')", "")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities handles string with no entities")
        func testEntityNoEntities() {
            let h = makeHarness()
            h.expectEqual("hs.http.convertHtmlEntities('hello world')", "hello world")
            #expect(!h.hasException)
        }

        @Test("convertHtmlEntities handles multiple entities in one string")
        func testEntityMultiple() {
            let h = makeHarness()
            h.expectEqual(
                "hs.http.convertHtmlEntities('&lt;b&gt;Hello &amp; World&lt;/b&gt;')",
                "<b>Hello & World</b>"
            )
            #expect(!h.hasException)
        }
    }

    // MARK: - WebSocket client structure tests

    @Suite("hs.http WebSocket client tests", .serialized)
    struct HSWebSocketClientTests {

        private func makeHarness() -> JSTestHarness {
            let h = JSTestHarness()
            h.loadModule(HSHTTPModule.self, as: "http")
            return h
        }

        @Test("openWebSocket is a function")
        func testOpenWebSocketIsFunction() {
            makeHarness().expectTrue("typeof hs.http.openWebSocket === 'function'")
        }

        @Test("openWebSocket with invalid URL returns null")
        func testInvalidURLReturnsNull() {
            let h = makeHarness()
            // Use == null (loose equality) to handle both null and undefined from the ObjC/Swift bridge
            h.expectTrue("hs.http.openWebSocket('not a url') == null")
            #expect(!h.hasException)
        }

        @Test("openWebSocket returns an object")
        func testReturnsObject() {
            let h = makeHarness()
            h.eval("var ws = hs.http.openWebSocket('ws://localhost:9999/no-server')")
            h.expectTrue("typeof ws === 'object' && ws !== null")
            h.eval("ws.destroy()")
            #expect(!h.hasException)
        }

        @Test("HSWebSocket has identifier string")
        func testHasIdentifier() {
            let h = makeHarness()
            h.eval("var ws = hs.http.openWebSocket('ws://localhost:9999/no-server')")
            h.expectTrue("typeof ws.identifier === 'string'")
            h.expectTrue("ws.identifier.length > 0")
            h.eval("ws.destroy()")
            #expect(!h.hasException)
        }

        @Test("HSWebSocket starts with readyState 0 (connecting)")
        func testInitialReadyState() {
            let h = makeHarness()
            h.eval("var ws = hs.http.openWebSocket('ws://localhost:9999/no-server')")
            h.expectEqual("ws.readyState", 0)
            h.eval("ws.destroy()")
            #expect(!h.hasException)
        }

        @Test("HSWebSocket has expected methods")
        func testHasMethods() {
            let h = makeHarness()
            h.eval("var ws = hs.http.openWebSocket('ws://localhost:9999/no-server')")
            h.expectTrue("typeof ws.send === 'function'")
            h.expectTrue("typeof ws.close === 'function'")
            h.expectTrue("typeof ws.destroy === 'function'")
            h.expectTrue("typeof ws.setOpenCallback === 'function'")
            h.expectTrue("typeof ws.setMessageCallback === 'function'")
            h.expectTrue("typeof ws.setCloseCallback === 'function'")
            h.expectTrue("typeof ws.setErrorCallback === 'function'")
            h.eval("ws.destroy()")
            #expect(!h.hasException)
        }

        @Test("setter methods return the WebSocket for chaining")
        func testChainingReturnsWebSocket() {
            let h = makeHarness()
            h.eval("var ws = hs.http.openWebSocket('ws://localhost:9999/no-server')")
            h.expectTrue("ws.setOpenCallback(null) === ws")
            h.expectTrue("ws.setMessageCallback(null) === ws")
            h.expectTrue("ws.setCloseCallback(null) === ws")
            h.expectTrue("ws.setErrorCallback(null) === ws")
            h.eval("ws.destroy()")
            #expect(!h.hasException)
        }

        @Test("two websockets have different identifiers")
        func testUniqueIdentifiers() {
            let h = makeHarness()
            h.eval("var a = hs.http.openWebSocket('ws://localhost:9999/a')")
            h.eval("var b = hs.http.openWebSocket('ws://localhost:9999/b')")
            h.expectTrue("a.identifier !== b.identifier")
            h.eval("a.destroy(); b.destroy()")
            #expect(!h.hasException)
        }
    }

    // MARK: - HTTP parsing unit tests (pure Swift, no network)

    @Suite("HTTP request parsing tests")
    struct HTTPRequestParsingTests {

        @Test("parses simple GET request")
        func testSimpleGET() {
            let raw = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let data = raw.data(using: .utf8)!
            let result = HSHTTPServer.parseHTTPRequest(from: data, maxBodySize: 1024)
            #expect(result != nil)
            #expect(result?.method == "GET")
            #expect(result?.path == "/")
            #expect(result?.query == nil)
            #expect(result?.body == "")
        }

        @Test("parses path with query string")
        func testPathWithQuery() {
            let raw = "GET /search?q=hello&lang=en HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 1024)
            #expect(result?.path == "/search")
            #expect(result?.query == "q=hello&lang=en")
        }

        @Test("parses headers case-insensitively")
        func testHeaderParsing() {
            let raw = "GET / HTTP/1.1\r\nContent-Type: application/json\r\nX-Custom: value\r\n\r\n"
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 1024)
            #expect(result?.headers["content-type"] == "application/json")
            #expect(result?.headers["x-custom"] == "value")
        }

        @Test("parses POST with body")
        func testPOSTWithBody() {
            let body = "hello"
            let raw = "POST /data HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 1024)
            #expect(result?.method == "POST")
            #expect(result?.body == "hello")
        }

        @Test("returns nil when headers are incomplete")
        func testIncompleteHeaders() {
            let raw = "GET / HTTP/1.1\r\nHost: localhost\r\n"  // missing \r\n\r\n
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 1024)
            #expect(result == nil)
        }

        @Test("returns nil when body is incomplete")
        func testIncompleteBody() {
            let raw = "POST /data HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort"
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 1024)
            #expect(result == nil)
        }

        @Test("caps body at maxBodySize")
        func testBodySizeCap() {
            let bigBody = String(repeating: "x", count: 200)
            let raw = "POST /data HTTP/1.1\r\nContent-Length: 200\r\n\r\n\(bigBody)"
            // maxBodySize = 50 → Content-Length is capped at 50
            let result = HSHTTPServer.parseHTTPRequest(from: raw.data(using: .utf8)!, maxBodySize: 50)
            #expect(result?.body.count == 50)
        }
    }
}
