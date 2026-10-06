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
    /// calls `fn` through callCapturingException and returns its result - the same shape as a
    /// native on() invoking its JS emitter.
    private func makeContext() -> (JSContext, ExceptionLog) {
        let context = JSContext(virtualMachine: JSVirtualMachine())!
        let log = ExceptionLog()
        context.exceptionHandler = { _, exception in
            log.messages.append(exception?.toString() ?? "unknown")
        }
        let nativeCall: @convention(block) (JSValue) -> JSValue? = { fn in
            guard let ctx = JSContext.current() else { return nil }
            return ctx.callCapturingException { fn.call(withArguments: []) }
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
    func testNoExceptionReturnsResult() {
        let (context, log) = makeContext()
        context.evaluateScript("var result = nativeCall(function() { return 42; })")
        #expect(log.messages.isEmpty)
        #expect(context.objectForKeyedSubscript("result")?.toInt32() == 42)
    }

    @Test("with no JS caller, an exception goes straight to the exceptionHandler, once")
    func testExceptionWithoutJSCallerIsLoggedOnce() throws {
        // As when native code runs on a timer or notification: there's no calling JS to rethrow
        // into, so the exception must be logged directly rather than left in context.exception.
        let (context, log) = makeContext()
        let thrower = try #require(context.evaluateScript("(function() { throw new Error('boom'); })"))
        _ = context.callCapturingException { thrower.call(withArguments: []) }
        #expect(log.messages == ["Error: boom"])
        #expect(context.exception == nil)
    }
}
