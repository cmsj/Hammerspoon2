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

extension JSContext {
    func injectLogging() {
        // Provide:
        //  * console.log
        //  * console.debug
        //  * console.info
        //  * console.warning
        //  * console.error
        let consoleLog: @convention(block) (Any?) -> Void = { message in
            AKConsole(message as? String ?? "nil")
        }
        let traceLog: @convention(block) (Any?) -> Void = { message in
            AKTrace(message as? String ?? "nil")
        }
        let infoLog: @convention(block) (Any?) -> Void = { message in
            AKInfo(message as? String ?? "nil")
        }
        let warningLog: @convention(block) (Any?) -> Void = { message in
            AKWarning(message as? String ?? "nil")
        }
        let errorLog: @convention(block) (Any?) -> Void = { message in
            AKError(message as? String ?? "nil")
        }

        let console = JSValue(newObjectIn: self)!
        console.setObject(consoleLog, forKeyedSubscript: NSString("log"))
        console.setObject(traceLog, forKeyedSubscript: NSString("debug"))
        console.setObject(infoLog, forKeyedSubscript: NSString("info"))
        console.setObject(warningLog, forKeyedSubscript: NSString("warning"))
        console.setObject(errorLog, forKeyedSubscript: NSString("error"))
        self.setObject(console, forKeyedSubscript: NSString("console"))

        // Exception handler
        self.exceptionHandler = { _, exception in
            AKError("JavaScript Exception: \(exception?.toString() ?? "unknown")")
        }
    }
}

@_documentation(visibility: private)
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
