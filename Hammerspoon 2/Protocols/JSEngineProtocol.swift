//
//  JSEngineProtocol.swift
//  Hammerspoon 2
//
//  Created by Claude on 05/11/2025.
//

import Foundation

/// Protocol abstraction for the JavaScript engine to enable dependency injection and testability
@_documentation(visibility: private)
protocol JSEngineProtocol {
    /// Subscript access to JavaScript context objects
    subscript(key: String) -> Any? { get set }

    /// Evaluates a JavaScript string and returns the result
    /// - Parameter script: The JavaScript code to evaluate
    /// - Returns: The result of the evaluation, or nil if evaluation fails
    @discardableResult func eval(_ script: String) -> Any?

    /// Evaluates JavaScript from a file URL
    /// - Parameters:
    ///   - url: The URL of the JavaScript file to evaluate
    ///   - wrapInIIFE: If true, wraps the script in an immediately-invoked function expression.
    ///     This scopes `const`/`let` bindings to the function rather than the global lexical
    ///     environment, making JS proxies for Swift objects GC-eligible once the script finishes.
    /// - Returns: The result of the evaluation, or nil if evaluation fails
    /// - Throws: HammerspoonError if the file cannot be read or evaluated
    @discardableResult func evalFromURL(_ url: URL, wrapInIIFE: Bool) throws -> Any?

    /// Resets the JavaScript context, creating a fresh environment
    /// - Throws: HammerspoonError if context creation fails
    func resetContext() throws

    /// Checks if a JavaScript context exists
    /// - Returns: true if a context exists, false otherwise
    func hasContext() -> Bool
}

extension JSEngineProtocol {
    /// Convenience overload that evaluates without IIFE wrapping.
    @discardableResult func evalFromURL(_ url: URL) throws -> Any? {
        try evalFromURL(url, wrapInIIFE: false)
    }
}
