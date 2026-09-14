//
//  JSFunction.swift
//  Hammerspoon 2
//

import JavaScriptCore

/// A type alias for JSValue representing a JavaScript function parameter.
/// Using JSFunction (instead of JSValue) in @objc protocol signatures signals
/// to callers and documentation tooling that a callable JS value is expected.
typealias JSFunction = JSValue

/// A type alias for JSValue representing a parameter that should hold a JS string.
///
/// Declaring a JSExport parameter as `String` lets JavaScriptCore silently coerce whatever
/// was actually passed (a number, an array, `null`, ...) into some Swift string before the
/// method body ever runs, which throws away the information needed to reject the call the way
/// Node does (`TypeError [ERR_INVALID_ARG_TYPE]`). Using `JSString` instead signals to callers
/// and documentation tooling that a string is expected here (it still maps to `string` in
/// generated docs/TypeScript, same as `String` would), while letting the method body check
/// `.isString` itself before coercing.
typealias JSString = JSValue

extension JSContext {
    /// Calls `body` and reports whether it raised a JS exception, leaving `self.exception`
    /// set to it if so. `context.exception` itself cannot be polled for this directly: once a
    /// JSContext has a custom `exceptionHandler` installed (as every context in this app does),
    /// JSC clears `context.exception` immediately after invoking that handler, for both
    /// `JSValue.call(withArguments:)` and `.invokeMethod(_:withArguments:)` - confirmed
    /// empirically, not documented behavior. Temporarily wrapping the handler to capture the
    /// exception ourselves, then setting `context.exception` to it fresh right before
    /// returning, propagates it to our own caller.
    func callCapturingException(_ body: () -> JSValue?) -> JSValue? {
        let previousHandler = exceptionHandler
        var caught: JSValue?
        exceptionHandler = { context, exception in
            caught = exception
            previousHandler?(context, exception)
        }
        let result = body()
        exceptionHandler = previousHandler
        if let caught {
            exception = caught
        }
        return result
    }
}
