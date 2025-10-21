//
//  HammerCore.swift
//  Hammerspoon 2 Demo
//
//  Created by Chris Jones on 23/09/2025.
//

import Foundation
import JavaScriptCore

@_documentation(visibility: private)
class JSEngine {
    static let shared = JSEngine()

    var id = UUID()
    private var vm: JSVirtualMachine?
    private var context: JSContext?

    subscript(key: String) -> Any? {
        get {
            AKTrace("JSEngine subscript get for: \(key)")
            return context?.objectForKeyedSubscript(key as (NSCopying & NSObjectProtocol))
        }
        set {
            AKTrace("JSEngine subscript set for: \(key)")
            context?.setObject(newValue, forKeyedSubscript: key as (NSCopying & NSObjectProtocol))
        }
    }

    @discardableResult func eval(_ script: String) -> Any? {
        return context?.evaluateScript(script)?.toObject()
    }

    @discardableResult func evalFromURL(_ url: URL) throws -> Any? {
        let script = try String(contentsOf: url, encoding: .utf8)
        return eval(script)
    }

    // MARK: - Log handling
    func injectLogging() {
        // Provide console.log
        let consoleLog: @convention(block) (Any?) -> Void = { message in
            AKConsole(message as? String ?? "nil")
        }

        let console = JSValue(newObjectIn: context)!
        console.setObject(consoleLog, forKeyedSubscript: "log" as (NSCopying & NSObjectProtocol))
        context?.setObject(console, forKeyedSubscript: "console" as (NSCopying & NSObjectProtocol))

        // Exception handler
        context?.exceptionHandler = { _, exception in
            AKError("JavaScript Error: \(exception?.toString() ?? "unknown")")
        }
    }

    // MARK: - Engine JavaScript component
    func injectEngineJS() {
        guard let engineJS = Bundle.main.url(forResource: "engine", withExtension: "js") else {
            fatalError("Unable to load engine.js - application bundle is corrupt")
        }
        do {
            try evalFromURL(engineJS)
        } catch {
            AKError("engine.js error: \(error.localizedDescription)")
        }
    }

    // MARK: - JSContext Managing
    func createContext() throws(HammerspoonError) {
        AKTrace("createContext()")
        vm = JSVirtualMachine()
        guard vm != nil else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (vm)")
        }

        context = JSContext(virtualMachine: vm)
        guard context != nil else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (context)")
        }

        context?.name = "Hammerspoon \(id)"
        injectLogging()
        injectEngineJS()
        self["hs"] = ModuleRoot()
    }

    func deleteContext() {
        AKTrace("deleteContext()")
        // FIXME: This will need to go through and cleanup any resources currently held by our modules
        // FIXME: This method also needs to be aware if a partial-context exists, e.g. vm is !nil, but context is nil
        context = nil
        vm = nil
    }

    func resetContext() throws {
        if hasContext() {
            AKTrace("resetContext()")
            deleteContext()
        }
        try createContext()
    }

    func hasContext() -> Bool {
        return vm != nil || context != nil
    }
}

