//
//  HSIPCProtocols.swift
//  Hammerspoon 2
//
//  Shared XPC protocol definitions. The same declarations live in hs/HSIPCProtocols.swift
//  for the CLI target — both sides must agree on the ObjC selector names.
//

import Foundation

/// Implemented by the Hammerspoon 2 app; called by the `hs` CLI tool.
@objc protocol HSIPCServerProtocol: NSObjectProtocol {
    /// Configure log forwarding and confirm the connection.
    ///
    /// - Parameter minLogLevel: Minimum log severity raw value to receive.
    ///   Pass `Int.max` to suppress all log messages.
    /// - Parameter reply: Called with `"connected"` on success.
    nonisolated func hello(minLogLevel: Int, withReply reply: @escaping (String) -> Void)

    /// Evaluate JavaScript in the live Hammerspoon 2 engine.
    ///
    /// - Parameter id: Opaque request identifier echoed back in the reply.
    /// - Parameter code: JavaScript source to evaluate.
    /// - Parameter reply: Called with `(resultString, isError)`.
    nonisolated func evaluate(id: String, code: String, withReply reply: @escaping (String, Bool) -> Void)
}

/// Implemented by the `hs` CLI tool; called by Hammerspoon 2 to push log entries.
@objc protocol HSIPCClientProtocol: NSObjectProtocol {
    /// Deliver a single log entry to the CLI.
    nonisolated func logEntry(level: String, message: String)
}
