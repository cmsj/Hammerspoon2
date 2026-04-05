//
//  IPCProtocol.swift
//  Hammerspoon 2
//
//  Created on 2025-12-27.
//  IPC Protocol Definitions
//

import Foundation

/// IPC Message IDs for communication protocol
/// These are defined here for reference; the JS side uses its own MSG_ID constants
/// and the CLI uses MSGID_* constants in HSClient.swift.
enum IPCMessageID: Int32 {
    /// Register a new CLI instance
    case register = 100

    /// Unregister a CLI instance
    case unregister = 200

    /// Execute a command
    case command = 500

    /// Execute a query (returns value directly)
    case query = 501

    /// Error message
    case error = -1

    /// Output message
    case output = 1

    /// Return value message
    case returnValue = 2
}
