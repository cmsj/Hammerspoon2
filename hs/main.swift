//
//  main.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Connects to Hammerspoon 2 via XPC (service name: net.tenshu.Hammerspoon-2.ipc),
//  evaluates JavaScript, and optionally streams log messages with colour-coded levels.
//
//  Security: in release builds the XPC connection is rejected by Hammerspoon 2 unless
//  both sides are signed with the same Team ID.
//

import Foundation
import CommandLineKit

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

private nonisolated func writeStderr(_ s: String) {
    if let data = s.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - Log delegate (receives pushed log entries from Hammerspoon 2)

// nonisolated so NSXPCConnection can call logEntry from its internal queue.
private nonisolated final class HSIPCLogDelegate: NSObject, HSIPCClientProtocol {
    nonisolated func logEntry(level: String, message: String) {
        guard let logLevel = LogLevel(string: level) else { return }
        // '\n' before the message keeps output clean even when a readline prompt is showing.
        print("\n\(logLevel.textProperties.apply(to: "[\(logLevel.label)]")) \(message)")
    }
}

// MARK: - IPC client actor
//
// Wraps NSXPCConnection in an actor so the connection is always accessed from the
// actor's isolated context. Actors are Sendable, so the client can be captured in
// @Sendable closures (e.g. the tab-completion syncEval callback).

private actor HSIPCClient {
    private let connection: NSXPCConnection

    init() {
        let c = NSXPCConnection(machServiceName: "net.tenshu.Hammerspoon-2.ipc")
        c.remoteObjectInterface = NSXPCInterface(with: HSIPCServerProtocol.self)
        c.exportedInterface = NSXPCInterface(with: HSIPCClientProtocol.self)
        c.exportedObject = HSIPCLogDelegate()
        c.invalidationHandler = {
            writeStderr("Error: Connection to Hammerspoon 2 was lost.\n")
            exit(1)
        }
        c.resume()
        connection = c
    }

    // Send hello and wait for the "connected" reply.
    func connect(minLogLevel: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? HSIPCServerProtocol
            guard let proxy else {
                continuation.resume(throwing: NSError(domain: "HSIPCClient", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to obtain XPC proxy"]))
                return
            }
            proxy.hello(minLogLevel: minLogLevel) { _ in continuation.resume() }
        }
    }

    // Evaluate JS and return (result, isError).
    func eval(code: String) async -> (String, Bool) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(String, Bool), Never>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: ("XPC error: \(error.localizedDescription)", true))
            } as? HSIPCServerProtocol
            guard let proxy else {
                continuation.resume(returning: ("XPC proxy unavailable", true))
                return
            }
            proxy.evaluate(id: UUID().uuidString, code: code) { result, isError in
                continuation.resume(returning: (result, isError))
            }
        }
    }

    func invalidate() { connection.invalidate() }
}

// MARK: - Argument parsing

private var flags = Flags()
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
        hs.ipc.start()

    INSTALL THE BINARY
      From the Hammerspoon 2 JavaScript console:
        hs.ipc.installBinary()              // installs to /usr/local/bin/hs
        hs.ipc.installBinary("/opt/homebrew/bin")
    """)
    exit(0)
}

private let showPrompt = !noPromptFlag.wasSet

private let minLogLevel: Int = {
    guard let str = logLevelFlag.value else { return Int.max }
    if str.lowercased() == "none" { return Int.max }
    return LogLevel(string: str)?.rawValue ?? Int.max
}()

// MARK: - Completion helpers

// Passes a result from a Task.detached back to a DispatchSemaphore caller.
// @unchecked Sendable is safe: the semaphore provides happens-before ordering between
// the Task write and the outer-scope read — there is no concurrent access.
private final class ResultBox<T: Sendable>: @unchecked Sendable {
    nonisolated(unsafe) var value: T?
}

// MARK: - Entry point
//
// Top-level `await` makes the program entry point async (@MainActor by default isolation).
// HSIPCClient is an actor so it runs on the Swift cooperative pool independently of the
// main thread, preventing NWConnection-style blocking conflicts.

private let client = HSIPCClient()

// Parse api.json concurrently with the XPC connection so completions are ready
// by the time the first prompt appears.
async let completionLoad = loadCompletions()

do {
    try await client.connect(minLogLevel: minLogLevel)
} catch {
    writeStderr("Error: Cannot connect to Hammerspoon 2.\n")
    writeStderr("Make sure Hammerspoon 2 is running and IPC is enabled:\n")
    writeStderr("  hs.ipc.start()\n")
    exit(1)
}

print(TextProperties(.blue, nil).apply(to: "Connected to Hammerspoon 2"))
if showPrompt { print("Type JavaScript to evaluate. Use --help for options.") }

let completionTable = await completionLoad

// REPL loop — LineReader provides readline-style editing and history when stdin is a
// terminal. For piped input or --no-prompt mode, fall back to plain readLine().
private let lineReader = showPrompt ? LineReader() : nil

if let lr = lineReader, let table = completionTable {
    // Synchronous IPC round-trip for live JS reflection (tab-completion only).
    //
    // Task.detached dispatches the eval on the cooperative pool while DispatchSemaphore
    // holds the main OS thread. HSIPCClient is a plain actor (not @MainActor), so its
    // continuations resolve on the cooperative pool — the blocked main thread doesn't
    // create a deadlock. Timeout: 300 ms (a local XPC call should never take this long).
    let syncEval: @Sendable (String) -> String? = { [client] code in
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<String>()
        Task.detached {
            let (r, isError) = await client.eval(code: code)
            if !isError { box.value = r }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.3)
        return box.value
    }

    lr.setCompletionCallback { buffer in
        table.complete(input: buffer, ipcEval: syncEval)
    }
    // Hints fire on every keypress — use api.json only to keep latency near zero.
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
        await client.invalidate()
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
