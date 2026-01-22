//
//  HammerCore.swift
//  Hammerspoon 2 Demo
//
//  Created by Chris Jones on 23/09/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

@_documentation(visibility: private)
class JSEngine {
    static let shared = JSEngine()

    private(set) var id = UUID()
    private var vm: JSVirtualMachine?
    private var context: JSContext?



    // MARK: - JSContext Managing
    private func createContext() throws(HammerspoonError) {
        AKTrace("createContext()")
        vm = JSVirtualMachine()
        guard vm != nil else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (vm)")
        }

        context = JSContext(virtualMachine: vm)
        guard let context else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (context)")
        }

        id = UUID()
        context.name = "Hammerspoon \(id)"

        // This is our startup sequence - install all components in order
        do {
            try context.install([
                ConsoleModuleInstaller(),      // console namespace
                RequireInstaller(),            // require() function
                TypeBridgesInstaller(),        // HSPoint, HSSize, HSRect, HSFont, HSAlert
                .bundled(path: "engine.js", in: .main),  // EventEmitter class
                ModuleRootInstaller(),         // hs namespace
            ])
        } catch {
            throw HammerspoonError(.vmCreation, msg: "Failed to install context components: \(error.localizedDescription)")
        }
    }

    private func deleteContext() {
        AKTrace("deleteContext()")

        if let hs = self["hs"] as? JSValue, let moduleRoot = hs.toObjectOf(ModuleRoot.self) as? ModuleRoot {
            moduleRoot.shutdown()
            self["hs"] = nil
        }

        context = nil
        vm = nil
    }
}

// MARK: - JSEngineProtocol Conformance
extension JSEngine: JSEngineProtocol {
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
        guard url.isFileURL else {
            throw HammerspoonError(.jsEvalURLKind, msg: "Refusing to eval remote URL")
        }

        let script = try String(contentsOf: url, encoding: .utf8)
        return context?.evaluateScript(script, withSourceURL: url)
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

// MARK: - JSContextInstallable Implementations

struct RequireInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let require: @convention(block) (String) -> (JSValue?) = { path in
            let expandedPath = NSString(string: path).expandingTildeInPath

            // Return void or throw an error here.
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                AKError("require(): \(expandedPath) could not be found. Current working directory is \(FileManager.default.currentDirectoryPath)")
                return nil
            }

            let fileURL = URL(fileURLWithPath: expandedPath)

            guard let fileContent = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
                AKError("require(): Unable to read \(expandedPath)")
                return nil
            }

            return context.evaluateScript(fileContent, withSourceURL: fileURL)
        }

        context.setObject(require, forKeyedSubscript: "require" as NSString)
    }
}

