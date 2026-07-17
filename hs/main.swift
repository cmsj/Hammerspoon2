//
//  main.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Connects to Hammerspoon 2's IPC server (started with hs.ipc.start() in your config),
//  evaluates JavaScript, and optionally streams log messages with colour-coded levels.
//

import Foundation
import Network

// MARK: - Constants

private let defaultPort: UInt16 = 51423

// MARK: - ANSI helpers

// nonisolated so these constants are accessible from the actor's executor
// (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would otherwise infer @MainActor here).
private enum ANSI {
    nonisolated static let reset  = "\u{1B}[0m"
    nonisolated static let bold   = "\u{1B}[1m"
    nonisolated static let red    = "\u{1B}[31m"
    nonisolated static let yellow = "\u{1B}[33m"
    nonisolated static let green  = "\u{1B}[32m"
    nonisolated static let blue   = "\u{1B}[34m"
    nonisolated static let gray   = "\u{1B}[90m"
}

// MARK: - Log levels (must match HammerspoonLogType raw values)

private enum LogLevel: Int, CaseIterable {
    case trace = 0, info = 1, warning = 2, error = 3, console = 4

    nonisolated init?(string: String) {
        switch string.lowercased() {
        case "trace", "debug":          self = .trace
        case "info":                    self = .info
        case "warning", "warn":         self = .warning
        case "error":                   self = .error
        case "javascript", "console", "js": self = .console
        default: return nil
        }
    }

    nonisolated var color: String {
        switch self {
        case .trace:   return ANSI.gray
        case .info:    return ANSI.blue
        case .warning: return ANSI.yellow
        case .error:   return ANSI.red
        case .console: return ANSI.green
        }
    }

    nonisolated var label: String {
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
    var result = Arguments()
    let argv = CommandLine.arguments
    var idx = 1
    while idx < argv.count {
        switch argv[idx] {
        case "--port", "-p":
            idx += 1
            if idx < argv.count, let p = UInt16(argv[idx]) { result.port = p }
        case "--log-level", "-l":
            idx += 1
            if idx < argv.count {
                if let level = LogLevel(string: argv[idx]) {
                    result.minLogLevel = level.rawValue
                } else if argv[idx].lowercased() == "none" {
                    result.minLogLevel = Int.max
                }
            }
        case "--no-prompt":
            result.showPrompt = false
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            break
        }
        idx += 1
    }
    return result
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
//
// Declared as an `actor` so its mutable state is actor-isolated rather than
// @MainActor-isolated (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would otherwise
// infer @MainActor on a plain class, conflicting with the NWConnection callbacks
// that run on networkQueue). Actors have their own executor; the module default
// does not apply to them.

private actor IPCClient {
    private let port: UInt16
    private let minLogLevel: Int
    private let showPrompt: Bool

    private var nwConn: NWConnection?
    private var receiveBuffer = Data()

    // Stored continuations — actor isolation serialises all access, no lock needed.
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var evalContinuation: CheckedContinuation<(String, Bool), Never>?

    // NWConnection requires a DispatchQueue for its callbacks.
    private let networkQueue = DispatchQueue(label: "net.tenshu.Hammerspoon2.hs-ipc")

    init(port: UInt16, minLogLevel: Int, showPrompt: Bool) {
        self.port = port
        self.minLogLevel = minLogLevel
        self.showPrompt = showPrompt
    }

    // MARK: - Public interface

    /// Connect to Hammerspoon 2; throws on failure.
    func connect() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HSIPCClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to create NWConnection port"])
        }

        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort),
            using: .tcp
        )
        nwConn = conn

        // Bridge NWConnection callbacks onto the actor via Task.
        conn.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in await self?.handleConnectionState(state) }
        }

        // Wait for TCP connection to become ready (or fail).
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            conn.start(queue: networkQueue)
        }

        // After connect, drop the state handler so post-connect state changes
        // (e.g. deferred .cancelled after we disconnect) don't touch the now-nil
        // connectContinuation.
        conn.stateUpdateHandler = nil

        let levelParam = minLogLevel < Int.max ? minLogLevel : -1
        sendRaw(["type": "hello", "minLogLevel": levelParam])
        scheduleReceive()
    }

    /// Evaluate JavaScript; suspends until the result arrives or a 30-second timeout.
    func eval(code: String) async -> (String, Bool) {
        sendRaw(["type": "eval", "id": UUID().uuidString, "code": code])

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.timeoutCurrentEval()
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(String, Bool), Never>) in
            evalContinuation = continuation
        }

        timeoutTask.cancel()
        return result
    }

    func disconnect() {
        nwConn?.cancel()
    }

    // MARK: - Connection state

    private func handleConnectionState(_ state: NWConnection.State) {
        guard let continuation = connectContinuation else { return }
        switch state {
        case .ready:
            connectContinuation = nil
            continuation.resume()
        case .failed(let error):
            connectContinuation = nil
            continuation.resume(throwing: error)
        case .cancelled:
            connectContinuation = nil
            continuation.resume(throwing: CancellationError())
        default:
            break
        }
    }

    private func timeoutCurrentEval() {
        if let cb = evalContinuation {
            evalContinuation = nil
            cb.resume(returning: ("Eval timed out after 30 seconds", true))
        }
    }

    // MARK: - Networking

    private func sendRaw(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        var line = data
        line.append(0x0A)
        nwConn?.send(content: line, completion: .idempotent)
    }

    private func scheduleReceive() {
        nwConn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            // NWConnection callback runs on networkQueue; hop to the actor.
            Task { [weak self] in await self?.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let data, !data.isEmpty {
            receiveBuffer.append(data)
            processBuffer()
        }
        if isComplete || error != nil {
            if let error {
                print("\(ANSI.red)Connection lost: \(error.localizedDescription)\(ANSI.reset)")
            }
            if let cb = evalContinuation {
                evalContinuation = nil
                cb.resume(returning: ("Connection lost", true))
            }
            exit(1)
        } else {
            scheduleReceive()
        }
    }

    private func processBuffer() {
        while let nl = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(receiveBuffer[receiveBuffer.startIndex..<nl])
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...nl)
            if !lineData.isEmpty { handleMessage(lineData) }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "connected":
            let p = (json["port"] as? Int).map { "\($0)" } ?? "\(port)"
            print("\(ANSI.blue)Connected to Hammerspoon 2 on port \(p)\(ANSI.reset)")
            if showPrompt { print("Type JavaScript to evaluate. Use --help for options.") }

        case "result":
            let result = json["result"] as? String ?? "undefined"
            let isError = json["isError"] as? Bool ?? false
            if let cb = evalContinuation {
                evalContinuation = nil
                cb.resume(returning: (result, isError))
            }

        case "log":
            guard let levelStr = json["level"] as? String,
                  let message = json["message"] as? String,
                  let level = LogLevel(string: levelStr),
                  level.rawValue >= minLogLevel else { return }
            // '\n' before the message keeps the output clean even if a prompt is showing.
            print("\n\(level.color)\(ANSI.bold)[\(level.label)]\(ANSI.reset) \(message)")
            if showPrompt { print("hs> ", terminator: "") }

        default:
            break
        }
    }
}

// MARK: - Entry point
//
// Top-level `await` makes the program entry point async (@MainActor by default isolation).
// The `IPCClient` actor runs on the Swift cooperative pool so NWConnection callbacks
// and log message printing are not blocked by `readLine()` on the main thread.

private let args = parseArguments()
private let client = IPCClient(port: args.port, minLogLevel: args.minLogLevel, showPrompt: args.showPrompt)

do {
    try await client.connect()
} catch {
    writeStderr("Error: Cannot connect to Hammerspoon 2 on port \(args.port).\n")
    writeStderr("Make sure Hammerspoon 2 is running and IPC is enabled:\n")
    writeStderr("  hs.ipc.start()        // default port \(defaultPort)\n")
    writeStderr("  hs.ipc.start(\(args.port))  // this port\n")
    exit(1)
}

// REPL loop — readLine() blocks the main thread but the actor's cooperative-pool
// executor is unaffected, so log messages and eval results are still delivered.
while true {
    if args.showPrompt {
        print("hs> ", terminator: "")
    }

    guard let line = readLine(strippingNewline: true) else {
        await client.disconnect()
        break
    }

    let code = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { continue }

    let (result, isError) = await client.eval(code: code)

    if isError {
        print("\(ANSI.red)\(result)\(ANSI.reset)")
    } else if result != "undefined" {
        print(result)
    }
}
