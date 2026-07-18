//
//  HSIPCProtocols.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Mirror of Hammerspoon 2/Modules/hs.ipc/HSIPCProtocols.swift.
//  Both sides must declare identical @objc protocol names and selector signatures
//  so NSXPCInterface can match them at runtime.
//

import Foundation

/// Implemented by the Hammerspoon 2 app; called by the `hs` CLI tool.
@objc protocol HSIPCServerProtocol: NSObjectProtocol {
    nonisolated func hello(minLogLevel: Int, withReply reply: @escaping (String) -> Void)
    nonisolated func evaluate(id: String, code: String, withReply reply: @escaping (String, Bool) -> Void)
}

/// Implemented by the `hs` CLI tool; called by Hammerspoon 2 to push log entries.
@objc protocol HSIPCClientProtocol: NSObjectProtocol {
    nonisolated func logEntry(level: String, message: String)
}
