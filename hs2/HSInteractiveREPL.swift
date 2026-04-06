//
//  HSInteractiveREPL.swift
//  hs2
//
//  Created on 2025-12-27.
//  Interactive REPL using libedit
//

import Foundation
import Darwin

/// Interactive REPL for hs2 CLI tool
class HSInteractiveREPL {
    // MARK: - Properties

    let client: HSClient

    /// Timeout for tab completion IPC queries (seconds).
    /// Shorter than the default command timeout since completions should feel instant.
    private static let completionTimeout: CFTimeInterval = 1.0

    // Global state for completion (needed for C callback).
    // Single-REPL assumption: only one HSInteractiveREPL instance exists at a time.
    private static var currentCompletions: [String] = []
    private static var completionIndex: Int = 0
    private static var completionClient: HSClient?

    // MARK: - Initialization

    init(client: HSClient) {
        self.client = client

        // Set static reference for completion callback
        HSInteractiveREPL.completionClient = client
    }

    // MARK: - REPL Main Loop

    func run() {
        setupReadline()

        // Print banner
        print(client.getBanner())

        // Main loop
        while true {
            // Display prompt
            let prompt = client.getPrompt()

            // Read line using libedit
            guard let inputPtr = readline(prompt) else {
                // Ctrl-D pressed or EOF
                print()  // Print newline
                break
            }

            // Convert to Swift string
            let input = String(cString: inputPtr)
            free(inputPtr)

            // Skip empty lines
            if input.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                continue
            }

            // Add to history (in-memory only for v1.0)
            add_history(input)

            // Execute command
            if !client.executeCommand(input) {
                // IPC error — report it but stay in the REPL
                fputs("Error: command failed (IPC error)\n", stderr)
            }
        }

        // Note: History persistence deferred to v2.0
    }

    // MARK: - Readline Setup

    private func setupReadline() {
        // Set completion function
        rl_attempted_completion_function = HSInteractiveREPL.completionFunction

        // Don't append space after completion
        rl_completion_append_character = 0

        // Note: History loading/saving deferred to v2.0
    }

    // MARK: - Tab Completion

    /// Completion function bridge for libedit
    private static let completionFunction: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) = { text, start, end in
        rl_attempted_completion_over = 1

        guard let text = text else { return nil }

        // Convert to Swift string
        let inputText = String(cString: text)

        // Query Hammerspoon for completions.
        // This is a synchronous IPC call from the readline callback, which runs on the
        // main thread. CFMessagePortSendRequest internally spins the calling thread's
        // run loop while waiting for a reply, but this is safe because the main thread
        // has no CFRunLoop sources registered — readline owns the thread, so there is
        // nothing to re-enter. The IPC run loop for receiving messages lives on a
        // separate thread (hs2-ipc-client).
        // Note: if Hammerspoon is unresponsive, this blocks for up to sendTimeout +
        // recvTimeout (default 8s total).
        if let client = HSInteractiveREPL.completionClient {
            // JSON-encode the input to safely embed it in a JS string literal
            guard let jsonData = try? JSONSerialization.data(withJSONObject: [inputText]),
                  let jsonArray = String(data: jsonData, encoding: .utf8) else {
                HSInteractiveREPL.currentCompletions = []
                return nil
            }
            // jsonArray is e.g. ["hs.win"] — extract the inner string including quotes
            let jsonStr = String(jsonArray.dropFirst(1).dropLast(1))
            let query = "JSON.stringify(completionsForInputString(\(jsonStr)))"
            let message = "\(client.localName)\0\(query)"

            if let responseData = client.sendToRemote(message, msgID: MSGID_QUERY, wantResponse: true, timeout: HSInteractiveREPL.completionTimeout),
               let response = String(data: responseData as Data, encoding: .utf8) {
                // Parse JSON response
                if let jsonData = response.data(using: .utf8),
                   let completions = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                    HSInteractiveREPL.currentCompletions = completions
                } else {
                    HSInteractiveREPL.currentCompletions = []
                }
            } else {
                HSInteractiveREPL.currentCompletions = []
            }
        }

        // Reset completion index
        HSInteractiveREPL.completionIndex = 0

        // Return matches using rl_completion_matches
        return rl_completion_matches(text, HSInteractiveREPL.completionGenerator)
    }

    /// Completion generator for libedit
    private static let completionGenerator: (@convention(c) (UnsafePointer<CChar>?, Int32) -> UnsafeMutablePointer<CChar>?) = { text, state in
        // On first call (state == 0), we've already populated currentCompletions
        // On subsequent calls, return next match

        if HSInteractiveREPL.completionIndex < HSInteractiveREPL.currentCompletions.count {
            let match = HSInteractiveREPL.currentCompletions[HSInteractiveREPL.completionIndex]
            HSInteractiveREPL.completionIndex += 1
            return strdup(match)
        }

        return nil
    }
}
