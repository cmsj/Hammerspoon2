//
//  main.swift
//  hs2 — Hammerspoon 2 interactive REPL
//
//  Connects to Hammerspoon 2 via XPC, through the HammerspoonIPCBroker launch agent
//  (service name: net.tenshu.Hammerspoon-2.ipc), evaluates JavaScript, and optionally
//  streams log messages with colour-coded levels.
//
//  Security: in release builds the broker rejects hs2 unless both are signed with the
//  same Team ID, and hs2 likewise only talks to a broker signed by that team.
//

import Foundation
import CommandLineKit
import Synchronization
import XPC

// MARK: - Log levels (must match HammerspoonLogType raw values)

extension HammerspoonLogType {
    nonisolated init?(string: String) {
        switch string.lowercased() {
        case "garbage":                     self = .Garbage
        case "debug":                       self = .Debug
        case "info":                        self = .Info
        case "warning", "warn":             self = .Warning
        case "error":                       self = .Error
        case "javascript", "console", "js": self = .Console
        default: return nil
        }
    }

    nonisolated var textProperties: TextProperties {
        switch self {
        case .Garbage: return TextProperties(.grey, nil)
        case .Debug:   return TextProperties(.grey, nil, .bold)
        case .Info:    return TextProperties(.blue, nil, .bold)
        case .Warning: return TextProperties(.yellow, nil, .bold)
        case .Error:   return TextProperties(.red, nil, .bold)
        case .Console: return TextProperties(.green, nil, .bold)
        case .Autocomplete: return TextProperties(.green, nil, .bold)
        }
    }

    nonisolated var label: String {
        switch self {
        case .Garbage: return "GARBAGE"
        case .Debug:   return "DEBUG  "
        case .Info:    return "INFO   "
        case .Warning: return "WARNING"
        case .Error:   return "ERROR  "
        case .Console: return "JS     "
        case .Autocomplete: return "AUTOCMPL"
        }
    }
}

// MARK: - Helpers

private nonisolated func writeStderr(_ s: String) {
    if let data = s.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - IPC client
//
// hs2 talks to Hammerspoon 2 through the HammerspoonIPCBroker launch agent (see HSIPCShared.swift).
// XPCSession is Sendable, so the client can be captured in @Sendable closures (e.g. the
// tab-completion syncEval callback).

private nonisolated func printLogEntry(level: Int, message: String) {
    guard let logLevel = HammerspoonLogType(rawValue: level) else { return }
    // '\n' before the message keeps output clean even when a readline prompt is showing.
    print("\n\(logLevel.textProperties.apply(to: "[\(logLevel.label)]")) \(message)")
}

private nonisolated func handleBrokerMessage(_ message: HSIPCBrokerToClient) -> (any Encodable)? {
    switch message {
    case .log(let level, let text):
        printLogEntry(level: level, message: text)
    case .hostStatus(let connected):
        let text = connected ? "Hammerspoon 2 connected" : "Hammerspoon 2 disconnected"
        print("\n" + TextProperties(.blue, nil).apply(to: text))
    }
    return nil
}

/// The result of evaluating one line of JavaScript in Hammerspoon 2.
private nonisolated enum EvaluationOutcome: Sendable {
    case value(String)
    /// The JavaScript threw; the payload is the error's string form.
    case javaScriptError(String)
    /// The evaluation never got a reply from Hammerspoon 2.
    case transportError(String)
}

private nonisolated final class HSIPCClient: Sendable {
    private let session: XPCSession
    // Set before a deliberate disconnect, so it isn't reported as a lost connection.
    private let isClosing = Atomic(false)

    init() throws {
#if DEBUG
        session = try XPCSession(machService: HSIPC.clientServiceName,
                                 options: .inactive,
                                 incomingMessageHandler: handleBrokerMessage)
#else
        session = try XPCSession(machService: HSIPC.clientServiceName,
                                 options: .inactive,
                                 requirement: HSIPC.brokerRequirement,
                                 incomingMessageHandler: handleBrokerMessage)
#endif
        session.setCancellationHandler { [weak self] error in
            guard let self, !self.isClosing.load(ordering: .acquiring) else { return }
            writeStderr("Error: Connection to the Hammerspoon 2 IPC broker was lost: \(error)\n")
            exit(1)
        }
        try session.activate()
    }

    // Send hello and wait for the broker's reply.
    func connect(minLogLevel: Int) async throws -> HSIPCHelloReply {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(HSIPCClientToBroker.hello(protocolVersion: HSIPC.protocolVersion, minLogLevel: minLogLevel)) {
                    (result: Result<HSIPCHelloReply, any Error>) in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func eval(code: String) async -> EvaluationOutcome {
        await withCheckedContinuation { continuation in
            do {
                try session.send(HSIPCClientToBroker.evaluate(code: code)) { (result: Result<HSIPCEvaluationReply, any Error>) in
                    switch result {
                    case .success(let reply) where !reply.wasEvaluated:
                        // isError is set too, but the failure was reaching Hammerspoon 2, not the JavaScript.
                        continuation.resume(returning: .transportError(reply.result))
                    case .success(let reply):
                        continuation.resume(returning: reply.isError ? .javaScriptError(reply.result) : .value(reply.result))
                    case .failure(let error):
                        continuation.resume(returning: .transportError("XPC error: \(error)"))
                    }
                }
            } catch {
                continuation.resume(returning: .transportError("XPC error: \(error)"))
            }
        }
    }

    func invalidate() {
        isClosing.store(true, ordering: .releasing)
        session.cancel(reason: "hs2 exiting")
    }
}

// MARK: - Argument parsing

private var flags = Flags()
private let logLevelFlag = flags.string("l", "log-level", description: "Show log messages at or above this level.\nLevels: garbage  debug  info  warning  error  javascript\nDefault: none (no log messages shown)")
private let noPromptFlag = flags.option(nil, "no-prompt",   description: "Suppress 'hs2> ' prompt (useful when piping input)")
private let helpFlag     = flags.option("h", "help",        description: "Show this help")

if let failure = flags.parsingFailure() {
    writeStderr("error: \(failure)\n")
    exit(1)
}

if helpFlag.wasSet {
    print(flags.usageDescription(usageName: "USAGE", synopsis: "hs2 [options]", optionsName: "OPTIONS"))
    print("""

    SETUP
      Add to your Hammerspoon 2 config (init.js):
        hs.ipc.start()

    INSTALL THE BINARY
      From the Hammerspoon 2 JavaScript console:
        hs.ipc.installBinary()              // installs to /usr/local/bin/hs2
        hs.ipc.installBinary("/opt/homebrew/bin")

    EXIT STATUS
      0   Success. Always the case for an interactive session.
      1   hs2 couldn't run, or couldn't reach Hammerspoon 2.
      65  JavaScript read from a pipe or file threw an error. Every line is still
          evaluated; the status reflects whether any of them threw.
    """)
    exit(0)
}

private let showPrompt = !noPromptFlag.wasSet

/// Whether a person is typing at hs2. When JavaScript arrives on a pipe or from a redirected file
/// instead, errors are reflected in the exit status so scripts can detect them.
private let isInteractive = isatty(STDIN_FILENO) != 0

/// Exit status when non-interactive input contained JavaScript that threw (EX_DATAERR in
/// sysexits.h). Distinct from 1, which means hs2 couldn't run or reach Hammerspoon 2 at all.
private let exitStatusJavaScriptError: Int32 = 65

private var sawJavaScriptError = false

private let minLogLevel: Int = {
    guard let str = logLevelFlag.value else { return Int.max }
    if str.lowercased() == "none" { return Int.max }
    return HammerspoonLogType(string: str)?.rawValue ?? Int.max
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
// XPC delivers replies on its own queues, so they resolve independently of the main thread.

private let notConnectedHelp = """
    Make sure Hammerspoon 2 is running and IPC is enabled:
      hs.ipc.start()

    """

private let client: HSIPCClient
do {
    client = try HSIPCClient()
} catch {
    writeStderr("Error: Cannot connect to the Hammerspoon 2 IPC broker: \(error)\n")
    writeStderr(notConnectedHelp)
    exit(1)
}

// Parse api.json concurrently with the XPC connection so completions are ready
// by the time the first prompt appears.
async let completionLoad = loadCompletions()

do {
    let hello = try await client.connect(minLogLevel: minLogLevel)
    guard hello.protocolVersion == HSIPC.protocolVersion else {
        writeStderr("Error: This hs2 speaks IPC protocol version \(HSIPC.protocolVersion), but the running broker (\(hello.brokerPath)) speaks \(hello.protocolVersion).\n")
        writeStderr("Make sure hs2 belongs to the copy of Hammerspoon 2 that is running.\n")
        exit(1)
    }
    guard hello.hostConnected else {
        writeStderr("Error: Hammerspoon 2 is not connected to the IPC broker.\n")
        writeStderr(notConnectedHelp)
        exit(1)
    }
} catch {
    writeStderr("Error: Cannot connect to Hammerspoon 2: \(error)\n")
    writeStderr(notConnectedHelp)
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
    // holds the main OS thread. HSIPCClient is not @MainActor and XPC replies arrive on
    // XPC's own queues, so the blocked main thread doesn't create a deadlock. Timeout: 300 ms (a local XPC call should never take this long).
    let syncEval: @Sendable (String) -> String? = { [client] code in
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<String>()
        Task.detached {
            if case .value(let r) = await client.eval(code: code) { unsafe box.value = r }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.3)
        return unsafe box.value
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
                prompt: "hs2> ",
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
        client.invalidate()
        break
    }

    let code = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { continue }

    lineReader?.addHistory(code)

    switch await client.eval(code: code) {
    case .value(let result):
        if result != "undefined" { print(result) }
    case .javaScriptError(let message):
        print(TextProperties(.red, nil).apply(to: message))
        sawJavaScriptError = true
    case .transportError(let message):
        if isInteractive {
            print(TextProperties(.red, nil).apply(to: message))
        } else {
            // Later lines can't be evaluated either, so stop rather than report each one.
            writeStderr("Error: \(message)\n")
            exit(1)
        }
    }
}

if !isInteractive && sawJavaScriptError {
    exit(exitStatusJavaScriptError)
}
