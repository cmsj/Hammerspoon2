//
//  JSTestHarness.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Testing
@testable import Hammerspoon_2

/// A test harness for JavaScript integration testing
///
/// This class provides a clean JSContext for testing how modules work
/// when accessed through JavaScript, exactly as users will use them.
///
/// Example usage:
/// ```swift
/// let harness = JSTestHarness()
/// harness.loadModule(HSHashModule.self, as: "hash")
/// let result = harness.eval("hs.hash.md5('hello')")
/// #expect(result == "5d41402abc4b2a76b9719d911017c592")
/// ```
class JSTestHarness {
    private(set) var vm: JSVirtualMachine
    private(set) var context: JSContext

    /// Tracks any JavaScript exceptions that occurred
    private(set) var lastException: JSValue?

    /// Callback storage for async testing
    private var callbacks: [String: () -> Void] = [:]

    init() {
        vm = JSVirtualMachine()
        context = JSContext(virtualMachine: vm)!
        context.name = "Test Context"

        // Capture JavaScript exceptions
        context.exceptionHandler = { [weak self] context, exception in
            self?.lastException = exception
            print("❌ JavaScript Exception: \(exception?.toString() ?? "unknown")")
        }

        // Inject type bridges (for HSRect, HSPoint, etc.)
        do {
            try context.install([TypeBridgesInstaller()])
        } catch {
            print("⚠️ Failed to install type bridges: \(error)")
        }

        // Create the hs namespace object
        setupHSNamespace()

        // Inject basic logging for debugging tests
        setupConsoleLogging()

        // Add test helper functions
        setupTestHelpers()

        let swiftHandler: @convention(block) (String) -> Void = { [weak self] callbackName in
            self?.callbacks[callbackName]?()
        }
        context.setObject(swiftHandler, forKeyedSubscript: "__test_callback" as NSString)
    }

    /// Drain the MainActor queue to ensure all pending tasks complete
    /// This prevents interference between tests
    @MainActor
    static func drainMainActorQueue() async {
        // Yield to allow any pending MainActor tasks to execute
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Module Loading

    /// Load a module into the test context under hs namespace
    /// - Parameters:
    ///   - moduleType: The Swift module class to instantiate
    ///   - name: The JavaScript property name (without 'hs.' prefix)
    func loadModule<T: HSModuleAPI>(_ moduleType: T.Type, as name: String) {
        let module = moduleType.init()

        // Get the hs object and set the module as a property
        guard let hs = context.objectForKeyedSubscript("hs") else {
            print("⚠️ hs namespace not found, call setupHSNamespace first")
            return
        }

        hs.setObject(module, forKeyedSubscript: name as NSString)

        // Try to load the JavaScript enhancement file if it exists
        // Look in the Hammerspoon_2 bundle, not the test bundle
        let bundles = [
            Bundle.main,
            Bundle(identifier: "net.tenshu.Hammerspoon-2")
        ].compactMap { $0 }

        for bundle in bundles {
            if let moduleJS = bundle.url(forResource: "hs.\(name)", withExtension: "js") {
                do {
                    let jsCode = try String(contentsOf: moduleJS, encoding: .utf8)
                    context.evaluateScript(jsCode)
                    break // Successfully loaded, don't try other bundles
                } catch {
                    print("⚠️ Could not load JavaScript enhancement for \(name): \(error)")
                }
            }
        }
    }

    /// Load the full ModuleRoot as 'hs' (mimics real environment)
    func loadModuleRoot() {
        let moduleRoot = ModuleRoot()
        context.setObject(moduleRoot, forKeyedSubscript: "hs" as NSString)
    }

    // MARK: - Script Execution

    /// Evaluate JavaScript code and return the result
    /// - Parameter script: JavaScript code to execute
    /// - Returns: The result converted to a Swift type
    @discardableResult
    func eval(_ script: String) -> Any? {
        lastException = nil
        let result = context.evaluateScript(script)
        return result?.toObject()
    }

    /// Evaluate JavaScript and return the JSValue directly (for advanced assertions)
    /// - Parameter script: JavaScript code to execute
    /// - Returns: The raw JSValue
    func evalValue(_ script: String) -> JSValue? {
        lastException = nil
        return context.evaluateScript(script)
    }

    /// Check if the last evaluation threw a JavaScript exception
    var hasException: Bool {
        return lastException != nil
    }

    /// Get the last exception message (if any)
    var exceptionMessage: String? {
        return lastException?.toString()
    }

    // MARK: - Async Testing Support

    /// Register a Swift callback that JavaScript can invoke
    /// - Parameters:
    ///   - name: JavaScript function name
    ///   - callback: Swift closure to call
    func registerCallback(_ name: String, callback: @escaping () -> Void) {
        callbacks[name] = callback

//        // Create a JavaScript function that calls our Swift callback
//        let jsFunction = context.evaluateScript("""
//            (function() {
//                return function \(name)() {
//                    __swift_callback_\(name)();
//                };
//            })()
//            """)

        // Register the Swift side handler
//        let swiftHandler: @convention(block) (String) -> Void = { [weak self] callbackName in
//            self?.callbacks[callbackName]?()
//        }
//        context.setObject(swiftHandler, forKeyedSubscript: "__test_callback" as NSString)
//        context.setObject(unsafeBitCast(swiftHandler, to: AnyObject.self), forKeyedSubscript: "__swift_callback_\(name)" as NSString)

        // Set the JavaScript function in global scope
//        context.setObject(jsFunction, forKeyedSubscript: name as NSString)
    }

    /// Register a callback that expects arguments
    func registerCallback<T>(_ name: String, callback: @escaping (T) -> Void) {
        // Create a JavaScript function that calls our Swift callback
        let jsFunction = context.evaluateScript("""
            (function() {
                return function \(name)(arg) {
                    __swift_callback_\(name)(arg);
                };
            })()
            """)

        // Register the Swift side handler (using Any to avoid @convention(block) limitation)
        let swiftHandler: @convention(block) (Any) -> Void = { arg in
            if let typedArg = arg as? T {
                callback(typedArg)
            }
        }
        context.setObject(unsafeBitCast(swiftHandler, to: AnyObject.self), forKeyedSubscript: "__swift_callback_\(name)" as NSString)

        // Set the JavaScript function in global scope
        context.setObject(jsFunction, forKeyedSubscript: name as NSString)
    }

    /// Wait for a condition to be true (with timeout)
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - condition: Closure that returns true when the condition is met
    /// - Returns: True if condition was met, false if timeout occurred
    @discardableResult
    func waitFor(timeout: TimeInterval = 2.0, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // Run the runloop to allow timers to fire
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))

            if condition() {
                return true
            }
        }

        return false
    }

    /// Async wait for a condition to be true (with timeout) - supports MainActor tasks
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - condition: Closure that returns true when the condition is met
    /// - Returns: True if condition was met, false if timeout occurred
    @discardableResult
    func waitForAsync(timeout: TimeInterval = 2.0, condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // Use Task.sleep to properly yield and allow MainActor tasks to execute
            try? await Task.sleep(for: .milliseconds(10))

            if condition() {
                return true
            }
        }

        return false
    }

    // MARK: - Assertions

    /// Assert that a JavaScript expression evaluates to true
    /// - Parameter expression: JavaScript expression to evaluate
    func expectTrue(_ expression: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let result = evalValue(expression)
        #expect(result?.toBool() == true, "Expected '\(expression)' to be true", sourceLocation: sourceLocation)
    }

    /// Assert that a JavaScript expression evaluates to false
    /// - Parameter expression: JavaScript expression to evaluate
    func expectFalse(_ expression: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let result = evalValue(expression)
        #expect(result?.toBool() == false, "Expected '\(expression)' to be false", sourceLocation: sourceLocation)
    }

    /// Assert that a JavaScript expression equals a specific value
    /// - Parameters:
    ///   - expression: JavaScript expression to evaluate
    ///   - expected: Expected value
    func expectEqual<T: Equatable>(_ expression: String, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
        let result = eval(expression)
        #expect(result as? T == expected, "Expected '\(expression)' to equal \(expected), got \(String(describing: result))", sourceLocation: sourceLocation)
    }

    /// Assert that the last JavaScript evaluation threw an exception
    func expectException(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(hasException, "Expected JavaScript exception", sourceLocation: sourceLocation)
    }

    // MARK: - Private Setup

    private func setupHSNamespace() {
        // Create an empty hs object to hold modules
        let hs = JSValue(newObjectIn: context)!
        context.setObject(hs, forKeyedSubscript: "hs" as NSString)
    }

    private func setupConsoleLogging() {
        let console = JSValue(newObjectIn: context)!

        console.setObject({ (args: [Any]) in
            let message = args.map { "\($0)" }.joined(separator: " ")
            print("📝 [JS Console]: \(message)")
        }, forKeyedSubscript: "log" as NSString)

        console.setObject({ (args: [Any]) in
            let message = args.map { "\($0)" }.joined(separator: " ")
            print("⚠️ [JS Console]: \(message)")
        }, forKeyedSubscript: "warn" as NSString)

        console.setObject({ (args: [Any]) in
            let message = args.map { "\($0)" }.joined(separator: " ")
            print("❌ [JS Console]: \(message)")
        }, forKeyedSubscript: "error" as NSString)

        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func setupTestHelpers() {
        // Add a typeof function for convenience
        eval("""
        function typeOf(value) {
            return typeof value;
        }
        """)

        // Add assertion helpers
        eval("""
        function assertEquals(actual, expected, message) {
            if (actual !== expected) {
                throw new Error((message || 'Assertion failed') +
                               ': expected ' + expected + ', got ' + actual);
            }
        }

        function assertTrue(value, message) {
            if (!value) {
                throw new Error(message || 'Expected true, got false');
            }
        }

        function assertFalse(value, message) {
            if (value) {
                throw new Error(message || 'Expected false, got true');
            }
        }
        """)
    }
}

// MARK: - Convenience Extensions

extension JSTestHarness {
    /// Load multiple modules at once
    func loadModules(_ modules: [(type: any HSModuleAPI.Type, name: String)]) {
        for (_, name) in modules {
            // We need to use runtime type information here
            // This is a limitation of Swift's type system
            switch name {
            case "hash", "hashing":
                loadModule(HSHashModule.self, as: name)
            case "timer":
                loadModule(HSTimerModule.self, as: name)
            case "application":
                loadModule(HSApplicationModule.self, as: name)
            case "console":
                loadModule(HSConsoleModule.self, as: name)
            case "appinfo":
                loadModule(HSAppInfoModule.self, as: name)
            case "permissions":
                loadModule(HSPermissionsModule.self, as: name)
            case "ax":
                loadModule(HSAXModule.self, as: name)
            case "window":
                loadModule(HSWindowModule.self, as: name)
            default:
                print("⚠️ Unknown module: \(name)")
            }
        }
    }
}
