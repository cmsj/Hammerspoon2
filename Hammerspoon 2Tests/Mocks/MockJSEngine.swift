//
//  MockJSEngine.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 05/11/2025.
//

import Foundation
@testable import Hammerspoon_2

/// Mock implementation of JSEngineProtocol for testing
class MockJSEngine: JSEngineProtocol {
    // Track calls for verification
    var evalCalls: [(script: String, result: Any?)] = []
    var evalFromURLCalls: [(url: URL, wrapInIIFE: Bool, result: Any?)] = []
    var resetContextCalls: Int = 0
    var hasContextValue: Bool = true

    // Mock storage for subscript
    private var storage: [String: Any?] = [:]

    // Configure behavior
    var shouldThrowOnEval: Bool = false
    var shouldThrowOnEvalFromURL: Bool = false
    /// Thrown by evalFromURL instead of the generic error when shouldThrowOnEvalFromURL is set
    var evalFromURLError: Error?
    var shouldThrowOnReset: Bool = false
    var evalReturnValue: Any? = "mock eval result"
    var evalFromURLReturnValue: Any? = "mock evalFromURL result"
    /// The onAsyncException handler passed to each evalFromURL call, to simulate a later failure
    var evalFromURLAsyncExceptionHandlers: [((HammerspoonError) -> Void)?] = []

    subscript(key: String) -> Any? {
        get {
            return storage[key] ?? nil
        }
        set {
            storage[key] = newValue
        }
    }

    @discardableResult func eval(_ script: String) -> Any? {
        if shouldThrowOnEval {
            return nil
        }
        let result = evalReturnValue
        evalCalls.append((script: script, result: result))
        return result
    }

    @discardableResult func evalFromURL(_ url: URL,
                                        wrapInIIFE: Bool,
                                        onAsyncException: ((HammerspoonError) -> Void)?) throws -> Any? {
        if shouldThrowOnEvalFromURL {
            throw evalFromURLError ?? HammerspoonError(.vmCreation, msg: "Mock error: evalFromURL failed")
        }
        let result = evalFromURLReturnValue
        evalFromURLCalls.append((url: url, wrapInIIFE: wrapInIIFE, result: result))
        evalFromURLAsyncExceptionHandlers.append(onAsyncException)
        return result
    }

    func resetContext() throws {
        if shouldThrowOnReset {
            throw HammerspoonError(.vmCreation, msg: "Mock error: resetContext failed")
        }
        resetContextCalls += 1
        storage.removeAll()
    }

    func hasContext() -> Bool {
        return hasContextValue
    }

    func shutdown() {
        reset()
    }

    // Helper methods for testing
    func reset() {
        evalCalls.removeAll()
        evalFromURLCalls.removeAll()
        evalFromURLAsyncExceptionHandlers.removeAll()
        resetContextCalls = 0
        storage.removeAll()
        shouldThrowOnEval = false
        shouldThrowOnEvalFromURL = false
        evalFromURLError = nil
        shouldThrowOnReset = false
        hasContextValue = true
    }
}
