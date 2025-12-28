//
//  HSClient.swift
//  hs2
//
//  Created on 2025-12-27.
//  IPC client for hs2 CLI tool
//

import Foundation
import CoreFoundation

/// Message ID constants (must match IPCProtocol.swift)
let MSGID_REGISTER: Int32 = 100
let MSGID_UNREGISTER: Int32 = 200
let MSGID_COMMAND: Int32 = 500
let MSGID_QUERY: Int32 = 501
let MSGID_ERROR: Int32 = -1
let MSGID_OUTPUT: Int32 = 1
let MSGID_RETURN: Int32 = 2
let MSGID_CONSOLE: Int32 = 3

/// IPC client managing communication with Hammerspoon 2
class HSClient: Thread {
    // MARK: - Properties

    let remoteName: String
    let localName: String
    let sendTimeout: CFTimeInterval
    let recvTimeout: CFTimeInterval
    let useColors: Bool
    let quietMode: Bool
    let consoleMirroring: Bool
    let customArgs: [String]

    var exitCode: Int32 = 0
    var isDone: Bool = false

    private var localPort: CFMessagePort?
    private var remotePort: CFMessagePort?
    private var runLoop: CFRunLoop?

    // ANSI color codes
    private let colorReset = "\u{001B}[0m"
    private let colorBanner = "\u{001B}[1;34m"  // Bright blue
    private let colorInput = "\u{001B}[32m"     // Green
    private let colorOutput = "\u{001B}[0m"     // Default
    private let colorError = "\u{001B}[31m"     // Red

    // MARK: - Initialization

    init(remoteName: String, timeout: TimeInterval, useColors: Bool, quietMode: Bool, consoleMirroring: Bool, customArgs: [String]) {
        self.remoteName = remoteName
        self.localName = UUID().uuidString
        self.sendTimeout = timeout
        self.recvTimeout = timeout
        self.useColors = useColors
        self.quietMode = quietMode
        self.consoleMirroring = consoleMirroring
        self.customArgs = customArgs

        super.init()
    }

    // MARK: - Thread Main

    override func main() {
        autoreleasepool {
            // Create remote port
            guard let remote = CFMessagePortCreateRemote(nil, remoteName as CFString) else {
                fputs("Error: Could not connect to Hammerspoon 2 (port '\(remoteName)' not found)\n", stderr)
                exitCode = EX_UNAVAILABLE
                isDone = true
                return
            }
            self.remotePort = remote

            // Create local port for receiving messages
            var context = CFMessagePortContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            var shouldFreeInfo: DarwinBoolean = false
            guard let local = CFMessagePortCreateLocal(
                nil,
                localName as CFString,
                { port, msgID, data, info in
                    return HSClient.localPortCallback(port, msgID, data, info)
                },
                &context,
                &shouldFreeInfo
            ) else {
                fputs("Error: Could not create local message port\n", stderr)
                exitCode = EX_UNAVAILABLE
                isDone = true
                return
            }
            self.localPort = local

            // Add to run loop
            let runLoopSource = CFMessagePortCreateRunLoopSource(nil, local, 0)
            let currentRunLoop = CFRunLoopGetCurrent()
            self.runLoop = currentRunLoop
            CFRunLoopAddSource(currentRunLoop, runLoopSource, .defaultMode)

            // Register with remote
            if !registerWithRemote() {
                exitCode = EX_UNAVAILABLE
                isDone = true
                return
            }

            // Run event loop
            CFRunLoopRun()

            // Cleanup
            if let local = localPort {
                CFMessagePortInvalidate(local)
            }
            if let remote = remotePort {
                CFMessagePortInvalidate(remote)
            }

            isDone = true
        }
    }

    // MARK: - Registration

    func registerWithRemote() -> Bool {
        // Construct registration message: instanceID\0{...json...}
        let args: [String: Any] = [
            "quiet": quietMode,
            "console": consoleMirroring,
            "customArgs": customArgs
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: args),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            fputs("Error: Failed to encode registration data\n", stderr)
            return false
        }

        let message = "\(localName)\0\(jsonString)"

        guard let responseData = sendToRemote(message, msgID: MSGID_REGISTER, wantResponse: true) else {
            fputs("Error: Failed to register with Hammerspoon 2\n", stderr)
            return false
        }

        guard let response = String(data: responseData as Data, encoding: .utf8),
              response.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
            fputs("Error: Registration failed\n", stderr)
            return false
        }

        return true
    }

    func unregister() {
        _ = sendToRemote(localName, msgID: MSGID_UNREGISTER, wantResponse: false)
    }

    // MARK: - Command Execution

    func executeCommand(_ command: String) -> Bool {
        fputs("DEBUG: executeCommand called with: '\(command)'\n", stderr)
        fflush(stderr)

        let message = "\(localName)\0\(command)"
        fputs("DEBUG: Sending COMMAND message, msgID=\(MSGID_COMMAND)\n", stderr)
        fflush(stderr)

        guard let responseData = sendToRemote(message, msgID: MSGID_COMMAND, wantResponse: true) else {
            fputs("DEBUG: sendToRemote returned nil\n", stderr)
            fflush(stderr)
            exitCode = EX_UNAVAILABLE
            return false
        }

        fputs("DEBUG: Got response data, length=\(CFDataGetLength(responseData))\n", stderr)
        fflush(stderr)

        guard let response = String(data: responseData as Data, encoding: .utf8),
              response.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
            fputs("DEBUG: Response was not 'ok'\n", stderr)
            fflush(stderr)
            exitCode = EX_DATAERR
            return false
        }

        fputs("DEBUG: executeCommand succeeded\n", stderr)
        fflush(stderr)
        return true
    }

    // MARK: - Message Sending

    func sendToRemote(_ message: String, msgID: Int32, wantResponse: Bool) -> CFData? {
        guard let remote = remotePort else { return nil }

        guard let messageData = message.data(using: .utf8) else { return nil }
        let cfData = messageData as CFData

        let result: Int32
        var returnDataPtr: Unmanaged<CFData>?

        if wantResponse {
            result = withUnsafeMutablePointer(to: &returnDataPtr) { ptr in
                CFMessagePortSendRequest(
                    remote,
                    msgID,
                    cfData,
                    sendTimeout,
                    recvTimeout,
                    CFRunLoopMode.defaultMode.rawValue as CFString,
                    ptr
                )
            }
        } else {
            result = CFMessagePortSendRequest(
                remote,
                msgID,
                cfData,
                sendTimeout,
                0,
                nil,
                nil
            )
        }

        if result != kCFMessagePortSuccess {
            return nil
        }

        return returnDataPtr?.takeRetainedValue()
    }

    // MARK: - Message Receiving

    static func localPortCallback(
        _ port: CFMessagePort?,
        _ msgID: Int32,
        _ data: CFData?,
        _ info: UnsafeMutableRawPointer?
    ) -> Unmanaged<CFData>? {
        guard let info = info else {
            fputs("DEBUG: callback - no info\n", stderr)
            return nil
        }
        let client = Unmanaged<HSClient>.fromOpaque(info).takeUnretainedValue()

        guard let data = data else {
            fputs("DEBUG: callback - no data\n", stderr)
            return nil
        }
        let nsData = data as Data

        guard let message = String(data: nsData, encoding: .utf8) else {
            fputs("DEBUG: callback - invalid UTF8\n", stderr)
            return nil
        }

        fputs("DEBUG: callback - msgID=\(msgID), message='\(message)'\n", stderr)
        fflush(stderr)

        // Route based on message ID
        switch msgID {
        case MSGID_OUTPUT, MSGID_RETURN, MSGID_CONSOLE:
            fputs("DEBUG: Processing OUTPUT/RETURN/CONSOLE message\n", stderr)
            fflush(stderr)
            // Output to stdout
            if !client.quietMode {
                fputs("DEBUG: Not quiet mode, outputting to stdout\n", stderr)
                fflush(stderr)
                let color = client.useColors ? client.colorOutput : ""
                let reset = client.useColors ? client.colorReset : ""
                print("\(color)\(message)\(reset)", terminator: "")
                fflush(stdout)
            } else {
                fputs("DEBUG: Quiet mode enabled\n", stderr)
                fflush(stderr)
            }

        case MSGID_ERROR:
            // Output to stderr
            let color = client.useColors ? client.colorError : ""
            let reset = client.useColors ? client.colorReset : ""
            fputs("\(color)\(message)\(reset)", stderr)
            fflush(stderr)

        default:
            break
        }

        // Return acknowledgment
        let ack = "ack".data(using: .utf8)!
        return Unmanaged.passRetained(ack as CFData)
    }

    // MARK: - Helpers

    func getBanner() -> String {
        if useColors {
            return "\(colorBanner)Hammerspoon 2 REPL\(colorReset)\n"
        } else {
            return "Hammerspoon 2 REPL\n"
        }
    }

    func getPrompt() -> String {
        if useColors {
            return "\(colorInput)> \(colorReset)"
        } else {
            return "> "
        }
    }

    func stopRunLoop() {
        if let runLoop = runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    func stopRunLoopAfterDelay(_ delay: TimeInterval) {
        if let runLoop = runLoop {
            // Schedule a timer on the client thread's run loop to stop it after delay
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in
                CFRunLoopStop(runLoop)
            }
            CFRunLoopAddTimer(runLoop, timer, .defaultMode)
        }
    }
}
