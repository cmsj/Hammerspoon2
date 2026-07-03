//
//  HSWebSocket.swift
//  Hammerspoon 2

import Foundation
import JavaScriptCore

// MARK: - Protocol

/// A WebSocket client connection created by `hs.http.openWebSocket()`.
///
/// The connection opens immediately when returned. Use the chainable setter methods to register
/// event callbacks, then call `send()` to transmit messages.
///
/// Do not instantiate `HSWebSocket` directly — use `hs.http.openWebSocket()`.
@objc protocol HSWebSocketAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this connection (UUID string).
    @objc var identifier: String { get }

    /// The current connection state.
    ///
    /// - `0` = Connecting
    /// - `1` = Open
    /// - `2` = Closing
    /// - `3` = Closed
    @objc var readyState: Int { get }

    /// Set the callback invoked when the connection is established.
    ///
    /// - Parameter callback: {() => void} Called when the connection opens.
    /// - Returns: This WebSocket, for chaining.
    /// - Example:
    /// ```js
    /// ws.setOpenCallback(() => console.log("Connected!"))
    /// ```
    @objc @discardableResult func setOpenCallback(_ callback: JSFunction?) -> HSWebSocket

    /// Set the callback invoked when a text message is received from the server.
    ///
    /// - Parameter callback: {(message: string) => void} Called with each received message.
    /// - Returns: This WebSocket, for chaining.
    /// - Example:
    /// ```js
    /// ws.setMessageCallback(msg => console.log("Got: " + msg))
    /// ```
    @objc @discardableResult func setMessageCallback(_ callback: JSFunction?) -> HSWebSocket

    /// Set the callback invoked when the connection is closed by the remote end.
    ///
    /// - Parameter callback: {(code: number, reason: string) => void} Called with the WebSocket close code and reason.
    /// - Returns: This WebSocket, for chaining.
    /// - Example:
    /// ```js
    /// ws.setCloseCallback((code, reason) => console.log("Closed: " + code))
    /// ```
    @objc @discardableResult func setCloseCallback(_ callback: JSFunction?) -> HSWebSocket

    /// Set the callback invoked when a connection or protocol error occurs.
    ///
    /// - Parameter callback: {(error: string) => void} Called with the error description.
    /// - Returns: This WebSocket, for chaining.
    /// - Example:
    /// ```js
    /// ws.setErrorCallback(err => console.log("Error: " + err))
    /// ```
    @objc @discardableResult func setErrorCallback(_ callback: JSFunction?) -> HSWebSocket

    /// Send a text message to the server.
    ///
    /// The connection must be open (`readyState === 1`).
    ///
    /// - Parameter message: The text message to send.
    /// - Returns: This WebSocket, for chaining.
    /// - Example:
    /// ```js
    /// ws.send("Hello, server!")
    /// ```
    @objc @discardableResult func send(_ message: String) -> HSWebSocket

    /// Close the WebSocket connection with a normal closure code (1000).
    ///
    /// If a close callback is registered, it is invoked synchronously.
    ///
    /// - Example:
    /// ```js
    /// ws.close()
    /// ```
    @objc func close()

    /// Destroy this WebSocket, releasing all resources without invoking callbacks.
    ///
    /// Called automatically by `hs.http.shutdown()`. After `destroy()`, do not use this object.
    ///
    /// - Example:
    /// ```js
    /// ws.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - URLSession delegate

// Kept as a separate class so the @MainActor HSWebSocket does not need to conform to
// URLSessionWebSocketDelegate. The URLSession is created with delegateQueue: .main so every
// delegate callback arrives on the main thread; MainActor.assumeIsolated is therefore safe.
private final class WebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate {
    // nonisolated(unsafe): this property is only ever read from inside MainActor.assumeIsolated,
    // which guarantees main-actor execution. The nonisolated(unsafe) annotation suppresses the
    // Swift 6 isolation warning while preserving the actual safety guarantee.
    nonisolated(unsafe) weak var owner: HSWebSocket?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        MainActor.assumeIsolated { unsafe owner?.handleOpen() }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let code = closeCode.rawValue
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        MainActor.assumeIsolated { unsafe owner?.handleClose(code: code, reason: reasonStr) }
    }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWebSocket: NSObject, HSWebSocketAPI {
    @objc var typeName = "HSWebSocket"
    @objc let identifier = UUID().uuidString

    private let url: URL
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    // URLSession holds its delegate weakly; we must keep a strong reference here.
    private var sessionDelegate: WebSocketSessionDelegate?

    private var _readyState: Int = 0
    @objc var readyState: Int { _readyState }

    private var _openCallback: JSCallback?
    private var _messageCallback: JSCallback?
    private var _closeCallback: JSCallback?
    private var _errorCallback: JSCallback?

    init(url: URL) {
        self.url = url
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSWebSocket(\(identifier))")
    }

    // Called by HSHTTPModule.openWebSocket() after the object is created.
    func connect() {
        let delegate = WebSocketSessionDelegate()
        unsafe delegate.owner = self
        sessionDelegate = delegate
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        task = session?.webSocketTask(with: url)
        task?.resume()
        scheduleNextReceive()
        AKTrace("HSWebSocket(\(identifier)): Connecting to \(url)")
    }

    // MARK: - Internal event handlers (always called on main thread)

    fileprivate func handleOpen() {
        guard _readyState == 0 else { return }
        _readyState = 1
        _ = _openCallback?.value?.call(withArguments: [])
        AKTrace("HSWebSocket(\(identifier)): Open")
    }

    fileprivate func handleClose(code: Int, reason: String) {
        guard _readyState == 1 else { return }
        _readyState = 3
        _ = _closeCallback?.value?.call(withArguments: [code, reason])
        AKTrace("HSWebSocket(\(identifier)): Closed by remote (code \(code))")
    }

    // MARK: - Receive loop

    private func scheduleNextReceive() {
        task?.receive { [weak self] result in
            // Delivered on delegateQueue (.main); assumeIsolated is correct.
            MainActor.assumeIsolated {
                guard let self, self._readyState < 3 else { return }
                switch result {
                case .success(let message):
                    let text: String
                    switch message {
                    case .string(let s): text = s
                    case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                    @unknown default: text = ""
                    }
                    _ = self._messageCallback?.value?.call(withArguments: [text])
                    self.scheduleNextReceive()
                case .failure(let error):
                    // URLError.cancelled means the task was cancelled deliberately (by close() or
                    // destroy()); let didCloseWith / explicit state changes handle the close.
                    let nsError = error as NSError
                    if nsError.code == NSURLErrorCancelled { return }
                    guard self._readyState == 1 else { return }
                    self._readyState = 3
                    _ = self._errorCallback?.value?.call(withArguments: [error.localizedDescription])
                    self.session?.invalidateAndCancel()
                    self.session = nil
                    self.task = nil
                }
            }
        }
    }

    // MARK: - HSWebSocketAPI

    @objc @discardableResult func setOpenCallback(_ callback: JSFunction?) -> HSWebSocket {
        _openCallback?.detach(from: self)
        _openCallback = callback.flatMap { JSCallback(value: $0, owner: self) }
        return self
    }

    @objc @discardableResult func setMessageCallback(_ callback: JSFunction?) -> HSWebSocket {
        _messageCallback?.detach(from: self)
        _messageCallback = callback.flatMap { JSCallback(value: $0, owner: self) }
        return self
    }

    @objc @discardableResult func setCloseCallback(_ callback: JSFunction?) -> HSWebSocket {
        _closeCallback?.detach(from: self)
        _closeCallback = callback.flatMap { JSCallback(value: $0, owner: self) }
        return self
    }

    @objc @discardableResult func setErrorCallback(_ callback: JSFunction?) -> HSWebSocket {
        _errorCallback?.detach(from: self)
        _errorCallback = callback.flatMap { JSCallback(value: $0, owner: self) }
        return self
    }

    @objc @discardableResult func send(_ message: String) -> HSWebSocket {
        guard _readyState == 1 else {
            AKWarning("HSWebSocket(\(identifier)): send() called but readyState is \(_readyState)")
            return self
        }
        task?.send(.string(message)) { [weak self] error in
            // Delivered on delegateQueue (.main)
            MainActor.assumeIsolated {
                if let error {
                    _ = self?._errorCallback?.value?.call(withArguments: [error.localizedDescription])
                }
            }
        }
        return self
    }

    @objc func close() {
        guard _readyState < 3 else { return }
        let wasOpen = _readyState == 1
        _readyState = 3
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        task = nil
        if wasOpen {
            _ = _closeCallback?.value?.call(withArguments: [1000, "Normal closure"])
        }
        AKTrace("HSWebSocket(\(identifier)): Closed (user initiated)")
    }

    @objc func destroy() {
        // Set closed state first so pending async callbacks are silenced.
        _readyState = 3
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        task = nil
        sessionDelegate = nil
        _openCallback?.detach(from: self)
        _messageCallback?.detach(from: self)
        _closeCallback?.detach(from: self)
        _errorCallback?.detach(from: self)
        _openCallback = nil
        _messageCallback = nil
        _closeCallback = nil
        _errorCallback = nil
    }
}
