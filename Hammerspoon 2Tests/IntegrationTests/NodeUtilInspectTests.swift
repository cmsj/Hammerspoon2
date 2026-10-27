//
//  NodeUtilInspectTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for how `NodeUtil.inspect` (which backs `console.log`) renders values
@MainActor
@Suite("NodeUtil.inspect tests")
struct NodeUtilInspectTests {
    private func inspect(_ script: String, in harness: JSTestHarness) throws -> String {
        let value = try #require(harness.context.evaluateScript(script))
        return NodeUtil.inspect(value)
    }

    @Test("a native object renders as its toString(), not 'undefined {}'")
    func nativeObjectUsesToString() throws {
        let harness = JSTestHarness()
        harness.loadModule(HSApplicationModule.self, as: "application")

        let rendered = try inspect("hs.application.fromPID(\(ProcessInfo.processInfo.processIdentifier))", in: harness)

        #expect(rendered.hasPrefix("<HSApplication: "))
        #expect(rendered.hasSuffix("(pid \(ProcessInfo.processInfo.processIdentifier))>"))
    }

    @Test("a native object nested in a plain object renders as its toString()")
    func nestedNativeObjectUsesToString() throws {
        let harness = JSTestHarness()
        harness.loadModule(HSApplicationModule.self, as: "application")

        let rendered = try inspect("({ app: hs.application.fromPID(\(ProcessInfo.processInfo.processIdentifier)) })", in: harness)

        #expect(rendered.hasPrefix("{ app: <HSApplication: "))
    }

    @Test("an empty class instance renders with its class name")
    func emptyClassInstance() throws {
        let harness = JSTestHarness()
        #expect(try inspect("class Foo {}; new Foo()", in: harness) == "Foo {}")
    }

    @Test("a populated class instance renders with its class name and keys")
    func populatedClassInstance() throws {
        let harness = JSTestHarness()
        #expect(try inspect("class Foo { constructor() { this.a = 1 } }; new Foo()", in: harness) == "Foo { a: 1 }")
    }

    @Test("a plain object renders without a prefix")
    func plainObject() throws {
        let harness = JSTestHarness()
        #expect(try inspect("({})", in: harness) == "{}")
        #expect(try inspect("({ a: 'x' })", in: harness) == "{ a: 'x' }")
    }

    @Test("inspecting an object with no own keys doesn't run inherited or non-enumerable getters")
    func emptyObjectGettersNotInvoked() throws {
        let harness = JSTestHarness()
        harness.eval("var _getterCalls = 0;")

        _ = try inspect("Object.create({ get inherited() { _getterCalls++; return 1; } })", in: harness)
        _ = try inspect("""
            Object.defineProperty({}, 'hidden', { get() { _getterCalls++; return 1; }, enumerable: false })
            """, in: harness)
        _ = try inspect("class Foo { get x() { _getterCalls++; return 1; } }; new Foo()", in: harness)

        harness.expectEqual("_getterCalls", 0)
    }

    @Test("an object whose constructor has no string name gets no prefix")
    func constructorWithoutName() throws {
        let harness = JSTestHarness()
        #expect(try inspect("({ constructor: {} })", in: harness).hasPrefix("{ constructor: "))
        #expect(try inspect("Object.create({ constructor: {} })", in: harness) == "{}")
    }
}
