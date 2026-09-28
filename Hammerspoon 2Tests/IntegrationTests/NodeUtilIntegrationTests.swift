//
//  NodeUtilIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Test context

// NodeUtilTestContext creates an isolated JSContext with the Node builtins registry and
// require() installed (mirroring NodeFSTestContext in NodeFSIntegrationTests.swift).
private final class NodeUtilTestContext {
    let context: JSContext
    private(set) var lastException: JSValue?

    init() throws {
        let vm = JSVirtualMachine()
        let ctx = JSContext(virtualMachine: vm)!
        ctx.name = "NodeUtilTestContext"
        context = ctx

        ctx.exceptionHandler = { [weak self] _, exc in self?.lastException = exc }
        try NodeBuiltinModulesInstaller().install(in: ctx)
        try RequireInstaller().install(in: ctx)
        ctx.evaluateScript("var util = require('util')")
    }

    @discardableResult
    func eval(_ script: String) -> Any? {
        lastException = nil
        return context.evaluateScript(script)?.toObject()
    }

    func evalString(_ script: String) -> String? { eval(script) as? String }
    func evalBool(_ script: String) -> Bool? { eval(script) as? Bool }

    var hadException: Bool { lastException != nil }
}

// MARK: - Test suites

@Suite("util tests")
struct NodeUtilTests {

    @Suite("util API structure tests")
    struct NodeUtilStructureTests {
        @Test("util.inspect is a function")
        func testInspectIsFunction() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("typeof util.inspect") == "function")
        }
    }

    @Suite("util.inspect default behaviour")
    struct NodeUtilInspectDefaultTests {
        @Test("formats plain objects and arrays")
        func testBasicFormatting() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: 1, b: [1, 2, 3] })") == "{ a: 1, b: [ 1, 2, 3 ] }")
        }

        @Test("collapses nested objects past the default depth")
        func testDefaultDepth() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: { b: { c: { d: 1 } } } })")
                    == "{ a: { b: { c: [Object] } } }")
        }

        @Test("inspecting a native (JSExport-bridged) object shows no spurious 'undefined' prefix")
        func testNativeObjectNoUndefinedPrefix() throws {
            // Regression test: a native object's `constructor.name` is JS `undefined` (not
            // missing - JSExport-bridged objects don't get a named constructor), and
            // `.toString()` on that faithfully stringifies to the literal text "undefined",
            // which `constructorPrefix` used to treat as a real class name. Uses fs.statSync's
            // Stats object as a convenient native object; the bug wasn't specific to fs.
            let ctx = try NodeUtilTestContext()
            ctx.eval("var fs = require('fs')")
            let result = ctx.evalString("util.inspect(fs.statSync('/tmp'))")
            #expect(result == "{}")
        }

        @Test("does not invoke getters by default")
        func testGettersSkippedByDefault() throws {
            let ctx = try NodeUtilTestContext()
            ctx.eval("var __invoked = false")
            #expect(ctx.evalString("""
                util.inspect({ get x() { __invoked = true; return 42; } })
            """) == "{ x: [Getter] }")
            #expect(ctx.evalBool("__invoked") == false)
        }
    }

    @Suite("util.inspect options parameter")
    struct NodeUtilInspectOptionsTests {
        @Test("depth option expands further than the default")
        func testDepthOption() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: { b: { c: { d: 1 } } } }, { depth: 4 })")
                    == "{ a: { b: { c: { d: 1 } } } }")
        }

        @Test("depth: null expands without limit")
        func testDepthNull() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: { b: { c: { d: { e: 1 } } } } }, { depth: null })")
                    == "{ a: { b: { c: { d: { e: 1 } } } } }")
        }

        @Test("getters: true invokes an own enumerable getter and shows a primitive result inline")
        func testGettersOptionPrimitive() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ get x() { return 42; } }, { getters: true })")
                    == "{ x: [Getter: 42] }")
        }

        @Test("getters: true shows an object result on its own formatted value")
        func testGettersOptionObject() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ get x() { return { y: 1 }; } }, { getters: true })")
                    == "{ x: [Getter] { y: 1 } }")
        }

        @Test("getters: true marks a getter/setter pair distinctly from a getter-only property")
        func testGetterSetterLabel() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                util.inspect({ get x() { return 1; }, set x(v) {} }, { getters: true })
            """) == "{ x: [Getter/Setter: 1] }")
        }

        @Test("a non-object second argument is treated as if no options were passed")
        func testNonObjectOptionsIgnored() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: 1 }, 'ignored')") == "{ a: 1 }")
            #expect(!ctx.hadException)
        }
    }
}
