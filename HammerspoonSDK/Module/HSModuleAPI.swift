//
//  ModuleAPI.swift
//  HammerspoonSDK
//
//  Created by Chris Jones on 27/09/2025.
//

import Foundation
import JavaScriptCore

/// A module: a JS-facing object that Hammerspoon 2 creates once per engine, such as `hs.timer`, or
/// a third-party extension loaded with `require('ext:<name>')`.
///
/// Hammerspoon 2 creates a module the first time a script uses it, with `init(engineID:)`, and
/// calls `shutdown()` when the engine is torn down (on reload or quit). A module must release
/// everything it holds from JavaScript in `shutdown()`: its `JSCallback`s, its `HSObjectTracker`s
/// (with `shutdown()`), and any `JSValue`s its JavaScript enhancement script set on it.
@objc public protocol HSModuleAPI: JSExport {
    /// The module's name, such as `"hs.timer"`, used in log messages
    @objc var moduleName: String { get }

    /// The engine that created the module. A new engine, with a new ID, is created on each reload.
    @objc var engineID: UUID { get }

    /// Creates the module for an engine.
    /// - Parameter engineID: The engine creating it
    init(engineID: UUID)

    /// Stops everything the module started and releases everything it holds from JavaScript.
    /// Called once, when the engine is torn down.
    func shutdown()

    // Drives console.log()/String()/template-literal output in JS. JSExport's default
    // toString() just yields "[object ClassName]", so every conformer must provide its
    // own human-readable rendering.
    /// A human-readable description of the module, for `console.log()` and `String()`
    /// - Returns: The description
    @objc func toString() -> String
}
