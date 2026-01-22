//
//  ConsoleModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/12/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

/// These functions are provided to maintain convenience with the console.log() function present in many JavaScript instances.
@objc protocol ConsoleModuleAPI: JSExport {
    /// Log a message to the Hammerspoon Log Window
    /// - Parameter message: A message to log
    @objc func log(_ message: String)

    /// Log an error to the Hammerspoon Log Window
    /// - Parameter message: An error message
    @objc func error(_ message: String)

    /// Log a warning to the Hammerspoon Log WIndow
    /// - Parameter message: A warning message
    @objc func warn(_ message: String)

    /// Log an informational message to the Hammerspoon Log Window
    /// - Parameter message: An informational message
    @objc func info(_ message: String)

    /// Log a debug message to the Hammerspoon Log Window
    /// - Parameter message: A debug message
    @objc func debug(_ message: String)
}

@objc class ConsoleModule: NSObject, ConsoleModuleAPI {
    @objc func log(_ message: String) {
        AKConsole(message)
    }

    @objc func error(_ message: String) {
        AKError(message)
    }

    @objc func warn(_ message: String) {
        AKWarning(message)
    }

    @objc func info(_ message: String) {
        AKInfo(message)
    }

    @objc func debug(_ message: String) {
        AKTrace(message)
    }
}

// MARK: - JSContextInstallable

struct ConsoleModuleInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        context.setObject(ConsoleModule(), forKeyedSubscript: "console" as NSString)
    }
}
