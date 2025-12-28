//
//  HammerCore.swift
//  Hammerspoon 2 Demo
//
//  Created by Chris Jones on 23/09/2025.
//

import Foundation
import InternalESModuleForSwiftJavaScriptCore
import JavaScriptCore

@_documentation(visibility: private)
class JSEngine {
    static let shared = JSEngine()

    private(set) var id = UUID()
    private var vm: JSVirtualMachine?
    private var context: JSContext?
    private var moduleLoader: MultiRootFSModuleLoader?

    // MARK: - Engine JavaScript component
    private func injectEngineJS() {
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
    private func createContext() throws(HammerspoonError) {
        AKTrace("createContext()")
        vm = JSVirtualMachine()
        guard let vm else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (vm)")
        }

        context = JSContext(virtualMachine: vm)
        guard let context else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (context)")
        }

        id = UUID()
        context.name = "Hammerspoon \(id)"

        var baseURLs = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]
        if let bundleURL = Bundle.main.resourceURL {
            baseURLs.append(bundleURL)
        }
        let moduleLoader = MultiRootFSModuleLoader(virtualMachine: vm, baseURLs: baseURLs)
        self.moduleLoader = moduleLoader
        context.moduleLoaderDelegate = moduleLoader

        // This is our startup sequence.

        // First ensure the console namespace is populated
        self["console"] = ConsoleModule()

        // Inject custom types we want to bridge between JS and Swift
        context.injectTypeBridges()

        // Load and run engine.js
        injectEngineJS()

        // Prepare the hs namespace
        self["hs"] = ModuleRoot()
    }

    private func deleteContext() {
        AKTrace("deleteContext()")

        if let hs = self["hs"] as? JSValue,
            let moduleRoot = hs.toObjectOf(ModuleRoot.self) as? ModuleRoot
        {
            moduleRoot.shutdown()
            self["hs"] = nil
        }

        context = nil
        vm = nil
        moduleLoader = nil
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

        guard let context else {
            throw HammerspoonError(.unknown, msg: "JavaScript context is not available")
        }
        do {
            guard let module = try moduleLoader?.module(for: url) else {
                throw HammerspoonError(.jsModuleEvaluation, msg: "Unable to resolve module URL")
            }
            return try context.evaluate(esModule: module)
        } catch {
            throw HammerspoonError(.jsModuleEvaluation, msg: "\(error)")
        }

    }

    @discardableResult func evalFromURL(_ url: URL) async throws -> Any? {
        guard url.isFileURL else {
            throw HammerspoonError(.jsEvalURLKind, msg: "Refusing to eval remote URL")
        }

        guard let context else {
            throw HammerspoonError(.unknown, msg: "JavaScript context is not available")
        }
        do {
            guard let module = try moduleLoader?.module(for: url) else {
                throw HammerspoonError(.jsModuleEvaluation, msg: "Unable to resolve module URL")
            }
            let promise = try context.evaluate(esModule: module)
            try await awaitPromise(promise, in: context)
            return promise
        } catch {
            throw HammerspoonError(.jsModuleEvaluation, msg: "\(error)")
        }

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

    private func awaitPromise(_ value: JSValue, in context: JSContext) async throws {
        guard value.hasProperty("then") else {
            throw PromiseAwaitError.invalidPromise
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resolve: @convention(block) (JSValue) -> Void = { _ in
                continuation.resume()
            }
            let reject: @convention(block) (JSValue) -> Void = { error in
                let message = error.toString() ?? "Promise rejected"
                continuation.resume(throwing: PromiseAwaitError.rejected(message))
            }
            let resolveValue = JSValue(object: resolve, in: context)
            let rejectValue = JSValue(object: reject, in: context)
            _ = value.invokeMethod(
                "then", withArguments: [resolveValue as Any, rejectValue as Any])
        }
    }
}

@_documentation(visibility: private)
enum PromiseAwaitError: Error {
    case invalidPromise
    case rejected(String)
}
