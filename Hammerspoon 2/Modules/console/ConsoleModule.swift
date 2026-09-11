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
    /// Log a value to the Hammerspoon Log Window
    ///
    /// Accepts any number of values, which are space-separated in the log output. Non-string
    /// values (objects, arrays, errors, etc.) are formatted the way Node's `util.inspect` would
    /// render them.
    /// - Parameter value: A value to log
    /// - Example: `console.log("window count:", hs.window.allWindows().length)`
    @objc func log(_ value: JSValue)

    /// Log an error to the Hammerspoon Log Window
    ///
    /// Accepts any number of values; see ``log(_:)`` for formatting details.
    /// - Parameter value: A value to log
    /// - Example: `console.error("failed to load config:", err)`
    @objc func error(_ value: JSValue)

    /// Log a warning to the Hammerspoon Log WIndow
    ///
    /// Accepts any number of values; see ``log(_:)`` for formatting details.
    /// - Parameter value: A value to log
    /// - Example: `console.warn("deprecated call to", "hs.oldThing()")`
    @objc func warn(_ value: JSValue)

    /// Log an informational message to the Hammerspoon Log Window
    ///
    /// Accepts any number of values; see ``log(_:)`` for formatting details.
    /// - Parameter value: A value to log
    /// - Example: `console.info("config reloaded")`
    @objc func info(_ value: JSValue)

    /// Log a debug message to the Hammerspoon Log Window
    ///
    /// Accepts any number of values; see ``log(_:)`` for formatting details.
    /// - Parameter value: A value to log
    /// - Example: `console.debug("state:", { x: 1, y: 2 })`
    @objc func debug(_ value: JSValue)

    /// SKIP_DOCS
    @objc func _internal(_ value: JSValue)
}

@objc class ConsoleModule: NSObject, ConsoleModuleAPI {
    override init() {
        super.init()
        AKGarbage("Init of ConsoleModule")
    }

    isolated deinit {
        AKGarbage("Deinit of ConsoleModule")
    }

    @objc func log(_ value: JSValue) {
        AKConsole(Self.formattedArguments())
    }

    @objc func error(_ value: JSValue) {
        AKError(Self.formattedArguments())
    }

    @objc func warn(_ value: JSValue) {
        AKWarning(Self.formattedArguments())
    }

    @objc func info(_ value: JSValue) {
        AKInfo(Self.formattedArguments())
    }

    @objc func debug(_ value: JSValue) {
        AKDebug(Self.formattedArguments())
    }

    @objc func _internal(_ value: JSValue) {
        AKGarbage(Self.formattedArguments())
    }

    /// Real `console.log`-family functions are variadic, which `JSExport` cannot declare
    /// directly. `JSContext.currentArguments()` recovers every argument JS actually passed,
    /// regardless of the single declared Swift parameter above.
    private static func formattedArguments() -> String {
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
        return arguments.map { NodeUtil.inspect($0) }.joined(separator: " ")
    }
}

// MARK: - JSContextInstallable

struct ConsoleModuleInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        context.setObject(ConsoleModule(), forKeyedSubscript: "console" as NSString)
    }
}
