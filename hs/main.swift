//
//  main.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Connects to Hammerspoon 2's IPC server (started with hs.ipc.start() in your config),
//  evaluates JavaScript, and optionally streams log messages with colour-coded levels.
//

import Foundation
import Network
import CommandLineKit

// MARK: - Constants

private let defaultPort: UInt16 = 51423

// MARK: - Log levels (must match HammerspoonLogType raw values)

private enum LogLevel: Int, CaseIterable {
    case trace = 0, info = 1, warning = 2, error = 3, console = 4

    nonisolated init?(string: String) {
        switch string.lowercased() {
        case "trace", "debug":              self = .trace
        case "info":                        self = .info
        case "warning", "warn":             self = .warning
        case "error":                       self = .error
        case "javascript", "console", "js": self = .console
        default: return nil
        }
    }

    nonisolated var textProperties: TextProperties {
        switch self {
        case .trace:   return TextProperties(.grey, nil)
        case .info:    return TextProperties(.blue, nil, .bold)
        case .warning: return TextProperties(.yellow, nil, .bold)
        case .error:   return TextProperties(.red, nil, .bold)
        case .console: return TextProperties(.green, nil, .bold)
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

// MARK: - Helpers

private func writeStderr(_ s: String) {
    if let data = s.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - Argument parsing

private var flags = Flags()
private let portFlag     = flags.int("p", "port",      description: "Connect to port (default: \(defaultPort))", value: Int(defaultPort))
private let logLevelFlag = flags.string("l", "log-level", description: "Show log messages at or above this level.\nLevels: trace  info  warning  error  javascript\nDefault: none (no log messages shown)")
private let noPromptFlag = flags.option(nil, "no-prompt",   description: "Suppress 'hs> ' prompt (useful when piping input)")
private let helpFlag     = flags.option("h", "help",        description: "Show this help")

if let failure = flags.parsingFailure() {
    writeStderr("error: \(failure)\n")
    exit(1)
}

if helpFlag.wasSet {
    print(flags.usageDescription(usageName: "USAGE", synopsis: "hs [options]", optionsName: "OPTIONS"))
    print("""

    SETUP
      Add to your Hammerspoon 2 config (init.js):
        hs.ipc.start()          // default port \(defaultPort)
        hs.ipc.start(9999)      // custom port → hs --port 9999

    INSTALL THE BINARY
      From the Hammerspoon 2 JavaScript console:
        hs.ipc.installBinary()              // installs to /usr/local/bin/hs
        hs.ipc.installBinary("/opt/homebrew/bin")
    """)
    exit(0)
}

private let port: UInt16 = {
    let raw = portFlag.value ?? Int(defaultPort)
    return UInt16(clamping: max(1, min(raw, 65535)))
}()

private let showPrompt = !noPromptFlag.wasSet

private let minLogLevel: Int = {
    guard let str = logLevelFlag.value else { return Int.max }
    if str.lowercased() == "none" { return Int.max }
    return LogLevel(string: str)?.rawValue ?? Int.max
}()

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
                print(TextProperties(.red, nil).apply(to: "Connection lost: \(error.localizedDescription)"))
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
            print(TextProperties(.blue, nil).apply(to: "Connected to Hammerspoon 2 on port \(p)"))
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
            // '\n' before the message keeps output clean even when a prompt is showing.
            print("\n\(level.textProperties.apply(to: "[\(level.label)]")) \(message)")

        default:
            break
        }
    }
}

// MARK: - Entry point
//
// Top-level `await` makes the program entry point async (@MainActor by default isolation).
// The `IPCClient` actor runs on the Swift cooperative pool so NWConnection callbacks
// and log message printing are not blocked by readline on the main thread.

private let client = IPCClient(port: port, minLogLevel: minLogLevel, showPrompt: showPrompt)

// Parse api.json concurrently with the TCP connection so tab-completion is ready
// by the time the first prompt appears.
async let completionLoad = loadCompletions()

do {
    try await client.connect()
} catch {
    writeStderr("Error: Cannot connect to Hammerspoon 2 on port \(port).\n")
    writeStderr("Make sure Hammerspoon 2 is running and IPC is enabled:\n")
    writeStderr("  hs.ipc.start()        // default port \(defaultPort)\n")
    writeStderr("  hs.ipc.start(\(port))  // this port\n")
    exit(1)
}

let completionTable = await completionLoad

// REPL loop — LineReader provides readline-style editing and history when stdin is a
// terminal. For piped input or --no-prompt mode we fall back to plain readLine().
private let lineReader = showPrompt ? LineReader() : nil

if let lr = lineReader, let table = completionTable {
    lr.setCompletionCallback { buffer in
        table.complete(input: buffer)
    }
    lr.setHintsCallback { buffer in
        let completions = table.complete(input: buffer)
        guard let first = completions.first else { return nil }
        return (String(first.dropFirst(buffer.count)), TextProperties(.grey, nil))
    }
}

while true {
    let rawLine: String?

    if let lr = lineReader {
        do {
            rawLine = try lr.readLine(
                prompt: "hs> ",
                promptProperties: TextProperties(.blue, nil, .bold)
            )
        } catch LineReaderError.CTRLC {
            rawLine = nil
        } catch {
            rawLine = nil
        }
    } else {
        rawLine = readLine(strippingNewline: true)
    }

    guard let line = rawLine else {
        await client.disconnect()
        break
    }

    let code = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { continue }

    lineReader?.addHistory(code)

    let (result, isError) = await client.eval(code: code)

    if isError {
        print(TextProperties(.red, nil).apply(to: result))
    } else if result != "undefined" {
        print(result)
    }
}
