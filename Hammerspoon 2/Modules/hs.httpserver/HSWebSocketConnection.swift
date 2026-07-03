//
//  HSWebSocketConnection.swift
//  Hammerspoon 2

import Foundation
import JavaScriptCore
import Network
import CryptoKit

// MARK: - WebSocket frame utilities

struct ParsedWebSocketFrame {
    let opcode: UInt8
    let payload: Data
}

// MARK: - Protocol

/// A WebSocket connection to a single client, passed to the callback registered with
/// `server.setWebSocketCallback()`.
///
/// Use `send()` to push messages to the connected client and `close()` to end the connection.
///
/// Do not instantiate `HSWebSocketConnection` directly — it is created by the server when a
/// client performs a WebSocket upgrade.
@objc protocol HSWebSocketConnectionAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this connection (UUID string).
    @objc var identifier: String { get }

    /// Send a text message to the connected WebSocket client.
    ///
    /// - Parameter message: The text message to send.
    /// - Example:
    /// ```js
    /// server.setWebSocketCallback('/ws', (event, conn, msg) => {
    ///     if (event === 'message') conn.send('Echo: ' + msg)
    /// })
    /// ```
    @objc func send(_ message: String)

    /// Close the WebSocket connection to the client.
    ///
    /// Sends a WebSocket close frame and cancels the underlying TCP connection.
    ///
    /// - Example:
    /// ```js
    /// conn.close()
    /// ```
    @objc func close()

    /// Destroy this connection object, releasing all resources.
    ///
    /// - Example:
    /// ```js
    /// conn.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWebSocketConnection: NSObject, HSWebSocketConnectionAPI {
    @objc var typeName = "HSWebSocketConnection"
    @objc let identifier = UUID().uuidString

    // Strong reference to the NWConnection so the connection stays alive while JS holds
    // this object, even after the server removes it from its own tracking dictionary.
    var connection: NWConnection?
    var isClosed = false

    init(connection: NWConnection) {
        self.connection = connection
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSWebSocketConnection(\(identifier))")
    }

    @objc func send(_ message: String) {
        guard !isClosed, let conn = connection else {
            AKWarning("HSWebSocketConnection(\(identifier)): send() called on closed connection")
            return
        }
        let frame = HSWebSocketConnection.buildFrame(opcode: 0x01, payload: Data(message.utf8))
        conn.send(content: frame, completion: .idempotent)
    }

    @objc func close() {
        destroy()
    }

    @objc func destroy() {
        guard !isClosed else { return }
        isClosed = true
        if let conn = connection {
            let closeFrame = HSWebSocketConnection.buildFrame(opcode: 0x08, payload: Data())
            conn.send(content: closeFrame, completion: .contentProcessed { _ in
                MainActor.assumeIsolated { conn.cancel() }
            })
        }
        connection = nil
        AKTrace("HSWebSocketConnection(\(identifier)): Destroyed")
    }
}

// MARK: - Static WebSocket utilities

extension HSWebSocketConnection {

    /// Compute the `Sec-WebSocket-Accept` value for the WebSocket handshake (RFC 6455 §4.2.2).
    static func webSocketAcceptKey(for key: String) -> String {
        let combined = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    /// Build an unmasked WebSocket frame (server-to-client direction).
    static func buildFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(0x80 | (opcode & 0x0F))  // FIN=1, RSV=0, opcode
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))         // MASK=0
        } else if length < 65536 {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    /// Parse the next WebSocket frame from `buffer` (which must have startIndex == 0).
    /// Returns the parsed frame and the number of bytes consumed, or nil if the frame is
    /// incomplete and more data must be accumulated first.
    static func parseNextFrame(from buffer: Data) -> (frame: ParsedWebSocketFrame, consumed: Int)? {
        guard buffer.count >= 2 else { return nil }

        let byte0 = buffer[0]
        let byte1 = buffer[1]

        let opcode = byte0 & 0x0F
        let isMasked = (byte1 & 0x80) != 0
        var payloadLength = Int(byte1 & 0x7F)
        var headerBytes = 2

        if payloadLength == 126 {
            guard buffer.count >= 4 else { return nil }
            payloadLength = Int(buffer[2]) << 8 | Int(buffer[3])
            headerBytes = 4
        } else if payloadLength == 127 {
            guard buffer.count >= 10 else { return nil }
            var len: UInt64 = 0
            for i in 0..<8 { len = (len << 8) | UInt64(buffer[2 + i]) }
            payloadLength = Int(len)
            headerBytes = 10
        }

        let maskBytes = isMasked ? 4 : 0
        let totalBytes = headerBytes + maskBytes + payloadLength
        guard buffer.count >= totalBytes else { return nil }

        var maskKey = [UInt8](repeating: 0, count: 4)
        if isMasked {
            for i in 0..<4 { maskKey[i] = buffer[headerBytes + i] }
        }

        var payload = Data(buffer[(headerBytes + maskBytes)..<totalBytes])
        if isMasked {
            for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
        }

        return (ParsedWebSocketFrame(opcode: opcode, payload: payload), totalBytes)
    }
}
