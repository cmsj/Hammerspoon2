//
//  HammerLog.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import JavaScriptCore
import Synchronization
import os

@_documentation(visibility: private)
enum HammerspoonLogType: Int, CaseIterable, Identifiable {
    case Trace = 0
    case Info
    case Warning
    case Error
    case Console

    var id: Self { self }
    nonisolated var asString: String {
        switch (self) {
        case .Trace:
            return "Debug"
        case .Info:
            return "Info"
        case .Warning:
            return "Warning"
        case .Error:
            return "Error"
        case .Console:
            return "JavaScript"
        }
    }
}

@_documentation(visibility: private)
struct HammerspoonLogEntry: Identifiable, Equatable, Hashable {
    let id = UUID()
    let date = Date()
    let logType: HammerspoonLogType
    let msg: String

    var levelString: String {
        get {
            return self.logType.asString
        }
    }
}

@_documentation(visibility: private)
extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs for Hammerspoon
    static let Hammerspoon = Logger(subsystem: subsystem, category: "Hammerspoon")
}

@_documentation(visibility: private)
@Observable
@MainActor
final class HammerspoonLog: Sendable {
    nonisolated(unsafe) static let shared = HammerspoonLog()

    /// These properties use nonisolated(unsafe) because they need to be readable
    /// from CFRunLoop callbacks (e.g., IPC message port) which run on the main thread
    /// but NOT through GCD's main queue. The @objc thunk and MainActor.assumeIsolated
    /// both use dispatch_assert_queue which fails in that context.
    /// SAFETY: All mutations happen on MainActor (main thread). Reads from CFRunLoop
    /// callbacks are also on the main thread, so there are no data races.
    nonisolated(unsafe) var entries: [HammerspoonLogEntry] = []
    nonisolated(unsafe) var evalHistory: [String] = []

    func log(_ level: HammerspoonLogType, _ msg: String) {
        entries.append(HammerspoonLogEntry(logType: level, msg: msg))
        // FIXME: Make the 100 here, configurable
        if entries.count > 100 {
            entries.removeFirst()
        }
    }

    func clearLog() {
        entries.removeAll()
    }
}

@_documentation(visibility: private)
func AKLog(_ level: HammerspoonLogType, _ msg: String) {
    Task { @MainActor in
        HammerspoonLog.shared.log(level, msg)
    }
}

@_documentation(visibility: private)
func AKInfo(_ msg: String) {
    Logger.Hammerspoon.info("\(msg)")
    AKLog(.Info, msg)
}

@_documentation(visibility: private)
func AKWarning(_ msg: String) {
    Logger.Hammerspoon.warning("\(msg)")
    AKLog(.Warning, msg)
}

@_documentation(visibility: private)
func AKError(_ msg: String) {
    Logger.Hammerspoon.error("\(msg)")
    AKLog(.Error, msg)
}

@_documentation(visibility: private)
func AKTrace(_ msg: String) {
    Logger.Hammerspoon.debug("\(msg)")
    AKLog(.Trace, msg)
}

@_documentation(visibility: private)
func AKConsole(_ msg: String) {
    Logger.Hammerspoon.info("JS Console: \(msg)")
    AKLog(.Console, msg)
}
