//
//  main.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Connects to Hammerspoon 2's IPC server (started with hs.ipc.start() in your config),
//  evaluates JavaScript, and optionally streams log messages with colour-coded levels.
//

import Foundation
import Network
import Synchronization

// MARK: - Constants

private let defaultPort: UInt16 = 51423
private let evalTimeoutSeconds: Double = 30.0

// MARK: - ANSI helpers

private enum ANSI {
    static let reset  = "\u{1B}[0m"
    static let bold   = "\u{1B}[1m"
    static let red    = "\u{1B}[31m"
    static let yellow = "\u{1B}[33m"
    static let green  = "\u{1B}[32m"
    static let blue   = "\u{1B}[34m"
    static let gray   = "\u{1B}[90m"
}

// MARK: - Log levels (must match HammerspoonLogType raw values)

private enum LogLevel: Int, CaseIterable {
    case trace = 0, info = 1, warning = 2, error = 3, console = 4

    init?(string: String) {
        switch string.lowercased() {
        case "trace", "debug": self = .trace
        case "info":           self = .info
        case "warning", "warn": self = .warning
        case "error":          self = .error
        case "javascript", "console", "js": self = .console
        default: return nil
        }
    }

    var color: String {
        switch self {
        case .trace:   return ANSI.gray
        case .info:    return ANSI.blue
        case .warning: return ANSI.yellow
        case .error:   return ANSI.red
        case .console: return ANSI.green
        }
    }

    // Fixed-width label for aligned output
    var label: String {
        switch self {
        case .trace:   return "DEBUG  "
        case .info:    return "INFO   "
        case .warning: return "WARNING"
        case .error:   return "ERROR  "
        case .console: return "JS     "
        }
    }
}

// MARK: - Argument parsing

private struct Arguments {
    var port: UInt16 = defaultPort
    var minLogLevel: Int = Int.max   // Int.max → suppress all log messages
    var showPrompt: Bool = true
}

private func parseArguments() -> Arguments {
    var args = Arguments()
    let argv = CommandLine.arguments
    var idx = 1
    while idx < argv.count {
        switch argv[idx] {
        case "--port", "-p":
            idx += 1
            if idx < argv.count, let p = UInt16(argv[idx]) { args.port = p }
        case "--log-level", "-l":
            idx += 1
            if idx < argv.count {
                if let level = LogLevel(string: argv[idx]) {
                    args.minLogLevel = level.rawValue
                } else if argv[idx].lowercased() == "none" {
                    args.minLogLevel = Int.max
                }
            }
        case "--no-prompt":
            args.showPrompt = false
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            break
        }
        idx += 1
    }
    return args
}

private func writeStderr(_ s: String) {
    if let data = s.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func printHelp() {
    print("""
    hs — Hammerspoon 2 interactive REPL

    USAGE
      hs [options]

    OPTIONS
      -p, --port <n>          Connect to port (default: \(defaultPort))
      -l, --log-level <lvl>   Show log messages at or above this level.
                              Levels: trace  info  warning  error  javascript
                              Default: none (no log messages shown)
          --no-prompt         Suppress "hs> " prompt (useful when piping input)
      -h, --help              Show this help

    SETUP
      Add to your Hammerspoon 2 config (init.js):
        hs.ipc.start()          // default port \(defaultPort)
        hs.ipc.start(9999)      // custom port → hs --port 9999

    INSTALL THE BINARY
      From the Hammerspoon 2 JavaScript console:
        hs.ipc.installBinary()              // installs to /usr/local/bin/hs
        hs.ipc.installBinary("/usr/bin")    // custom directory

    """)
}

// MARK: - IPC client

private final class IPCClient {
    private let port: UInt16
    private let minLogLevel: Int
    private let showPrompt: Bool

    private var nwConn: NWConnection?
    private var receiveBuffer = Data()

    // Background queue for NWConnection callbacks
    private let receiveQueue = DispatchQueue(label: "net.tenshu.Hammerspoon2.hs-ipc")

    // Protects pendingCallback, accessed from both main thread and receiveQueue
    private let lock = NSLock()
    private var pendingCallback: ((String, Bool) -> Void)?

    init(port: UInt16, minLogLevel: Int, showPrompt: Bool) {
        self.port = port
        self.minLogLevel = minLogLevel
        self.showPrompt = showPrompt
    }

    /// Connect synchronously; throws on failure.
    func connect() throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HSIPCClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to create NWConnection port"])
        }

        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host("127.0.0.1"),
                          port: port),
            using: .tcp
        )
        nwConn = conn

        let sema = DispatchSemaphore(value: 0)
        let connectError = Mutex<String?>(nil)

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sema.signal()
            case .failed(let e):
                connectError.withLock { $0 = e.localizedDescription }
                sema.signal()
            case .cancelled:
                connectError.withLock { $0 = "cancelled" }
                sema.signal()
            default:
                break
            }
        }
        conn.start(queue: receiveQueue)
        sema.wait()

        if let err = connectError.withLock({ $0 }) {
            throw NSError(domain: "HSIPCClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: err])
        }

        // Announce which log levels we want
        let levelParam = minLogLevel < Int.max ? minLogLevel : -1
        sendRaw(["type": "hello", "minLogLevel": levelParam])
        scheduleReceive()
    }

    /// Send a JavaScript string for evaluation; blocks until the result arrives (or times out).
    func eval(code: String) -> (result: String, isError: Bool) {
        let evalID = UUID().uuidString
        let sema = DispatchSemaphore(value: 0)
        var evalResult: (String, Bool) = ("undefined", false)

        lock.lock()
        pendingCallback = { result, isError in
            evalResult = (result, isError)
            sema.signal()
        }
        lock.unlock()

        sendRaw(["type": "eval", "id": evalID, "code": code])
        _ = sema.wait(timeout: .now() + evalTimeoutSeconds)

        lock.lock()
        pendingCallback = nil
        lock.unlock()

        return evalResult
    }

    func disconnect() {
        nwConn?.cancel()
    }

    // MARK: - Private networking

    private func sendRaw(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        var line = data
        line.append(0x0A)
        nwConn?.send(content: line, completion: .idempotent)
    }

    private func scheduleReceive() {
        nwConn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                if let error {
                    self.write("\(ANSI.red)Connection lost: \(error.localizedDescription)\(ANSI.reset)\n")
                }
                // Unblock any in-flight eval
                self.lock.lock()
                let cb = self.pendingCallback
                self.pendingCallback = nil
                self.lock.unlock()
                cb?("Connection lost", true)
                exit(1)
            } else {
                self.scheduleReceive()
            }
        }
    }

    private func processBuffer() {
        while let nl = receiveBuffer.firstIndex(of: 0x0A) {
            let line = Data(receiveBuffer[receiveBuffer.startIndex..<nl])
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...nl)
            if !line.isEmpty { handleMessage(line) }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "connected":
            let p = (json["port"] as? Int).map { "\($0)" } ?? "\(port)"
            write("\(ANSI.blue)Connected to Hammerspoon 2 on port \(p)\(ANSI.reset)\n")
            if showPrompt { write("Type JavaScript to evaluate. Use --help for options.\n") }

        case "result":
            let result = json["result"] as? String ?? "undefined"
            let isError = json["isError"] as? Bool ?? false
            lock.lock()
            let cb = pendingCallback
            lock.unlock()
            cb?(result, isError)

        case "log":
            guard let levelStr = json["level"] as? String,
                  let message = json["message"] as? String,
                  let level = LogLevel(string: levelStr),
                  level.rawValue >= minLogLevel else { return }
            // '\n' before the message creates a clean line even if a prompt is showing.
            write("\n\(level.color)\(ANSI.bold)[\(level.label)]\(ANSI.reset) \(message)\n")
            // Re-print the prompt so the user knows we're still ready.
            if showPrompt { write("hs> ") }

        default:
            break
        }
    }

    private func write(_ s: String) {
        print(s, terminator: "")
    }
}

// MARK: - Entry point

private let args = parseArguments()
private let client = IPCClient(port: args.port, minLogLevel: args.minLogLevel, showPrompt: args.showPrompt)

do {
    try client.connect()
} catch {
    writeStderr("Error: Cannot connect to Hammerspoon 2 on port \(args.port).\n")
    writeStderr("Make sure Hammerspoon 2 is running and IPC is enabled:\n")
    writeStderr("  hs.ipc.start()        // default port \(defaultPort)\n")
    writeStderr("  hs.ipc.start(\(args.port))  // this port\n")
    exit(1)
}

// REPL loop — runs on the main thread; NWConnection callbacks arrive on receiveQueue.
while true {
    if args.showPrompt {
        print("hs> ", terminator: "")
    }

    guard let line = readLine(strippingNewline: true) else {
        // EOF (Ctrl-D)
        client.disconnect()
        break
    }

    let code = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { continue }

    let (result, isError) = client.eval(code: code)

    if isError {
        print("\(ANSI.red)\(result)\(ANSI.reset)")
    } else if result != "undefined" {
        print(result)
    }
}
