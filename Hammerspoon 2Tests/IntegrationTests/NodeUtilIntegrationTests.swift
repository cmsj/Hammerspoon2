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
            #expect(result?.hasPrefix("undefined") == false)
            // Stats' data fields are primed as real own, enumerable properties (see
            // NodeFSStats.primeEnumerableProperties), so they're genuinely visible here too -
            // this isn't just "no longer says undefined", it shows real content.
            #expect(result?.contains("size:") == true)
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

        @Test("getters: true invokes the getter with the inspected object as its receiver")
        func testGettersOptionReceiver() throws {
            // Regression test: the getter must see `this` as the object actually being
            // inspected, not undefined/global - otherwise a getter that reads a sibling
            // property (the common case) reports the wrong value.
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("util.inspect({ a: 1, get x() { return this.a; } }, { getters: true })")
                    == "{ a: 1, x: [Getter: 1] }")
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

        @Test("depth: null terminates on a self-referencing object instead of recursing forever")
        func testCircularReferenceUnlimitedDepth() throws {
            // Regression test: the review's exact example. Without cycle detection this
            // recurses indefinitely (stack overflow/hang) once `depth: null` removes the only
            // thing that used to stop it.
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                (function() {
                    const o = {};
                    o.self = o;
                    return util.inspect(o, { depth: null });
                })()
            """) == "{ self: [Circular *1] }")
        }

        @Test("a finite depth still reports a genuine cycle as circular, not as [Object]")
        func testCircularReferenceFiniteDepth() throws {
            // Even when a depth limit would eventually stop the recursion anyway, Node still
            // recognizes the true cycle and reports it distinctly from an unrelated value that
            // merely got collapsed for being too deep.
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                (function() {
                    const o = {};
                    o.self = o;
                    return util.inspect(o, { depth: 4 });
                })()
            """) == "{ self: [Circular *1] }")
        }

        @Test("equal but unrelated sibling values are not mistaken for a cycle")
        func testEqualSiblingsAreNotCircular() throws {
            // The ancestor check must only match values still on the current path down to the
            // root, not any value that happens to be `===` to something formatted elsewhere in
            // the tree.
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                (function() {
                    const shared = { x: 1 };
                    return util.inspect({ a: shared, b: shared }, { depth: null });
                })()
            """) == "{ a: { x: 1 }, b: { x: 1 } }")
        }

        @Test("a cycle through an array is also reported as circular")
        func testCircularReferenceInArray() throws {
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                (function() {
                    const a = [];
                    a.push(a);
                    return util.inspect(a, { depth: null });
                })()
            """) == "[ [Circular *1] ]")
        }

        @Test("cycle detection survives a script deleting/overriding the global Object.is")
        func testCycleDetectionSurvivesObjectIsTampering() throws {
            // Regression test: the ancestor check used to go through the JS-level global
            // `Object.is`, which the very script being inspected can reassign or delete before
            // calling `util.inspect` - it's ordinary mutable global state, not something this
            // engine controls. An override that always returns `false` (or a missing/deleted
            // `Object.is`) would silently disable cycle detection, letting a genuine cycle
            // recurse without bound under `{ depth: null }`; one that always returns `true`
            // would falsely flag unrelated nested objects as circular. Covers both directions
            // plus outright deletion, none of which should be able to affect the result now
            // that identity goes through JSValue's own native `isEqual(_:)` instead.
            let ctx = try NodeUtilTestContext()

            #expect(ctx.evalString("""
                (function() {
                    Object.is = function() { return false; };
                    const o = {};
                    o.self = o;
                    return util.inspect(o, { depth: null });
                })()
            """) == "{ self: [Circular *1] }")

            #expect(ctx.evalString("""
                (function() {
                    delete Object.is;
                    const o = {};
                    o.self = o;
                    return util.inspect(o, { depth: null });
                })()
            """) == "{ self: [Circular *1] }")

            #expect(ctx.evalString("""
                (function() {
                    Object.is = function() { return true; };
                    return util.inspect({ a: { x: 1 }, b: { y: 2 } }, { depth: null });
                })()
            """) == "{ a: { x: 1 }, b: { y: 2 } }")
        }

        @Test("getters: true still catches a cycle through the getter's returned value")
        func testCircularReferenceThroughGetter() throws {
            // Regression test: a getter that returns its own owning object must not bypass
            // the ancestor check - verified against real Node (v26.8.2), which produces
            // "<ref *1> { self: [Getter] [Circular *1] }" here (this module omits the
            // "<ref *1>" back-reference decoration, per the existing simplification used by
            // the plain-property circular tests above, but still must label the cycle).
            let ctx = try NodeUtilTestContext()
            #expect(ctx.evalString("""
                (function() {
                    const o = {};
                    Object.defineProperty(o, 'self', { get() { return o; }, enumerable: true });
                    return util.inspect(o, { getters: true });
                })()
            """) == "{ self: [Getter] [Circular *1] }")
        }

        @Test("a getter's returned object is collapsed at the same depth as an equivalent plain property")
        func testGetterResultUsesSameDepthAsPlainProperty() throws {
            // Regression test: verified against real Node (v26.8.2) - a getter's returned
            // object is formatted at the *same* recursion depth as the property itself would
            // use for a plain value, not one level deeper. Consuming an extra depth level for
            // the getter indirection (as naive intuition might suggest) would make
            // getter-wrapped objects collapse a level earlier than their plain-property
            // equivalents, which would be a real divergence from Node - so this locks in the
            // current (correct) behaviour against that regression.
            let ctx = try NodeUtilTestContext()
            let plain = ctx.evalString("util.inspect({ a: { b: { c: { d: 1 } } } })")
            let viaGetter = ctx.evalString("""
                util.inspect({ get a() { return { b: { c: { d: 1 } } }; } }, { getters: true })
            """)
            #expect(plain == "{ a: { b: { c: [Object] } } }")
            #expect(viaGetter == "{ a: [Getter] { b: { c: [Object] } } }")
        }
    }
}
