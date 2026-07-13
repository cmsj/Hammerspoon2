//
//  HSHotkeyModalIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import ApplicationServices
@testable import Hammerspoon_2

@Suite("hs.hotkey.modal tests")
struct HSHotkeyModalTests {

    // MARK: - Structure

    @Suite("hs.hotkey.modal API structure tests")
    struct HSHotkeyModalStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        @Test("hs.hotkey.createModal is a function")
        func testCreateModalIsFunction() {
            makeHarness().expectTrue("typeof hs.hotkey.createModal === 'function'")
        }

        @Test("created modal has bind as a function")
        func testBindIsFunction() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m.bind === 'function'")
            #expect(!harness.hasException)
        }

        @Test("created modal has enter as a function")
        func testEnterIsFunction() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m.enter === 'function'")
            #expect(!harness.hasException)
        }

        @Test("created modal has exit as a function")
        func testExitIsFunction() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m.exit === 'function'")
            #expect(!harness.hasException)
        }

        @Test("created modal has destroy as a function")
        func testDestroyIsFunction() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m.destroy === 'function'")
            #expect(!harness.hasException)
        }

        @Test("created modal has enterFn as null initially")
        func testEnterFnIsInitiallyNull() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("m.enterFn === null || m.enterFn === undefined")
            #expect(!harness.hasException)
        }

        @Test("created modal has exitFn as null initially")
        func testExitFnIsInitiallyNull() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("m.exitFn === null || m.exitFn === undefined")
            #expect(!harness.hasException)
        }

        @Test("created modal has isActive as boolean")
        func testIsActiveIsBoolean() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m.isActive === 'boolean'")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Behaviour

    @Suite("hs.hotkey.modal behaviour tests")
    struct HSHotkeyModalBehaviourTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        @Test("createModal() with no trigger returns a non-null object")
        func testCreateNoTriggerReturnsObject() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("typeof m === 'object' && m !== null")
            #expect(!harness.hasException)
        }

        @Test("createModal() with a trigger key returns a non-null object")
        func testCreateWithTriggerReturnsObject() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal(['cmd'], 'h')")
            harness.expectTrue("typeof m === 'object' && m !== null")
            #expect(!harness.hasException)
        }

        @Test("isActive is false before enter()")
        func testIsActiveFalseInitially() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("m.isActive === false")
            #expect(!harness.hasException)
        }

        @Test("isActive is true after enter()")
        func testIsActiveTrueAfterEnter() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.eval("m.enter()")
            harness.expectTrue("m.isActive === true")
            #expect(!harness.hasException)
        }

        @Test("isActive is false after exit()")
        func testIsActiveFalseAfterExit() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.eval("m.enter()")
            harness.eval("m.exit()")
            harness.expectTrue("m.isActive === false")
            #expect(!harness.hasException)
        }

        @Test("enter() returns the modal for chaining")
        func testEnterReturnsModal() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("m.enter() === m")
            #expect(!harness.hasException)
        }

        @Test("exit() returns the modal for chaining")
        func testExitReturnsModal() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.eval("m.enter()")
            harness.expectTrue("m.exit() === m")
            #expect(!harness.hasException)
        }

        @Test("bind() returns the modal for chaining")
        func testBindReturnsModal() {
            let harness = makeHarness()
            harness.eval("var m = hs.hotkey.createModal([], '')")
            harness.expectTrue("m.bind(['shift'], 'a', () => {}, null) === m")
            #expect(!harness.hasException)
        }

        @Test("enterFn is called when enter() is called")
        func testEnterFnCalledOnEnter() {
            let harness = makeHarness()
            var called = false
            harness.registerCallback("onEnter") { called = true }
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.enterFn = () => __test_callback('onEnter')
                m.enter()
            """)
            #expect(called, "enterFn should have been called synchronously")
            #expect(!harness.hasException)
        }

        @Test("exitFn is called when exit() is called")
        func testExitFnCalledOnExit() {
            let harness = makeHarness()
            var called = false
            harness.registerCallback("onExit") { called = true }
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.enter()
                m.exitFn = () => __test_callback('onExit')
                m.exit()
            """)
            #expect(called, "exitFn should have been called synchronously")
            #expect(!harness.hasException)
        }

        @Test("enterFn is not called on repeated enter() calls")
        func testEnterFnNotCalledTwice() {
            let harness = makeHarness()
            var callCount = 0
            harness.registerCallback("onEnter") { callCount += 1 }
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.enterFn = () => __test_callback('onEnter')
                m.enter()
                m.enter()  // second call is a no-op while already active
            """)
            #expect(callCount == 1, "enterFn should only fire once")
            #expect(!harness.hasException)
        }

        @Test("exitFn is not called when exit() called while not active")
        func testExitFnNotCalledWhenNotActive() {
            let harness = makeHarness()
            var called = false
            harness.registerCallback("onExit") { called = true }
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.exitFn = () => __test_callback('onExit')
                m.exit()  // no-op — never entered
            """)
            #expect(!called, "exitFn should not fire when not active")
            #expect(!harness.hasException)
        }

        @Test("destroy() does not throw")
        func testDestroyDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.bind(['shift'], 'a', () => {}, null)
                m.enter()
                m.destroy()
            """)
            #expect(!harness.hasException)
        }

        @Test("bind() with unknown key does not throw")
        func testBindUnknownKeyDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.bind(['cmd'], 'notakey', () => {}, null)
            """)
            #expect(!harness.hasException)
        }

        @Test("multiple modals are independent")
        func testMultipleModalsAreIndependent() {
            let harness = makeHarness()
            harness.eval("""
                var m1 = hs.hotkey.createModal([], '')
                var m2 = hs.hotkey.createModal([], '')
                m1.enter()
            """)
            harness.expectTrue("m1.isActive === true")
            harness.expectTrue("m2.isActive === false")
            #expect(!harness.hasException)
        }

        @Test("enter/exit callbacks are settable and replaceable")
        func testCallbacksAreReplaceable() {
            let harness = makeHarness()
            var firstCount = 0
            var secondCount = 0
            harness.registerCallback("first") { firstCount += 1 }
            harness.registerCallback("second") { secondCount += 1 }
            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.enterFn = () => __test_callback('first')
                m.enter()
                m.exit()
                m.enterFn = () => __test_callback('second')
                m.enter()
            """)
            #expect(firstCount == 1)
            #expect(secondCount == 1)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Accessibility-gated tests

    private nonisolated func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    @Suite("hs.hotkey.modal accessibility tests",
           .serialized,
           .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"))
    struct HSHotkeyModalAccessibilityTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        @Test("modal hotkey fires after enter()")
        func testModalHotkeyFiresAfterEnter() async {
            let harness = makeHarness()
            var fired = false
            harness.registerCallback("onKey") { fired = true }

            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.bind([], 'a', () => __test_callback('onKey'), null)
                m.enter()
            """)
            harness.eval("hs.eventtap.keyStroke([], 'a')")

            let ok = harness.waitFor(timeout: 1.0) { fired }
            harness.eval("m.destroy()")
            await harness.cleanup()
            #expect(ok, "Modal hotkey callback should have fired after enter()")
            #expect(!harness.hasException)
        }

        @Test("modal hotkey does not fire after exit()")
        func testModalHotkeyDoesNotFireAfterExit() async {
            let harness = makeHarness()
            var fired = false
            harness.registerCallback("onKey") { fired = true }

            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.bind([], 'a', () => __test_callback('onKey'), null)
                m.enter()
                m.exit()
            """)
            harness.eval("hs.eventtap.keyStroke([], 'a')")

            _ = harness.waitFor(timeout: 0.2) { fired }
            harness.eval("m.destroy()")
            await harness.cleanup()
            #expect(!fired, "Modal hotkey callback should not fire after exit()")
            #expect(!harness.hasException)
        }

        @Test("hotkey bound while modal is active fires without re-entering")
        func testBindWhileActiveFires() async {
            let harness = makeHarness()
            var fired = false
            harness.registerCallback("onKey") { fired = true }

            harness.eval("""
                var m = hs.hotkey.createModal([], '')
                m.enter()
                m.bind([], 'b', () => __test_callback('onKey'), null)
            """)
            harness.eval("hs.eventtap.keyStroke([], 'b')")

            let ok = harness.waitFor(timeout: 1.0) { fired }
            harness.eval("m.destroy()")
            await harness.cleanup()
            #expect(ok, "Hotkey bound while modal is active should fire without re-entering")
            #expect(!harness.hasException)
        }

        @Test("trigger hotkey auto-enters the modal")
        func testTriggerHotkeyAutoEnters() async {
            let harness = makeHarness()
            var entered = false
            harness.registerCallback("onEnter") { entered = true }

            // Use Ctrl+Shift+Z — avoids any system-reserved shortcuts that could
            // cause the test runner to hide or switch focus before our tap fires.
            harness.eval("""
                var m = hs.hotkey.createModal(['ctrl', 'shift'], 'z')
                m.enterFn = () => __test_callback('onEnter')
            """)
            harness.eval("hs.eventtap.keyStroke(['ctrl', 'shift'], 'z')")

            let ok = harness.waitFor(timeout: 1.0) { entered }
            harness.eval("m.destroy()")
            await harness.cleanup()
            #expect(ok, "Trigger hotkey should have entered the modal")
            #expect(!harness.hasException)
        }
    }
}
