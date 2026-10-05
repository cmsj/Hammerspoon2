//
//  JSFunction.swift
//  Hammerspoon 2
//

import JavaScriptCore

/// A type alias for JSValue representing a JavaScript function parameter.
/// Using JSFunction (instead of JSValue) in @objc protocol signatures signals
/// to callers and documentation tooling that a callable JS value is expected.
typealias JSFunction = JSValue

extension JSContext {
    /// Calls `body` and reports whether it raised a JS exception, leaving `self.exception`
    /// set to it if so. `context.exception` itself cannot be polled for this directly: once a
    /// JSContext has a custom `exceptionHandler` installed (as every context in this app does),
    /// JSC clears `context.exception` immediately after invoking that handler, for both
    /// `JSValue.call(withArguments:)` and `.invokeMethod(_:withArguments:)` - confirmed
    /// empirically, not documented behavior. Temporarily wrapping the handler to capture the
    /// exception ourselves, then setting `context.exception` to it fresh right before
    /// returning, propagates it to our own caller.
    ///
    /// The captured exception is deliberately NOT forwarded to the previous handler: it is being
    /// rethrown into the calling JS, which may well catch it (e.g. `try { hs.ax.on(...) }`), and
    /// the app's handler logs every exception it sees as an error. If the caller doesn't catch
    /// it, it reaches that handler anyway, once, when it escapes the top-level evaluation.
    func callCapturingException(_ body: () -> JSValue?) -> JSValue? {
        let previousHandler = exceptionHandler
        var caught: JSValue?
        exceptionHandler = { _, exception in
            caught = exception
        }
        let result = body()
        exceptionHandler = previousHandler
        if let caught {
            exception = caught
        }
        return result
    }
}
