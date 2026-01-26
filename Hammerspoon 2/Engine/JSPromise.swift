//
//  JSPromise.swift
//  Hammerspoon 2
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

// Helper class to hold Promise resolve/reject functions
// Pattern inspired by SwiftyJSCore's JSPromiseHolder
//
// This class manages the JS Promise resolve/reject functions and ensures
// they are called on the main thread where JSContext is safe to use.
@_documentation(visibility: private)
@MainActor
final class JSPromiseHolder {
    private let resolve: JSValue
    private let reject: JSValue

    init(resolve: JSValue, reject: JSValue) {
        self.resolve = resolve
        self.reject = reject
    }

    /// Resolve the promise with a value
    func resolveWith(_ value: Any?) {
        resolve.call(withArguments: [value as Any])
    }

    /// Reject the promise with an error
    func rejectWith(_ error: Error) {
        reject.call(withArguments: [error.localizedDescription])
    }

    /// Reject the promise with a string message
    func rejectWithMessage(_ message: String) {
        reject.call(withArguments: [message])
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
func wrapAsyncInJSPromise(in context: JSContext, body: @escaping @MainActor (JSPromiseHolder) -> Void) -> JSValue? {
    // Create the Promise executor function
    let executor: @convention(block) (JSValue, JSValue) -> Void = { resolve, reject in
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
    func createResolvedPromise(with value: Any?) -> JSValue? {
        guard let promiseConstructor = self.objectForKeyedSubscript("Promise") else {
            return nil
        }
        return promiseConstructor.invokeMethod("resolve", withArguments: [value as Any])
    }

    /// Creates a Promise that rejects with the given error message
    @MainActor
    func createRejectedPromise(with error: String) -> JSValue? {
        guard let promiseConstructor = self.objectForKeyedSubscript("Promise") else {
            return nil
        }
        return promiseConstructor.invokeMethod("reject", withArguments: [error])
    }
}
