//
//  HSHotkeyIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.hotkey tests")
struct HSHotkeyTests {

    // MARK: - Structure

    @Suite("hs.hotkey API structure tests")
    struct HSHotkeyStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        @Test("bind is a function")
        func testBindIsFunction() {
            makeHarness().expectTrue("typeof hs.hotkey.bind === 'function'")
        }

        @Test("bindSpec is a function")
        func testBindSpecIsFunction() {
            makeHarness().expectTrue("typeof hs.hotkey.bindSpec === 'function'")
        }

        @Test("getKeyCodeMap is a function")
        func testGetKeyCodeMapIsFunction() {
            makeHarness().expectTrue("typeof hs.hotkey.getKeyCodeMap === 'function'")
        }

        @Test("getModifierMap is a function")
        func testGetModifierMapIsFunction() {
            makeHarness().expectTrue("typeof hs.hotkey.getModifierMap === 'function'")
        }
    }

    // MARK: - Behaviour

    // Serialized to prevent within-process Carbon hotkey registration conflicts.
    // Each test uses a unique key so cross-process conflicts are also avoided.
    @Suite("hs.hotkey behaviour tests", .serialized)
    struct HSHotkeyBehaviourTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        @Test("getKeyCodeMap returns an object containing standard keys")
        func testKeyCodeMapContainsStandardKeys() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.hotkey.getKeyCodeMap() === 'object'")
            harness.expectTrue("typeof hs.hotkey.getKeyCodeMap()['a'] === 'number'")
            harness.expectTrue("typeof hs.hotkey.getKeyCodeMap()['space'] === 'number'")
            harness.expectTrue("typeof hs.hotkey.getKeyCodeMap()['return'] === 'number'")
            harness.expectTrue("typeof hs.hotkey.getKeyCodeMap()['f1'] === 'number'")
            #expect(!harness.hasException)
        }

        @Test("getModifierMap returns an object with cmd, shift, alt, ctrl")
        func testModifierMapContainsExpectedKeys() {
            let harness = makeHarness()
            let js = "hs.hotkey.getModifierMap()"
            harness.expectTrue("typeof \(js) === 'object'")
            for mod in ["cmd", "shift", "alt", "ctrl"] {
                harness.expectTrue("typeof \(js)['\(mod)'] === 'number'")
            }
            #expect(!harness.hasException)
        }

        @Test("bind with valid args returns a hotkey object")
        func testBindReturnsHotkeyObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '1', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            harness.expectTrue("typeof hk.enable === 'function'")
            harness.expectTrue("typeof hk.disable === 'function'")
            harness.expectTrue("typeof hk.isEnabled === 'function'")
            #expect(!harness.hasException)
        }

        @Test("bind auto-enables the hotkey")
        func testBindAutoEnables() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '2', () => {}, () => {})")
            harness.expectTrue("hk.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("disable makes isEnabled return false")
        func testDisableMakesIsEnabledFalse() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '3', () => {}, () => {})")
            harness.eval("hk.disable()")
            harness.expectTrue("hk.isEnabled() === false")
            #expect(!harness.hasException)
        }

        @Test("enable after disable restores isEnabled to true")
        func testEnableAfterDisable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '4', () => {}, () => {})")
            harness.eval("hk.disable()")
            harness.eval("hk.enable()")
            harness.expectTrue("hk.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("bind with unknown key returns null")
        func testBindUnknownKeyReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['cmd'], 'notakey', () => {}, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("bind with unknown modifier returns null")
        func testBindUnknownModifierReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['supermod'], 'h', () => {}, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("fn modifier is not supported in hs.hotkey.bind (returns null)")
        func testFnModifierReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['fn'], 'f1', () => {}, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("side-specific modifiers are not supported in hs.hotkey.bind (returns null)")
        func testSideSpecificModifiersReturnNull() {
            let harness = makeHarness()
            for mod in ["leftCmd", "rightCmd", "leftAlt", "rightAlt", "leftCtrl", "rightCtrl", "leftShift", "rightShift"] {
                harness.eval("var hk = hs.hotkey.bind(['\(mod)'], 'a', () => {}, () => {})")
                harness.expectTrue("hk === null || hk === undefined")
                #expect(!harness.hasException, "bind with '\(mod)' should return null in Carbon-backed hs.hotkey")
            }
        }

        @Test("callbackPressed is settable after bind")
        func testCallbackPressedIsSettable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '5', () => {}, () => {})")
            harness.eval("hk.callbackPressed = () => {}")
            #expect(!harness.hasException)
        }

        @Test("bindSpec with message returns a hotkey object")
        func testBindSpecReturnsHotkeyObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bindSpec(['ctrl'], '6', 'test', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(!harness.hasException)
        }

        @Test("two hotkeys with different keys have different objects")
        func testTwoHotkeysAreDifferentObjects() {
            let harness = makeHarness()
            harness.eval("var hk1 = hs.hotkey.bind(['ctrl'], '7', () => {}, () => {})")
            harness.eval("var hk2 = hs.hotkey.bind(['ctrl'], '8', () => {}, () => {})")
            harness.expectTrue("hk1 !== hk2")
            #expect(!harness.hasException)
        }
    }
}
