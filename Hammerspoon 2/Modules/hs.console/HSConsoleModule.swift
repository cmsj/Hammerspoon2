//
//  ConsoleModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

// TODO: Rename this to hs.log and have the UI talk about it as a Log Window. "Console" is more confusing than ever, given JavaScript.

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import AppKit

// MARK: - Declare our JavaScript API

/// Module for controlling the Hammerspoon console
@objc protocol HSConsoleModuleAPI: JSExport {
    /// Open the console window
    @objc func open()

    /// Close the console window
    @objc func close()

    /// Clear all console output
    @objc func clear()

    /// Print a message to the console
    /// - Parameter message: The message to print
    @objc func print(_ message: String)

    /// Print a debug message to the console
    /// - Parameter message: The message to print
    @objc func debug(_ message: String)

    /// Print an info message to the console
    /// - Parameter message: The message to print
    @objc func info(_ message: String)

    /// Print a warning message to the console
    /// - Parameter message: The message to print
    @objc func warning(_ message: String)

    /// Print an error message to the console
    /// - Parameter message: The message to print
    @objc func error(_ message: String)

    /// Get all console output as a single string
    /// - Returns: All log entries formatted with timestamps
    @objc func getConsole() -> String

    /// Get the REPL evaluation history
    /// - Returns: Array of previously evaluated expressions
    @objc func getHistory() -> [String]
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSConsoleModule: NSObject, HSModuleAPI, HSConsoleModuleAPI {
    var name = "hs.console"

    // MARK: - Module lifecycle
    override required init() { super.init() }

    func shutdown() {}

    isolated deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Window management

    @objc func open() {
        if let url = URL(string:"hammerspoon2://openConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func close() {
        if let url = URL(string:"hammerspoon2://closeConsole") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Console output

    @objc func clear() {
        Task { @MainActor in
            HammerspoonLog.shared.clearLog()
        }
    }

    @objc func print(_ message: String) {
        AKConsole(message)
    }

    @objc func debug(_ message: String) {
        AKTrace(message)
    }

    @objc func info(_ message: String) {
        AKInfo(message)
    }

    @objc func warning(_ message: String) {
        AKWarning(message)
    }

    @objc func error(_ message: String) {
        AKError(message)
    }

    // MARK: - Console read methods

    @objc func getConsole() -> String {
        let log = HammerspoonLog.shared
        return log.entries.map { entry in
            let date = entry.date.formatted(
                .verbatim(
                    "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                    locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent
                )
            )
            return "\(date) - \(entry.logType.asString): \(entry.msg)"
        }.joined(separator: "\n")
    }

    @objc func getHistory() -> [String] {
        HammerspoonLog.shared.evalHistory
    }
}
