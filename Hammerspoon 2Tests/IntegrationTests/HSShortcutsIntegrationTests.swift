//
//  HSShortcutsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.shortcuts tests")
struct HSShortcutsIntegrationTests {

    // MARK: - API Structure Tests

    @Suite("hs.shortcuts API structure tests")
    struct HSShortcutsStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")
            return harness
        }

        @Test("hs.shortcuts is an object")
        func testModuleIsObject() {
            makeHarness().expectTrue("typeof hs.shortcuts === 'object'")
        }

        @Test("list is a function")
        func testListIsFunction() {
            makeHarness().expectTrue("typeof hs.shortcuts.list === 'function'")
        }

        @Test("run is a function")
        func testRunIsFunction() {
            makeHarness().expectTrue("typeof hs.shortcuts.run === 'function'")
        }

        @Test("open is a function")
        func testOpenIsFunction() {
            makeHarness().expectTrue("typeof hs.shortcuts.open === 'function'")
        }
    }

    // MARK: - Behaviour Tests

    @Suite("hs.shortcuts behaviour tests")
    struct HSShortcutsBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")
            return harness
        }

        @Test("list() returns an array")
        func testListReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.shortcuts.list())")
            #expect(!harness.hasException)
        }

        @Test("list() entries each have a name string")
        func testListEntriesHaveName() {
            let harness = makeHarness()
            harness.eval("var shortcuts = hs.shortcuts.list()")
            harness.expectTrue("""
                shortcuts.every(s => typeof s.name === 'string')
            """)
            #expect(!harness.hasException)
        }

        @Test("list() entries each have an id string")
        func testListEntriesHaveId() {
            let harness = makeHarness()
            harness.eval("var shortcuts = hs.shortcuts.list()")
            harness.expectTrue("""
                shortcuts.every(s => typeof s.id === 'string')
            """)
            #expect(!harness.hasException)
        }

        @Test("list() entries each have an acceptsInput boolean")
        func testListEntriesHaveAcceptsInput() {
            let harness = makeHarness()
            harness.eval("var shortcuts = hs.shortcuts.list()")
            harness.expectTrue("""
                shortcuts.every(s => typeof s.acceptsInput === 'boolean')
            """)
            #expect(!harness.hasException)
        }

        @Test("list() entries each have an actionCount number")
        func testListEntriesHaveActionCount() {
            let harness = makeHarness()
            harness.eval("var shortcuts = hs.shortcuts.list()")
            harness.expectTrue("""
                shortcuts.every(s => typeof s.actionCount === 'number')
            """)
            #expect(!harness.hasException)
        }

        @Test("run() returns a Promise")
        func testRunReturnsPromise() {
            let harness = makeHarness()
            harness.expectTrue("hs.shortcuts.run('__test__') instanceof Promise")
            #expect(!harness.hasException)
        }

        @Test("run() of a non-existent shortcut rejects")
        @MainActor
        func testRunNonExistentShortcutRejects() async {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")

            var rejected = false
            harness.registerCallback("onRejected") {
                rejected = true
            }
            harness.eval("""
                hs.shortcuts.run('__hammerspoon_nonexistent_shortcut__')
                    .catch(() => __test_callback('onRejected'))
            """)
            #expect(!harness.hasException)

            let ok = await harness.waitForAsync(timeout: 10.0) { rejected }
            #expect(ok, "Promise should reject for a non-existent shortcut")
            #expect(rejected)
        }

        @Test("open() does not throw for any name")
        func testOpenDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.shortcuts.open('__test_shortcut__')")
            #expect(!harness.hasException)
        }
    }
}
