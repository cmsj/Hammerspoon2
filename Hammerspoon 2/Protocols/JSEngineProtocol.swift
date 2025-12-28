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

    /// Evaluates JavaScript from a file URL synchronously
    /// - Parameter url: The URL of the JavaScript file to evaluate
    /// - Returns: The result of the evaluation, or nil if evaluation fails
    /// - Throws: HammerspoonError if the file cannot be read or evaluated
    @discardableResult func evalFromURL(_ url: URL) throws -> Any?

    /// Evaluates JavaScript from a file URL asynchronously as an ES module
    /// - Parameter url: The file URL of the JavaScript file to evaluate
    /// - Returns: The result of the evaluation, or nil if evaluation fails
    /// - Throws: HammerspoonError if the file cannot be read or evaluated
    @discardableResult func evalFromURL(_ url: URL) async throws -> Any?

    /// Resets the JavaScript context, creating a fresh environment
    /// - Throws: HammerspoonError if context creation fails
    func resetContext() throws

    /// Checks if a JavaScript context exists
    /// - Returns: true if a context exists, false otherwise
    func hasContext() -> Bool
}
