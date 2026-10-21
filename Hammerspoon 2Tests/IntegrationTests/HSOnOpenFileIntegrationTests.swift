//
//  HSOnOpenFileIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for `hs.onOpenFile`. The open event itself comes from AppKit, so these call
/// `ModuleRoot.callOnOpenFile(_:)` directly, as `AppDelegate.application(_:open:)` does.
@Suite("hs.onOpenFile tests")
struct HSOnOpenFileTests {
    @Test("onOpenFile is null until it's set")
    func testDefaultsToNull() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        #expect(harness.evalValue("hs.onOpenFile")?.isNull == true)
        #expect(root.callOnOpenFile("/tmp/example.txt") == false)
    }

    @Test("A function assigned to onOpenFile is called with the path")
    func testCallbackIsCalledWithPath() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        var paths: [String] = []
        harness.registerCallback("openedFile") { (path: String) in paths.append(path) }
        harness.eval("hs.onOpenFile = function(path) { openedFile(path) }")
        #expect(!harness.hasException)
        #expect(harness.evalTypeOf("hs.onOpenFile") == "function")

        #expect(root.callOnOpenFile("/tmp/one.txt") == true)
        #expect(root.callOnOpenFile("/tmp/two folder") == true)
        #expect(paths == ["/tmp/one.txt", "/tmp/two folder"])
    }

    @Test("Assigning null removes the callback")
    func testAssigningNullRemovesCallback() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        var calls = 0
        harness.registerCallback("onOpenFile") { calls += 1 }
        harness.eval("hs.onOpenFile = function() { __test_callback('onOpenFile') }")
        harness.eval("hs.onOpenFile = null")
        #expect(!harness.hasException)

        #expect(harness.evalValue("hs.onOpenFile")?.isNull == true)
        #expect(root.callOnOpenFile("/tmp/example.txt") == false)
        #expect(calls == 0)
    }

    @Test("Assigning something that isn't a function leaves no callback")
    func testAssigningNonFunctionLeavesNoCallback() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        harness.eval("hs.onOpenFile = 'not a function'")
        #expect(!harness.hasException)

        #expect(harness.evalValue("hs.onOpenFile")?.isNull == true)
        #expect(root.callOnOpenFile("/tmp/example.txt") == false)
    }

    @Test("A callback that throws still counts as handled")
    func testThrowingCallbackCountsAsHandled() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        harness.eval("hs.onOpenFile = function() { throw new Error('boom') }")

        #expect(root.callOnOpenFile("/tmp/example.txt") == true)
    }

    @Test("A callback nothing else references survives garbage collection")
    func testUnreferencedCallbackSurvivesGC() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        var calls = 0
        harness.registerCallback("onOpenFile") { calls += 1 }
        // `void` + autoreleasepool, so eval's completion value doesn't keep the function alive
        autoreleasepool { _ = harness.eval("void (hs.onOpenFile = function() { __test_callback('onOpenFile') })") }
        harness.collectGarbage()

        #expect(root.callOnOpenFile("/tmp/example.txt") == true)
        #expect(calls == 1)
    }

    @Test("Shutdown removes the callback")
    func testShutdownRemovesCallback() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        var calls = 0
        harness.registerCallback("onOpenFile") { calls += 1 }
        harness.eval("hs.onOpenFile = function() { __test_callback('onOpenFile') }")

        root.shutdown()
        #expect(root.callOnOpenFile("/tmp/example.txt") == false)
        #expect(calls == 0)
    }
}
