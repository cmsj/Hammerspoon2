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
    let historyFilePath: URL

    // Global state for completion (needed for C callback)
    private static var currentCompletions: [String] = []
    private static var completionIndex: Int = 0
    private static var completionClient: HSClient?

    // MARK: - Initialization

    init(client: HSClient) {
        self.client = client

        // v1.0: Hardcode history location (persistence deferred to v2.0)
        let configDir = URL(fileURLWithPath: NSString("~/.config/Hammerspoon2").expandingTildeInPath)
        self.historyFilePath = configDir.appendingPathComponent(".cli.history")

        // Set static reference for completion callback
        HSInteractiveREPL.completionClient = client
    }

    // MARK: - REPL Main Loop

    func run() {
        setupReadline()

        // Print banner
        print(client.getBanner())

        // Main loop
        while client.exitCode == EX_OK {
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
                // Error occurred, but continue in interactive mode
                // Exit code is set but we don't exit
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

        // Query Hammerspoon for completions
        if let client = HSInteractiveREPL.completionClient {
            let escaped = inputText.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "'", with: "\\'")
            let query = "JSON.stringify(hs.completionsForInputString('\(escaped)'))"
            let message = "\(client.localName)\0\(query)"

            if let responseData = client.sendToRemote(message, msgID: MSGID_QUERY, wantResponse: true),
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
