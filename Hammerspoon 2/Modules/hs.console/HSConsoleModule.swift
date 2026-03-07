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
}

// MARK: - Thread-safe accessors for IPC
// These are free functions because @objc thunks on a @MainActor class
// enforce actor isolation at runtime, even for nonisolated methods.
// The CFMessagePort callback may fire on any thread, so we need truly
// nonisolated entry points that dispatch to main internally.
// They are exposed to JavaScript via @convention(block) closures.

/// Phase 1: Register __hsConsoleGetConsole / __hsConsoleGetHistory globals.
/// Must run BEFORE ModuleRootInstaller (needs the globals to exist).
struct HSConsoleReadInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let getConsole: @convention(block) () -> String = {
            hsConsoleGetConsole()
        }
        let getHistory: @convention(block) () -> [String] = {
            hsConsoleGetHistory()
        }
        context.setObject(getConsole, forKeyedSubscript: "__hsConsoleGetConsole" as NSString)
        context.setObject(getHistory, forKeyedSubscript: "__hsConsoleGetHistory" as NSString)
    }
}

/// Phase 2: Override the hs.console getter so the FIRST access already
/// returns a wrapper that includes getConsole/getHistory.
/// Must run AFTER ModuleRootInstaller (needs `hs` to exist).
struct HSConsoleGetterInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        context.evaluateScript("""
            (function() {
                var proto = Object.getPrototypeOf(hs);
                var origGetter = Object.getOwnPropertyDescriptor(proto, 'console').get;
                var cached = null;

                Object.defineProperty(proto, 'console', {
                    get: function() {
                        if (!cached) {
                            var orig = origGetter.call(this);
                            cached = Object.create(orig);
                            cached.getConsole = __hsConsoleGetConsole;
                            cached.getHistory = __hsConsoleGetHistory;
                        }
                        return cached;
                    },
                    configurable: true
                });
            })();
        """)
    }
}

@_documentation(visibility: private)
nonisolated func hsConsoleGetConsole() -> String {
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

@_documentation(visibility: private)
nonisolated func hsConsoleGetHistory() -> [String] {
    HammerspoonLog.shared.evalHistory
}
