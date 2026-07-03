//
//  HSHTTPServer.swift
//  Hammerspoon 2

import Foundation
import JavaScriptCore
import Network
import Security
import UniformTypeIdentifiers

// MARK: - Protocol

/// An HTTP server instance created by `hs.httpserver.create()`.
///
/// Configure with chainable setter methods, then call `start()` to begin accepting connections.
/// The server supports synchronous and async (Promise-returning) request callbacks, optional
/// static file serving, HTTP Basic authentication, Bonjour advertisement, and TLS via PKCS#12.
///
/// Do not instantiate `HSHTTPServer` directly — use `hs.httpserver.create()`.
@objc protocol HSHTTPServerAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this server instance (UUID string).
    @objc var identifier: String { get }

    /// Set the TCP port to listen on. Must be called before `start()`.
    ///
    /// Pass 0 to let the OS assign an available port (use `getPort()` after `start()` to discover it).
    ///
    /// - Parameter port: TCP port number (0–65535).
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setPort(8080)
    /// ```
    @objc @discardableResult func setPort(_ port: Int) -> HSHTTPServer

    /// Set the network interface to listen on.
    ///
    /// Pass `null` to listen on all interfaces (the default). Pass `"localhost"` or `"loopback"`
    /// to restrict to the loopback interface only.
    ///
    /// - Parameter iface: Interface name or IP address string, or `null` for all interfaces.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setInterface("localhost")  // loopback only
    /// server.setInterface(null)         // all interfaces
    /// ```
    @objc @discardableResult func setInterface(_ iface: String?) -> HSHTTPServer

    /// Set a password required for Basic authentication.
    ///
    /// When set, every request must supply an `Authorization: Basic` header with any
    /// username and the configured password. Pass `null` to disable authentication.
    ///
    /// - Parameter password: The required password, or `null` to remove authentication.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setPassword("s3cr3t")
    /// ```
    @objc @discardableResult func setPassword(_ password: String?) -> HSHTTPServer

    /// Set the maximum allowed incoming request body size in bytes.
    ///
    /// Requests with a body exceeding this limit receive a 413 response. Defaults to 10 MB.
    ///
    /// - Parameter size: Maximum body size in bytes.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setMaxBodySize(1024 * 1024)  // 1 MB
    /// ```
    @objc @discardableResult func setMaxBodySize(_ size: Int) -> HSHTTPServer

    /// Set the Bonjour service name advertised on the local network.
    ///
    /// Only used when Bonjour is enabled via `setBonjour(true)`.
    ///
    /// - Parameter name: The Bonjour service name.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setName("My Hammerspoon Server")
    /// ```
    @objc @discardableResult func setName(_ name: String) -> HSHTTPServer

    /// Enable or disable Bonjour advertisement of this server on the local network.
    ///
    /// - Parameter enable: `true` to advertise via Bonjour, `false` to disable (default).
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setBonjour(true)
    /// ```
    @objc @discardableResult func setBonjour(_ enable: Bool) -> HSHTTPServer

    /// Set the request handler callback.
    ///
    /// The callback receives `(method, path, headers, body)` and must return either:
    /// - A plain object `{body, status, headers}` for a synchronous response.
    /// - A Promise resolving to `{body, status, headers}` for an async response.
    ///
    /// If the callback returns `null` or `undefined`, the server falls through to static file serving
    /// (if a document root is set), or responds with 404.
    ///
    /// - Parameter callback: {((method: string, path: string, headers: object, body: string) => ({body: string, status: number, headers: object} | Promise<{body: string, status: number, headers: object}>)) | null} The request handler, or `null` to clear.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setCallback((method, path, headers, body) => {
    ///     return {body: "<h1>Hello!</h1>", status: 200, headers: {"Content-Type": "text/html"}}
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSHTTPServer

    /// Set the filesystem path to serve static files from.
    ///
    /// When a document root is set, requests not handled by the callback are served as
    /// static files from this directory. Pass `null` to disable static file serving.
    ///
    /// - Parameter path: Absolute path to a directory, or `null` to disable.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setDocumentRoot("/Users/me/Sites")
    /// ```
    @objc @discardableResult func setDocumentRoot(_ path: String?) -> HSHTTPServer

    /// Set the list of index filenames checked when a directory is requested.
    ///
    /// Defaults to `["index.html", "index.htm"]`. Files are checked in order.
    ///
    /// - Parameter files: Array of filename strings.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setDirectoryIndex(["index.html", "default.html"])
    /// ```
    @objc @discardableResult func setDirectoryIndex(_ files: [String]) -> HSHTTPServer

    /// Enable or disable directory listing for requests that map to a directory with no index file.
    ///
    /// When disabled (the default), directory requests without an index file return 403.
    ///
    /// - Parameter allow: `true` to serve directory listings, `false` to return 403 (default).
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setAllowDirectoryListing(true)
    /// ```
    @objc @discardableResult func setAllowDirectoryListing(_ allow: Bool) -> HSHTTPServer

    /// Configure TLS using a PKCS#12 (.p12) identity file.
    ///
    /// When TLS is configured, the server accepts HTTPS connections. The `.p12` file must
    /// contain both the certificate and the private key.
    ///
    /// - Parameter path: Absolute path to the `.p12` file.
    /// - Parameter password: The password protecting the `.p12` file.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setTLSFromPKCS12("/path/to/identity.p12", "passphrase").start()
    /// ```
    @objc @discardableResult func setTLSFromPKCS12(_ path: String, _ password: String) -> HSHTTPServer

    /// Start the server and begin accepting connections.
    ///
    /// The server must be configured before calling `start()`. To restart the server with new
    /// settings, call `stop()` followed by `start()`.
    ///
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// const server = hs.httpserver.create().setPort(8080).setCallback(handler).start()
    /// ```
    @objc @discardableResult func start() -> HSHTTPServer

    /// Stop the server and close all connections.
    ///
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.stop()
    /// ```
    @objc @discardableResult func stop() -> HSHTTPServer

    /// Destroy this server, releasing all resources.
    ///
    /// After calling `destroy()`, the server object should not be used.
    ///
    /// - Example:
    /// ```js
    /// server.destroy()
    /// ```
    @objc func destroy()

    /// Get the TCP port the server is currently listening on.
    ///
    /// Returns 0 if the server is not running.
    ///
    /// - Returns: The TCP port number.
    /// - Example:
    /// ```js
    /// console.log("Listening on port " + server.getPort())
    /// ```
    @objc func getPort() -> Int

    /// Get the configured Bonjour service name.
    ///
    /// - Returns: The Bonjour service name.
    /// - Example:
    /// ```js
    /// console.log(server.getName())
    /// ```
    @objc func getName() -> String

    /// Get the configured network interface, or `null` if listening on all interfaces.
    ///
    /// - Returns: The interface name or IP address string, or `null`.
    /// - Example:
    /// ```js
    /// console.log(server.getInterface())
    /// ```
    @objc func getInterface() -> String?

    /// Register a WebSocket handler for a URL path.
    ///
    /// When a client connects and performs a WebSocket upgrade handshake on `path`, the callback
    /// is invoked with three arguments: `event` (string), `connection` (HSWebSocketConnection),
    /// and `message` (string).
    ///
    /// **Events:**
    /// - `"connected"` — a new client connected; `message` is `""`.
    /// - `"message"` — the client sent a text frame; `message` contains the text.
    /// - `"closed"` — the client disconnected; `message` is `""`.
    ///
    /// Pass `null` to remove the WebSocket handler for the path.
    ///
    /// - Parameter path: The URL path to handle WebSocket connections on (e.g. `"/ws"`).
    /// - Parameter callback: {((event: string, connection: HSWebSocketConnection, message: string) => void) | null} The event handler, or `null` to remove.
    /// - Returns: This server, for chaining.
    /// - Example:
    /// ```js
    /// server.setWebSocketCallback('/ws', (event, conn, msg) => {
    ///     if (event === 'connected') conn.send('Welcome!')
    ///     else if (event === 'message') conn.send('Echo: ' + msg)
    /// })
    /// ```
    @objc @discardableResult func setWebSocketCallback(_ path: String, _ callback: JSFunction?) -> HSHTTPServer
}

// MARK: - Parsed request

struct ParsedHTTPRequest {
    let method: String
    let path: String
    let query: String?
    let headers: [String: String]
    let body: String
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHTTPServer: NSObject, HSHTTPServerAPI {
    @objc var typeName = "HSHTTPServer"
    @objc let identifier = UUID().uuidString

    // Configuration
    private var _port: UInt16 = 0
    private var _interface: String? = nil
    private var _password: String? = nil
    private var maxBodySize = 10 * 1024 * 1024  // 10 MB
    private var _name = "Hammerspoon HTTP Server"
    private var _bonjour = false
    private var _documentRoot: String? = nil
    private var _directoryIndex: [String] = ["index.html", "index.htm"]
    private var _allowDirectoryListing = false
    private var _tlsIdentity: SecIdentity? = nil

    // Runtime state
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var isRunning = false

    // WebSocket state
    private var _wsCallbacks: [String: JSCallback] = [:]
    private var _wsConnections = HSWeakObjectSet<HSWebSocketConnection>()

    // Callbacks (JSCallback prevents retain cycles)
    private var _callback: JSCallback?

    override init() {
        super.init()
    }

    isolated deinit {
        // destroy() was called by shutdown() — this is just the final ARC release
        AKDebug("deinit of HSHTTPServer(\(identifier))")
    }

    @objc func destroy() {
        _ = stop()
        _callback?.detach(from: self)
        _callback = nil
        for (_, cb) in _wsCallbacks { cb.detach(from: self) }
        _wsCallbacks.removeAll()
        _wsConnections.removeAllObjects()
        _tlsIdentity = nil
    }

    // MARK: - Configuration

    @objc @discardableResult func setPort(_ port: Int) -> HSHTTPServer {
        _port = UInt16(clamping: port)
        return self
    }

    @objc @discardableResult func setInterface(_ iface: String?) -> HSHTTPServer {
        _interface = iface
        return self
    }

    @objc @discardableResult func setPassword(_ password: String?) -> HSHTTPServer {
        _password = password
        return self
    }

    @objc @discardableResult func setMaxBodySize(_ size: Int) -> HSHTTPServer {
        maxBodySize = max(1024, size)
        return self
    }

    @objc @discardableResult func setName(_ name: String) -> HSHTTPServer {
        _name = name
        return self
    }

    @objc @discardableResult func setBonjour(_ enable: Bool) -> HSHTTPServer {
        _bonjour = enable
        return self
    }

    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSHTTPServer {
        _callback?.detach(from: self)
        _callback = callback.flatMap { JSCallback(value: $0, owner: self) }
        return self
    }

    @objc @discardableResult func setWebSocketCallback(_ path: String, _ callback: JSFunction?) -> HSHTTPServer {
        _wsCallbacks[path]?.detach(from: self)
        if let callback {
            _wsCallbacks[path] = JSCallback(value: callback, owner: self)
        } else {
            _wsCallbacks.removeValue(forKey: path)
        }
        return self
    }

    @objc @discardableResult func setDocumentRoot(_ path: String?) -> HSHTTPServer {
        _documentRoot = path
        return self
    }

    @objc @discardableResult func setDirectoryIndex(_ files: [String]) -> HSHTTPServer {
        _directoryIndex = files
        return self
    }

    @objc @discardableResult func setAllowDirectoryListing(_ allow: Bool) -> HSHTTPServer {
        _allowDirectoryListing = allow
        return self
    }

    @objc @discardableResult func setTLSFromPKCS12(_ path: String, _ password: String) -> HSHTTPServer {
        _tlsIdentity = loadIdentityFromP12(atPath: path, password: password)
        if _tlsIdentity == nil {
            AKError("HSHTTPServer(\(identifier)): Failed to load TLS identity from \(path)")
        }
        return self
    }

    // MARK: - State

    @objc func getPort() -> Int {
        guard let rawValue = listener?.port?.rawValue else { return 0 }
        return Int(rawValue)
    }

    @objc func getName() -> String { _name }

    @objc func getInterface() -> String? { _interface }

    // MARK: - Lifecycle

    @objc @discardableResult func start() -> HSHTTPServer {
        guard !isRunning else {
            AKWarning("HSHTTPServer(\(identifier)): Already running")
            return self
        }

        do {
            let parameters = makeParameters()
            let port = NWEndpoint.Port(rawValue: _port) ?? .any
            listener = try NWListener(using: parameters, on: port)

            if _bonjour {
                listener?.service = NWListener.Service(name: _name, type: "_http._tcp")
            }

            listener?.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.acceptConnection(connection) }
            }

            listener?.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        AKTrace("HSHTTPServer(\(self.identifier)): Listening on port \(self.getPort())")
                    case .failed(let error):
                        AKError("HSHTTPServer(\(self.identifier)): Failed: \(error)")
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .main)
            isRunning = true
            AKTrace("HSHTTPServer(\(identifier)): Starting on port \(_port == 0 ? "auto" : "\(_port)")")
        } catch {
            AKError("HSHTTPServer(\(identifier)): Could not create listener: \(error)")
        }

        return self
    }

    @objc @discardableResult func stop() -> HSHTTPServer {
        guard isRunning else { return self }
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        isRunning = false
        AKTrace("HSHTTPServer(\(identifier)): Stopped")
        return self
    }

    // MARK: - Connection handling

    private func acceptConnection(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection

        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .cancelled, .failed:
                    self.connections.removeValue(forKey: key)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receiveRequest(on: connection, accumulating: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulating buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                var newBuffer = buffer
                if let chunk { newBuffer.append(chunk) }

                if newBuffer.count > self.maxBodySize + 65536 {
                    self.sendResponse(on: connection, status: 413, body: "Request Too Large", headers: [:])
                    return
                }

                if let parsed = Self.parseHTTPRequest(from: newBuffer, maxBodySize: self.maxBodySize) {
                    self.handleRequest(parsed, on: connection)
                } else if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receiveRequest(on: connection, accumulating: newBuffer)
                }
            }
        }
    }

    // MARK: - HTTP parsing

    static func parseHTTPRequest(from data: Data, maxBodySize: Int) -> ParsedHTTPRequest? {
        guard let sepRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerSection = String(data: data[..<sepRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let rawPath = parts[1]

        var path = rawPath
        var query: String? = nil
        if let qIdx = rawPath.firstIndex(of: "?") {
            path = String(rawPath[..<qIdx])
            query = String(rawPath[rawPath.index(after: qIdx)...])
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = sepRange.upperBound
        let contentLength = min(Int(headers["content-length"] ?? "0") ?? 0, maxBodySize)
        let available = data.count - bodyStart

        if available < contentLength {
            return nil  // need more data
        }

        let bodyData = contentLength > 0 ? Data(data[bodyStart..<(bodyStart + contentLength)]) : Data()
        let body = String(data: bodyData, encoding: .utf8) ?? ""

        return ParsedHTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    // MARK: - Request dispatching

    private func handleRequest(_ request: ParsedHTTPRequest, on connection: NWConnection) {
        // Basic auth check
        if let password = _password, !checkBasicAuth(headers: request.headers, password: password) {
            sendResponse(on: connection, status: 401, body: "Unauthorized",
                         headers: ["WWW-Authenticate": "Basic realm=\"Hammerspoon\""])
            return
        }

        // WebSocket upgrade
        if isWebSocketUpgrade(headers: request.headers), let wsCallback = _wsCallbacks[request.path] {
            performWebSocketUpgrade(request: request, connection: connection, callback: wsCallback)
            return
        }

        // Try JS callback
        if let callbackValue = _callback?.value {
            let result = callbackValue.call(withArguments: [
                request.method,
                request.path,
                request.headers as [String: Any],
                request.body
            ])

            // Check if result is a thenable (Promise)
            if let result, result.isObject,
               let thenFn = result.objectForKeyedSubscript("then"),
               !thenFn.isUndefined, !thenFn.isNull, thenFn.isObject,
               let ctx = result.context {

                let onFulfilled = JSValue(object: { [weak self] (resolved: JSValue) in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if resolved.isNull || resolved.isUndefined {
                            if let docRoot = self._documentRoot {
                                self.serveStaticFile(request: request, documentRoot: docRoot, on: connection)
                            } else {
                                self.sendResponse(on: connection, status: 404, body: "Not Found", headers: [:])
                            }
                        } else {
                            let (body, status, hdrs) = self.extractResponse(from: resolved)
                            self.sendResponse(on: connection, status: status, body: body, headers: hdrs)
                        }
                    }
                } as @convention(block) (JSValue) -> Void, in: ctx)

                let onRejected = JSValue(object: { [weak self] (_: JSValue) in
                    MainActor.assumeIsolated {
                        self?.sendResponse(on: connection, status: 500, body: "Callback error", headers: [:])
                    }
                } as @convention(block) (JSValue) -> Void, in: ctx)

                result.invokeMethod("then", withArguments: [onFulfilled!, onRejected!])
                return
            }

            if let result, !result.isNull, !result.isUndefined {
                let (body, status, hdrs) = extractResponse(from: result)
                sendResponse(on: connection, status: status, body: body, headers: hdrs)
                return
            }

            // Callback returned null/undefined — fall through to static file serving
        }

        // Try static file serving
        if let docRoot = _documentRoot {
            serveStaticFile(request: request, documentRoot: docRoot, on: connection)
            return
        }

        sendResponse(on: connection, status: 404, body: "Not Found", headers: [:])
    }

    // MARK: - WebSocket upgrade

    private func isWebSocketUpgrade(headers: [String: String]) -> Bool {
        return headers["upgrade"]?.lowercased() == "websocket" &&
               headers["connection"]?.lowercased().contains("upgrade") == true &&
               headers["sec-websocket-key"] != nil
    }

    private func performWebSocketUpgrade(
        request: ParsedHTTPRequest,
        connection: NWConnection,
        callback: JSCallback
    ) {
        guard let key = request.headers["sec-websocket-key"] else {
            sendResponse(on: connection, status: 400, body: "Missing Sec-WebSocket-Key", headers: [:])
            return
        }
        let acceptKey = HSWebSocketConnection.webSocketAcceptKey(for: key)
        let handshake = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(acceptKey)",
            "\r\n"
        ].joined(separator: "\r\n")

        // Send the 101 response WITHOUT closing the connection (unlike normal HTTP responses).
        connection.send(content: handshake.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, error == nil else { return }
                let path = request.path
                let wsConn = HSWebSocketConnection(connection: connection)
                self._wsConnections.add(wsConn)
                _ = callback.value?.call(withArguments: ["connected", wsConn, ""])
                self.receiveWebSocketFrames(on: connection, wsConn: wsConn, path: path, buffer: Data())
                AKTrace("HSHTTPServer(\(self.identifier)): WebSocket upgrade on \(path)")
            }
        })
    }

    private func receiveWebSocketFrames(
        on connection: NWConnection,
        wsConn: HSWebSocketConnection,
        path: String,
        buffer: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !wsConn.isClosed else { return }

                var buf = buffer
                if let chunk { buf.append(chunk) }

                // Parse all complete frames from the accumulated buffer.
                while !wsConn.isClosed {
                    // buf always has startIndex == 0 because it's built from Data() + append.
                    guard let (frame, consumed) = HSWebSocketConnection.parseNextFrame(from: buf) else { break }
                    buf = Data(buf.dropFirst(consumed))

                    switch frame.opcode {
                    case 0x01, 0x02:  // text or binary frame
                        let text = String(data: frame.payload, encoding: .utf8) ?? ""
                        _ = self._wsCallbacks[path]?.value?.call(withArguments: ["message", wsConn, text])
                    case 0x08:  // close frame
                        wsConn.isClosed = true
                        _ = self._wsCallbacks[path]?.value?.call(withArguments: ["closed", wsConn, ""])
                        let closeFrame = HSWebSocketConnection.buildFrame(opcode: 0x08, payload: Data())
                        connection.send(content: closeFrame, completion: .contentProcessed { _ in
                            MainActor.assumeIsolated { connection.cancel() }
                        })
                        return
                    case 0x09:  // ping → respond with pong
                        let pong = HSWebSocketConnection.buildFrame(opcode: 0x0A, payload: frame.payload)
                        connection.send(content: pong, completion: .idempotent)
                    default:
                        break
                    }
                }

                if error != nil || isComplete {
                    if !wsConn.isClosed {
                        wsConn.isClosed = true
                        _ = self._wsCallbacks[path]?.value?.call(withArguments: ["closed", wsConn, ""])
                    }
                    return
                }

                self.receiveWebSocketFrames(on: connection, wsConn: wsConn, path: path, buffer: buf)
            }
        }
    }

    private func extractResponse(from value: JSValue) -> (body: String, status: Int, headers: [String: String]) {
        guard value.isObject, !value.isNull else {
            return ("Not Found", 404, [:])
        }
        let body = value.objectForKeyedSubscript("body")?.toString() ?? ""
        let status = Int(value.objectForKeyedSubscript("status")?.toInt32() ?? 200)
        var headers: [String: String] = [:]
        if let hdrsObj = value.objectForKeyedSubscript("headers"),
           hdrsObj.isObject, !hdrsObj.isNull,
           let dict = hdrsObj.toObject() as? [String: Any] {
            for (k, v) in dict { headers[k] = "\(v)" }
        }
        return (body, status, headers)
    }

    // MARK: - Auth

    private func checkBasicAuth(headers: [String: String], password: String) -> Bool {
        guard let authHeader = headers["authorization"],
              authHeader.lowercased().hasPrefix("basic "),
              let decoded = Data(base64Encoded: String(authHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)),
              let credentials = String(data: decoded, encoding: .utf8) else {
            return false
        }
        // Accept any username; only the password is checked
        if let colonIdx = credentials.firstIndex(of: ":") {
            return String(credentials[credentials.index(after: colonIdx)...]) == password
        }
        return credentials == password
    }

    // MARK: - Static file serving

    private func serveStaticFile(request: ParsedHTTPRequest, documentRoot: String, on connection: NWConnection) {
        let fm = FileManager.default

        // Prevent directory traversal
        let sanitized = (request.path as NSString).standardizingPath
        guard sanitized.hasPrefix("/") else {
            sendResponse(on: connection, status: 400, body: "Bad Request", headers: [:])
            return
        }
        let fullPath = (documentRoot as NSString).appendingPathComponent(sanitized)

        var isDir: ObjCBool = false
        guard unsafe fm.fileExists(atPath: fullPath, isDirectory: &isDir) else {
            sendResponse(on: connection, status: 404, body: "Not Found", headers: [:])
            return
        }

        if isDir.boolValue {
            for indexFile in _directoryIndex {
                let indexPath = (fullPath as NSString).appendingPathComponent(indexFile)
                if fm.fileExists(atPath: indexPath) {
                    sendFile(at: indexPath, on: connection)
                    return
                }
            }
            if _allowDirectoryListing {
                sendDirectoryListing(at: fullPath, requestPath: request.path, on: connection)
            } else {
                sendResponse(on: connection, status: 403, body: "Forbidden", headers: [:])
            }
        } else {
            sendFile(at: fullPath, on: connection)
        }
    }

    private func sendFile(at path: String, on connection: NWConnection) {
        guard let data = FileManager.default.contents(atPath: path) else {
            sendResponse(on: connection, status: 500, body: "Could not read file", headers: [:])
            return
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime = mimeType(forExtension: ext)
        sendRawResponse(on: connection, status: 200, body: data,
                        headers: ["Content-Type": mime])
    }

    private func sendDirectoryListing(at path: String, requestPath: String, on connection: NWConnection) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
            sendResponse(on: connection, status: 500, body: "Could not list directory", headers: [:])
            return
        }
        let base = requestPath.hasSuffix("/") ? requestPath : requestPath + "/"
        let escapedPath = Self.htmlEscape(requestPath)
        let escapedBase = Self.htmlEscape(base)
        var html = "<html><head><title>Index of \(escapedPath)</title></head><body>"
        html += "<h1>Index of \(escapedPath)</h1><ul>"
        if requestPath != "/" { html += "<li><a href=\"../\">..</a></li>" }
        for entry in entries.sorted() {
            var entryIsDir: ObjCBool = false
            unsafe fm.fileExists(atPath: (path as NSString).appendingPathComponent(entry), isDirectory: &entryIsDir)
            let display = entryIsDir.boolValue ? "\(entry)/" : entry
            let escapedDisplay = Self.htmlEscape(display)
            html += "<li><a href=\"\(escapedBase)\(escapedDisplay)\">\(escapedDisplay)</a></li>"
        }
        html += "</ul></body></html>"
        sendResponse(on: connection, status: 200, body: html,
                     headers: ["Content-Type": "text/html; charset=utf-8"])
    }

    // MARK: - Response sending

    private func sendResponse(on connection: NWConnection, status: Int, body: String, headers: [String: String]) {
        var finalHeaders = headers
        if finalHeaders["Content-Type"] == nil {
            finalHeaders["Content-Type"] = "text/plain; charset=utf-8"
        }
        sendRawResponse(on: connection, status: status,
                        body: body.data(using: .utf8) ?? Data(), headers: finalHeaders)
    }

    private func sendRawResponse(on connection: NWConnection, status: Int, body: Data, headers: [String: String]) {
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        allHeaders["Connection"] = "close"

        var headerStr = "HTTP/1.1 \(status) \(httpStatusText(status))\r\n"
        for (k, v) in allHeaders { headerStr += "\(k): \(v)\r\n" }
        headerStr += "\r\n"

        var response = headerStr.data(using: .utf8) ?? Data()
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { [weak connection] _ in
            MainActor.assumeIsolated { connection?.cancel() }
        })
    }

    // MARK: - TLS / Network parameters

    private func makeParameters() -> NWParameters {
        if let identity = _tlsIdentity {
            let tlsOptions = NWProtocolTLS.Options()
            if let secId = sec_identity_create(identity) {
                sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secId)
            }
            return NWParameters(tls: tlsOptions)
        }
        return .tcp
    }

    private func loadIdentityFromP12(atPath path: String, password: String) -> SecIdentity? {
        guard let data = FileManager.default.contents(atPath: path) else {
            AKError("HSHTTPServer: Cannot read PKCS12 file at \(path)")
            return nil
        }
        let options = [kSecImportExportPassphrase: password] as CFDictionary
        var items: CFArray?
        let status = unsafe SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else {
            AKError("HSHTTPServer: PKCS12 import failed (status \(status))")
            return nil
        }
        return (identity as! SecIdentity)
    }

    // MARK: - Helpers

    private static func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func mimeType(forExtension ext: String) -> String {
        if let utType = UTType(filenameExtension: ext),
           let mime = utType.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        default:  return "Unknown"
        }
    }
}
