//
//  HSUDPSocket.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin
import HammerspoonSDK

// UDP is implemented with BSD sockets rather than Network.framework, which can't send
// broadcasts, and models UDP as one connection per remote peer rather than a single socket that
// receives from anyone and reports who sent each datagram.

// MARK: - Protocol

/// A UDP socket, created by `hs.socket.createUDP()`.
///
/// A UDP socket can send datagrams to any host, or be connected to a single peer, and can
/// receive datagrams once it has a local port: either one chosen with `bind()`, or one the system
/// assigns when it first connects or sends.
///
/// IPv4 and IPv6 are both supported, using a separate system socket for each.
///
/// Do not instantiate `HSUDPSocket` directly - use `hs.socket.createUDP()`.
@objc protocol HSUDPSocketAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this socket (UUID string).
    /// - Example:
    /// ```js
    /// console.log(hs.socket.createUDP().identifier)
    /// ```
    @objc var identifier: String { get }

    /// Whether the socket has been bound to a local port with `bind()`.
    /// - Example:
    /// ```js
    /// console.log(udp.isBound)
    /// ```
    @objc var isBound: Bool { get }

    /// Whether the socket is connected to a single peer with `connect()`.
    /// - Example:
    /// ```js
    /// console.log(udp.isConnected)
    /// ```
    @objc var isConnected: Bool { get }

    /// Whether the socket is currently receiving datagrams.
    /// - Example:
    /// ```js
    /// console.log(udp.isReceiving)
    /// ```
    @objc var isReceiving: Bool { get }

    /// The local port the socket is using, or 0 if it doesn't have one yet.
    /// - Example:
    /// ```js
    /// console.log(udp.bind(0).localPort)
    /// ```
    @objc var localPort: Int { get }

    /// Whether the socket may send to broadcast addresses (e.g. `255.255.255.255`). Defaults to
    /// `false`. Broadcasts are IPv4 only.
    /// - Example:
    /// ```js
    /// udp.broadcast = true
    /// udp.send("hello", "255.255.255.255", 9999)
    /// ```
    @objc var broadcast: Bool { get set }

    /// Whether other sockets may bind to the same port, e.g. so several programs can receive the
    /// same broadcasts. Defaults to `false`. Set it before calling `bind()`.
    /// - Example:
    /// ```js
    /// udp.reusePort = true
    /// udp.bind(9999)
    /// ```
    @objc var reusePort: Bool { get set }

    /// Whether the socket uses IPv4. Defaults to `true`. Set it before the socket binds,
    /// connects or sends.
    /// - Example:
    /// ```js
    /// udp.ipv4Enabled = false
    /// ```
    @objc var ipv4Enabled: Bool { get set }

    /// Whether the socket uses IPv6. Defaults to `true`. Set it before the socket binds,
    /// connects or sends.
    /// - Example:
    /// ```js
    /// udp.ipv6Enabled = false
    /// ```
    @objc var ipv6Enabled: Bool { get set }

    /// Sets the callback that receives this socket's events.
    ///
    /// The callback receives the event name, the socket, and event-specific arguments:
    /// - `"data"` - a datagram arrived; the third argument is a `Uint8Array` and the fourth is the
    ///   sender's address, as `{host, port, family}`, where family is `"ipv4"` or `"ipv6"`.
    /// - `"connected"` - `connect()` succeeded; the fourth argument is the peer's address.
    /// - `"error"` - something went wrong; the third argument is a description.
    ///
    /// - Parameter callback: {((event: "data" | "connected" | "error", socket: HSUDPSocket, data?: Uint8Array | string | null, address?: {host: string, port: number, family: string}) => void) | null} The event handler, or `null` to remove it.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.setCallback((event, sock, data, address) => {
    ///     if (event === "data") console.log(address.host + " sent " + hs.socket.decodeText(data))
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSUDPSocket

    /// Binds the socket to a local port, so it can receive datagrams sent to that port. Call it
    /// before `connect()` or sending.
    ///
    /// By default the socket binds on all network interfaces. Pass one of this Mac's IP addresses
    /// to bind only to that address (and so only to the interface that has it). Use
    /// `hs.network.addresses()` to find an interface's addresses.
    /// If the interface's address can change (e.g. it comes from DHCP), watch
    /// `State:/Network/Interface/<name>/IPv4` with `hs.network.configurationWatcher()` and bind again
    /// when it does.
    ///
    /// - Note: A socket bound to an address only uses that address's family (IPv4 or IPv6), and doesn't receive broadcasts
    /// - Parameter port: The UDP port to bind to, or 0 to let the system choose one (see `localPort`).
    /// - Parameter address?: A local IPv4 or IPv6 address to bind to, e.g. `"127.0.0.1"` or `"192.168.1.20"`. Defaults to all addresses.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.createUDP().setCallback(handler).bind(9999).receive()
    ///
    /// // Only on the Wi-Fi interface's IPv4 address
    /// const wifi = hs.network.addresses().find(a => a.interface === "en0" && a.family === "ipv4")
    /// hs.socket.createUDP().setCallback(handler).bind(9999, wifi.address).receive()
    /// ```
    @objc @discardableResult func bind(_ port: Int, _ address: String?) -> HSUDPSocket

    /// Connects the socket to a single peer. Afterwards, `send()` needs no host and port, and only
    /// datagrams from that peer are received. The callback receives `"connected"` once the host
    /// has been looked up.
    ///
    /// - Parameter host: The host name or IP address of the peer.
    /// - Parameter port: The peer's UDP port.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// hs.socket.createUDP().connect("192.168.1.10", 9999).send("hello").receive()
    /// ```
    @objc @discardableResult func connect(_ host: String, _ port: Int) -> HSUDPSocket

    /// Sends text, encoded as UTF-8, as one datagram.
    ///
    /// - Parameter text: The text to send.
    /// - Parameter host?: The host name or IP address to send to. Omit it if the socket is connected.
    /// - Parameter port?: The UDP port to send to. Omit it if the socket is connected.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.send("hello", "127.0.0.1", 9999)
    /// ```
    @objc @discardableResult func send(_ text: String, _ host: String?, _ port: Int) -> HSUDPSocket

    /// Sends raw bytes as one datagram.
    ///
    /// - Parameter bytes: {Uint8Array | ArrayBuffer} The bytes to send. Any typed array is accepted.
    /// - Parameter host?: The host name or IP address to send to. Omit it if the socket is connected.
    /// - Parameter port?: The UDP port to send to. Omit it if the socket is connected.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.sendBytes(new Uint8Array([0xFF, 0x00]), "127.0.0.1", 9999)
    /// ```
    @objc @discardableResult func sendBytes(_ bytes: JSValue, _ host: String?, _ port: Int) -> HSUDPSocket

    /// Starts delivering every datagram that arrives to the callback, until `pause()` or
    /// `close()`. The socket must have a local port first (see `bind()`).
    ///
    /// - Note: A receiving socket, and its callback, stay alive until it stops receiving, even if you don't keep a reference to it
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.bind(9999).receive()
    /// ```
    @objc @discardableResult func receive() -> HSUDPSocket

    /// Delivers the next datagram that arrives to the callback, then stops receiving.
    ///
    /// - Note: A receiving socket, and its callback, stay alive until it stops receiving, even if you don't keep a reference to it
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.send("ping", "127.0.0.1", 9999).receiveOne()
    /// ```
    @objc @discardableResult func receiveOne() -> HSUDPSocket

    /// Stops receiving datagrams. Datagrams that arrive meanwhile are queued by the system (up to
    /// its buffer size) and delivered once you receive again.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.pause()
    /// ```
    @objc @discardableResult func pause() -> HSUDPSocket

    /// Closes the socket immediately, discarding any sends still waiting for a host lookup. The
    /// socket can be bound, connected or used to send again afterwards.
    /// - Returns: The socket, for chaining.
    /// - Example:
    /// ```js
    /// udp.close()
    /// ```
    @objc @discardableResult func close() -> HSUDPSocket

    /// Closes the socket and releases its callback.
    /// - Example:
    /// ```js
    /// udp.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSUDPSocket: NSObject, HSUDPSocketAPI, HSTrackedObject {
    @objc var typeName = "HSUDPSocket"
    @objc let identifier = UUID().uuidString

    @objc func toString() -> String {
        let status = endpoints.isEmpty ? "closed" : (isConnected ? "connected" : (isBound ? "bound" : "open"))
        return "<\(typeName): \(status)\(localPort > 0 ? ", port \(localPort)" : "")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    /// The largest possible UDP payload
    private static let maximumDatagramSize = 65535

    private enum Event: String {
        case data, connected, error
    }

    private enum ReceiveMode {
        case off, continuous, once

        var isActive: Bool {
            switch self {
            case .off:
                return false
            case .continuous, .once:
                return true
            }
        }
    }

    private enum Operation {
        case connect(host: String, port: Int)
        case send(Data, host: String?, port: Int)

        var host: String? {
            switch self {
            case .connect(let host, _): return host
            case .send(_, let host, _): return host
            }
        }

        var port: Int {
            switch self {
            case .connect(_, let port), .send(_, _, let port): return port
            }
        }
    }

    /// One system socket, for one address family, monitored for incoming datagrams on the main
    /// run loop.
    ///
    /// This uses CFSocket rather than a dispatch source because invalidating a CFSocket closes the
    /// system socket immediately, so its port is free as soon as `close()` returns. A dispatch
    /// source's descriptor may only be closed from its cancel handler, which runs later.
    fileprivate final class Endpoint {
        let fd: Int32
        let family: Int32
        fileprivate weak var owner: HSUDPSocket?
        private var socket: CFSocket?
        private var isReading = false

        /// Takes ownership of `fd`, which is closed by `close()`, or straight away if this fails.
        init?(fd: Int32, family: Int32, owner: HSUDPSocket) {
            self.fd = fd
            self.family = family
            self.owner = owner
            var context = unsafe CFSocketContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                          retain: nil, release: nil, copyDescription: nil)
            guard let socket = unsafe CFSocketCreateWithNative(nil, fd, CFSocketCallBackType.readCallBack.rawValue,
                                                               udpEndpointReadable, &context) else {
                _ = Darwin.close(fd)
                return nil
            }
            CFSocketDisableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
            let source = CFSocketCreateRunLoopSource(nil, socket, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.socket = socket
        }

        func startReading() {
            guard !isReading, let socket else { return }
            CFSocketEnableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
            isReading = true
        }

        func stopReading() {
            guard isReading, let socket else { return }
            CFSocketDisableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
            isReading = false
        }

        isolated deinit {
            close()
        }

        /// Removes the socket from the run loop and closes it.
        func close() {
            guard let socket else { return }
            CFSocketInvalidate(socket)
            self.socket = nil
            isReading = false
        }
    }

    private weak var tracker: HSObjectTracker<HSUDPSocket>?
    private var callback: JSCallback?
    private var endpoints: [Endpoint] = []
    /// The peer's address, once connected
    private var peerAddress: Data?
    @objc private(set) var isBound = false
    /// Incremented by close(), so lookups that finish afterwards are ignored
    private var generation = 0

    // Receiving, and queued operations, are pending activity: the socket stays alive with its
    // callback until they end, even if the user dropped their reference to it.
    private var receiveMode: ReceiveMode = .off {
        didSet { updateActivity() }
    }
    /// Connects and sends, run in order, since a host lookup can't complete synchronously
    private var operations: [Operation] = [] {
        didSet { updateActivity() }
    }
    private var isRunningOperation = false
    /// Whether runOperations() is on the stack, so a callback that queues more doesn't re-enter it
    private var isDrainingOperations = false

    @objc var broadcast = false {
        didSet {
            for endpoint in endpoints where endpoint.family == AF_INET {
                setOption(endpoint.fd, SOL_SOCKET, SO_BROADCAST, broadcast)
            }
        }
    }

    @objc var reusePort = false {
        didSet {
            if !endpoints.isEmpty {
                AKWarning("HSUDPSocket(\(identifier)): reusePort only applies to sockets created after it's set")
            }
        }
    }

    @objc var ipv4Enabled = true
    @objc var ipv6Enabled = true

    init(tracker: HSObjectTracker<HSUDPSocket>) {
        self.tracker = tracker
        super.init()
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSUDPSocket(\(identifier))")
    }

    private func updateActivity() {
        tracker?.setActive(self, receiveMode.isActive || !operations.isEmpty)
    }

    // MARK: - Properties

    @objc var isConnected: Bool { peerAddress != nil }
    @objc var isReceiving: Bool { receiveMode != .off }

    @objc var localPort: Int {
        guard let endpoint = endpoints.first else { return 0 }
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                unsafe getsockname(endpoint.fd, address, &length)
            }
        }
        guard result == 0 else { return 0 }
        return socketAddressPort(unsafe Data(bytes: &storage, count: Int(length)))
    }

    // MARK: - Configuration

    @objc @discardableResult func setCallback(_ callback: JSFunction?) -> HSUDPSocket {
        self.callback?.detach(from: self)
        self.callback = callback.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        return self
    }

    // MARK: - Binding

    @objc @discardableResult func bind(_ port: Int, _ address: String?) -> HSUDPSocket {
        guard endpoints.isEmpty else {
            emitError("bind() must be called before the socket connects or sends")
            return self
        }
        guard (0...65535).contains(port) else {
            emitError("Invalid port \(port)")
            return self
        }
        var localAddress: Data?
        if let address = normalizedOptionalString(address) {
            guard let parsed = try? lookupSocketAddresses(host: address, port: port, numericOnly: true).first else {
                emitError("\(address) is not an IP address")
                return self
            }
            localAddress = parsed
        }
        let families = localAddress.map { [socketAddressFamily($0)] } ?? enabledFamilies
        guard families.allSatisfy(enabledFamilies.contains), !families.isEmpty else {
            emitError(localAddress == nil ? "Both IPv4 and IPv6 are disabled" : "\(families[0] == AF_INET ? "IPv4" : "IPv6") is disabled")
            return self
        }

        // When the system chooses the port, the first family's choice is used for the other, so
        // both sockets share one port.
        var boundPort = port
        for family in families {
            guard let endpoint = makeEndpoint(family: family) else {
                closeEndpoints()
                return self
            }
            let bindAddress = localAddress ?? (family == AF_INET ? ipv4AnyAddress(port: boundPort) : ipv6AnyAddress(port: boundPort))
            let result = unsafe bindAddress.withUnsafeBytes { raw in
                // swiftlint:disable:next force_unwrapping
                unsafe Darwin.bind(endpoint.fd, raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(bindAddress.count))
            }
            guard result == 0 else {
                let message = currentErrorMessage()
                closeEndpoints()
                emitError("Could not bind to \(localAddress.flatMap(networkAddressString).map { "\($0) " } ?? "")port \(boundPort): \(message)")
                return self
            }
            if boundPort == 0 {
                boundPort = localPort
            }
        }
        isBound = true
        startReadingIfNeeded()
        AKDebug("HSUDPSocket(\(identifier)): bound to port \(boundPort)")
        return self
    }

    // MARK: - Connecting and sending

    @objc @discardableResult func connect(_ host: String, _ port: Int) -> HSUDPSocket {
        guard !host.isEmpty, (1...65535).contains(port) else {
            emitError("connect() needs a host and a port from 1 to 65535")
            return self
        }
        enqueue(.connect(host: host, port: port))
        return self
    }

    @objc @discardableResult func send(_ text: String, _ host: String?, _ port: Int) -> HSUDPSocket {
        enqueueSend(Data(text.utf8), host: host, port: port)
    }

    @objc @discardableResult func sendBytes(_ bytes: JSValue, _ host: String?, _ port: Int) -> HSUDPSocket {
        guard let data = bytes.typedArrayBytes else {
            emitError("sendBytes() needs a typed array or ArrayBuffer")
            return self
        }
        return enqueueSend(Data(data), host: host, port: port)
    }

    private func enqueueSend(_ data: Data, host: String?, port: Int) -> HSUDPSocket {
        guard data.count <= Self.maximumDatagramSize else {
            emitError("A datagram can't be larger than \(Self.maximumDatagramSize) bytes")
            return self
        }
        let host = normalizedOptionalString(host)
        if let host, host.isEmpty || !(1...65535).contains(port) {
            emitError("send() needs a host and a port from 1 to 65535")
            return self
        }
        enqueue(.send(data, host: host, port: port))
        return self
    }

    private func enqueue(_ operation: Operation) {
        operations.append(operation)
        runOperations()
    }

    /// Runs queued operations in order. A host that's an IP address is used straight away;
    /// anything else is looked up in the background first.
    private func runOperations() {
        guard !isDrainingOperations else { return }
        isDrainingOperations = true
        defer { isDrainingOperations = false }
        while !isRunningOperation, let operation = operations.first {
            guard let host = operation.host else {
                finish(operation, addresses: .success([]))
                continue
            }
            if let addresses = try? lookupSocketAddresses(host: host, port: operation.port, numericOnly: true) {
                finish(operation, addresses: .success(addresses))
                continue
            }

            isRunningOperation = true
            let generation = self.generation
            let port = operation.port
            Task {
                let result: Result<[Data], Error>
                do {
                    result = .success(try await lookupSocketAddressesInBackground(host: host, port: port))
                } catch {
                    result = .failure(error)
                }
                guard generation == self.generation else { return }
                self.isRunningOperation = false
                // The operation stays queued while its callbacks run, so they mustn't start it again
                self.isDrainingOperations = true
                self.finish(operation, addresses: result)
                self.isDrainingOperations = false
                self.runOperations()
            }
            return
        }
    }

    /// Performs the operation at the front of the queue, then removes it. It stays queued while
    /// it runs, so the socket stays active if its callback starts something new.
    private func finish(_ operation: Operation, addresses: Result<[Data], Error>) {
        let generation = self.generation
        perform(operation, addresses: addresses)
        if generation == self.generation, !operations.isEmpty {
            operations.removeFirst()
        }
    }

    private func perform(_ operation: Operation, addresses: Result<[Data], Error>) {
        let resolved: [Data]
        switch addresses {
        case .success(let list):
            resolved = list
        case .failure(let error):
            emitError("Could not look up \(operation.host ?? ""): \(error.localizedDescription)")
            return
        }

        let address: Data?
        if operation.host != nil {
            let families = enabledFamilies
            // Prefer a family the socket already has, so a bound or connected socket keeps its port
            let existing = Set(endpoints.map(\.family))
            address = resolved.first { existing.contains(socketAddressFamily($0)) }
                ?? resolved.first { families.contains(socketAddressFamily($0)) }
            guard address != nil else {
                emitError("\(operation.host ?? "") has no address the socket can use")
                return
            }
        } else {
            address = nil
        }

        switch operation {
        case .connect:
            guard let address else { return }
            performConnect(to: address)
        case .send(let data, _, _):
            performSend(data, to: address)
        }
    }

    private func performConnect(to address: Data) {
        let family = socketAddressFamily(address)
        guard let endpoint = endpoint(for: family) else { return }
        let result = unsafe address.withUnsafeBytes { raw in
            // swiftlint:disable:next force_unwrapping
            unsafe Darwin.connect(endpoint.fd, raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
        }
        guard result == 0 else {
            emitError("Could not connect: \(currentErrorMessage())")
            return
        }
        // A connected socket only talks to its peer, so the other family's socket is no use
        for other in endpoints where other.family != family {
            other.close()
        }
        endpoints.removeAll { $0.family != family }
        peerAddress = address
        emit(.connected, NSNull(), socketAddressDictionary(address))
    }

    private func performSend(_ data: Data, to address: Data?) {
        let sent: Int
        if let address {
            if let peerAddress, address != peerAddress {
                emitError("A connected socket can only send to its peer")
                return
            }
            guard let endpoint = endpoint(for: socketAddressFamily(address)) else { return }
            sent = unsafe data.withUnsafeBytes { bytes in
                unsafe address.withUnsafeBytes { raw in
                    unsafe sendto(endpoint.fd, bytes.baseAddress, bytes.count, 0,
                                  // swiftlint:disable:next force_unwrapping
                                  raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
                }
            }
        } else {
            guard peerAddress != nil, let endpoint = endpoints.first else {
                emitError("send() needs a host and port unless the socket is connected")
                return
            }
            sent = unsafe data.withUnsafeBytes { bytes in
                unsafe Darwin.send(endpoint.fd, bytes.baseAddress, bytes.count, 0)
            }
        }
        if sent < 0 {
            emitError("Send failed: \(currentErrorMessage())")
        }
    }

    // MARK: - Receiving

    @objc @discardableResult func receive() -> HSUDPSocket {
        startReceiving(.continuous)
    }

    @objc @discardableResult func receiveOne() -> HSUDPSocket {
        startReceiving(.once)
    }

    private func startReceiving(_ mode: ReceiveMode) -> HSUDPSocket {
        guard !endpoints.isEmpty || isRunningOperation || !operations.isEmpty else {
            emitError("The socket has no local port to receive on: call bind(), connect() or send() first")
            return self
        }
        receiveMode = mode
        startReadingIfNeeded()
        return self
    }

    @objc @discardableResult func pause() -> HSUDPSocket {
        receiveMode = .off
        for endpoint in endpoints {
            endpoint.stopReading()
        }
        return self
    }

    private func startReadingIfNeeded() {
        guard receiveMode != .off else { return }
        for endpoint in endpoints {
            endpoint.startReading()
        }
    }

    fileprivate func readDatagram(from endpoint: Endpoint) {
        guard receiveMode != .off, endpoints.contains(where: { $0 === endpoint }) else { return }
        var buffer = [UInt8](repeating: 0, count: Self.maximumDatagramSize)
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let count = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &storage) { pointer in
                unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    unsafe recvfrom(endpoint.fd, bytes.baseAddress, bytes.count, 0, address, &length)
                }
            }
        }
        guard count >= 0 else {
            let code = errno
            guard code != EAGAIN && code != EWOULDBLOCK && code != EINTR else { return }
            // e.g. ECONNREFUSED, when a connected socket's peer isn't listening
            emitError("Receive failed: \(errorMessage(code))")
            return
        }

        let function = callback?.value
        if receiveMode == .once {
            // Stop before calling back, since the callback may ask for another datagram
            pause()
        }
        guard let function, let bytes = function.context.makeUint8Array(buffer[..<count]) else { return }
        let address = socketAddressDictionary(unsafe Data(bytes: &storage, count: Int(length)))
        _ = function.call(withArguments: [Event.data.rawValue, self, bytes, address])
    }

    // MARK: - Closing

    @objc @discardableResult func close() -> HSUDPSocket {
        generation &+= 1
        isRunningOperation = false
        operations.removeAll()
        receiveMode = .off
        closeEndpoints()
        return self
    }

    @objc func destroy() {
        close()
        callback?.detach(from: self)
        callback = nil
    }

    private func closeEndpoints() {
        for endpoint in endpoints {
            endpoint.close()
        }
        endpoints.removeAll()
        peerAddress = nil
        isBound = false
    }

    // MARK: - System sockets

    private var enabledFamilies: [Int32] {
        (ipv4Enabled ? [AF_INET] : []) + (ipv6Enabled ? [AF_INET6] : [])
    }

    /// Returns the socket for `family`, creating it if the socket hasn't bound or connected.
    private func endpoint(for family: Int32) -> Endpoint? {
        if let endpoint = endpoints.first(where: { $0.family == family }) {
            return endpoint
        }
        guard !isBound, peerAddress == nil else {
            emitError("The socket is bound or connected without \(family == AF_INET ? "IPv4" : "IPv6")")
            return nil
        }
        guard enabledFamilies.contains(family) else {
            emitError("\(family == AF_INET ? "IPv4" : "IPv6") is disabled")
            return nil
        }
        let endpoint = makeEndpoint(family: family)
        startReadingIfNeeded()
        return endpoint
    }

    /// Creates a non-blocking socket for `family`, configured from the socket's options, and adds
    /// it to `endpoints`.
    private func makeEndpoint(family: Int32) -> Endpoint? {
        let fd = Darwin.socket(family, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            emitError("Could not create socket: \(currentErrorMessage())")
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        if family == AF_INET6 {
            // IPv4 has its own socket, so this one shouldn't also claim the IPv4 port
            setOption(fd, IPPROTO_IPV6, IPV6_V6ONLY, true)
        }
        if reusePort {
            setOption(fd, SOL_SOCKET, SO_REUSEADDR, true)
            setOption(fd, SOL_SOCKET, SO_REUSEPORT, true)
        }
        if family == AF_INET && broadcast {
            setOption(fd, SOL_SOCKET, SO_BROADCAST, true)
        }

        guard let endpoint = Endpoint(fd: fd, family: family, owner: self) else {
            emitError("Could not monitor socket")
            return nil
        }
        endpoints.append(endpoint)
        return endpoint
    }

    private func setOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ enabled: Bool) {
        var value: Int32 = enabled ? 1 : 0
        _ = unsafe setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    // MARK: - Callback

    private func emit(_ event: Event, _ arguments: Any...) {
        guard let function = callback?.value else { return }
        _ = function.call(withArguments: [event.rawValue, self] + arguments)
    }

    private func emitError(_ message: String) {
        AKDebug("HSUDPSocket(\(identifier)): \(message)")
        emit(.error, message)
    }
}

// MARK: - Address helpers

nonisolated private func errorMessage(_ code: Int32) -> String {
    unsafe String(cString: strerror(code))
}

nonisolated private func currentErrorMessage() -> String {
    errorMessage(errno)
}

nonisolated private func ipv4AnyAddress(port: Int) -> Data {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(port).bigEndian
    address.sin_addr = in_addr(s_addr: INADDR_ANY)
    return unsafe Data(bytes: &address, count: MemoryLayout<sockaddr_in>.size)
}

nonisolated private func ipv6AnyAddress(port: Int) -> Data {
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = UInt16(port).bigEndian
    address.sin6_addr = in6addr_any
    return unsafe Data(bytes: &address, count: MemoryLayout<sockaddr_in6>.size)
}

nonisolated private func socketAddressFamily(_ address: Data) -> Int32 {
    unsafe address.withUnsafeBytes { raw in
        // swiftlint:disable:next force_unwrapping
        Int32(unsafe raw.load(fromByteOffset: MemoryLayout<sockaddr>.offset(of: \.sa_family)!, as: sa_family_t.self))
    }
}

nonisolated private func socketAddressPort(_ address: Data) -> Int {
    switch socketAddressFamily(address) {
    case AF_INET:
        let port = unsafe address.withUnsafeBytes { unsafe $0.loadUnaligned(as: sockaddr_in.self).sin_port }
        return Int(UInt16(bigEndian: port))
    case AF_INET6:
        let port = unsafe address.withUnsafeBytes { unsafe $0.loadUnaligned(as: sockaddr_in6.self).sin6_port }
        return Int(UInt16(bigEndian: port))
    default:
        return 0
    }
}

/// A sockaddr as the `{host, port, family}` object the callback receives.
nonisolated private func socketAddressDictionary(_ address: Data) -> [String: Any] {
    let family = socketAddressFamily(address)
    return [
        "host": networkAddressString(from: address) ?? "",
        "port": socketAddressPort(address),
        "family": family == AF_INET6 ? "ipv6" : "ipv4",
    ]
}

/// Looks up the IPv4 and IPv6 socket addresses for `host` and `port`, in the system's preferred
/// order. With `numericOnly`, `host` must be an IP address, and nothing is looked up, so it's
/// safe to call on the main thread.
nonisolated private func lookupSocketAddresses(host: String, port: Int, numericOnly: Bool) throws -> [Data] {
    var hints = unsafe addrinfo()
    unsafe hints.ai_family = AF_UNSPEC
    unsafe hints.ai_socktype = SOCK_DGRAM
    unsafe hints.ai_flags = AI_NUMERICSERV | (numericOnly ? AI_NUMERICHOST : AI_ADDRCONFIG)

    var results: UnsafeMutablePointer<addrinfo>?
    let status = unsafe getaddrinfo(host, String(port), &hints, &results)
    defer { if let results = unsafe results { unsafe freeaddrinfo(results) } }
    guard status == 0 else {
        throw NSError(domain: "hs.socket", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: unsafe String(cString: gai_strerror(status)),
        ])
    }

    var addresses: [Data] = []
    var current = unsafe results
    while let info = unsafe current {
        let family = unsafe info.pointee.ai_family
        if family == AF_INET || family == AF_INET6, let address = unsafe info.pointee.ai_addr {
            unsafe addresses.append(Data(bytes: address, count: Int(info.pointee.ai_addrlen)))
        }
        unsafe current = unsafe info.pointee.ai_next
    }
    return addresses
}

/// Looks up `host` off the main thread, since getaddrinfo blocks while it queries DNS.
@concurrent
nonisolated private func lookupSocketAddressesInBackground(host: String, port: Int) async throws -> [Data] {
    try lookupSocketAddresses(host: host, port: port, numericOnly: false)
}

/// Called on the main run loop when one of an `HSUDPSocket.Endpoint`'s sockets is readable.
///
/// `nonisolated` and at file scope, since CFSocket calls it as a C function.
nonisolated private func udpEndpointReadable(_ socket: CFSocket?, _ type: CFSocketCallBackType, _ address: CFData?,
                                             _ data: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) {
    guard let info = unsafe info else { return }
    let endpoint = unsafe Unmanaged<HSUDPSocket.Endpoint>.fromOpaque(info).takeUnretainedValue()
    MainActor.assumeIsolated {
        endpoint.owner?.readDatagram(from: endpoint)
    }
}
