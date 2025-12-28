//
//  IPCProtocol.swift
//  Hammerspoon 2
//
//  Created on 2025-12-27.
//  IPC Protocol Definitions
//

import Foundation

/// IPC Protocol Version
let IPCProtocolVersion = "2.0"

/// IPC Message IDs for communication protocol
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

    /// Console mirror message
    case console = 3
}

/// Message encoding and decoding utilities
struct IPCMessage {
    /// Encodes a message with optional instance ID
    /// Format: "instanceID\0payload" for messages with instance ID, plain payload otherwise
    static func encode(instanceID: String?, payload: String) -> Data {
        if let instanceID = instanceID {
            let combined = "\(instanceID)\0\(payload)"
            return combined.data(using: .utf8) ?? Data()
        } else {
            return payload.data(using: .utf8) ?? Data()
        }
    }

    /// Decodes a message into instance ID and payload
    /// Returns (instanceID, payload) or (nil, fullMessage) if no null delimiter found
    static func decode(data: Data) -> (instanceID: String?, payload: String) {
        guard let string = String(data: data, encoding: .utf8) else {
            return (nil, "")
        }

        // Look for null delimiter
        if let nullIndex = string.firstIndex(of: "\0") {
            let instanceID = String(string[..<nullIndex])
            let payloadStart = string.index(after: nullIndex)
            let payload = String(string[payloadStart...])
            return (instanceID, payload)
        } else {
            // No delimiter, entire string is payload
            return (nil, string)
        }
    }

    /// Validates an instance ID format (should be a valid UUID or identifier)
    static func isValidInstanceID(_ instanceID: String) -> Bool {
        // Check for UUID format or non-empty alphanumeric string
        if UUID(uuidString: instanceID) != nil {
            return true
        }
        return !instanceID.isEmpty && !instanceID.contains("\0")
    }
}
