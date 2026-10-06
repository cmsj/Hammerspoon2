//
//  CallCapturingExceptionTests.swift
//  Hammerspoon 2Tests
//
//  Tests of JSContext.callCapturingException (Engine/JSFunction.swift), which native methods
//  such as hs.ax.on() use to rethrow an exception from the JS they call into back to their own
//  JS caller. The context's exceptionHandler is the app's error log, so an exception the caller
//  catches must never reach it, and one the caller doesn't catch must reach it exactly once.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("callCapturingException tests")
struct CallCapturingExceptionTests {

    /// Records every exception the context's exceptionHandler sees. A JSTestHarness can't be
    /// used here, since it only keeps the most recent exception, not how many there were.
    private final class ExceptionLog {
        var messages: [String] = []
    }

    /// A bare context with a counting exceptionHandler, and a global `nativeCall(fn)` that
    /// calls `fn` through callCapturingException - the same shape as a native on() invoking
    /// its JS emitter.
    private func makeContext() -> (JSContext, ExceptionLog) {
        let context = JSContext(virtualMachine: JSVirtualMachine())!
        let log = ExceptionLog()
        context.exceptionHandler = { _, exception in
            log.messages.append(exception?.toString() ?? "unknown")
        }
        let nativeCall: @convention(block) (JSValue) -> Void = { fn in
            guard let ctx = JSContext.current() else { return }
            _ = ctx.callCapturingException { fn.call(withArguments: []) }
        }
        context.setObject(nativeCall, forKeyedSubscript: "nativeCall" as NSString)
        return (context, log)
    }

    @Test("an uncaught exception reaches the exceptionHandler exactly once")
    func testUncaughtExceptionIsLoggedOnce() {
        let (context, log) = makeContext()
        context.evaluateScript("nativeCall(function() { throw new Error('boom'); })")
        #expect(log.messages == ["Error: boom"])
    }

    @Test("a caught exception never reaches the exceptionHandler")
    func testCaughtExceptionIsNotLogged() {
        let (context, log) = makeContext()
        context.evaluateScript("""
            var caught = null;
            try {
                nativeCall(function() { throw new Error('boom'); });
            } catch (err) {
                caught = err.message;
            }
        """)
        #expect(log.messages.isEmpty)
        #expect(context.objectForKeyedSubscript("caught")?.toString() == "boom")
    }

    @Test("an exception rethrown through nested native calls is logged exactly once")
    func testNestedUncaughtExceptionIsLoggedOnce() {
        let (context, log) = makeContext()
        context.evaluateScript("""
            nativeCall(function() {
                nativeCall(function() { throw new Error('boom'); });
            })
        """)
        #expect(log.messages == ["Error: boom"])
    }

    @Test("no exception leaves the exceptionHandler untouched and returns the result")
    func testNoExceptionIsNotLogged() {
        let (context, log) = makeContext()
        context.evaluateScript("var ran = false; nativeCall(function() { ran = true; })")
        #expect(log.messages.isEmpty)
        #expect(context.objectForKeyedSubscript("ran")?.toBool() == true)
    }
}
