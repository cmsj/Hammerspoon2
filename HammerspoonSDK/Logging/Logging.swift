//
//  Logging.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import Synchronization
import os

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "net.tenshu.Hammerspoon-2"

    /// Logs for Hammerspoon
    nonisolated static let Hammerspoon = Logger(subsystem: subsystem, category: "Hammerspoon")
}

/// Hands a log entry to the host app's Console, on the main actor. Before the host has registered
/// a log handler, entries only reach the unified log.
nonisolated func AKLog(_ level: HammerspoonLogType, _ msg: String) {
    Task { @MainActor in
        HSSDK.logHandler?(level, msg)
    }
}

/// Logs useful information for the user, to the Hammerspoon 2 Console. Callable from any thread.
/// - Parameter msg: The message
nonisolated public func AKInfo(_ msg: String) {
    Logger.Hammerspoon.info("\(msg)")
    AKLog(.Info, msg)
}

/// Logs a recoverable bad state, such as invalid input, to the Hammerspoon 2 Console. Callable
/// from any thread.
/// - Parameter msg: The message
nonisolated public func AKWarning(_ msg: String) {
    Logger.Hammerspoon.warning("\(msg)")
    AKLog(.Warning, msg)
}

/// Logs an unrecoverable failure, such as an OS call failing, to the Hammerspoon 2 Console.
/// Callable from any thread.
/// - Parameter msg: The message
nonisolated public func AKError(_ msg: String) {
    Logger.Hammerspoon.error("\(msg)")
    AKLog(.Error, msg)
}

/// Logs a debug or trace event, such as a watcher starting, to the Hammerspoon 2 Console.
/// Callable from any thread.
/// - Parameter msg: The message
nonisolated public func AKDebug(_ msg: String) {
    Logger.Hammerspoon.debug("\(msg)")
    AKLog(.Debug, msg)
}

/// Logs a line of output from JavaScript's `console` to the Hammerspoon 2 Console.
/// - Parameter msg: The message
@_spi(HammerspoonHost)
nonisolated public func AKConsole(_ msg: String) {
    Logger.Hammerspoon.info("JS Console: \(msg)")
    AKLog(.Console, msg)
}

/// Logs a Console autocompletion result.
/// - Parameter msg: The message
@_spi(HammerspoonHost)
nonisolated public func AKAutocomplete(_ msg: String) {
    // NOTE: This does not pass into Logger, there's really no need
    AKLog(.Autocomplete, msg)
}

/// Lock-free, thread-agnostic gate for `AKGarbage`. `AKGarbage` is called from
/// arbitrary threads/actors (including deinits of non-MainActor types) on some
/// hot paths, so checking whether garbage logging is enabled must not require
/// hopping to `SettingsManager`'s `@MainActor` isolation or touching UserDefaults.
nonisolated private let garbageLoggingGate = Atomic<Bool>(false)

/// Enables/disables `AKGarbage`'s runtime gate. Callable from any thread/actor.
/// `SettingsManager` calls this whenever `garbageLoggingEnabled` changes.
/// - Parameter enabled: Whether `AKGarbage` messages are recorded
@_spi(HammerspoonHost)
nonisolated public func akSetGarbageLoggingEnabled(_ enabled: Bool) {
    garbageLoggingGate.store(enabled, ordering: .relaxed)
}

/// Logs an object lifecycle event (init/deinit), used to diagnose retain cycles and garbage
/// collection. Only recorded when the user turns on garbage collection logging, so the message
/// is only built then. Callable from any thread.
/// - Parameter msg: The message
nonisolated public func AKGarbage(_ msg: @autoclosure () -> String) {
    guard garbageLoggingGate.load(ordering: .relaxed) else { return }
    let message = msg()
    Logger.Hammerspoon.debug("\(message)")
    AKLog(.Garbage, message)
}
