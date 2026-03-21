//
//  main.swift
//  hs2
//
//  Created on 2025-12-27.
//  Command-line tool for Hammerspoon 2 IPC
//

import Foundation
import AppKit

// Exit codes (following sysexits.h convention)
let EX_OK: Int32 = 0
let EX_USAGE: Int32 = 64
let EX_DATAERR: Int32 = 65
let EX_NOINPUT: Int32 = 66
let EX_UNAVAILABLE: Int32 = 69
let EX_TEMPFAIL: Int32 = 75

// MARK: - Argument Parsing

var interactive = false
var readStdin = false
var fileName: String?
var commandsToExecute: [String] = []
var remoteName = "Hammerspoon2"
var customArgs: [String] = []
var useColors: Bool? = nil
var quietMode = false
var consoleMirroring = false
var timeout: TimeInterval = 4.0

// Parse arguments
var i = 1
while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]

    if arg == "--" {
        // All remaining args are custom args
        i += 1
        while i < CommandLine.arguments.count {
            customArgs.append(CommandLine.arguments[i])
            i += 1
        }
        break
    }

    switch arg {
    case "-a":
        i += 1
        guard i < CommandLine.arguments.count else {
            fputs("Error: -a requires an argument\n", stderr)
            exit(EX_USAGE)
        }
        customArgs.append(CommandLine.arguments[i])

    case "-i":
        interactive = true

    case "-s":
        readStdin = true

    case "-c":
        i += 1
        guard i < CommandLine.arguments.count else {
            fputs("Error: -c requires an argument\n", stderr)
            exit(EX_USAGE)
        }
        commandsToExecute.append(CommandLine.arguments[i])

    case "-m":
        i += 1
        guard i < CommandLine.arguments.count else {
            fputs("Error: -m requires an argument\n", stderr)
            exit(EX_USAGE)
        }
        remoteName = CommandLine.arguments[i]

    case "-n":
        useColors = false

    case "-N":
        useColors = true

    case "-C":
        consoleMirroring = true

    case "-q":
        quietMode = true

    case "-t":
        i += 1
        guard i < CommandLine.arguments.count else {
            fputs("Error: -t requires an argument\n", stderr)
            exit(EX_USAGE)
        }
        guard let value = TimeInterval(CommandLine.arguments[i]) else {
            fputs("Error: -t requires a numeric argument\n", stderr)
            exit(EX_USAGE)
        }
        timeout = value

    case "-h", "--help":
        print("""
            Usage: hs2 [options] [file] [args]

            Options:
              -a <arg>        Pass argument to script (requires -c or file)
              -i              Interactive REPL mode
              -s              Read commands from stdin
              -c <code>       Execute code string
              -m <name>       Remote port name (default: Hammerspoon2)
              -n              Disable colored output
              -N              Force colored output
              -C              Enable console mirroring (not yet functional)
              -q              Quiet mode (suppress output)
              -t <seconds>    IPC timeout (default: 4.0)
              -h, --help      Show this help

            Arguments after -- are passed to the script as custom arguments.

            Examples:
              hs2 -c "hs.alert.show('Hello')"
              hs2 -i
              hs2 script.js arg1 arg2
              hs2 -c "print(...)" -- custom arg1 arg2
            """)
        exit(EX_OK)

    default:
        if arg.hasPrefix("-") {
            fputs("Error: Unknown option '\(arg)'\n", stderr)
            exit(EX_USAGE)
        } else {
            // First non-option argument is the file name
            if fileName == nil {
                fileName = arg
            } else {
                // Subsequent non-option arguments are custom args
                customArgs.append(arg)
            }
        }
    }

    i += 1
}

// Validate: -a requires -c or file
if !customArgs.isEmpty && commandsToExecute.isEmpty && fileName == nil && !readStdin {
    fputs("Error: -a requires -c <code> or a file argument\n", stderr)
    exit(EX_USAGE)
}

// Validate: conflicting input modes
do {
    var modeCount = 0
    if readStdin { modeCount += 1 }
    if !commandsToExecute.isEmpty { modeCount += 1 }
    if fileName != nil { modeCount += 1 }
    if modeCount > 1 {
        fputs("Error: conflicting options — specify only one of -s, -c, or a file\n", stderr)
        exit(EX_USAGE)
    }
}

// Detect stdin pipe (only if no explicit commands or file specified)
if isatty(STDIN_FILENO) == 0 && commandsToExecute.isEmpty && fileName == nil && !interactive {
    readStdin = true
}

// Determine interactive mode
if !readStdin && fileName == nil && commandsToExecute.isEmpty && !interactive {
    if isatty(STDOUT_FILENO) != 0 {
        interactive = true
    }
}

// Auto-detect colors if not explicitly set
if useColors == nil {
    useColors = isatty(STDOUT_FILENO) != 0
}

// MARK: - Check if Hammerspoon 2 is Running

let bundleID = "net.tenshu.Hammerspoon-2"

func isHammerspoonRunning() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    return runningApps.contains { $0.bundleIdentifier == bundleID }
}

if !isHammerspoonRunning() {
    fputs("Error: Hammerspoon 2 is not running. Please launch it and try again.\n", stderr)
    exit(EX_UNAVAILABLE)
}

// MARK: - Create IPC Client

let client = HSClient(
    remoteName: remoteName,
    timeout: timeout,
    useColors: useColors ?? false,
    quietMode: quietMode,
    consoleMirroring: consoleMirroring,
    customArgs: customArgs
)

// Start client and wait for initialization
if !client.start() {
    exit(client.exitCode)
}

// MARK: - Execute Commands

if interactive {
    // Interactive REPL mode
    let repl = HSInteractiveREPL(client: client)
    repl.run()
} else if readStdin {
    // Read from stdin
    var input = ""
    while let line = readLine() {
        input += line + "\n"
    }

    if !input.isEmpty {
        _ = client.executeCommand(input)
    }
} else if !commandsToExecute.isEmpty {
    // Execute commands from -c
    for command in commandsToExecute {
        if !client.executeCommand(command) {
            break
        }
    }
} else if let file = fileName {
    // Execute file
    let fileURL = URL(fileURLWithPath: file)

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fputs("Error: File not found: \(file)\n", stderr)
        exit(EX_NOINPUT)
    }

    do {
        let script = try String(contentsOf: fileURL, encoding: .utf8)
        _ = client.executeCommand(script)
    } catch {
        fputs("Error: Failed to read file: \(error.localizedDescription)\n", stderr)
        exit(EX_NOINPUT)
    }
}

// Unregister and stop run loop
client.unregister()
client.stopRunLoopAfterDelay(0.5)

// Wait for client thread to finish
client.waitForCompletion(timeout: 5.0)

// Exit with client's exit code
exit(client.exitCode)
