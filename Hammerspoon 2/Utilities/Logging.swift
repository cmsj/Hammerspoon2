//
//  HammerLog.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import Synchronization
import os

enum HammerspoonLogType: Int, CaseIterable, Identifiable {
    case Trace = 0
    case Info
    case Warning
    case Error
    case Console

    var id: Self { self }
    var asString: String {
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
            return "JS"
        }
    }
}

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

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs for Hammerspoon
    static let Hammerspoon = Logger(subsystem: subsystem, category: "Hammerspoon")
}

@Observable
@MainActor
final class HammerspoonLog: Sendable {
    static let shared = HammerspoonLog()

    var entries: [HammerspoonLogEntry] = []

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

func AKLog(_ level: HammerspoonLogType, _ msg: String) {
    Task { @MainActor in
        HammerspoonLog.shared.log(level, msg)
    }
}

func AKInfo(_ msg: String) {
    Logger.Hammerspoon.info("\(msg)")
    AKLog(.Info, msg)
}

func AKWarning(_ msg: String) {
    Logger.Hammerspoon.warning("\(msg)")
    AKLog(.Warning, msg)
}

func AKError(_ msg: String) {
    Logger.Hammerspoon.error("\(msg)")
    AKLog(.Error, msg)
}

func AKTrace(_ msg: String) {
    Logger.Hammerspoon.debug("\(msg)")
    AKLog(.Trace, msg)
}

func AKConsole(_ msg: String) {
    Logger.Hammerspoon.info("JS Console: \(msg)")
    AKLog(.Console, msg)
}
