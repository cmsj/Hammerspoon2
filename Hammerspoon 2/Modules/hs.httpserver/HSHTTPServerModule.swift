//
//  HSHTTPServerModule.swift
//  Hammerspoon 2

import Foundation
import JavaScriptCore

/// Module for creating and managing HTTP servers.
///
/// Create a server with `hs.httpserver.create()`, configure it with chainable setters,
/// then call `start()`. The server accepts both synchronous and async (Promise-returning)
/// request handler callbacks.
///
/// ## Quick start
///
/// ```js
/// const server = hs.httpserver.create()
///     .setPort(8080)
///     .setCallback((method, path, headers, body) => {
///         return {body: "<h1>Hello from Hammerspoon!</h1>", status: 200, headers: {"Content-Type": "text/html"}}
///     })
///     .start()
/// console.log("Listening on port " + server.getPort())
/// ```
///
/// ## Async callback
///
/// ```js
/// server.setCallback(async (method, path, headers, body) => {
///     const data = await hs.http.get("https://api.example.com/data")
///     return {body: data.body, status: 200, headers: {"Content-Type": "application/json"}}
/// })
/// ```
///
/// ## Static file serving
///
/// ```js
/// const server = hs.httpserver.create()
///     .setPort(8080)
///     .setDocumentRoot("/Users/me/Sites")
///     .start()
/// ```
///
/// ## TLS (HTTPS)
///
/// Hammerspoon 2 cannot generate TLS certificates itself, you will need to supply a p12 file, which you can generate with:
/// ```bash
/// openssl genrsa -out key.pem 2048
/// openssl req -new -x509 -key key.pem -out cert.pem -days 365
/// openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem
/// ```
///
/// ```js
/// const server = hs.httpserver.create()
///     .setPort(8443)
///     .setTLSFromPKCS12("/path/to/identity.p12", "passphrase")
///     .setCallback(handler)
///     .start()
/// ```
@objc protocol HSHTTPServerModuleAPI: JSExport {

    /// Create a new HTTP server instance.
    ///
    /// The server is not running until you call `start()` on the returned object.
    ///
    /// - Returns: A new `HSHTTPServer` instance.
    /// - Example:
    /// ```js
    /// const server = hs.httpserver.create()
    ///     .setPort(8080)
    ///     .setCallback((method, path, headers, body) => {
    ///         return {body: "Hello!", status: 200, headers: {}}
    ///     })
    ///     .start()
    /// console.log("Running on port " + server.getPort())
    /// ```
    @objc func create() -> HSHTTPServer
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHTTPServerModule: NSObject, HSModuleAPI, HSHTTPServerModuleAPI {
    var name = "hs.httpserver"
    let engineID: UUID
    private var servers = HSWeakObjectSet<HSHTTPServer>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for server in servers.allObjects {
            server.destroy()
        }
        servers.removeAllObjects()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    @objc func create() -> HSHTTPServer {
        let server = HSHTTPServer()
        servers.add(server)
        return server
    }
}
