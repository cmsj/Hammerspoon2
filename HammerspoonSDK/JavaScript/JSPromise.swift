//
//  JSPromise.swift
//  HammerspoonSDK
//
//  Created by Claude Code
//
//  Promise helper implementation inspired by SwiftyJSCore's JSPromiseHolder pattern.
//  See: https://github.com/michalbencur/SwiftyJSCore
//
//  We implement this ourselves rather than importing the library because:
//  - SwiftyJSCore uses Codable-based serialization, not JSExport
//  - We only need the Promise wrapping pattern, not the full library
//  - This avoids adding an unnecessary dependency
//

import Foundation
import JavaScriptCore

/// Type alias for JSValue when it represents a JavaScript Promise.
/// This helps documentation generators identify promise-returning functions.
public typealias JSPromise = JSValue

// Helper class to hold Promise resolve/reject functions
// Pattern inspired by SwiftyJSCore's JSPromiseHolder
//
// This class manages the JS Promise resolve/reject functions and ensures
// they are called on the main thread where JSContext is safe to use.
@_documentation(visibility: private)
@MainActor
public final class JSPromiseHolder {
    private let resolve: JSFunction
    private let reject: JSFunction

    init(resolve: JSFunction, reject: JSFunction) {
        self.resolve = resolve
        self.reject = reject
    }

    /// Resolve the promise with a value
    public func resolveWith(_ value: Any?) {
        resolve.call(withArguments: [value as Any])
    }

    /// Reject the promise with an error
    public func rejectWith(_ error: Error) {
        reject.call(withArguments: [error.localizedDescription])
    }

    /// Reject the promise with a string message
    public func rejectWithMessage(_ message: String) {
        reject.call(withArguments: [message])
    }

    /// Reject the promise with a JS `Error` whose `code` property is set, in the style of Node's
    /// errors (e.g. `err.code === "ENOENT"`), so callers can tell failures apart
    public func rejectWith(code: String, message: String) {
        guard let error = JSValue(newErrorFromMessage: message, in: reject.context) else {
            reject.call(withArguments: [message])
            return
        }
        error.setValue(code, forProperty: "code")
        reject.call(withArguments: [error])
    }
}

/// Wraps a Swift operation as a JavaScript Promise
/// The body closure runs on MainActor and receives a JSPromiseHolder.
///
/// Usage:
/// ```swift
/// let promise = wrapAsyncInJSPromise(in: context) { holder in
///     // This runs on MainActor
///     someAsyncOperation { result in
///         // Callback may be on any thread, dispatch back to main
///         DispatchQueue.main.async {
///             holder.resolveWith(result)
///         }
///     }
/// }
/// ```
@_documentation(visibility: private)
@MainActor
public func wrapAsyncInJSPromise(in context: JSContext, body: @escaping @MainActor (JSPromiseHolder) -> Void) -> JSPromise? {
    // Create the Promise executor function
    let executor: @convention(block) (JSFunction, JSFunction) -> Void = { resolve, reject in
        MainActor.assumeIsolated {
            let holder = JSPromiseHolder(resolve: resolve, reject: reject)
            body(holder)
        }
    }

    // Get the Promise constructor from the global context
    guard let promiseConstructor = context.objectForKeyedSubscript("Promise") else {
        AKError("JSPromise: Promise constructor not found in context")
        return nil
    }

    // Create and return the Promise
    return unsafe promiseConstructor.construct(withArguments: [unsafeBitCast(executor, to: AnyObject.self)])
}

/// Extension to JSContext to provide Promise-related helpers
extension JSContext {
    /// Creates a Promise that resolves with the given value
    @MainActor
    public func createResolvedPromise(with value: Any?) -> JSPromise? {
        guard let promiseConstructor = self.objectForKeyedSubscript("Promise") else {
            return nil
        }
        return promiseConstructor.invokeMethod("resolve", withArguments: [value as Any])
    }

    /// Creates a Promise that rejects with the given error message
    @MainActor
    public func createRejectedPromise(with error: String) -> JSPromise? {
        guard let promiseConstructor = self.objectForKeyedSubscript("Promise") else {
            return nil
        }
        return promiseConstructor.invokeMethod("reject", withArguments: [error])
    }
}
