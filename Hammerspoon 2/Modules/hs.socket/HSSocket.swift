//
//  HSSocket.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Network
import Security

// MARK: - Protocol

/// A TCP or Unix domain stream socket, created by `hs.socket.create()`.
///
/// A socket can either connect to a server (`connect()`/`connectUnix()`) or listen for incoming
/// connections (`listen()`/`listenUnix()`). Each connection a listening socket accepts is handed
/// to its callback as a new `HSSocket`, which inherits the listening socket's callback.
///
/// Reading is request-driven: queue a read with `readUntil()`, `readBytes()` or
/// `readAvailable()`, and the callback receives a `"data"` event once that read can be
/// satisfied. Data that arrives before you ask for it is buffered. Reads can be queued before
/// the socket connects, and each one carries an optional numeric tag that is passed back to the
/// callback, so a single callback can tell a protocol's reads apart (e.g. a header and a body).
///
/// Received data is delivered as a `Uint8Array`. Use `hs.socket.decodeText()` to turn it into a
/// string.
///
/// Do not instantiate `HSSocket` directly - use `hs.socket.create()`.
@objc protocol HSSocketAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this socket (UUID string).
    /// - Example:
    /// ```js
    /// console.log(hs.socket.create().identifier)
    /// ```
    @objc var identifier: String { get }

    /// Whether the socket is currently connected to a peer.
    /// - Example:
    /// ```js
    /// if (sock.isConnected) sock.write("ping\n")
    /// ```
    @objc var isConnected: Bool { get }

    /// {"idle" | "connecting" | "connected" | "listening"} What the socket is doing.
    /// - Example:
    /// ```js
    /// if (sock.state === "idle") sock.connect("localhost", 6379)
    /// ```
    @objc var state: String { get }

    /// Whether the socket is currently listening for incoming connections.
    /// - Example:
    /// ```js
    /// console.log(server.isListening)
    /// ```
    @objc var isListening: Bool { get }

    /// Whether the socket's connection is encrypted with TLS.
    /// - Example:
    /// ```js
    /// console.log(sock.isSecure)
    /// ```
    @objc var isSecure: Bool { get }

    /// The host of the connected peer, or `null` if the socket isn't connected over TCP.
    /// - Example:
    /// ```js
    /// console.log("Connected to " + sock.remoteHost + ":" + sock.remotePort)
    /// ```
    @objc var remoteHost: String? { get }

    /// The port of the connected peer, or 0 if the socket isn't connected over TCP.
    /// - Example:
    /// ```js
    /// console.log(sock.remotePort)
    /// ```
    @objc var remotePort: Int { get }

    /// The local address of the connection, or `null` if the socket isn't connected over TCP.
    /// - Example:
    /// ```js
    /// console.log(sock.localHost)
    /// ```
    @objc var localHost: String? { get }

    /// The local port of the connection, or the port a listening socket is listening on. 0 if
    /// neither applies, including while a listener is still starting up.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback((event, sock) => {
    ///     if (event === "listening") console.log("Listening on port " + sock.localPort)
    /// }).listen(0)
    /// ```
    @objc var localPort: Int { get }

    /// The path of the Unix domain socket this socket is connected to or listening on, or
    /// `null` if it isn't using a Unix domain socket.
    /// - Example:
    /// ```js
    /// console.log(sock.unixPath)
    /// ```
    @objc var unixPath: String? { get }

    /// The connections a listening socket has accepted that are still connected.
    /// - Example:
    /// ```js
    /// server.clients.forEach(client => client.write("Shutting down\n"))
    /// ```
    @objc var clients: [HSSocket] { get }

    /// How long, in seconds, connecting may take, including any TLS handshake. When it expires,
    /// the callback receives an `"error"` event and the socket disconnects. 0 (or any negative
    /// number) means no timeout. Defaults to `hs.socket.connectTimeout`.
    /// - Example:
    /// ```js
    /// sock.connectTimeout = 5
    /// ```
    @objc var connectTimeout: Double { get set }

    /// How long, in seconds, a queued read may wait with no data arriving. The timer runs only
    /// while a read is queued, and restarts whenever data arrives, so a slow but steady transfer
    /// doesn't time out, and nor does a connection that's quiet while no read is queued. When it
    /// expires, the callback receives an `"error"` event and the socket disconnects. 0 (or any
    /// negative number) means no timeout. Defaults to `hs.socket.readTimeout`.
    ///
    /// - Note: Protocols where the peer can stay quiet for a long time while a read is queued (e.g. waiting for the next line of a notification stream) usually want no read timeout
    /// - Example:
    /// ```js
    /// sock.readTimeout = 30
    /// ```
    @objc var readTimeout: Double { get set }

    /// Sets the callback that receives this socket's events.
    ///
    /// The callback receives the event name, the socket, and event-specific arguments:
    /// - `"connected"` - `connect()`/`connectUnix()` succeeded.
    /// - `"listening"` - `listen()`/`listenUnix()` succeeded, and `localPort` is now set.
    /// - `"connection"` - a listening socket accepted a connection; the third argument is the new
    ///   `HSSocket`, which has the same callback. Queue a read on it to start receiving.
    /// - `"data"` - a read completed; the third argument is a `Uint8Array` and the fourth is the
    ///   read's tag.
    /// - `"error"` - something went wrong; the third argument is a description. If it ended the
    ///   connection, a `"disconnected"` event follows.
    /// - `"disconnected"` - the connection closed, or the socket stopped listening, for any
    ///   reason, including calling `disconnect()`. Data received that no read had asked for yet
    ///   is discarded.
    ///
    /// An `"error"` event on its own never changes the socket's state: errors such as calling
    /// `connect()` on a socket that is already connecting, or writing to an idle socket, leave it
    /// as it was. Every connection that ends, and every listening socket that stops, gets a
    /// `"disconnected"` event, after the `"error"` that caused it, if any. So reconnecting belongs
    /// in the `"disconnected"` handler, not the `"error"` one.
    ///
    /// When the peer closes the connection, data already received for the first queued read is
    /// delivered to it in a last `"data"` event, before `"disconnected"`, even though the read
    /// isn't satisfied: it may be missing its delimiter, or be shorter than asked for. This is
    /// how to receive the end of a stream that the peer ends by closing, such as an HTTP/1.0
    /// response body.
    ///
    /// - Parameter callback: {((event: "connected" | "listening" | "connection" | "data" | "error" | "disconnected", socket: HSSocket, data?: Uint8Array | HSSocket | string, tag?: number) => void) | null} The event handler, or `null` to remove it.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.setCallback((event, sock, data, tag) => {
    ///     if (event === "data") console.log(hs.socket.decodeText(data))
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSSocket

    /// Connects to a TCP server. The callback receives `"connected"` once the connection is
    /// ready, or `"error"` if it fails.
    ///
    /// - Note: A connected socket, and its callback, stay alive until it disconnects, even if you don't keep a reference to it
    /// - Parameter host: The host name or IP address to connect to.
    /// - Parameter port: The TCP port to connect to.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback((event, sock, data) => {
    ///     if (event === "connected") sock.write("GET / HTTP/1.0\r\n\r\n").readUntil("\r\n\r\n")
    ///     if (event === "data") console.log(hs.socket.decodeText(data))
    /// }).connect("example.com", 80)
    /// ```
    @objc @discardableResult func connect(_ host: String, _ port: Int) -> HSSocket

    /// Connects to a Unix domain socket. The callback receives `"connected"` once the connection
    /// is ready, or `"error"` if it fails.
    ///
    /// - Note: A connected socket, and its callback, stay alive until it disconnects, even if you don't keep a reference to it
    /// - Parameter path: The path of the Unix domain socket.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback(handler).connectUnix("/var/run/mysql.sock")
    /// ```
    @objc @discardableResult func connectUnix(_ path: String) -> HSSocket

    /// Listens for incoming TCP connections. The callback receives `"listening"` once the socket
    /// is ready, then `"connection"` for each client that connects.
    ///
    /// By default the socket listens on all network interfaces. Pass one of this Mac's IP
    /// addresses to accept connections only on that address (and so only on the interface that
    /// has it), e.g. `"127.0.0.1"` to accept connections only from this Mac. Use
    /// `hs.network.addresses()` to find an interface's addresses.
    /// If the interface's address can change (e.g. it comes from DHCP), watch
    /// `State:/Network/Interface/<name>/IPv4` with `hs.network.configurationWatcher()` and listen again
    /// when it does.
    ///
    /// - Note: A listening socket, and its callback, stay alive until it stops listening, even if you don't keep a reference to it
    /// - Parameter port: The TCP port to listen on, or 0 to let the system choose one (see `localPort`).
    /// - Parameter address?: A local IPv4 or IPv6 address to listen on. Defaults to all addresses.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback((event, sock, data) => {
    ///     if (event === "connection") data.write("Hello!\n").readUntil("\n")
    ///     if (event === "data") sock.write(data)
    /// }).listen(9000)
    ///
    /// // Only reachable from this Mac
    /// hs.socket.create().setCallback(handler).listen(9001, "127.0.0.1")
    /// ```
    @objc @discardableResult func listen(_ port: Int, _ address: String?) -> HSSocket

    /// Listens for incoming connections on a Unix domain socket. A stale socket file left at
    /// `path` is replaced, and the file is removed when the socket stops listening.
    ///
    /// - Note: A listening socket, and its callback, stay alive until it stops listening, even if you don't keep a reference to it
    /// - Parameter path: The path to create the Unix domain socket at.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback(handler).listenUnix("/tmp/hammerspoon.sock")
    /// ```
    @objc @discardableResult func listenUnix(_ path: String) -> HSSocket

    /// Makes the next `connect()` use TLS. The server's certificate is checked against the
    /// system's trusted certificates and against `peerName`, or the host passed to `connect()`.
    ///
    /// - Parameter peerName?: The name the server's certificate must match, if it differs from the host you connect to.
    /// - Parameter allowUntrusted?: `true` to accept any certificate, e.g. a self-signed one. This makes the connection vulnerable to interception, so only use it for testing.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().enableTLS().setCallback(handler).connect("example.com", 443)
    /// ```
    @objc @discardableResult func enableTLS(_ peerName: String?, _ allowUntrusted: Bool) -> HSSocket

    /// Makes the next `listen()` use TLS, presenting the certificate and private key stored in a
    /// PKCS#12 (`.p12`) file. If the file can't be loaded, `listen()` reports an error instead of
    /// listening without encryption.
    ///
    /// A PKCS#12 file can be exported from Keychain Access, or made from a certificate and key
    /// with `openssl pkcs12 -export -in cert.pem -inkey key.pem -out server.p12`.
    ///
    /// - Note: TLS isn't supported on Unix domain sockets, so `listenUnix()` reports an error if this has been called
    /// - Parameter path: The path to the PKCS#12 file.
    /// - Parameter passphrase?: The passphrase protecting the file. Defaults to an empty passphrase.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback(handler).enableServerTLS("~/.config/server.p12", "secret").listen(8443)
    /// ```
    @objc @discardableResult func enableServerTLS(_ path: String, _ passphrase: String?) -> HSSocket

    /// Makes the next `listen()` use TLS, presenting a certificate and private key (an identity)
    /// from the keychain. The identity is found by its certificate's name, as Keychain Access
    /// shows it (usually the certificate's common name). If no identity has that name, `listen()`
    /// reports an error instead of listening without encryption.
    ///
    /// - Note: macOS may ask for permission to use the private key the first time a client connects
    /// - Note: TLS isn't supported on Unix domain sockets, so `listenUnix()` reports an error if this has been called
    /// - Parameter name: The name of the certificate, e.g. `"myhost.local"`.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.create().setCallback(handler).enableServerTLSFromKeychain("myhost.local").listen(8443)
    /// ```
    @objc @discardableResult func enableServerTLSFromKeychain(_ name: String) -> HSSocket

    /// Queues a read that completes once `delimiter` arrives. The callback receives the data up
    /// to and including the delimiter.
    ///
    /// - Parameter delimiter: The text that ends the read, e.g. `"\n"`. It is matched as UTF-8 bytes.
    /// - Parameter tag?: A number passed back to the callback with the data. Defaults to 0.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.readUntil("\r\n", 1)
    /// ```
    @objc @discardableResult func readUntil(_ delimiter: String, _ tag: Int) -> HSSocket

    /// Queues a read that completes once exactly `length` bytes have arrived.
    ///
    /// - Parameter length: The number of bytes to read.
    /// - Parameter tag?: A number passed back to the callback with the data. Defaults to 0.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.readBytes(4, 2)
    /// ```
    @objc @discardableResult func readBytes(_ length: Int, _ tag: Int) -> HSSocket

    /// Queues a read that completes with whatever data is available, as soon as there is any.
    ///
    /// - Parameter tag?: A number passed back to the callback with the data. Defaults to 0.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.readAvailable()
    /// ```
    @objc @discardableResult func readAvailable(_ tag: Int) -> HSSocket

    /// Sends text over the connection, encoded as UTF-8. Writes are sent in order, and can be
    /// made before the connection is ready.
    ///
    /// - Parameter text: The text to send.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.write("HELO example.com\r\n")
    /// ```
    @objc @discardableResult func write(_ text: String) -> HSSocket

    /// Sends raw bytes over the connection.
    ///
    /// - Parameter bytes: {Uint8Array | ArrayBuffer} The bytes to send. Any typed array is accepted.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.writeBytes(new Uint8Array([0x01, 0x02, 0x03]))
    /// ```
    @objc @discardableResult func writeBytes(_ bytes: JSValue) -> HSSocket

    /// Closes the connection after sending any data already written, or stops listening. A
    /// listening socket also disconnects every client it accepted. Queued reads, and data received
    /// that no read has asked for yet, are discarded.
    ///
    /// The socket can be connected or listen again afterwards.
    ///
    /// - Note: The callback receives `"disconnected"` (for this socket, and for each client of a listening socket) before `disconnect()` returns, so update any state the handler relies on before calling it
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.write("QUIT\r\n").disconnect()
    /// ```
    @objc @discardableResult func disconnect() -> HSSocket

    /// Disconnects the socket and releases its callback. Unlike `disconnect()`, the callback isn't
    /// called.
    /// - Example:
    /// ```js
    /// sock.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSocket: NSObject, HSSocketAPI, HSTrackedObject {
    @objc var typeName = "HSSocket"
    @objc let identifier = UUID().uuidString

    @objc func toString() -> String {
        let target = unixPath ?? remoteHost.map { "\($0):\(remotePort)" } ?? (localPort > 0 ? "port \(localPort)" : nil)
        return "<\(typeName): \(currentState.rawValue)\(target.map { ", \($0)" } ?? "")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    /// Reads waiting for a delimiter give up once this much data is buffered without finding it,
    /// so a peer that never sends one can't exhaust memory.
    static let maximumBufferedBytes = 16 * 1024 * 1024

    /// How much data is received before any read asks for it
    static let readAheadBytes = 1024 * 1024

    private enum State: String {
        case idle, connecting, connected, listening

        var isActive: Bool {
            switch (self) {
            case .idle:
                return false
            case .connecting, .connected, .listening:
                return true
            }
        }
    }

    private enum Event: String {
        case connected, listening, connection, data, error, disconnected
    }

    /// The identity a listening socket presents to its clients, or why it couldn't be loaded.
    private enum ServerTLS {
        case identity(SecIdentity)
        case unavailable(String)
    }

    private enum ReadRequest {
        case delimiter([UInt8], tag: Int)
        case length(Int, tag: Int)
        case available(tag: Int)

        var tag: Int {
            switch self {
            case .delimiter(_, let tag), .length(_, let tag), .available(let tag): return tag
            }
        }
    }

    private struct WeakSocket {
        weak var socket: HSSocket?
    }

    // Any state but idle is active: a connecting, connected or listening socket stays alive with
    // its callback until it stops, even if the user dropped their reference to it.
    private var currentState: State = .idle {
        didSet { tracker?.setActive(self, currentState.isActive) }
    }

    private weak var tracker: HSObjectTracker<HSSocket>?
    private var callback: JSCallback?

    private var connection: NWConnection?
    private var listener: NWListener?
    private var listenerPath: String?
    private var connectedPath: String?
    private var acceptedClients: [WeakSocket] = []
    /// The listening socket that accepted this one, which is told once it's ready
    private weak var acceptingSocket: HSSocket?

    private var tlsEnabled = false
    private var tlsPeerName: String?
    private var tlsAllowUntrusted = false
    private var connectionUsesTLS = false
    private var serverTLS: ServerTLS?
    private var listenerUsesTLS = false

    private var buffer: [UInt8] = []
    /// How far into `buffer` the current delimiter read has already searched
    private var delimiterSearchOffset = 0
    private var pendingReads: [ReadRequest] = []
    private var isReceiving = false
    private var isProcessingReads = false
    private var timeoutWorkItem: DispatchWorkItem?

    @objc var connectTimeout: Double
    @objc var readTimeout: Double

    init(tracker: HSObjectTracker<HSSocket>, connectTimeout: Double, readTimeout: Double) {
        self.tracker = tracker
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
        super.init()
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSSocket(\(identifier))")
    }

    // MARK: - Properties

    @objc var state: String { currentState.rawValue }
    @objc var isConnected: Bool { currentState == .connected }
    @objc var isListening: Bool { currentState == .listening }
    @objc var isSecure: Bool { currentState == .connected && connectionUsesTLS }

    private var remoteEndpoint: NWEndpoint? { connection?.currentPath?.remoteEndpoint }
    private var localEndpoint: NWEndpoint? { connection?.currentPath?.localEndpoint }

    @objc var remoteHost: String? { Self.host(of: remoteEndpoint) }
    @objc var remotePort: Int { Self.port(of: remoteEndpoint) }
    @objc var localHost: String? { Self.host(of: localEndpoint) }

    @objc var localPort: Int {
        if let port = listener?.port, listenerPath == nil { return Int(port.rawValue) }
        return Self.port(of: localEndpoint)
    }

    @objc var unixPath: String? {
        switch currentState {
        case .listening: return listenerPath
        case .connecting, .connected: return connectedPath
        case .idle: return nil
        }
    }

    @objc var clients: [HSSocket] {
        acceptedClients = acceptedClients.filter { $0.socket != nil }
        return acceptedClients.compactMap(\.socket).filter(\.isConnected)
    }

    // MARK: - Configuration

    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSSocket {
        self.callback?.detach(from: self)
        self.callback = callback.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        return self
    }

    @objc @discardableResult func enableTLS(_ peerName: String?, _ allowUntrusted: Bool) -> HSSocket {
        tlsEnabled = true
        tlsPeerName = normalizedOptionalString(peerName)
        tlsAllowUntrusted = allowUntrusted
        return self
    }

    @objc @discardableResult func enableServerTLS(_ path: String, _ passphrase: String?) -> HSSocket {
        // Checked against the arguments JS actually passed, since JSExport turns an omitted
        // passphrase into "undefined", which is also a valid passphrase
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
        let passphraseGiven = arguments.count > 1 && arguments[1].isString
        serverTLS = Self.loadIdentity(pkcs12At: path, passphrase: passphraseGiven ? passphrase ?? "" : "")
        logServerTLSFailure()
        return self
    }

    @objc @discardableResult func enableServerTLSFromKeychain(_ name: String) -> HSSocket {
        serverTLS = Self.findIdentity(named: name)
        logServerTLSFailure()
        return self
    }

    private func logServerTLSFailure() {
        if case .unavailable(let message) = serverTLS {
            AKError("HSSocket(\(identifier)): \(message)")
        }
    }

    // MARK: - Connecting

    @objc @discardableResult func connect(_ host: String, _ port: Int) -> HSSocket {
        guard requireIdle("connect") else { return self }
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), (1...65535).contains(port) else {
            AKWarning("HSSocket(\(identifier)): connect() needs a host and a port from 1 to 65535")
            emitError("Invalid host or port")
            return self
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        startConnection(NWConnection(to: endpoint, using: makeParameters(serverName: host)),
                        path: nil, usesTLS: tlsEnabled)
        return self
    }

    @objc @discardableResult func connectUnix(_ path: String) -> HSSocket {
        guard requireIdle("connectUnix") else { return self }
        guard !path.isEmpty else {
            emitError("Invalid socket path")
            return self
        }
        startConnection(NWConnection(to: .unix(path: path), using: .tcp), path: path, usesTLS: false)
        return self
    }

    private func startConnection(_ connection: NWConnection, path: String?, usesTLS: Bool) {
        self.connection = connection
        connectedPath = path
        connectionUsesTLS = usesTLS
        currentState = .connecting
        connection.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                self?.connectionStateChanged(newState, on: connection)
            }
        }
        startTimeout(after: connectTimeout, reason: "Connection timed out")
        connection.start(queue: .main)
    }

    /// Starts a connection accepted by a listening socket. It becomes `.connected`, and is
    /// announced to the listener, once it's ready.
    fileprivate func startAccepted(_ connection: NWConnection, by listener: HSSocket, path: String?) {
        acceptingSocket = listener
        startConnection(connection, path: path, usesTLS: listener.listenerUsesTLS)
    }

    private func connectionStateChanged(_ newState: NWConnection.State, on connection: NWConnection) {
        guard connection === self.connection else { return }
        switch newState {
        case .ready:
            guard currentState == .connecting else { return }
            cancelTimeout()
            currentState = .connected
            if let acceptingSocket {
                self.acceptingSocket = nil
                acceptingSocket.clientConnected(self)
            } else {
                emit(.connected)
            }
            processReads()
        case .waiting(let error), .failed(let error):
            // A connection that can't be made (e.g. refused) waits for the network to change
            // rather than failing, which for a socket API is just a failure.
            teardown(error: Self.describe(error), graceful: false)
        default:
            break
        }
    }

    // MARK: - Listening

    @objc @discardableResult func listen(_ port: Int, _ address: String?) -> HSSocket {
        guard requireIdle("listen") else { return self }
        guard (0...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            emitError("Invalid port \(port)")
            return self
        }
        var localHost: NWEndpoint.Host?
        if let address = normalizedOptionalString(address) {
            if let ipv4 = IPv4Address(address) {
                localHost = .ipv4(ipv4)
            } else if let ipv6 = IPv6Address(address) {
                localHost = .ipv6(ipv6)
            } else {
                emitError("\(address) is not an IP address")
                return self
            }
        }
        let parameters: NWParameters
        switch serverTLS {
        case .unavailable(let message):
            emitError(message)
            return self
        case .identity(let identity):
            guard let secIdentity = sec_identity_create(identity) else {
                emitError("The TLS identity can't be used")
                return self
            }
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        case nil:
            parameters = .tcp
        }
        parameters.allowLocalEndpointReuse = true
        if let localHost {
            parameters.requiredLocalEndpoint = .hostPort(host: localHost, port: nwPort)
        }
        startListener(parameters: parameters, port: localHost == nil ? nwPort : nil, path: nil, usesTLS: serverTLS != nil)
        return self
    }

    @objc @discardableResult func listenUnix(_ path: String) -> HSSocket {
        guard requireIdle("listenUnix") else { return self }
        guard !path.isEmpty else {
            emitError("Invalid socket path")
            return self
        }
        guard serverTLS == nil else {
            emitError("TLS isn't supported on Unix domain sockets")
            return self
        }
        guard removeStaleSocketFile(at: path) else {
            emitError("Another program is already listening at \(path)")
            return self
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        startListener(parameters: parameters, port: nil, path: path, usesTLS: false)
        return self
    }

    private func startListener(parameters: NWParameters, port: NWEndpoint.Port?, path: String?, usesTLS: Bool) {
        if tlsEnabled {
            AKWarning("HSSocket(\(identifier)): enableTLS() only applies to connect(), use enableServerTLS() to listen with TLS")
        }
        let listener: NWListener
        do {
            if let port {
                listener = try NWListener(using: parameters, on: port)
            } else {
                listener = try NWListener(using: parameters)
            }
        } catch {
            AKError("HSSocket(\(identifier)): could not create listener: \(error)")
            emitError(Self.describe(error))
            return
        }

        self.listener = listener
        listenerPath = path
        listenerUsesTLS = usesTLS
        currentState = .listening
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.accept(connection, on: listener)
            }
        }
        listener.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                self?.listenerStateChanged(newState, on: listener)
            }
        }
        listener.start(queue: .main)
    }

    private func listenerStateChanged(_ newState: NWListener.State, on listener: NWListener) {
        guard listener === self.listener else { return }
        switch newState {
        case .ready:
            AKDebug("HSSocket(\(identifier)): listening on \(listenerPath ?? "port \(localPort)")")
            emit(.listening)
        case .waiting(let error), .failed(let error):
            teardown(error: Self.describe(error), graceful: false)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection, on listener: NWListener) {
        guard listener === self.listener, let tracker else {
            connection.cancel()
            return
        }
        let client = HSSocket(tracker: tracker, connectTimeout: connectTimeout, readTimeout: readTimeout)
        tracker.add(client)
        if let value = callback?.value {
            client.callback = JSCallback(value: value, owner: client)
        }
        acceptedClients = acceptedClients.filter { $0.socket != nil }
        acceptedClients.append(WeakSocket(socket: client))
        client.startAccepted(connection, by: self, path: listenerPath)
    }

    fileprivate func clientConnected(_ client: HSSocket) {
        emit(.connection, client)
    }

    /// Removes a socket file left at `path` by a listener that has gone, so its path can be reused.
    /// - Returns: `false` if something is still listening there
    private func removeStaleSocketFile(at path: String) -> Bool {
        var info = stat()
        guard unsafe lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return true }
        guard !unixSocketAcceptsConnections(at: path) else { return false }
        unsafe unlink(path)
        return true
    }

    // MARK: - Reading

    @objc @discardableResult func readUntil(_ delimiter: String, _ tag: Int) -> HSSocket {
        guard !delimiter.isEmpty else {
            AKWarning("HSSocket(\(identifier)): readUntil() needs a non-empty delimiter")
            return self
        }
        return queueRead(.delimiter(Array(delimiter.utf8), tag: tag))
    }

    @objc @discardableResult func readBytes(_ length: Int, _ tag: Int) -> HSSocket {
        guard length > 0 else {
            AKWarning("HSSocket(\(identifier)): readBytes() needs a length greater than 0")
            return self
        }
        return queueRead(.length(length, tag: tag))
    }

    @objc @discardableResult func readAvailable(_ tag: Int) -> HSSocket {
        queueRead(.available(tag: tag))
    }

    private func queueRead(_ request: ReadRequest) -> HSSocket {
        guard currentState != .listening else {
            AKWarning("HSSocket(\(identifier)): can't read from a listening socket, read from the sockets it accepts instead")
            return self
        }
        pendingReads.append(request)
        processReads()
        return self
    }

    /// Completes every queued read the buffer can satisfy, then receives more data if a read is
    /// still waiting.
    private func processReads() {
        // A read completed by the callback re-enters here; the loop below picks it up.
        guard !isProcessingReads else { return }
        isProcessingReads = true
        defer { isProcessingReads = false }

        while currentState == .connected, let request = pendingReads.first {
            guard let data = takeData(for: request) else { break }
            pendingReads.removeFirst()
            delimiterSearchOffset = 0
            cancelTimeout()
            emitData(data, tag: request.tag)
        }

        guard currentState == .connected else { return }
        guard let request = pendingReads.first else {
            // Keep receiving a little ahead of the reads, so a peer closing the connection is
            // noticed even when no read is queued
            if buffer.count < Self.readAheadBytes {
                receiveMore()
            }
            return
        }
        if case .delimiter = request, buffer.count > Self.maximumBufferedBytes {
            teardown(error: "Read exceeded \(Self.maximumBufferedBytes) bytes without finding the delimiter", graceful: false)
            return
        }
        if timeoutWorkItem == nil {
            startTimeout(after: readTimeout, reason: "Read timed out")
        }
        receiveMore()
    }

    /// Gives whatever is left in the buffer to the first queued read, which can no longer be
    /// satisfied because the peer closed the connection.
    private func deliverRemainingData() {
        guard currentState == .connected, !buffer.isEmpty, let request = pendingReads.first else { return }
        pendingReads.removeFirst()
        let data = buffer
        buffer.removeAll()
        delimiterSearchOffset = 0
        cancelTimeout()
        emitData(data, tag: request.tag)
    }

    /// Removes and returns the data `request` needs from the buffer, or `nil` if it isn't all
    /// there yet.
    private func takeData(for request: ReadRequest) -> [UInt8]? {
        let count: Int
        switch request {
        case .length(let length, _):
            guard buffer.count >= length else { return nil }
            count = length
        case .available:
            guard !buffer.isEmpty else { return nil }
            count = buffer.count
        case .delimiter(let delimiter, _):
            guard let end = findDelimiter(delimiter) else { return nil }
            count = end
        }
        let data = Array(buffer[..<count])
        buffer.removeFirst(count)
        return data
    }

    /// Returns the index just past the first occurrence of `delimiter` in the buffer.
    private func findDelimiter(_ delimiter: [UInt8]) -> Int? {
        let last = buffer.count - delimiter.count
        var start = delimiterSearchOffset
        while start <= last {
            if buffer[start] == delimiter[0] && buffer[start..<(start + delimiter.count)].elementsEqual(delimiter) {
                return start + delimiter.count
            }
            start += 1
        }
        // Next time, resume where a delimiter could still begin
        delimiterSearchOffset = max(0, last + 1)
        return nil
    }

    private func receiveMore() {
        guard !isReceiving, let connection else { return }
        isReceiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, connection === self.connection else { return }
                self.isReceiving = false
                if let content, !content.isEmpty {
                    self.buffer.append(contentsOf: content)
                    // The read timeout measures time without data, so arriving data restarts it
                    self.cancelTimeout()
                }
                self.processReads()
                // A "data" callback may have disconnected, or even reconnected, the socket
                guard connection === self.connection else { return }
                if let error {
                    self.teardown(error: Self.describe(error), graceful: false)
                } else if isComplete {
                    // The peer closed its end, so no more data will complete the first read
                    self.deliverRemainingData()
                    guard connection === self.connection else { return }
                    self.teardown(error: nil, graceful: false)
                }
            }
        }
    }

    // MARK: - Writing

    @objc @discardableResult func write(_ text: String) -> HSSocket {
        send(Data(text.utf8))
    }

    @objc @discardableResult func writeBytes(_ bytes: JSValue) -> HSSocket {
        guard let data = bytes.typedArrayBytes else {
            AKWarning("HSSocket(\(identifier)): writeBytes() needs a typed array or ArrayBuffer")
            emitError("writeBytes() needs a typed array or ArrayBuffer")
            return self
        }
        return send(Data(data))
    }

    private func send(_ data: Data) -> HSSocket {
        guard currentState == .connecting || currentState == .connected, let connection else {
            emitError("Can't write: the socket isn't connected")
            return self
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, let error, connection === self.connection else { return }
                self.teardown(error: Self.describe(error), graceful: false)
            }
        })
        return self
    }

    // MARK: - Disconnecting

    @objc @discardableResult func disconnect() -> HSSocket {
        teardown(error: nil, graceful: true)
        return self
    }

    @objc func destroy() {
        teardown(error: nil, graceful: true, notify: false)
        callback?.detach(from: self)
        callback = nil
    }

    /// Ends the connection or stops listening, then tells the callback.
    /// - Parameters:
    ///   - error: Why the socket closed, if it failed
    ///   - graceful: Whether to send data already written before closing
    ///   - notify: Whether to call the callback
    private func teardown(error: String?, graceful: Bool, notify: Bool = true) {
        guard currentState != .idle else { return }
        cancelTimeout()
        pendingReads.removeAll()
        buffer.removeAll()
        delimiterSearchOffset = 0
        isReceiving = false
        acceptingSocket = nil

        if let connection {
            connection.stateUpdateHandler = nil
            if graceful {
                // Closes our end once everything already written has been sent. The connection is
                // captured here, not self, and force-cancelled if the peer stops reading.
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            } else {
                connection.cancel()
            }
            self.connection = nil
        }
        connectedPath = nil

        // Clients are disconnected only once this socket's own state is cleared, since their
        // callbacks may disconnect or restart it. Each one's connection is noted, so a client that
        // a callback has meanwhile reconnected keeps its new connection.
        var clientsToDisconnect: [(client: HSSocket, connection: NWConnection)] = []
        if let listener {
            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
            self.listener = nil
            clientsToDisconnect = acceptedClients.compactMap { entry in
                guard let client = entry.socket, let connection = client.connection else { return nil }
                return (client, connection)
            }
            acceptedClients.removeAll()
            if let listenerPath {
                unsafe unlink(listenerPath)
                self.listenerPath = nil
            }
        }

        // Hold the callback and our wrapper before going inactive, since the callback may start
        // the socket again, and un-pinning afterwards would drop that new activity's pin.
        let function = notify ? callback?.value : nil
        let wrapper = function.flatMap { JSValue(object: self, in: $0.context) }
        currentState = .idle
        AKDebug("HSSocket(\(identifier)): disconnected\(error.map { ": \($0)" } ?? "")")

        if let function, let wrapper {
            if let error {
                _ = function.call(withArguments: [Event.error.rawValue, wrapper, error])
            }
            // A callback that reconnected the socket after the error has already moved on
            if currentState == .idle {
                _ = function.call(withArguments: [Event.disconnected.rawValue, wrapper])
            }
        }

        for (client, connection) in clientsToDisconnect where client.connection === connection {
            client.teardown(error: nil, graceful: true, notify: notify)
        }
    }

    // MARK: - Timeouts

    private func startTimeout(after timeout: Double, reason: String) {
        cancelTimeout()
        guard timeout > 0 else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.timeoutWorkItem = nil
                self?.teardown(error: reason, graceful: false)
            }
        }
        timeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    // MARK: - Helpers

    private func requireIdle(_ method: String) -> Bool {
        guard currentState == .idle else {
            AKWarning("HSSocket(\(identifier)): \(method)() called while \(currentState.rawValue), call disconnect() first")
            emitError("\(method)() called while the socket is \(currentState.rawValue)")
            return false
        }
        return true
    }

    private func makeParameters(serverName: String) -> NWParameters {
        guard tlsEnabled else { return .tcp }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        unsafe sec_protocol_options_set_tls_server_name(options, tlsPeerName ?? serverName)
        if tlsAllowUntrusted {
            sec_protocol_options_set_verify_block(options, acceptAnyCertificate, .main)
        }
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }

    private func emit(_ event: Event, _ arguments: Any...) {
        guard let function = callback?.value else { return }
        _ = function.call(withArguments: [event.rawValue, self] + arguments)
    }

    private func emitData(_ data: [UInt8], tag: Int) {
        guard let function = callback?.value, let bytes = function.context.makeUint8Array(data) else { return }
        _ = function.call(withArguments: [Event.data.rawValue, self, bytes, tag])
    }

    private func emitError(_ message: String) {
        emit(.error, message)
    }

    private static func host(of endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        switch host {
        case .name(let name, _): return name
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        @unknown default: return "\(host)"
        }
    }

    private static func port(of endpoint: NWEndpoint?) -> Int {
        guard case .hostPort(_, let port) = endpoint else { return 0 }
        return Int(port.rawValue)
    }

    // MARK: - Server identities

    /// Loads the identity in a PKCS#12 file, keeping it in memory rather than adding it to the keychain.
    private static func loadIdentity(pkcs12At path: String, passphrase: String) -> ServerTLS {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unavailable("Could not read \(path): \(error.localizedDescription)")
        }
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
            kSecImportToMemoryOnly as String: true,
        ]
        var items: CFArray?
        let status = unsafe SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else {
            return .unavailable("Could not load \(path): \(describe(status))")
        }
        let identity = (items as? [[String: Any]])?.lazy.compactMap { $0[kSecImportItemIdentity as String] }.first
        guard let identity = identity.flatMap(Self.asIdentity) else {
            return .unavailable("\(path) doesn't contain a certificate with its private key")
        }
        return .identity(identity)
    }

    /// Finds the keychain identity whose certificate is called `name`.
    private static func findIdentity(named name: String) -> ServerTLS {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .unavailable("Could not search the keychain: \(describe(status))")
        }
        let identities = (result as? [Any] ?? []).compactMap(Self.asIdentity)
        let match = identities.first { identity in
            var certificate: SecCertificate?
            guard unsafe SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return false }
            return SecCertificateCopySubjectSummary(certificate) as String? == name
        }
        guard let match else {
            return .unavailable("No certificate called \"\(name)\" with a private key was found in the keychain")
        }
        return .identity(match)
    }

    private static func asIdentity(_ value: Any) -> SecIdentity? {
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == SecIdentityGetTypeID() else { return nil }
        return (object as! SecIdentity)
    }

    private static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code): return unsafe String(cString: strerror(code.rawValue))
        case .tls(let status): return "TLS error: \(describe(status))"
        case .dns(let code): return "DNS lookup failed (\(code))"
        default: return error.localizedDescription
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? NWError { return describe(error) }
        return error.localizedDescription
    }
}

/// TLS verification that accepts any certificate, for `enableTLS(peerName, true)`.
///
/// `nonisolated` and at file scope, so it carries no main actor check if Security ever calls it
/// off the queue it was given.
nonisolated private func acceptAnyCertificate(_ metadata: sec_protocol_metadata_t, _ trust: sec_trust_t,
                                              _ complete: @escaping sec_protocol_verify_complete_t) {
    complete(true)
}

/// JSExport passes an omitted trailing optional string as the literal string "undefined".
nonisolated func normalizedOptionalString(_ value: String?) -> String? {
    guard let value, value != "undefined", value != "null" else { return nil }
    return value
}

/// Whether something is listening on the Unix domain socket at `path`, found by trying to connect.
/// A socket file whose listener has gone refuses the connection.
nonisolated private func unixSocketAcceptsConnections(at path: String) -> Bool {
    var address = sockaddr_un()
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        unsafe buffer.copyBytes(from: pathBytes)
    }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    // Non-blocking, so a listener with a full backlog can't stall the main thread
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    let result = withUnsafePointer(to: &address) { pointer in
        unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    return result == 0 || errno == EAGAIN || errno == EINPROGRESS
}
