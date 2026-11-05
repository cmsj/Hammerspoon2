//
//  UnhandledRejectionInstaller.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

/// JavaScriptCore silently drops a rejected Promise that nothing handles, so an error in, say, a
/// `fetch()` or `hs.spoons.use()` callers didn't `.catch()` would never be seen. This installer
/// has JavaScriptCore report each one instead, by default to the console as an error, like an
/// uncaught exception.
///
/// JavaScriptCore reports a rejection once the microtask queue drains with it still unhandled,
/// so a handler attached in the same turn (`p = Promise.reject(e); p.catch(...)`) prevents it.
struct UnhandledRejectionInstaller: JSContextInstallable {
    /// Called with each unhandled rejection's reason
    var report: @MainActor (JSValue) -> Void = Self.log

    func install(in context: JSContext) throws {
        let report = self.report
        // JavaScriptCore calls this on the thread running JS, which is always the main thread
        let callback: @convention(block) (JSValue, JSValue) -> Void = { _, reason in
            MainActor.assumeIsolated { report(reason) }
        }
        guard let function = JSValue(object: unsafe unsafeBitCast(callback, to: AnyObject.self), in: context) else {
            throw HammerspoonError(.vmCreation, msg: "Couldn't create the unhandled rejection callback")
        }
        var exception: JSValueRef?
        unsafe JSGlobalContextSetUnhandledRejectionCallback(context.jsGlobalContextRef, function.jsValueRef, &exception)
        if unsafe exception != nil {
            throw HammerspoonError(.vmCreation, msg: "Couldn't install the unhandled rejection callback")
        }
    }

    /// Logs a rejection the way `JSEngine` logs an uncaught exception
    static func log(_ reason: JSValue) {
        AKError("Unhandled Promise rejection: \(reason.toString() ?? "unknown")")
        // Anything can be a rejection reason, and reading a property of undefined would throw
        if reason.isObject, let stack = reason.objectForKeyedSubscript("stack"), stack.isString {
            AKError("Stack trace: \(stack)")
        }
    }
}
