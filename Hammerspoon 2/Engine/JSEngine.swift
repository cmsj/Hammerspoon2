//
//  HammerCore.swift
//  Hammerspoon 2 Demo
//
//  Created by Chris Jones on 23/09/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - JSContext lifetime diagnostics

private var contextTrackerKey: UInt8 = 0

private final class ContextLifetimeTracker {
    let id: UUID
    init(id: UUID) { self.id = id }
    isolated deinit { AKDebug("JSContext freed: \(id)") }
}

// MARK: -

@_documentation(visibility: private)
class JSEngine {
    static let shared = JSEngine()

    private(set) var id = UUID()
    private var vm: JSVirtualMachine?
    private var context: JSContext?

    // MARK: - JSContext Managing
    private func createContext() throws(HammerspoonError) {
        id = UUID()
        AKTrace("Creating JavaScript context: \(id)")
        vm = JSVirtualMachine()
        guard vm != nil else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (vm)")
        }

        context = JSContext(virtualMachine: vm)
        guard let context else {
            throw HammerspoonError(.vmCreation, msg: "Unknown error (context)")
        }

        context.name = "Hammerspoon \(id)"

        // Attach a sentinel so we can observe exactly when this JSContext's ARC drops to 0.
        unsafe objc_setAssociatedObject(context, &contextTrackerKey, ContextLifetimeTracker(id: id), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Set up exception handler to catch JavaScript errors
        context.exceptionHandler = { context, exception in
            if let exception = exception {
                AKError("JavaScript Exception: \(exception.toString() ?? "unknown")")
                if let stack = exception.objectForKeyedSubscript("stack") {
                    AKError("Stack trace: \(stack)")
                }
            }
        }

        // This is our startup sequence - install all components in order
        do {
            try context.install([
                .fetch,
                ConsoleModuleInstaller(),      // console namespace
                RequireInstaller(),            // require() function
                TypeBridgesInstaller(),        // HSPoint, HSSize, HSRect, HSFont, HSAlert
                .bundled(path: "engine.js", in: .main),  // EventEmitter class
                ModuleRootInstaller(engineID: id),  // hs namespace
            ])
        } catch {
            throw HammerspoonError(.vmCreation, msg: "Failed to install context components: \(error.localizedDescription)")
        }
    }

    private func deleteContext() {
        AKTrace("Destroying JavaScript context: \(id)")

        SettingsManager.shared.removeAllDelegates()

        if let hs = self["hs"] as? JSValue, let moduleRoot = hs.toObjectOf(ModuleRoot.self) as? ModuleRoot {
            moduleRoot.shutdown()
            self["hs"] = nil
        }

        // ConsoleModule has no shutdown() so we can just nil it out
        self["console"] = nil

        // require() isn't even an object, so we can just nil it out
        self["require"] = nil

        if let context = context {
            // Remove global properties from the lexical environment.
            context.globalObject.deleteProperty("hs")
            context.globalObject.deleteProperty("console")
            context.globalObject.deleteProperty("require")
            // Defensively remove require primitives in case require.js failed before its IIFE ran
            context.globalObject.deleteProperty("_hs_readFile")
            context.globalObject.deleteProperty("_hs_fileExists")
            context.globalObject.deleteProperty("_hs_expandPath")
            context.globalObject.deleteProperty("_hs_eval")

            // Force a synchronous full GC cycle (mark → sweep → finalize) before
            // tearing down the VM. JSC's concurrent GC defers ObjC bridge finalizers
            // (CFRelease) to a background sweep thread; if VM teardown races with that
            // thread, the finalizer never runs and Swift objects leak permanently.
            // After shutdown() above, all managed references are removed and all JS
            // variables referencing module proxies are cleared, so every proxy is
            // now GC-unreachable. The synchronous GC collects them and calls each
            // proxy's destructor (CFRelease) before this line returns.
            // Do NOT use JSGarbageCollect here — it schedules an asynchronous
            // collection and returns immediately, re-introducing the same race.
            unsafe JSSynchronousGarbageCollectForDebugging(context.jsGlobalContextRef)
        }

        context = nil
        vm = nil
    }
}

// MARK: - JSEngineProtocol Conformance
extension JSEngine: JSEngineProtocol {
    subscript(key: String) -> Any? {
        get {
            AKDebug("JSEngine subscript get for: \(key)")
            return context?.objectForKeyedSubscript(key as (NSCopying & NSObjectProtocol))
        }
        set {
            AKDebug("JSEngine subscript set for: \(key)")
            context?.setObject(newValue, forKeyedSubscript: key as (NSCopying & NSObjectProtocol))
        }
    }

    @discardableResult func eval(_ script: String) -> Any? {
        return context?.evaluateScript(script)?.toObject()
    }

    @discardableResult func evalFromURL(_ url: URL, wrapInIIFE: Bool = false) throws -> Any? {
        guard url.isFileURL else {
            throw HammerspoonError(.jsEvalURLKind, msg: "Refusing to eval remote URL")
        }

        var script = try String(contentsOf: url, encoding: .utf8)
        if wrapInIIFE {
            // Wrapping in an IIFE scopes top-level `const`/`let` bindings to the function
            // rather than the global lexical environment. Without this, every `const t = hs.timer.new(...)`
            // creates a permanent GC root that prevents the JS proxy from
            // being collected until the entire JSContext is torn down — which only happens after reload
            // unwinds completely. With the IIFE, JSC's incremental GC can collect the proxy once the
            // function returns, allowing moduleRoot.shutdown() to be the sole cleanup path.
            //
            // The opening brace is placed on the same line as the script's first line so that
            // JSC line numbers match the user's file exactly (line N in the error = line N in the file).
            // The only artefact is a +12-column offset for errors on line 1, which is far less
            // confusing than every line number being off by one.
            script = "(function(){" + script + "\n})();"
        }
        return context?.evaluateScript(script, withSourceURL: url)
    }

    func resetContext() throws {
        if hasContext() {
            AKDebug("resetContext()")
            deleteContext()
        }
        try createContext()
    }

    func hasContext() -> Bool {
        return vm != nil || context != nil
    }

    func shutdown() {
        deleteContext()
    }

    /// Creates a Promise that wraps an async operation
    /// - Parameter body: A closure that receives a JSPromiseHolder to resolve/reject the promise
    /// - Returns: A JSPromise representing the Promise, or nil if context is unavailable
    @MainActor
    func createPromise(body: @escaping @MainActor (JSPromiseHolder) -> Void) -> JSPromise? {
        guard let context = context else {
            AKError("JSEngine.createPromise: No context available")
            return nil
        }
        return wrapAsyncInJSPromise(in: context, body: body)
    }

    /// Creates a Promise that resolves immediately with the given value
    /// - Parameter value: The value to resolve with
    /// - Returns: A JSPromise representing the resolved Promise
    func createResolvedPromise(with value: Any?) -> JSPromise? {
        return context?.createResolvedPromise(with: value)
    }

    /// Creates a Promise that rejects immediately with the given error
    /// - Parameter error: The error message
    /// - Returns: A JSPromise representing the rejected Promise
    func createRejectedPromise(with error: String) -> JSPromise? {
        return context?.createRejectedPromise(with: error)
    }
}

// MARK: - JSContextInstallable Implementations

struct RequireInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        // Four primitives used by require.js. They are captured in its IIFE closure
        // and then deleted from global scope, so user code cannot reach them.

        let readFile: @convention(block) (String) -> String? = { path in
            let expanded = NSString(string: path).expandingTildeInPath
            return try? String(contentsOfFile: expanded, encoding: .utf8)
        }

        let fileExists: @convention(block) (String) -> Bool = { path in
            let expanded = NSString(string: path).expandingTildeInPath
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir)
            return exists && !isDir.boolValue
        }

        let expandPath: @convention(block) (String) -> String = { path in
            NSString(string: path).expandingTildeInPath
        }

        let evalScript: @convention(block) (String, String) -> JSValue? = { [weak context] source, filename in
            guard let context else { return nil }
            return context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: filename))
        }

        context.setObject(readFile,   forKeyedSubscript: "_hs_readFile"   as NSString)
        context.setObject(fileExists, forKeyedSubscript: "_hs_fileExists" as NSString)
        context.setObject(expandPath, forKeyedSubscript: "_hs_expandPath" as NSString)
        context.setObject(evalScript, forKeyedSubscript: "_hs_eval"       as NSString)

        guard let requireURL = Bundle.main.url(forResource: "require", withExtension: "js") else {
            throw HammerspoonError(.vmCreation, msg: "require.js not found in bundle")
        }
        context.evaluateScript(try String(contentsOf: requireURL, encoding: .utf8), withSourceURL: requireURL)
    }
}

