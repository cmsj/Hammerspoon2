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

/// IPC client managing communication with Hammerspoon 2
///
/// Uses a dedicated thread for the CFRunLoop required by CFMessagePort.
/// Synchronization between the main thread and the run loop thread uses
/// DispatchSemaphore for proper signaling instead of polling.
class HSClient {
    // MARK: - Properties

    let remoteName: String
    let localName: String
    let sendTimeout: CFTimeInterval
    let recvTimeout: CFTimeInterval
    let useColors: Bool
    let quietMode: Bool
    let customArgs: [String]

    // Thread-safe state via lock
    private let lock = NSLock()
    private var _exitCode: Int32 = 0

    var exitCode: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return _exitCode
    }

    private func setExitCode(_ code: Int32) {
        lock.lock()
        _exitCode = code
        lock.unlock()
    }

    private var localPort: CFMessagePort?
    private var remotePort: CFMessagePort?
    private var runLoop: CFRunLoop?
    private var runLoopThread: Thread?

    /// Signaled when the run loop thread has initialized (or failed)
    private let readySemaphore = DispatchSemaphore(value: 0)
    /// Signaled when the run loop thread has exited
    private let doneSemaphore = DispatchSemaphore(value: 0)
    /// Set to true if initialization succeeded
    private var initSucceeded = false

    // ANSI color codes
    private let colorReset = "\u{001B}[0m"
    private let colorBanner = "\u{001B}[1;34m"  // Bright blue
    private let colorInput = "\u{001B}[32m"     // Green
    private let colorOutput = "\u{001B}[37m"    // White
    private let colorError = "\u{001B}[31m"     // Red

    // MARK: - Initialization

    init(remoteName: String, timeout: TimeInterval, useColors: Bool, quietMode: Bool, customArgs: [String]) {
        self.remoteName = remoteName
        self.localName = UUID().uuidString
        self.sendTimeout = timeout
        self.recvTimeout = timeout
        self.useColors = useColors
        self.quietMode = quietMode
        self.customArgs = customArgs
    }

    // MARK: - Lifecycle

    /// Start the client and wait for initialization to complete.
    /// Returns true if initialization succeeded.
    @discardableResult
    func start() -> Bool {
        let thread = Thread { [weak self] in
            self?.runLoopMain()
        }
        thread.name = "hs2-ipc-client"
        runLoopThread = thread
        thread.start()

        // Wait for initialization (with timeout)
        let result = readySemaphore.wait(timeout: .now() + sendTimeout)
        if result == .timedOut {
            fputs("Error: Timed out waiting for IPC initialization\n", stderr)
            setExitCode(EX_TEMPFAIL)
            return false
        }
        return initSucceeded
    }

    /// Wait for the run loop thread to finish.
    func waitForCompletion(timeout: TimeInterval) {
        _ = doneSemaphore.wait(timeout: .now() + timeout)
    }

    // MARK: - Run Loop Thread

    private func runLoopMain() {
        autoreleasepool {
            // Create remote port
            guard let remote = CFMessagePortCreateRemote(nil, remoteName as CFString) else {
                fputs("Error: Could not connect to Hammerspoon 2 (port '\(remoteName)' not found)\n", stderr)
                setExitCode(EX_UNAVAILABLE)
                readySemaphore.signal()
                doneSemaphore.signal()
                return
            }
            self.remotePort = remote

            // Create local port for receiving messages
            var context = CFMessagePortContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { (info: UnsafeRawPointer?) -> UnsafeRawPointer? in
                    guard let info = info else { return nil }
                    _ = Unmanaged<HSClient>.fromOpaque(info).retain()
                    return info
                },
                release: { (info: UnsafeRawPointer?) in
                    guard let info = info else { return }
                    Unmanaged<HSClient>.fromOpaque(info).release()
                },
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
                setExitCode(EX_UNAVAILABLE)
                readySemaphore.signal()
                doneSemaphore.signal()
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
                CFMessagePortInvalidate(local)
                CFMessagePortInvalidate(remote)
                setExitCode(EX_UNAVAILABLE)
                readySemaphore.signal()
                doneSemaphore.signal()
                return
            }

            // Signal that initialization succeeded
            initSucceeded = true
            readySemaphore.signal()

            // Run event loop (blocks until stopped)
            CFRunLoopRun()

            // Cleanup
            if let local = localPort {
                CFMessagePortInvalidate(local)
            }
            if let remote = remotePort {
                CFMessagePortInvalidate(remote)
            }

            doneSemaphore.signal()
        }
    }

    // MARK: - Registration

    func registerWithRemote() -> Bool {
        // Construct registration message: instanceID\0{...json...}
        let args: [String: Any] = [
            "quiet": quietMode,
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

    func executeCommand(_ command: String, isRetry: Bool = false) -> Bool {
        let message = "\(localName)\0\(command)"

        guard let responseData = sendToRemote(message, msgID: MSGID_COMMAND, wantResponse: true) else {
            setExitCode(EX_UNAVAILABLE)
            return false
        }

        let responseStr = String(data: responseData as Data, encoding: .utf8) ?? "<invalid UTF-8>"
        let trimmed = responseStr.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "error:js" {
            // JavaScript evaluation failed — set non-zero exit code but
            // return true so multi-command sequences continue executing.
            setExitCode(EX_DATAERR)
            return true
        }

        guard trimmed == "ok" else {
            // Auto-reconnect if registration was lost (e.g., JSExport proxy GC'd)
            if responseStr.contains("instance not registered") {
                if !isRetry, registerWithRemote() {
                    // Retry the command after re-registering
                    return executeCommand(command, isRetry: true)
                }
                fputs("Error: lost connection and failed to reconnect\n", stderr)
            } else {
                fputs("Error: unexpected response from Hammerspoon 2: \(responseStr)\n", stderr)
            }

            setExitCode(EX_DATAERR)
            return false
        }

        return true
    }

    // MARK: - Message Sending

    func sendToRemote(_ message: String, msgID: Int32, wantResponse: Bool) -> CFData? {
        guard let remote = remotePort else {
            fputs("Error: No remote port connection\n", stderr)
            return nil
        }

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
            fputs("Error: CFMessagePortSendRequest failed with code \(result)\n", stderr)
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
        guard let info = info else { return nil }
        let client = Unmanaged<HSClient>.fromOpaque(info).takeUnretainedValue()

        guard let data = data else { return nil }
        let nsData = data as Data

        guard let message = String(data: nsData, encoding: .utf8) else { return nil }

        // Route based on message ID
        switch msgID {
        case MSGID_OUTPUT, MSGID_RETURN:
            // Output to stdout
            if !client.quietMode {
                let color = client.useColors ? client.colorOutput : ""
                let reset = client.useColors ? client.colorReset : ""
                print("\(color)\(message)\(reset)", terminator: "")
                fflush(stdout)
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
        let hint = "Use 'var' for persistent bindings (let/const are scoped per entry)"
        if useColors {
            return "\(colorBanner)Hammerspoon 2 REPL\(colorReset)\n\(hint)\n"
        } else {
            return "Hammerspoon 2 REPL\n\(hint)\n"
        }
    }

    func getPrompt() -> String {
        if useColors {
            // \x01 and \x02 bracket non-printing sequences so libedit
            // calculates the visible prompt width correctly. Without them,
            // history navigation (up-arrow) garbles the display.
            return "\u{01}\(colorInput)\u{02}> \u{01}\(colorReset)\u{02}"
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
            // Schedule the timer on the run loop's own thread — CFRunLoop APIs
            // must be called from the thread that owns the run loop.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in
                    CFRunLoopStop(runLoop)
                }
                CFRunLoopAddTimer(runLoop, timer, .defaultMode)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }
}
