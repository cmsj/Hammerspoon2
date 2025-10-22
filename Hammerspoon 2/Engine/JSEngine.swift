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

        let console = JSValue(newObjectIn: context)!
        console.setObject(consoleLog, forKeyedSubscript: NSString("log"))
        console.setObject(traceLog, forKeyedSubscript: NSString("debug"))
        console.setObject(infoLog, forKeyedSubscript: NSString("info"))
        console.setObject(warningLog, forKeyedSubscript: NSString("warning"))
        console.setObject(errorLog, forKeyedSubscript: NSString("error"))
        context?.setObject(console, forKeyedSubscript: NSString("console"))

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

        if let hs = self["hs"] as? JSValue, let moduleRoot = hs.toObjectOf(ModuleRoot.self) as? ModuleRoot {
            moduleRoot.shutdown()
            self["hs"] = nil
        }

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

