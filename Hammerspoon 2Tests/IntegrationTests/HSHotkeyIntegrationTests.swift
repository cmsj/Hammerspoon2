//
//  HSHotkeyIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import Carbon
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
            #expect(makeHarness().evalTypeOf("hs.hotkey.bind") == "function")
        }

        @Test("bindSpec is a function")
        func testBindSpecIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.bindSpec") == "function")
        }

        @Test("getKeyCodeMap is a function")
        func testGetKeyCodeMapIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.getKeyCodeMap") == "function")
        }

        @Test("getModifierMap is a function")
        func testGetModifierMapIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.getModifierMap") == "function")
        }

        @Test("getHotkeys is a function")
        func testGetHotkeysIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.getHotkeys") == "function")
        }

        @Test("systemAssigned is a function")
        func testSystemAssignedIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.systemAssigned") == "function")
        }

        @Test("assignable is a function")
        func testAssignableIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.assignable") == "function")
        }

        @Test("deleteAll is a function")
        func testDeleteAllIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.deleteAll") == "function")
        }

        @Test("disableAll is a function")
        func testDisableAllIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.disableAll") == "function")
        }

        @Test("showHotkeys is a function")
        func testShowHotkeysIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.hotkey.showHotkeys") == "function")
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
            #expect(harness.evalTypeOf("hs.hotkey.getKeyCodeMap()") == "object")
            #expect(harness.evalTypeOf("hs.hotkey.getKeyCodeMap()['a']") == "number")
            #expect(harness.evalTypeOf("hs.hotkey.getKeyCodeMap()['space']") == "number")
            #expect(harness.evalTypeOf("hs.hotkey.getKeyCodeMap()['return']") == "number")
            #expect(harness.evalTypeOf("hs.hotkey.getKeyCodeMap()['f1']") == "number")
            #expect(!harness.hasException)
        }

        @Test("getModifierMap returns an object with cmd, shift, alt, ctrl")
        func testModifierMapContainsExpectedKeys() {
            let harness = makeHarness()
            let js = "hs.hotkey.getModifierMap()"
            #expect(harness.evalTypeOf(js) == "object")
            for mod in ["cmd", "shift", "alt", "ctrl"] {
                #expect(harness.evalTypeOf("\(js)['\(mod)']") == "number")
            }
            #expect(!harness.hasException)
        }

        @Test("bind with valid args returns a hotkey object")
        func testBindReturnsHotkeyObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '1', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(harness.evalTypeOf("hk.enable") == "function")
            #expect(harness.evalTypeOf("hk.disable") == "function")
            #expect(harness.evalTypeOf("hk.isEnabled") == "function")
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

        @Test("onPressed is settable after bind")
        func testCallbackPressedIsSettable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], '5', () => {}, () => {})")
            harness.eval("hk.onPressed = () => {}")
            #expect(!harness.hasException)
        }

        @Test("bindSpec with message returns a hotkey object")
        func testBindSpecReturnsHotkeyObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bindSpec({mods: ['ctrl'], key: '6', message: 'test', pressed: () => {}, released: () => {}})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(!harness.hasException)
        }

        @Test("bindSpec sets the message property on the returned hotkey")
        func testBindSpecSetsMessage() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bindSpec({mods: ['ctrl'], key: '9', message: 'test message', pressed: () => {}})")
            harness.expectTrue("hk.message === 'test message'")
            #expect(!harness.hasException)
        }

        @Test("bindSpec without a message leaves message unset")
        func testBindSpecWithoutMessage() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bindSpec({mods: ['ctrl'], key: '0', pressed: () => {}})")
            harness.expectTrue("hk.message === null || hk.message === undefined")
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

        @Test("onRepeat is settable after bind")
        func testCallbackRepeatIsSettable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'q', () => {}, () => {})")
            harness.eval("hk.onRepeat = () => {}")
            harness.expectTrue("typeof hk.onRepeat === 'function'")
            #expect(!harness.hasException)
        }

        @Test("bind accepts onRepeat as a 5th positional argument")
        func testBindAcceptsCallbackRepeatAsFifthArgument() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'g', () => {}, () => {}, () => {})")
            harness.expectTrue("typeof hk.onRepeat === 'function'")
            #expect(!harness.hasException)
        }

        @Test("create accepts onRepeat as a 5th positional argument")
        func testCreateAcceptsCallbackRepeatAsFifthArgument() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.create(['ctrl'], 'h', () => {}, () => {}, () => {})")
            harness.expectTrue("typeof hk.onRepeat === 'function'")
            #expect(!harness.hasException)
        }

        @Test("bind without a 5th argument leaves onRepeat unset")
        func testBindWithoutFifthArgumentLeavesCallbackRepeatUnset() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'j', () => {}, () => {})")
            harness.expectTrue("hk.onRepeat === null || hk.onRepeat === undefined")
            #expect(!harness.hasException)
        }

        @Test("bind treats an explicit null onRepeat the same as omitting it")
        func testBindWithNullCallbackRepeat() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'k', () => {}, () => {}, null)")
            harness.expectTrue("hk.onRepeat === null || hk.onRepeat === undefined")
            #expect(!harness.hasException)
        }

        @Test("bind without a released argument still binds (released is optional)")
        func testBindWithoutReleasedArgumentBinds() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'b', () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            harness.expectTrue("hk.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("bind treats an omitted released the same as null (no released callback)")
        func testBindOmittedReleasedIsUnset() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'd', () => {})")
            harness.expectTrue("hk.onReleased === null || hk.onReleased === undefined")
            #expect(!harness.hasException)
        }

        @Test("bind without a pressed argument returns null (pressed is required)")
        func testBindWithoutPressedReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'l')")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("repeat-only hotkey (pressed and released null) sets onRepeat")
        func testRepeatOnlyHotkeySetsRepeat() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'm', null, null, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(harness.evalTypeOf("hk.onRepeat") == "function")
            harness.expectTrue("hk.onPressed === null || hk.onPressed === undefined")
            #expect(!harness.hasException)
        }

        @Test("triggering press/release with a repeat callback set does not throw")
        func testTriggerWithRepeatDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'w', () => {}, () => {})")
            harness.eval("hk.onRepeat = () => {}")
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            // Exercises the repeat-timer start/stop path without depending on the
            // system's keyboard-repeat-delay setting (which varies, and can be
            // disabled entirely on some machines/CI), so we don't assert on actual
            // repeat firing here - only that press/release cycling is safe.
            hotkey.trigger(eventKind: UInt32(kEventHotKeyPressed))
            hotkey.trigger(eventKind: UInt32(kEventHotKeyReleased))
            #expect(!harness.hasException)
        }

        private func makeHarnessWithUI() -> JSTestHarness {
            let harness = makeHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("message shows an hs.ui alert before the pressed callback when pressed exists")
        func testMessageShowsAlertBeforePressed() {
            let harness = makeHarnessWithUI()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'z', () => {}, () => {}); hk.message = 'hi'")
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            hotkey.trigger(eventKind: UInt32(kEventHotKeyPressed))
            harness.expectTrue("hs.ui.toString().includes('1 alert')")
            #expect(!harness.hasException)
        }

        @Test("message shows an hs.ui alert before the released callback when only released exists")
        func testMessageShowsAlertBeforeReleasedWhenNoPressed() {
            let harness = makeHarnessWithUI()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'x', null, () => {}); hk.message = 'hi'")
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            hotkey.trigger(eventKind: UInt32(kEventHotKeyReleased))
            harness.expectTrue("hs.ui.toString().includes('1 alert')")
            #expect(!harness.hasException)
        }

        @Test("message is shown only once, before pressed, when both pressed and released exist")
        func testMessageShownOnceWhenBothCallbacksExist() {
            let harness = makeHarnessWithUI()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'c', () => {}, () => {}); hk.message = 'hi'")
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            hotkey.trigger(eventKind: UInt32(kEventHotKeyPressed))
            hotkey.trigger(eventKind: UInt32(kEventHotKeyReleased))
            harness.expectTrue("hs.ui.toString().includes('1 alert')")
            #expect(!harness.hasException)
        }

        @Test("no message means no alert is shown")
        func testNoMessageMeansNoAlert() {
            let harness = makeHarnessWithUI()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'v', () => {}, () => {})")
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            hotkey.trigger(eventKind: UInt32(kEventHotKeyPressed))
            harness.expectTrue("hs.ui.toString().includes('0 alert')")
            #expect(!harness.hasException)
        }

        @Test("a message containing quotes and script-injection-shaped content is shown safely, not executed")
        func testMessageWithInjectionShapedContentIsNotExecuted() {
            let harness = makeHarnessWithUI()
            harness.eval("globalThis.pwned = false")
            harness.eval(#"""
                var hk = hs.hotkey.bind(['ctrl'], 'f', () => {}, () => {})
                hk.message = "hi\"); globalThis.pwned = true; (\""
                """#)
            guard let hotkey = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey else {
                Issue.record("Could not extract HSHotkey")
                return
            }
            hotkey.trigger(eventKind: UInt32(kEventHotKeyPressed))
            harness.expectTrue("hs.ui.toString().includes('1 alert')")
            harness.expectTrue("globalThis.pwned === false")
            #expect(!harness.hasException)
        }

        @Test("getHotkeys includes an enabled hotkey and excludes a disabled one")
        func testGetHotkeysReflectsEnabledState() {
            let harness = makeHarness()
            harness.eval("""
                var hkOn = hs.hotkey.bind(['ctrl'], 'e', () => {}, null)
                var hkOff = hs.hotkey.bind(['ctrl'], 'r', () => {}, null)
                hkOff.disable()
                var list = hs.hotkey.getHotkeys()
                var onIdx = list.findIndex(h => h.key === 'e')
                var offIdx = list.findIndex(h => h.key === 'r')
                """)
            harness.expectTrue("onIdx !== -1")
            harness.expectTrue("offIdx === -1")
            #expect(!harness.hasException)
        }

        @Test("disableAll disables only hotkeys matching the given combo")
        func testDisableAllMatchesCombo() {
            let harness = makeHarness()
            harness.eval("""
                var hkMatch = hs.hotkey.bind(['ctrl'], 't', () => {}, null)
                var hkOther = hs.hotkey.bind(['ctrl'], 'y', () => {}, null)
                hs.hotkey.disableAll(['ctrl'], 't')
                """)
            harness.expectTrue("hkMatch.isEnabled() === false")
            harness.expectTrue("hkOther.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("deleteAll disables only hotkeys matching the given combo")
        func testDeleteAllMatchesCombo() {
            let harness = makeHarness()
            harness.eval("""
                var hkMatch = hs.hotkey.bind(['ctrl'], 'u', () => {}, null)
                var hkOther = hs.hotkey.bind(['ctrl'], 'i', () => {}, null)
                hs.hotkey.deleteAll(['ctrl'], 'u')
                """)
            harness.expectTrue("hkMatch.isEnabled() === false")
            harness.expectTrue("hkOther.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("assignable returns false for a combo already bound by this test")
        func testAssignableFalseForBoundCombo() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'o', () => {}, null)")
            harness.expectTrue("hs.hotkey.assignable(['ctrl'], 'o') === false")
            #expect(!harness.hasException)
        }

        @Test("assignable returns true for an unbound combo")
        func testAssignableTrueForUnboundCombo() {
            let harness = makeHarness()
            harness.expectTrue("hs.hotkey.assignable(['ctrl'], 'p') === true")
            #expect(!harness.hasException)
        }

        @Test("systemAssigned returns null for a combo this test just bound itself")
        func testSystemAssignedNullForOwnCombo() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'a', () => {}, null)")
            harness.expectTrue("hs.hotkey.systemAssigned(['ctrl'], 'a') === null || hs.hotkey.systemAssigned(['ctrl'], 'a') === undefined")
            #expect(!harness.hasException)
        }

        @Test("bind with no function callbacks returns null (at least one is required)")
        func testBindRequiresAtLeastOneFunction() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['ctrl'], 'n', null, null)")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("create with no callbacks still succeeds (deferred assignment)")
        func testCreateWithoutCallbacksSucceeds() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.create(['ctrl'], 'n', null, null)")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Keyboard layouts (issue #270)

    /// These replace the process-wide key code table to simulate a layout switch, so they're
    /// serialized and synchronous (nothing else on the main actor can run mid-test), and always
    /// restore the real table afterwards.
    @Suite("hs.hotkey keyboard layout tests", .serialized)
    struct HSHotkeyLayoutTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            return harness
        }

        private func layoutTable(_ sourceID: String) throws -> KeyCodeTable {
            try #require(KeyCodeTable.forInputSource(id: sourceID), "\(sourceID) should be installed")
        }

        /// Runs `body` with `table` as the current layout, then restores the real one.
        private func withLayout(_ table: KeyCodeTable, _ body: () throws -> Void) rethrows {
            let original = KeyboardLayout.shared.keyCodes
            KeyboardLayout.shared.replace(with: table)
            defer { KeyboardLayout.shared.replace(with: original) }
            try body()
        }

        @Test("followsKeyboardLayout defaults to true")
        func testFollowsKeyboardLayoutDefault() {
            #expect(makeHarness().evalBool("hs.hotkey.followsKeyboardLayout") == true)
        }

        @Test("bind accepts a numeric key code")
        func testBindNumericKeyCode() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 13, () => {})")
            #expect(harness.evalInt("hk.keyCode") == 13)
            #expect(harness.evalTypeOf("hk.key") == "number")
            #expect(harness.evalInt("hk.key") == 13)
            harness.eval("hk.destroy()")
            #expect(!harness.hasException)
        }

        @Test("a numeric string is a character, not a key code")
        func testBindDigitString() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], '0', () => {})")
            #expect(harness.evalInt("hk.keyCode") == KeyboardLayout.shared.keyCodes.keyCode(forName: "0"))
            #expect(harness.evalString("hk.key") == "0")
            harness.eval("hk.destroy()")
            #expect(!harness.hasException)
        }

        @Test("bind rejects a key that is neither a name nor a key code")
        func testBindRejectsBoolean() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], true, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("getHotkeys reports each hotkey's current key code")
        func testGetHotkeysIncludesKeyCode() {
            let harness = makeHarness()
            harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 13, () => {})")
            harness.expectTrue("hs.hotkey.getHotkeys().some(h => h.key === 13 && h.keyCode === 13)")
            harness.eval("hk.destroy()")
            #expect(!harness.hasException)
        }

        @Test("bind resolves names through the current layout")
        func testBindUsesCurrentLayout() throws {
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(dvorak) {
                harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 'w', () => {})")
                #expect(harness.evalInt("hk.keyCode") == kVK_ANSI_Comma)
                #expect(harness.evalInt("hs.hotkey.getKeyCodeMap()['w']") == kVK_ANSI_Comma)
                harness.eval("hk.destroy()")
            }
            #expect(!harness.hasException)
        }

        @Test("a layout change moves hotkeys bound by name, but not by key code")
        func testLayoutChangeMovesNamedHotkeys() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                harness.eval("""
                    var named = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 'w', () => {})
                    var coded = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 7, () => {})
                    var disabled = hs.hotkey.create(['cmd','alt','ctrl','shift'], 's', () => {})
                """)
                #expect(harness.evalInt("named.keyCode") == kVK_ANSI_W)

                KeyboardLayout.shared.replace(with: dvorak)
                #expect(harness.evalInt("named.keyCode") == kVK_ANSI_Comma)
                #expect(harness.evalBool("named.isEnabled()") == true)
                #expect(harness.evalInt("coded.keyCode") == kVK_ANSI_X)
                #expect(harness.evalBool("coded.isEnabled()") == true)
                // Disabled hotkeys move too, so enabling one later uses the current layout
                #expect(harness.evalInt("disabled.keyCode") == kVK_ANSI_Semicolon)
                #expect(harness.evalBool("disabled.isEnabled()") == false)

                harness.eval("named.destroy(); coded.destroy(); disabled.destroy()")
            }
            #expect(!harness.hasException)
        }

        @Test("hotkeys that swap keys on a layout change both stay enabled")
        func testLayoutChangeSwappingHotkeys() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                // US → Dvorak: "w" moves onto the "," key and "," moves onto the "w" key
                harness.eval("""
                    var w = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 'w', () => {})
                    var comma = hs.hotkey.bind(['cmd','alt','ctrl','shift'], ',', () => {})
                """)
                KeyboardLayout.shared.replace(with: dvorak)
                #expect(harness.evalInt("w.keyCode") == kVK_ANSI_Comma)
                #expect(harness.evalInt("comma.keyCode") == kVK_ANSI_W)
                #expect(harness.evalBool("w.isEnabled()") == true)
                #expect(harness.evalBool("comma.isEnabled()") == true)
                harness.eval("w.destroy(); comma.destroy()")
            }
            #expect(!harness.hasException)
        }

        @Test("followsKeyboardLayout = false keeps hotkeys in place until it's turned back on")
        func testFollowsKeyboardLayoutFalse() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                harness.eval("""
                    hs.hotkey.followsKeyboardLayout = false
                    var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 'w', () => {})
                """)
                KeyboardLayout.shared.replace(with: dvorak)
                #expect(harness.evalInt("hk.keyCode") == kVK_ANSI_W)

                harness.eval("hs.hotkey.followsKeyboardLayout = true")
                #expect(harness.evalInt("hk.keyCode") == kVK_ANSI_Comma)
                #expect(harness.evalBool("hk.isEnabled()") == true)

                harness.eval("hk.destroy()")
            }
            #expect(!harness.hasException)
        }

        @Test("disableAll finds hotkeys by name in the current layout")
        func testDisableAllUsesCurrentLayout() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                harness.eval("var hk = hs.hotkey.bind(['cmd','alt','ctrl','shift'], 'w', () => {})")
                KeyboardLayout.shared.replace(with: dvorak)
                harness.eval("hs.hotkey.disableAll(['cmd','alt','ctrl','shift'], 'w')")
                #expect(harness.evalBool("hk.isEnabled()") == false)
                harness.eval("hk.destroy()")
            }
            #expect(!harness.hasException)
        }
    }

    // MARK: - Key matching (Swift-level tests)

    @Suite("hs.hotkey Swift matching tests")
    struct HSHotkeyMatchingTests {

        @MainActor
        @Test("matches returns true for exact key and modifier")
        func testMatchesExactKeyAndModifier() {
            let coordinator = MockHotkeyCoordinator()
            let hotkey = HSEventTapHotkey(
                keyCode: 0x04,  // h
                requiredFlags: [.maskCommand],
                requiredDeviceBits: 0,
                coordinator: coordinator
            )
            // withExtendedLifetime guarantees coordinator is alive through enable().
            // Without it, Swift ARC may release coordinator at its last syntactic use
            // (the init argument), before enable() is called.
            withExtendedLifetime(coordinator) { _ = hotkey.enable() }

            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x04, keyDown: true) else {
                Issue.record("Could not create CGEvent")
                return
            }
            event.flags = .maskCommand

            #expect(hotkey.matches(event: event, type: .keyDown))
        }

        @MainActor
        @Test("matches returns false when extra modifier is present")
        func testMatchesReturnsFalseForExtraModifier() {
            let coordinator = MockHotkeyCoordinator()
            let hotkey = HSEventTapHotkey(
                keyCode: 0x04,
                requiredFlags: [.maskCommand],
                requiredDeviceBits: 0,
                coordinator: coordinator
            )
            withExtendedLifetime(coordinator) { _ = hotkey.enable() }

            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x04, keyDown: true) else {
                Issue.record("Could not create CGEvent")
                return
            }
            event.flags = [.maskCommand, .maskShift]  // extra shift

            #expect(!hotkey.matches(event: event, type: .keyDown))
        }

        @MainActor
        @Test("matches returns false for wrong key code")
        func testMatchesReturnsFalseForWrongKey() {
            let coordinator = MockHotkeyCoordinator()
            let hotkey = HSEventTapHotkey(
                keyCode: 0x04,  // h
                requiredFlags: [.maskCommand],
                requiredDeviceBits: 0,
                coordinator: coordinator
            )
            withExtendedLifetime(coordinator) { _ = hotkey.enable() }

            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true) else {
                Issue.record("Could not create CGEvent")
                return
            }
            event.flags = .maskCommand

            #expect(!hotkey.matches(event: event, type: .keyDown))
        }

        @MainActor
        @Test("matches returns false when hotkey is disabled")
        func testMatchesReturnsFalseWhenDisabled() {
            let coordinator = MockHotkeyCoordinator()
            let hotkey = HSEventTapHotkey(
                keyCode: 0x04,
                requiredFlags: [.maskCommand],
                requiredDeviceBits: 0,
                coordinator: coordinator
            )
            // Do NOT enable

            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x04, keyDown: true) else {
                Issue.record("Could not create CGEvent")
                return
            }
            event.flags = .maskCommand

            #expect(!hotkey.matches(event: event, type: .keyDown))
        }
    }

    // MARK: - Memory Leak Tests

    @Test("Active HSHotkey is released after shutdown")
    func testHotkeyDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            // bind() auto-enables the hotkey (adding it to the strong enabledHotkeys array).
            // We exercise disable/enable cycling to use the hotkey actively, then verify
            // shutdown() clears enabledHotkeys and calls destroy() on all hotkeys.
            harness.eval("""
                var hk = hs.hotkey.bind(['cmd'], 'h', function() {}, function() {})
                hk.disable()
                hk.enable()
            """)
            if let obj = harness.evalValue("hk")?.toObjectOf(HSHotkey.self) as? HSHotkey {
                tracker.track(obj)
            }
            harness.eval("hk = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }

    @Test("Active modal hotkey is released after shutdown")
    func testHotkeyModalDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            // Create a modal, bind a hotkey within it, enter the modal so it's active,
            // then verify shutdown() properly destroys the hotkey and releases it.
            harness.eval("""
                var modal = hs.hotkey.createModal([], '')
                modal.bind(['shift'], 'j', function() {}, null)
                modal.enter()
            """)
            if let obj = harness.evalValue("modal._hotkeys[0]")?.toObjectOf(HSHotkey.self) as? HSHotkey {
                tracker.track(obj)
            }
            harness.eval("modal = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
