//
//  HSUnixDatagramSocket.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin

// Like UDP, this is implemented with BSD sockets: Network.framework only supports Unix domain
// stream sockets.

// MARK: - Protocol

/// A Unix domain datagram socket, created by `hs.socket.createUnixDatagram()`.
///
/// A Unix domain datagram socket exchanges messages with other programs on this Mac through a
/// socket file. Each message arrives whole, as one `"data"` event. Other programs can only send
/// to it once it has been bound to a path with `bind()`, which creates the socket file there.
///
/// This is what tools such as Karabiner-Elements' `send_user_command` send to.
///
/// - Note: macOS limits datagrams sent by other programs to 2048 bytes unless they raise their send buffer size (see `sysctl net.local.dgram.maxdgram`). This socket raises its own, so it can send and receive up to 65536 bytes.
///
/// Do not instantiate `HSUnixDatagramSocket` directly - use `hs.socket.createUnixDatagram()`.
@objc protocol HSUnixDatagramSocketAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this socket (UUID string).
    /// - Example:
    /// ```js
    /// console.log(hs.socket.createUnixDatagram().identifier)
    /// ```
    @objc var identifier: String { get }

    /// Whether the socket has been bound to a path with `bind()`.
    /// - Example:
    /// ```js
    /// console.log(sock.isBound)
    /// ```
    @objc var isBound: Bool { get }

    /// Whether the socket is connected to a single peer with `connect()`.
    /// - Example:
    /// ```js
    /// console.log(sock.isConnected)
    /// ```
    @objc var isConnected: Bool { get }

    /// Whether the socket is currently receiving datagrams.
    /// - Example:
    /// ```js
    /// console.log(sock.isReceiving)
    /// ```
    @objc var isReceiving: Bool { get }

    /// The path the socket is bound to, or `null` if it isn't bound.
    /// - Example:
    /// ```js
    /// console.log(sock.localPath)
    /// ```
    @objc var localPath: String? { get }

    /// The path of the peer the socket is connected to, or `null` if it isn't connected.
    /// - Example:
    /// ```js
    /// console.log(sock.peerPath)
    /// ```
    @objc var peerPath: String? { get }

    /// Sets the callback that receives this socket's events.
    ///
    /// The callback receives the event name, the socket, and event-specific arguments:
    /// - `"data"` - a datagram arrived; the third argument is a `Uint8Array` and the fourth is the
    ///   sender's address, as `{path}`, or `null` if the sender's socket isn't bound to a path
    ///   (so it can't be replied to).
    /// - `"connected"` - `connect()` succeeded; the fourth argument is the peer's address.
    /// - `"error"` - something went wrong; the third argument is a description.
    ///
    /// - Parameter callback: {((event: "data" | "connected" | "error", socket: HSUnixDatagramSocket, data?: Uint8Array | string | null, address?: {path: string} | null) => void) | null} The event handler, or `null` to remove it.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.setCallback((event, sock, data, address) => {
    ///     if (event === "data") console.log("Received: " + hs.socket.decodeText(data))
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSUnixDatagramSocket

    /// Binds the socket to a path, creating a socket file there that other programs can send
    /// datagrams to. Call it before `connect()` or sending.
    ///
    /// A stale socket file left at the path by a socket that has gone is replaced, but binding
    /// fails if another socket is still using it. `close()` removes the socket file.
    ///
    /// - Parameter path: The path to create the socket file at, at most 103 bytes long, e.g. `"/tmp/hammerspoon.sock"`.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// // Receive Karabiner-Elements' send_user_command messages
    /// globalThis.karabiner = hs.socket.createUnixDatagram().setCallback((event, sock, data) => {
    ///     if (event === "data") console.log(JSON.parse(hs.socket.decodeText(data)).key)
    /// }).bind("/tmp/hammerspoon-karabiner.sock").receive()
    /// ```
    @objc @discardableResult func bind(_ path: String) -> HSUnixDatagramSocket

    /// Connects the socket to a single peer. Afterwards, `send()` needs no path, and only
    /// datagrams from that peer are received. The callback receives `"connected"` straight away.
    ///
    /// - Parameter path: The path of the peer's socket file.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.createUnixDatagram().connect("/tmp/other.sock").send("hello")
    /// ```
    @objc @discardableResult func connect(_ path: String) -> HSUnixDatagramSocket

    /// Sends text, encoded as UTF-8, as one datagram.
    ///
    /// - Parameter text: The text to send.
    /// - Parameter path?: The path of the socket file to send to. Omit it if the socket is connected.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.send("hello", "/tmp/other.sock")
    /// ```
    @objc @discardableResult func send(_ text: String, _ path: String?) -> HSUnixDatagramSocket

    /// Sends raw bytes as one datagram.
    ///
    /// - Parameter bytes: {Uint8Array | ArrayBuffer} The bytes to send. Any typed array is accepted.
    /// - Parameter path?: The path of the socket file to send to. Omit it if the socket is connected.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.sendBytes(new Uint8Array([0xFF, 0x00]), "/tmp/other.sock")
    /// ```
    @objc @discardableResult func sendBytes(_ bytes: JSValue, _ path: String?) -> HSUnixDatagramSocket

    /// Starts delivering every datagram that arrives to the callback, until `pause()` or
    /// `close()`. The socket must be bound first (see `bind()`).
    ///
    /// - Note: A receiving socket, and its callback, stay alive until it stops receiving, even if you don't keep a reference to it
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.bind("/tmp/hammerspoon.sock").receive()
    /// ```
    @objc @discardableResult func receive() -> HSUnixDatagramSocket

    /// Delivers the next datagram that arrives to the callback, then stops receiving.
    ///
    /// - Note: A receiving socket, and its callback, stay alive until it stops receiving, even if you don't keep a reference to it
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.bind("/tmp/hammerspoon.sock").send("ping", "/tmp/other.sock").receiveOne()
    /// ```
    @objc @discardableResult func receiveOne() -> HSUnixDatagramSocket

    /// Stops receiving datagrams. Datagrams that arrive meanwhile are queued by the system (up to
    /// its buffer size) and delivered once you receive again.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.pause()
    /// ```
    @objc @discardableResult func pause() -> HSUnixDatagramSocket

    /// Closes the socket immediately, and removes its socket file if it's bound. The socket can
    /// be bound, connected or used to send again afterwards.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// sock.close()
    /// ```
    @objc @discardableResult func close() -> HSUnixDatagramSocket

    /// Closes the socket and releases its callback.
    /// - Example:
    /// ```js
    /// sock.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSUnixDatagramSocket: NSObject, HSUnixDatagramSocketAPI, HSTrackedObject, DatagramEndpointOwner {
    @objc var typeName = "HSUnixDatagramSocket"
    @objc let identifier = UUID().uuidString

    @objc func toString() -> String {
        let status = endpoint == nil ? "closed" : (isConnected ? "connected" : (isBound ? "bound" : "open"))
        return "<\(typeName): \(status)\(localPath.map { ", \($0)" } ?? "")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    /// The largest datagram the socket sends or receives. Its send and receive buffers are raised
    /// to this, above the system's 2048 byte default.
    private static let maximumDatagramSize = 65536

    private enum Event: String {
        case data, connected, error
    }

    /// The socket file a bound socket created, so close() only removes that file, not one
    /// something else has since put at the same path
    private struct BoundFile {
        let path: String
        let device: dev_t
        let inode: ino_t
    }

    private weak var tracker: HSObjectTracker<HSUnixDatagramSocket>?
    private var callback: JSCallback?
    private var endpoint: DatagramEndpoint?
    private var boundFile: BoundFile?
    /// The peer's address, once connected
    private var peerAddress: Data?

    // Receiving is pending activity: the socket stays alive with its callback until it stops,
    // even if the user dropped their reference to it.
    private var receiveMode: DatagramReceiveMode = .off {
        didSet { tracker?.setActive(self, receiveMode.isActive) }
    }

    init(tracker: HSObjectTracker<HSUnixDatagramSocket>) {
        self.tracker = tracker
        super.init()
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSUnixDatagramSocket(\(identifier))")
    }

    // MARK: - Properties

    @objc var isBound: Bool { boundFile != nil }
    @objc var isConnected: Bool { peerAddress != nil }
    @objc var isReceiving: Bool { receiveMode != .off }
    @objc var localPath: String? { boundFile?.path }
    @objc var peerPath: String? { peerAddress.flatMap(unixSocketPath) }

    // MARK: - Configuration

    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSUnixDatagramSocket {
        self.callback?.detach(from: self)
        self.callback = callback.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        return self
    }

    // MARK: - Binding

    @objc @discardableResult func bind(_ path: String) -> HSUnixDatagramSocket {
        guard endpoint == nil else {
            emitError("bind() must be called before the socket connects or sends")
            return self
        }
        guard let address = validAddress(path) else { return self }
        guard removeStaleUnixSocketFile(at: path, type: SOCK_DGRAM) else {
            emitError("Another socket is already using \(path)")
            return self
        }
        guard let endpoint = makeEndpoint() else { return self }
        let result = unsafe address.withUnsafeBytes { raw in
            // swiftlint:disable:next force_unwrapping
            unsafe Darwin.bind(endpoint.fd, raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
        }
        guard result == 0 else {
            let message = currentSocketErrorMessage()
            closeEndpoint()
            emitError("Could not bind to \(path): \(message)")
            return self
        }
        var info = stat()
        _ = unsafe lstat(path, &info)
        boundFile = BoundFile(path: path, device: info.st_dev, inode: info.st_ino)
        startReadingIfNeeded()
        AKDebug("HSUnixDatagramSocket(\(identifier)): bound to \(path)")
        return self
    }

    // MARK: - Connecting and sending

    @objc @discardableResult func connect(_ path: String) -> HSUnixDatagramSocket {
        guard let address = validAddress(path), let endpoint = endpoint ?? makeEndpoint() else { return self }
        let result = unsafe address.withUnsafeBytes { raw in
            // swiftlint:disable:next force_unwrapping
            unsafe Darwin.connect(endpoint.fd, raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
        }
        guard result == 0 else {
            emitError("Could not connect to \(path): \(currentSocketErrorMessage())")
            return self
        }
        peerAddress = address
        emit(.connected, NSNull(), ["path": path])
        return self
    }

    @objc @discardableResult func send(_ text: String, _ path: String?) -> HSUnixDatagramSocket {
        performSend(Data(text.utf8), to: path)
    }

    @objc @discardableResult func sendBytes(_ bytes: JSValue, _ path: String?) -> HSUnixDatagramSocket {
        guard let data = bytes.typedArrayBytes else {
            emitError("sendBytes() needs a typed array or ArrayBuffer")
            return self
        }
        return performSend(Data(data), to: path)
    }

    private func performSend(_ data: Data, to path: String?) -> HSUnixDatagramSocket {
        guard data.count <= Self.maximumDatagramSize else {
            emitError("A datagram can't be larger than \(Self.maximumDatagramSize) bytes")
            return self
        }
        let sent: Int
        if let path = normalizedOptionalString(path) {
            guard let address = validAddress(path) else { return self }
            if let peerAddress, address != peerAddress {
                emitError("A connected socket can only send to its peer")
                return self
            }
            guard let endpoint = endpoint ?? makeEndpoint() else { return self }
            sent = unsafe data.withUnsafeBytes { bytes in
                unsafe address.withUnsafeBytes { raw in
                    unsafe sendto(endpoint.fd, bytes.baseAddress, bytes.count, 0,
                                  // swiftlint:disable:next force_unwrapping
                                  raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
                }
            }
        } else {
            guard peerAddress != nil, let endpoint else {
                emitError("send() needs a path unless the socket is connected")
                return self
            }
            sent = unsafe data.withUnsafeBytes { bytes in
                unsafe Darwin.send(endpoint.fd, bytes.baseAddress, bytes.count, 0)
            }
        }
        if sent < 0 {
            emitError("Send failed: \(currentSocketErrorMessage())")
        }
        return self
    }

    // MARK: - Receiving

    @objc @discardableResult func receive() -> HSUnixDatagramSocket {
        startReceiving(.continuous)
    }

    @objc @discardableResult func receiveOne() -> HSUnixDatagramSocket {
        startReceiving(.once)
    }

    private func startReceiving(_ mode: DatagramReceiveMode) -> HSUnixDatagramSocket {
        // An unbound socket has no address, so nothing can send to it
        guard isBound else {
            emitError("The socket has no path to receive on: call bind() first")
            return self
        }
        receiveMode = mode
        startReadingIfNeeded()
        return self
    }

    @objc @discardableResult func pause() -> HSUnixDatagramSocket {
        receiveMode = .off
        endpoint?.stopReading()
        return self
    }

    private func startReadingIfNeeded() {
        guard receiveMode != .off else { return }
        endpoint?.startReading()
    }

    func readDatagram(from endpoint: DatagramEndpoint) {
        guard receiveMode != .off, endpoint === self.endpoint,
              let result = endpoint.receive(maximumSize: Self.maximumDatagramSize) else { return }
        let datagram: (data: [UInt8], address: Data)
        switch result {
        case .success(let received):
            datagram = received
        case .failure(let error):
            emitError("Receive failed: \(error.message)")
            return
        }

        let function = callback?.value
        if receiveMode == .once {
            // Stop before calling back, since the callback may ask for another datagram
            pause()
        }
        guard let function, let bytes = function.context.makeUint8Array(datagram.data) else { return }
        let address: Any = unixSocketPath(from: datagram.address).map { ["path": $0] } ?? NSNull()
        _ = function.call(withArguments: [Event.data.rawValue, self, bytes, address])
    }

    // MARK: - Closing

    @objc @discardableResult func close() -> HSUnixDatagramSocket {
        receiveMode = .off
        closeEndpoint()
        return self
    }

    @objc func destroy() {
        close()
        callback?.detach(from: self)
        callback = nil
    }

    private func closeEndpoint() {
        endpoint?.close()
        endpoint = nil
        peerAddress = nil
        if let boundFile {
            var info = stat()
            if unsafe lstat(boundFile.path, &info) == 0, info.st_dev == boundFile.device, info.st_ino == boundFile.inode {
                unsafe unlink(boundFile.path)
            }
            self.boundFile = nil
        }
    }

    // MARK: - System sockets

    /// The `sockaddr_un` for `path`, or `nil`, after reporting an error, if it can't be one.
    private func validAddress(_ path: String) -> Data? {
        guard let address = unixSocketAddress(path: path) else {
            emitError(path.isEmpty ? "Invalid socket path"
                                   : "Socket paths can't be longer than \(maximumUnixSocketPathLength) bytes: \(path)")
            return nil
        }
        return address
    }

    /// Creates a non-blocking socket, and makes it the socket's endpoint.
    private func makeEndpoint() -> DatagramEndpoint? {
        let fd = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            emitError("Could not create socket: \(currentSocketErrorMessage())")
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        // Unix datagrams can't be larger than the sender's send buffer
        setSocketOption(fd, SOL_SOCKET, SO_SNDBUF, Int32(Self.maximumDatagramSize))
        setSocketOption(fd, SOL_SOCKET, SO_RCVBUF, Int32(Self.maximumDatagramSize * 4))

        guard let endpoint = DatagramEndpoint(fd: fd, family: AF_UNIX, owner: self) else {
            emitError("Could not monitor socket")
            return nil
        }
        self.endpoint = endpoint
        startReadingIfNeeded()
        return endpoint
    }

    // MARK: - Callback

    private func emit(_ event: Event, _ arguments: Any...) {
        guard let function = callback?.value else { return }
        _ = function.call(withArguments: [event.rawValue, self] + arguments)
    }

    private func emitError(_ message: String) {
        AKDebug("HSUnixDatagramSocket(\(identifier)): \(message)")
        emit(.error, message)
    }
}
