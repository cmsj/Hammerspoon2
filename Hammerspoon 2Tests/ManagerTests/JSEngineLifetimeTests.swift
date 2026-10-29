//
//  JSEngineLifetimeTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import JavaScriptCore
import Testing
@testable import Hammerspoon_2

/// Reloading must free the previous `JSContext`, or every reload leaks its whole JavaScript heap
/// (#365). These tests use a real `JSEngine`, so they cover everything it installs into a context
/// (`fetch()`, `require()`, `console` and so on), which `JSTestHarness` doesn't.
///
/// They don't use the `hs` modules, because `ModuleRoot` loads each module's JS into
/// `JSEngine.shared` rather than into the engine under test. `JSTestHarness`'s leak tests cover
/// those.
@Suite("JSEngine context lifetime")
struct JSEngineLifetimeTests {
    @Test("Reloading frees the previous JSContext", arguments: [
        "",
        "console.log('hello'); require('util').inspect({ a: 1 })",
        "new Promise(() => {})",
    ])
    func reloadFreesContext(script: String) async throws {
        #expect(try await contextIsFreedAfterReload(script: script))
    }

    @Test("Reloading frees a JSContext whose fetch() has settled", arguments: [
        "fetch('https://hs2.test/').then((r) => r.text()).then(() => { globalThis.settled = true })",
        "fetch('https://hs2.test/fail').catch(() => { globalThis.settled = true })",
    ])
    func reloadFreesContextAfterFetch(script: String) async throws {
        #expect(try await contextIsFreedAfterReload(script: script, waitingFor: "globalThis.settled === true"))
    }

    @Test("Reloading frees a JSContext whose fetch() is still in flight")
    func reloadFreesContextDuringFetch() async throws {
        #expect(try await contextIsFreedAfterReload(script: "fetch('https://hs2.test/hang')"))
    }

    /// Runs `script` in a fresh context, waits until `condition` is true in it, reloads, and
    /// returns whether the previous context was then freed.
    private func contextIsFreedAfterReload(script: String, waitingFor condition: String? = nil) async throws -> Bool {
        let engine = JSEngine(fetchSessionConfiguration: .stubbed)
        defer { engine.shutdown() }
        weak var oldContext: JSContext?

        // `void` + autoreleasepool, so the script's completion value can't keep the context alive
        try autoreleasepool {
            try engine.resetContext()
            oldContext = engine.context
            engine.eval("void (\(script))")
        }
        if let condition {
            let isMet = await waitUntil { autoreleasepool { engine.eval(condition) as? Bool == true } }
            try #require(isMet, "\(condition) never became true")
        }

        try engine.resetContext()
        return await waitUntil { oldContext == nil }
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// Answers requests to `/fail` with an error, never answers requests to `/hang`, and answers
/// everything else with "hello", so fetch() can be tested without the network.
private nonisolated final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        switch url.path {
        case "/hang":
            return
        case "/fail":
            client.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        default:
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data("hello".utf8))
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static var stubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}
