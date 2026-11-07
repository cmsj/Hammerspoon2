//
//  HSSocketModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// Module for communicating over raw TCP, UDP and Unix domain sockets.
///
/// `hs.socket.create()` makes a stream socket, which can connect to a TCP server or Unix domain
/// socket (optionally over TLS), or listen for incoming connections. `hs.socket.createUDP()`
/// makes a UDP socket, which can send and receive datagrams, including broadcasts.
///
/// Sockets report everything through a single callback, set with `setCallback()`. Received data
/// is delivered as a `Uint8Array`; `hs.socket.decodeText()` turns it into a string.
///
/// ## TCP client
///
/// ```js
/// hs.socket.create().setCallback((event, sock, data) => {
///     if (event === "connected") sock.write("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n").readUntil("\r\n\r\n")
///     if (event === "data") console.log(hs.socket.decodeText(data))
///     if (event === "error") console.error(data)
/// }).connect("example.com", 80)
/// ```
///
/// ## TCP server
///
/// Each connection a listening socket accepts arrives as a new socket, with the same callback.
///
/// ```js
/// const server = hs.socket.create().setCallback((event, sock, data) => {
///     if (event === "connection") data.readUntil("\n")
///     if (event === "data") sock.write("You said: " + hs.socket.decodeText(data)).readUntil("\n")
/// }).listen(9000)
/// ```
///
/// ## UDP
///
/// ```js
/// const udp = hs.socket.createUDP().setCallback((event, sock, data, address) => {
///     if (event === "data") console.log(address.host + ": " + hs.socket.decodeText(data))
/// }).bind(9999).receive()
/// udp.send("hello", "127.0.0.1", 9999)
/// ```
@objc protocol HSSocketModuleAPI: JSExport {

    /// The timeout, in seconds, that new stream sockets start with (see `HSSocket.timeout`).
    /// 0 means no timeout, which is the default.
    /// - Example:
    /// ```js
    /// hs.socket.timeout = 10
    /// ```
    @objc var timeout: Double { get set }

    /// Creates a TCP or Unix domain stream socket. It does nothing until you connect it or make
    /// it listen.
    /// - Returns: A new `HSSocket`.
    /// - Example:
    /// ```js
    /// const sock = hs.socket.create().setCallback(handler).connect("localhost", 6379)
    /// ```
    @objc func create() -> HSSocket

    /// Creates a UDP socket.
    /// - Returns: A new `HSUDPSocket`.
    /// - Example:
    /// ```js
    /// const udp = hs.socket.createUDP().setCallback(handler).bind(9999).receive()
    /// ```
    @objc func createUDP() -> HSUDPSocket

    /// Decodes bytes as UTF-8 text.
    /// - Parameter bytes: {Uint8Array | ArrayBuffer} The bytes to decode, e.g. the data from a `"data"` event.
    /// - Returns: The text, or `null` if the bytes aren't valid UTF-8.
    /// - Example:
    /// ```js
    /// console.log(hs.socket.decodeText(new Uint8Array([104, 105])))  // "hi"
    /// ```
    @objc func decodeText(_ bytes: JSValue) -> String?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSocketModule: NSObject, HSModuleAPI, HSSocketModuleAPI {
    var moduleName = "hs.socket"
    let engineID: UUID
    private var sockets = HSObjectTracker<HSSocket>()
    private var udpSockets = HSObjectTracker<HSUDPSocket>()

    @objc var timeout: Double = 0

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        sockets.shutdown()
        udpSockets.shutdown()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = sockets.activeCount + udpSockets.activeCount
        return "<\(moduleName): \(n) active socket\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func create() -> HSSocket {
        let socket = HSSocket(tracker: sockets, timeout: timeout)
        sockets.add(socket)
        return socket
    }

    @objc func createUDP() -> HSUDPSocket {
        let socket = HSUDPSocket(tracker: udpSockets)
        udpSockets.add(socket)
        return socket
    }

    @objc func decodeText(_ bytes: JSValue) -> String? {
        guard let data = bytes.typedArrayBytes else {
            AKWarning("hs.socket.decodeText(): needs a typed array or ArrayBuffer")
            return nil
        }
        return String(validating: data, as: UTF8.self)
    }
}
