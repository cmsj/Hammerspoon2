//
//  HSKeyboardIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import IOKit.hid
@testable import Hammerspoon_2

private nonisolated func isInputMonitoringEnabled() -> Bool {
    IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}

@Suite("hs.keyboard tests")
struct HSKeyboardTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.keyboard API structure tests")
    struct HSKeyboardStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeyboardModule.self, as: "keyboard")
            return harness
        }

        @Test("capsLockState is a function")
        func testCapsLockStateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.capsLockState") == "function")
        }

        @Test("setCapsLockState is a function")
        func testSetCapsLockStateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.setCapsLockState") == "function")
        }

        @Test("toggleCapsLockState is a function")
        func testToggleCapsLockStateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.toggleCapsLockState") == "function")
        }

        @Test("setLED is a function")
        func testSetLEDIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.setLED") == "function")
        }

        @Test("attachedKeyboards is a function")
        func testAttachedKeyboardsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.attachedKeyboards") == "function")
        }

        @Test("keyboardCapsLockState is a function")
        func testKeyboardCapsLockStateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.keyboardCapsLockState") == "function")
        }

        @Test("setKeyboardLED is a function")
        func testSetKeyboardLEDIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.keyboard.setKeyboardLED") == "function")
        }
    }

    // MARK: - Suite 2: Behaviour (read-only / non-mutating; safe everywhere)
    //
    // setCapsLockState/toggleCapsLockState/setLED/setKeyboardLED are deliberately NOT exercised
    // here — they mutate real system CapsLock state and physical keyboard LEDs, which would
    // disrupt whoever is at the keyboard while the suite runs (see HSTests skill: "Hardware
    // mutations"). Only their input-validation paths (which fail before touching hardware) and
    // their existence as functions (Suite 1) are covered.

    @Suite("hs.keyboard behaviour tests")
    struct HSKeyboardBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeyboardModule.self, as: "keyboard")
            return harness
        }

        @Test("capsLockState returns a boolean")
        func testCapsLockStateReturnsBoolean() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.keyboard.capsLockState()") == "boolean")
            #expect(!harness.hasException)
        }

        @Test("attachedKeyboards returns an array")
        func testAttachedKeyboardsReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.keyboard.attachedKeyboards())")
            #expect(!harness.hasException)
        }

        @Test("each attached keyboard has the required fields")
        func testAttachedKeyboardShape() {
            let harness = makeHarness()
            harness.eval("""
                var keyboards = hs.keyboard.attachedKeyboards();
                var allValid = keyboards.every(function(k) {
                    return typeof k.keyboardID === 'number' &&
                           typeof k.productName === 'string' &&
                           typeof k.vendorName === 'string' &&
                           typeof k.productID === 'number' &&
                           typeof k.vendorID === 'number';
                });
            """)
            harness.expectTrue("allValid")
            #expect(!harness.hasException)
        }

        @Test("setLED with an unsupported name returns false without throwing")
        func testSetLEDInvalidName() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.keyboard.setLED('bogus', true)") == false)
            #expect(!harness.hasException)
        }

        @Test("keyboardCapsLockState with an unknown keyboardID returns false without throwing")
        func testKeyboardCapsLockStateUnknownID() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.keyboard.keyboardCapsLockState(-1)") == false)
            #expect(!harness.hasException)
        }

        @Test("setKeyboardLED with an unknown keyboardID returns false without throwing")
        func testSetKeyboardLEDUnknownID() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.keyboard.setKeyboardLED(-1, 'caps', true)") == false)
            #expect(!harness.hasException)
        }

        @Test("setKeyboardLED with an unsupported name returns false without throwing")
        func testSetKeyboardLEDInvalidName() {
            let harness = makeHarness()
            #expect(harness.evalBool("hs.keyboard.setKeyboardLED(-1, 'bogus', true)") == false)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: Input Monitoring-gated tests
    //
    // Reading a specific keyboard's own CapsLock LED requires Input Monitoring permission.
    // This is read-only (no hardware mutation), so it is safe to exercise for real when the
    // permission has been granted in the test environment.

    @Suite("hs.keyboard Input Monitoring tests",
           .disabled(if: !isInputMonitoringEnabled(), "Input Monitoring not granted"))
    struct HSKeyboardInputMonitoringTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeyboardModule.self, as: "keyboard")
            return harness
        }

        @Test("keyboardCapsLockState for a real attached keyboard returns a boolean")
        func testKeyboardCapsLockStateRealDevice() {
            let harness = makeHarness()
            harness.eval("""
                var keyboards = hs.keyboard.attachedKeyboards();
                var result = keyboards.length > 0 ? hs.keyboard.keyboardCapsLockState(keyboards[0].keyboardID) : null;
            """)
            #expect(!harness.hasException)
            let resultType = harness.evalTypeOf("result")
            #expect(resultType == "boolean" || resultType == "object")
        }
    }
}
