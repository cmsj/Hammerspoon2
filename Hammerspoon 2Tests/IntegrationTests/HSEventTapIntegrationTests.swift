//
//  HSEventTapIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import ApplicationServices
import Carbon
@testable import Hammerspoon_2

@Suite("hs.eventtap tests")
struct HSEventTapTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.eventtap API structure tests")
    struct HSEventTapStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            return harness
        }

        // MARK: Constants

        @Test("eventTypes is an object")
        func testEventTypesIsObject() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.eventTypes") == "object")
        }

        @Test("eventTypes.keyDown is a number")
        func testEventTypesKeyDownIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.eventTypes.keyDown") == "number")
        }

        @Test("eventTypes.keyUp is a number")
        func testEventTypesKeyUpIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.eventTypes.keyUp") == "number")
        }

        @Test("eventTypes.leftMouseDown is a number")
        func testEventTypesLeftMouseDownIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.eventTypes.leftMouseDown") == "number")
        }

        @Test("eventTypes.scrollWheel is a number")
        func testEventTypesScrollWheelIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.eventTypes.scrollWheel") == "number")
        }

        @Test("modifierFlags is an object")
        func testModifierFlagsIsObject() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags") == "object")
        }

        @Test("modifierFlags.cmd is a number")
        func testModifierFlagsCmdIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.cmd") == "number")
        }

        @Test("modifierFlags.shift is a number")
        func testModifierFlagsShiftIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.shift") == "number")
        }

        @Test("modifierFlags.leftCmd is a number")
        func testModifierFlagsLeftCmdIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.leftCmd") == "number")
        }

        @Test("modifierFlags.rightCmd is a number")
        func testModifierFlagsRightCmdIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.rightCmd") == "number")
        }

        @Test("modifierFlags.leftAlt is a number")
        func testModifierFlagsLeftAltIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.leftAlt") == "number")
        }

        @Test("modifierFlags.rightAlt is a number")
        func testModifierFlagsRightAltIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.rightAlt") == "number")
        }

        @Test("modifierFlags.leftCtrl is a number")
        func testModifierFlagsLeftCtrlIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.leftCtrl") == "number")
        }

        @Test("modifierFlags.rightCtrl is a number")
        func testModifierFlagsRightCtrlIsNumber() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.modifierFlags.rightCtrl") == "number")
        }

        @Test("consume is a boolean")
        func testConsumeIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.consume") == "boolean")
        }

        @Test("emit is a boolean")
        func testEmitIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.emit") == "boolean")
        }

        // MARK: Watcher management

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.addWatcher") == "function")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.removeWatcher") == "function")
        }

        // MARK: Event constructors

        @Test("makeKeyEvent is a function")
        func testMakeKeyEventIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.makeKeyEvent") == "function")
        }

        @Test("makeKeyEventWithCode is a function")
        func testMakeKeyEventWithCodeIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.makeKeyEventWithCode") == "function")
        }

        @Test("makeMouseEvent is a function")
        func testMakeMouseEventIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.makeMouseEvent") == "function")
        }

        @Test("makeScrollWheelEvent is a function")
        func testMakeScrollWheelEventIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.makeScrollWheelEvent") == "function")
        }

        // MARK: Convenience senders

        @Test("keyStroke is a function")
        func testKeyStrokeIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.keyStroke") == "function")
        }

        @Test("keyStrokes is a function")
        func testKeyStrokesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.keyStrokes") == "function")
        }

        @Test("keyStrokesAsync is a function")
        func testKeyStrokesAsyncIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.keyStrokesAsync") == "function")
        }

        @Test("leftClick is a function")
        func testLeftClickIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.leftClick") == "function")
        }

        @Test("rightClick is a function")
        func testRightClickIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.rightClick") == "function")
        }

        @Test("doubleLeftClick is a function")
        func testDoubleLeftClickIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.doubleLeftClick") == "function")
        }

        @Test("middleClick is a function")
        func testMiddleClickIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.middleClick") == "function")
        }

        @Test("scrollWheel is a function")
        func testScrollWheelIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.scrollWheel") == "function")
        }

        // MARK: System state

        @Test("currentModifiers is a function")
        func testCurrentModifiersIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.currentModifiers") == "function")
        }

        @Test("checkMouseButtons is a function")
        func testCheckMouseButtonsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.checkMouseButtons") == "function")
        }

        @Test("mouseLocation is a function")
        func testMouseLocationIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.mouseLocation") == "function")
        }

        @Test("doubleClickInterval is a function")
        func testDoubleClickIntervalIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.doubleClickInterval") == "function")
        }

        @Test("keyRepeatDelay is a function")
        func testKeyRepeatDelayIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.keyRepeatDelay") == "function")
        }

        @Test("keyRepeatInterval is a function")
        func testKeyRepeatIntervalIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.keyRepeatInterval") == "function")
        }

        // MARK: Event object API

        @Test("event.post is a function")
        func testEventPostIsFunction() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            #expect(harness.evalTypeOf("evt.post") == "function")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2: Behaviour / pure calculations

    @Suite("hs.eventtap behaviour tests")
    struct HSEventTapBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            return harness
        }

        // MARK: Consume / emit constants

        @Test("consume equals false")
        func testConsumeEqualsFalse() {
            #expect(makeHarness().evalBool("hs.eventtap.consume") == false)
        }

        @Test("emit equals true")
        func testEmitEqualsTrue() {
            #expect(makeHarness().evalBool("hs.eventtap.emit") == true)
        }

        @Test("consume and emit are different values")
        func testConsumeAndEmitDiffer() {
            makeHarness().expectTrue("hs.eventtap.consume !== hs.eventtap.emit")
        }

        // MARK: Event type constants

        @Test("keyDown and keyUp have different values")
        func testKeyDownKeyUpDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.eventTypes.keyDown !== hs.eventtap.eventTypes.keyUp"
            )
        }

        @Test("leftMouseDown and rightMouseDown have different values")
        func testMouseDownsDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.eventTypes.leftMouseDown !== hs.eventtap.eventTypes.rightMouseDown"
            )
        }

        @Test("modifierFlags cmd and shift have different values")
        func testModifierFlagsDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.modifierFlags.cmd !== hs.eventtap.modifierFlags.shift"
            )
        }

        @Test("leftCmd and rightCmd have different values")
        func testLeftCmdRightCmdDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.modifierFlags.leftCmd !== hs.eventtap.modifierFlags.rightCmd"
            )
        }

        @Test("leftAlt and rightAlt have different values")
        func testLeftAltRightAltDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.modifierFlags.leftAlt !== hs.eventtap.modifierFlags.rightAlt"
            )
        }

        @Test("leftCtrl and rightCtrl have different values")
        func testLeftCtrlRightCtrlDiffer() {
            makeHarness().expectTrue(
                "hs.eventtap.modifierFlags.leftCtrl !== hs.eventtap.modifierFlags.rightCtrl"
            )
        }

        // MARK: makeKeyEvent

        @Test("makeKeyEvent returns an object for a valid key")
        func testMakeKeyEventReturnsObject() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            harness.expectTrue("typeof evt === 'object' && evt !== null")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent sets the correct event type for keyDown")
        func testMakeKeyEventTypeIsKeyDown() throws {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            let eventType = try #require(harness.evalInt("evt.type"))
            let keyDownType = try #require(harness.evalInt("hs.eventtap.eventTypes.keyDown"))
            #expect(eventType == keyDownType)
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent sets the correct event type for keyUp")
        func testMakeKeyEventTypeIsKeyUp() throws {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', false)")
            let eventType = try #require(harness.evalInt("evt.type"))
            let keyUpType = try #require(harness.evalInt("hs.eventtap.eventTypes.keyUp"))
            #expect(eventType == keyUpType)
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent sets a non-zero keyCode for 'a'")
        func testMakeKeyEventKeyCodeForA() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            #expect(harness.evalTypeOf("evt.keyCode") == "number")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent returns null for unknown key")
        func testMakeKeyEventUnknownKeyReturnsNull() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('xyzzy_nonexistent_key', true)")
            harness.expectTrue("evt === null || evt === undefined")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent with 'space' returns an object")
        func testMakeKeyEventSpace() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('space', true)")
            harness.expectTrue("evt !== null && evt !== undefined")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent with 'return' returns an object")
        func testMakeKeyEventReturn() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('return', true)")
            harness.expectTrue("evt !== null && evt !== undefined")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent with symbol word alias 'minus' returns an object")
        func testMakeKeyEventMinus() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('minus', true)")
            harness.expectTrue("evt !== null && evt !== undefined")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent 'minus' and '-' produce the same keyCode")
        func testMakeKeyEventMinusAliasMatchesChar() throws {
            let harness = makeHarness()
            harness.eval("""
                var evt1 = hs.eventtap.makeKeyEvent('minus', true)
                var evt2 = hs.eventtap.makeKeyEvent('-', true)
            """)
            let keyCode1 = try #require(harness.evalInt("evt1.keyCode"))
            let keyCode2 = try #require(harness.evalInt("evt2.keyCode"))
            #expect(keyCode1 == keyCode2)
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent accepts a numeric key code, including 0-9 (issue #270)")
        func testMakeKeyEventNumericKeyCode() {
            let harness = makeHarness()
            harness.eval("var evt0 = hs.eventtap.makeKeyEvent(0, true); var evt13 = hs.eventtap.makeKeyEvent(13, true)")
            #expect(harness.evalInt("evt0.keyCode") == 0)
            #expect(harness.evalInt("evt13.keyCode") == 13)
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent treats a digit string as a character, not a key code")
        func testMakeKeyEventDigitString() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('0', true)")
            #expect(harness.evalInt("evt.keyCode") == KeyboardLayout.shared.keyCodes.keyCode(forName: "0"))
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent resolves characters through the current layout")
        func testMakeKeyEventFollowsLayout() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('w', true)")
            #expect(harness.evalInt("evt.keyCode") == KeyboardLayout.shared.keyCodes.keyCode(forName: "w"))
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent returns null for a key that is neither a name nor a key code")
        func testMakeKeyEventRejectsBoolean() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent(true, true)")
            harness.expectTrue("evt === null || evt === undefined")
            #expect(!harness.hasException)
        }

        // MARK: makeKeyEventWithCode

        @Test("makeKeyEventWithCode returns an object")
        func testMakeKeyEventWithCodeReturnsObject() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEventWithCode(0, true)")
            harness.expectTrue("typeof evt === 'object' && evt !== null")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEventWithCode sets the keyCode correctly")
        func testMakeKeyEventWithCodeSetsKeyCode() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEventWithCode(36, true)")
            #expect(harness.evalInt("evt.keyCode") == 36)
            #expect(!harness.hasException)
        }

        // MARK: Event properties

        @Test("event keyCode can be read and written")
        func testEventKeyCodeGetSet() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeKeyEvent('a', true)
                evt.keyCode = 42
            """)
            #expect(harness.evalInt("evt.keyCode") == 42)
            #expect(!harness.hasException)
        }

        @Test("event rawFlags can be read and written")
        func testEventRawFlagsGetSet() throws {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeKeyEvent('a', true)
                evt.rawFlags = hs.eventtap.modifierFlags.cmd
            """)
            let rawFlags = try #require(harness.evalInt("evt.rawFlags"))
            let cmdFlag = try #require(harness.evalInt("hs.eventtap.modifierFlags.cmd"))
            #expect(rawFlags == cmdFlag)
            #expect(!harness.hasException)
        }

        @Test("event flags returns an array")
        func testEventFlagsReturnsArray() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            harness.expectTrue("Array.isArray(evt.flags)")
            #expect(!harness.hasException)
        }

        @Test("event location returns object with x and y")
        func testEventLocationHasXAndY() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 100, 200, 0)")
            #expect(harness.evalTypeOf("evt.location") == "object")
            #expect(harness.evalTypeOf("evt.location.x") == "number")
            #expect(harness.evalTypeOf("evt.location.y") == "number")
            #expect(!harness.hasException)
        }

        @Test("event location can be modified")
        func testEventLocationCanBeModified() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.mouseMoved, 0, 0, 0)
                evt.location = {x: 150, y: 250}
            """)
            #expect(harness.evalInt("evt.location.x") == 150)
            #expect(harness.evalInt("evt.location.y") == 250)
            #expect(!harness.hasException)
        }

        // MARK: makeMouseEvent

        @Test("makeMouseEvent returns an object for leftMouseDown")
        func testMakeMouseEventReturnsObject() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 400, 300, 0)")
            harness.expectTrue("typeof evt === 'object' && evt !== null")
            #expect(!harness.hasException)
        }

        @Test("makeMouseEvent sets the correct event type")
        func testMakeMouseEventType() throws {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 400, 300, 0)")
            let eventType = try #require(harness.evalInt("evt.type"))
            let leftMouseDownType = try #require(harness.evalInt("hs.eventtap.eventTypes.leftMouseDown"))
            #expect(eventType == leftMouseDownType)
            #expect(!harness.hasException)
        }

        @Test("makeMouseEvent preserves Hammerspoon coordinates in location")
        func testMakeMouseEventCoordinates() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 123, 456, 0)")
            #expect(harness.evalInt("evt.location.x") == 123)
            #expect(harness.evalInt("evt.location.y") == 456)
            #expect(!harness.hasException)
        }

        // MARK: makeScrollWheelEvent

        @Test("makeScrollWheelEvent returns an object")
        func testMakeScrollWheelEventReturnsObject() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeScrollWheelEvent(0, 3, 500, 400)")
            harness.expectTrue("typeof evt === 'object' && evt !== null")
            #expect(!harness.hasException)
        }

        @Test("makeScrollWheelEvent has scroll event type")
        func testMakeScrollWheelEventType() throws {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeScrollWheelEvent(0, 3, 500, 400)")
            let eventType = try #require(harness.evalInt("evt.type"))
            let scrollWheelType = try #require(harness.evalInt("hs.eventtap.eventTypes.scrollWheel"))
            #expect(eventType == scrollWheelType)
            #expect(!harness.hasException)
        }

        // MARK: duplicate

        @Test("duplicate returns a new event object")
        func testDuplicateReturnsNewObject() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeKeyEvent('a', true)
                var copy = evt.duplicate()
            """)
            harness.expectTrue("copy !== null && copy !== undefined")
            harness.expectTrue("copy !== evt")
            #expect(!harness.hasException)
        }

        @Test("duplicate creates an independent copy")
        func testDuplicateIsIndependent() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeKeyEvent('a', true)
                var copy = evt.duplicate()
                copy.keyCode = 99
            """)
            harness.expectTrue("evt.keyCode !== 99")
            #expect(harness.evalInt("copy.keyCode") == 99)
            #expect(!harness.hasException)
        }

        // MARK: addWatcher returns watcher object

        @Test("addWatcher returns an object with identifier")
        func testAddWatcherReturnsObjectWithIdentifier() {
            let harness = makeHarness()
            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) {}
                )
            """)
            harness.expectTrue("tap !== null && tap !== undefined")
            #expect(harness.evalTypeOf("tap.identifier") == "string")
            harness.expectTrue("tap.identifier.length > 0")
            #expect(!harness.hasException)
        }

        @Test("two taps have different identifiers")
        func testTapIdentifiersAreUnique() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function() {})
                    var b = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function() {})
                    return a.identifier !== b.identifier
                })()
            """)
        }

        @Test("tap isEnabled returns false before start")
        func testTapIsDisabledBeforeStart() {
            let harness = makeHarness()
            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) {}
                )
            """)
            harness.expectTrue("tap.isEnabled() === false")
            #expect(!harness.hasException)
        }

        @Test("listenOnly defaults to false")
        func testListenOnlyDefaultsFalse() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(evt) {})")
            #expect(harness.evalBool("tap.listenOnly") == false)
            #expect(!harness.hasException)
        }

        @Test("addWatcher with listenOnly true sets listenOnly property")
        func testAddWatcherListenOnly() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(evt) {}, true)")
            #expect(harness.evalBool("tap.listenOnly") == true)
            #expect(!harness.hasException)
        }

        @Test("addWatcher with listenOnly false sets listenOnly property to false")
        func testAddWatcherExplicitModify() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(evt) {}, false)")
            #expect(harness.evalBool("tap.listenOnly") == false)
            #expect(!harness.hasException)
        }

        @Test("addWatcher with empty types returns null")
        func testAddWatcherEmptyTypes() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([], function() {})")
            harness.expectTrue("tap === null || tap === undefined")
            #expect(!harness.hasException)
        }

        // MARK: keyStrokesAsync

        @Test("keyStrokesAsync returns a Promise")
        func testKeyStrokesAsyncReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var p = hs.eventtap.keyStrokesAsync('a')")
            harness.expectTrue("p !== null && p !== undefined && typeof p.then === 'function'")
            #expect(!harness.hasException)
        }

        // keyStrokesAsync() posts events from a @concurrent background task, then hops back
        // to the main actor to resolve the Promise. waitForAsync() cooperatively yields the
        // main actor so that continuation can run and the .then handler fires.
        @Test("keyStrokesAsync resolves after posting all characters")
        @MainActor
        func testKeyStrokesAsyncResolves() async {
            let harness = makeHarness()
            harness.eval("""
                var __keyStrokesAsyncDone = false;
                hs.eventtap.keyStrokesAsync('ab').then(function() {
                    __keyStrokesAsyncDone = true;
                });
            """)
            let ok = await harness.waitForAsync(timeout: 5.0) {
                harness.evalValue("__keyStrokesAsyncDone")?.toBool() == true
            }
            #expect(ok, "keyStrokesAsync() did not resolve within timeout")
            #expect(!harness.hasException)
        }

        // MARK: System state queries

        @Test("currentModifiers returns an array")
        func testCurrentModifiersReturnsArray() {
            let harness = makeHarness()
            harness.eval("var mods = hs.eventtap.currentModifiers()")
            harness.expectTrue("Array.isArray(mods)")
            #expect(!harness.hasException)
        }

        @Test("checkMouseButtons returns an object with left/right/middle")
        func testCheckMouseButtonsReturnsObject() {
            let harness = makeHarness()
            harness.eval("var buttons = hs.eventtap.checkMouseButtons()")
            #expect(harness.evalTypeOf("buttons") == "object")
            #expect(harness.evalTypeOf("buttons.left") == "boolean")
            #expect(harness.evalTypeOf("buttons.right") == "boolean")
            #expect(harness.evalTypeOf("buttons.middle") == "boolean")
            #expect(!harness.hasException)
        }

        @Test("mouseLocation returns object with numeric x and y")
        func testMouseLocationReturnsObject() {
            let harness = makeHarness()
            harness.eval("var loc = hs.eventtap.mouseLocation()")
            #expect(harness.evalTypeOf("loc") == "object")
            #expect(harness.evalTypeOf("loc.x") == "number")
            #expect(harness.evalTypeOf("loc.y") == "number")
            #expect(!harness.hasException)
        }

        @Test("doubleClickInterval returns a positive number")
        func testDoubleClickIntervalIsPositive() {
            let harness = makeHarness()
            harness.eval("var interval = hs.eventtap.doubleClickInterval()")
            harness.expectTrue("typeof interval === 'number' && interval > 0")
            #expect(!harness.hasException)
        }

        @Test("keyRepeatDelay returns a positive number")
        func testKeyRepeatDelayIsPositive() {
            let harness = makeHarness()
            harness.eval("var delay = hs.eventtap.keyRepeatDelay()")
            harness.expectTrue("typeof delay === 'number' && delay > 0")
            #expect(!harness.hasException)
        }

        @Test("keyRepeatInterval returns a positive number")
        func testKeyRepeatIntervalIsPositive() {
            let harness = makeHarness()
            harness.eval("var interval = hs.eventtap.keyRepeatInterval()")
            harness.expectTrue("typeof interval === 'number' && interval > 0")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: Accessibility-gated tests

    private nonisolated func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    @Suite("hs.eventtap accessibility-gated tests",
           .serialized,
           .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"))
    struct HSEventTapAccessibilityTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            return harness
        }

        @Test("addWatcher start/stop lifecycle works with accessibility")
        func testWatcherStartStop() {
            let harness = makeHarness()
            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) { return hs.eventtap.emit }
                )
                tap.start()
            """)
            harness.expectTrue("tap.isEnabled() === true")
            harness.eval("tap.stop()")
            harness.expectTrue("tap.isEnabled() === false")
            #expect(!harness.hasException)
        }

        @Test("listen-only tap start/stop lifecycle works")
        func testListenOnlyWatcherStartStop() {
            let harness = makeHarness()
            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) {},
                    true
                )
                tap.start()
            """)
            harness.expectTrue("tap.isEnabled() === true")
            #expect(harness.evalBool("tap.listenOnly") == true)
            harness.eval("tap.stop()")
            harness.expectTrue("tap.isEnabled() === false")
            #expect(!harness.hasException)
        }

        @Test("listen-only tap callback fires when synthetic event is posted")
        func testListenOnlyTapCallbackFires() {
            let harness = makeHarness()
            var fired = false
            harness.registerCallback("onKeyDown") { fired = true }

            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) { __test_callback('onKeyDown') },
                    true
                )
                tap.start()
            """)
            harness.eval("hs.eventtap.keyStroke([], 'a')")

            let ok = harness.waitFor(timeout: 1.0) { fired }

            harness.eval("tap.stop()")
            #expect(ok, "Listen-only tap callback should have fired")
            #expect(!harness.hasException)
        }

        @Test("event tap callback fires when synthetic event is posted")
        func testTapCallbackFires() {
            let harness = makeHarness()
            var fired = false
            harness.registerCallback("onKeyDown") { fired = true }

            // Start the tap first; stop it only after the callback window.
            harness.eval("""
                var tap = hs.eventtap.addWatcher(
                    [hs.eventtap.eventTypes.keyDown],
                    function(evt) {
                        __test_callback('onKeyDown')
                        return hs.eventtap.consume
                    }
                )
                tap.start()
            """)
            // Post a synthetic key event while the tap is active.
            harness.eval("hs.eventtap.keyStroke([], 'a')")

            // waitFor runs the RunLoop so the tap callback can be delivered.
            let ok = harness.waitFor(timeout: 1.0) { fired }

            harness.eval("tap.stop()")
            #expect(ok, "Tap callback should have fired")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 4: HSEventTapHotkey matching (Swift-level)

    @Suite("HSEventTapHotkey matching tests")
    struct HSEventTapHotkeyMatchingTests {

        @MainActor
        @Test("matches returns true for exact key and modifier")
        func testMatchesExactKeyAndModifier() {
            let coordinator = MockEventTapHotkeyCoordinator()
            let hotkey = HSEventTapHotkey(
                keyCode: 0x04,  // h
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
            event.flags = .maskCommand

            #expect(hotkey.matches(event: event, type: .keyDown))
        }

        @MainActor
        @Test("matches returns false when extra modifier is present")
        func testMatchesReturnsFalseForExtraModifier() {
            let coordinator = MockEventTapHotkeyCoordinator()
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
            let coordinator = MockEventTapHotkeyCoordinator()
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
            let coordinator = MockEventTapHotkeyCoordinator()
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

    // MARK: - bindHotkey and keyboard layouts (issue #270)

    /// These replace the process-wide key code table to simulate a layout switch, so they're
    /// serialized and synchronous (nothing else on the main actor can run mid-test), and always
    /// restore the real table afterwards.
    @Suite("hs.eventtap.bindHotkey keyboard layout tests", .serialized)
    struct HSEventTapBindHotkeyLayoutTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
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
            #expect(makeHarness().evalBool("hs.eventtap.followsKeyboardLayout") == true)
        }

        @Test("bindHotkey reports the key it was bound with and its key code")
        func testKeyAndKeyCode() {
            let harness = makeHarness()
            harness.eval("""
                var named = hs.eventtap.bindHotkey(['cmd','alt','ctrl','shift'], 'f1', () => {}, null)
                var coded = hs.eventtap.bindHotkey(['cmd','alt','ctrl','shift'], 13, () => {}, null)
            """)
            #expect(harness.evalString("named.key") == "f1")
            #expect(harness.evalInt("named.keyCode") == 122)
            #expect(harness.evalTypeOf("coded.key") == "number")
            #expect(harness.evalInt("coded.keyCode") == 13)
            harness.eval("hs.eventtap.removeHotkey(named); hs.eventtap.removeHotkey(coded)")
            #expect(!harness.hasException)
        }

        @Test("a layout change moves hotkeys bound by name, but not by key code")
        func testLayoutChangeMovesNamedHotkeys() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                harness.eval("""
                    var named = hs.eventtap.bindHotkey(['cmd','alt','ctrl','shift'], 'w', () => {}, null)
                    var coded = hs.eventtap.bindHotkey(['cmd','alt','ctrl','shift'], 13, () => {}, null)
                """)
                #expect(harness.evalInt("named.keyCode") == 13)

                KeyboardLayout.shared.replace(with: dvorak)
                #expect(harness.evalInt("named.keyCode") == 43)
                #expect(harness.evalBool("named.isEnabled()") == true)
                #expect(harness.evalInt("coded.keyCode") == 13)

                harness.eval("hs.eventtap.removeHotkey(named); hs.eventtap.removeHotkey(coded)")
            }
            #expect(!harness.hasException)
        }

        @Test("a moved hotkey matches events from its new key")
        func testMovedHotkeyMatchesNewKey() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            try withLayout(us) {
                harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'w', () => {}, null)")
                KeyboardLayout.shared.replace(with: dvorak)
                let hotkey = try #require(harness.evalValue("hk")?.toObjectOf(HSEventTapHotkey.self) as? HSEventTapHotkey)

                let source = CGEventSource(stateID: .privateState)
                let oldKey = try #require(CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: true))
                let newKey = try #require(CGEvent(keyboardEventSource: source, virtualKey: 43, keyDown: true))
                oldKey.flags = .maskCommand
                newKey.flags = .maskCommand
                #expect(!hotkey.matches(event: oldKey, type: .keyDown))
                #expect(hotkey.matches(event: newKey, type: .keyDown))

                harness.eval("hs.eventtap.removeHotkey(hk)")
            }
            #expect(!harness.hasException)
        }

        /// Sends a synthetic key event through the module's hotkey dispatcher, returning true if
        /// a hotkey consumed it.
        private func dispatch(_ module: HSEventTapModule, _ type: CGEventType, keyCode: CGKeyCode,
                              flags: CGEventFlags) throws -> Bool {
            let source = CGEventSource(stateID: .privateState)
            let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: type == .keyDown))
            event.flags = flags
            return module.dispatchKeyEvent(type: type, event: event) == nil
        }

        @Test("a hotkey that moves while its key is held still gets that key's release")
        func testReleaseAfterMoveWhileHeld() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            let module = try #require(harness.evalValue("hs.eventtap")?.toObjectOf(HSEventTapModule.self) as? HSEventTapModule)
            try withLayout(us) { () throws in
                // "," moves onto the key "w" leaves (code 13), so it must not get w's release
                harness.eval("""
                    var wPressed = 0, wReleased = 0, commaReleased = 0
                    var w = hs.eventtap.bindHotkey(['cmd'], 'w', () => wPressed++, () => wReleased++)
                    var comma = hs.eventtap.bindHotkey(['cmd'], ',', null, () => commaReleased++)
                """)

                #expect(try dispatch(module, .keyDown, keyCode: 13, flags: .maskCommand))
                KeyboardLayout.shared.replace(with: dvorak)
                #expect(try dispatch(module, .keyUp, keyCode: 13, flags: .maskCommand))

                #expect(harness.evalInt("wPressed") == 1)
                #expect(harness.evalInt("wReleased") == 1)
                #expect(harness.evalInt("commaReleased") == 0)

                harness.eval("hs.eventtap.removeHotkey(w); hs.eventtap.removeHotkey(comma)")
            }
            #expect(!harness.hasException)
        }

        @Test("a held hotkey gets its release even if a modifier was let go first")
        func testReleaseAfterModifierLetGo() throws {
            let harness = makeHarness()
            let module = try #require(harness.evalValue("hs.eventtap")?.toObjectOf(HSEventTapModule.self) as? HSEventTapModule)
            harness.eval("""
                var released = 0
                var hk = hs.eventtap.bindHotkey(['cmd'], 'f13', null, () => released++)
            """)

            #expect(try dispatch(module, .keyDown, keyCode: CGKeyCode(kVK_F13), flags: .maskCommand))
            #expect(try dispatch(module, .keyUp, keyCode: CGKeyCode(kVK_F13), flags: []))
            #expect(harness.evalInt("released") == 1)

            // Once released, the same key-up no longer belongs to the hotkey
            #expect(try dispatch(module, .keyUp, keyCode: CGKeyCode(kVK_F13), flags: []) == false)

            harness.eval("hs.eventtap.removeHotkey(hk)")
            #expect(!harness.hasException)
        }

        @Test("a hotkey disabled while its key is held lets the release through")
        func testReleaseAfterDisableWhileHeld() throws {
            let harness = makeHarness()
            let module = try #require(harness.evalValue("hs.eventtap")?.toObjectOf(HSEventTapModule.self) as? HSEventTapModule)
            harness.eval("""
                var released = 0
                var hk = hs.eventtap.bindHotkey(['cmd'], 'f13', null, () => released++)
            """)

            #expect(try dispatch(module, .keyDown, keyCode: CGKeyCode(kVK_F13), flags: .maskCommand))
            harness.eval("hk.disable()")
            #expect(try dispatch(module, .keyUp, keyCode: CGKeyCode(kVK_F13), flags: .maskCommand) == false)
            #expect(harness.evalInt("released") == 0)

            harness.eval("hs.eventtap.removeHotkey(hk)")
            #expect(!harness.hasException)
        }

        @Test("followsKeyboardLayout = false keeps hotkeys in place until it's turned back on")
        func testFollowsKeyboardLayoutFalse() throws {
            let us = try layoutTable("com.apple.keylayout.US")
            let dvorak = try layoutTable("com.apple.keylayout.Dvorak")
            let harness = makeHarness()
            withLayout(us) {
                harness.eval("""
                    hs.eventtap.followsKeyboardLayout = false
                    var hk = hs.eventtap.bindHotkey(['cmd','alt','ctrl','shift'], 'w', () => {}, null)
                """)
                KeyboardLayout.shared.replace(with: dvorak)
                #expect(harness.evalInt("hk.keyCode") == 13)

                harness.eval("hs.eventtap.followsKeyboardLayout = true")
                #expect(harness.evalInt("hk.keyCode") == 43)

                harness.eval("hs.eventtap.removeHotkey(hk)")
            }
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 5: bindHotkey API structure

    @Suite("hs.eventtap.bindHotkey API structure tests")
    struct HSEventTapBindHotkeyStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSEventTapModule.self, as: "eventtap")
            return harness
        }

        @Test("bindHotkey is a function")
        func testBindHotkeyIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.bindHotkey") == "function")
        }

        @Test("removeHotkey is a function")
        func testRemoveHotkeyIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.eventtap.removeHotkey") == "function")
        }

        @Test("bindHotkey with valid args returns an object")
        func testBindHotkeyReturnsObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(harness.evalTypeOf("hk.enable") == "function")
            #expect(harness.evalTypeOf("hk.disable") == "function")
            #expect(harness.evalTypeOf("hk.isEnabled") == "function")
            #expect(!harness.hasException)
        }

        @Test("bindHotkey with fn modifier returns an object")
        func testBindHotkeyFnModifier() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['fn'], 'f1', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            #expect(!harness.hasException)
        }

        @Test("bindHotkey with side-specific modifier returns an object")
        func testBindHotkeySideSpecificModifier() {
            let harness = makeHarness()
            for mod in ["leftCmd", "rightCmd", "leftAlt", "rightAlt", "leftCtrl", "rightCtrl", "leftShift", "rightShift"] {
                harness.eval("var hk = hs.eventtap.bindHotkey(['\(mod)'], 'a', () => {}, () => {})")
                harness.expectTrue("typeof hk === 'object' && hk !== null")
                #expect(!harness.hasException, "bindHotkey with '\(mod)' should succeed")
            }
        }

        @Test("bindHotkey with unknown key returns null")
        func testBindHotkeyUnknownKeyReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'notakey', () => {}, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("bindHotkey with unknown modifier returns null")
        func testBindHotkeyUnknownModifierReturnsNull() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['supermod'], 'h', () => {}, () => {})")
            harness.expectTrue("hk === null || hk === undefined")
            #expect(!harness.hasException)
        }

        @Test("bindHotkey auto-enables the hotkey")
        func testBindHotkeyAutoEnables() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.expectTrue("hk.isEnabled() === true")
            #expect(!harness.hasException)
        }

        @Test("disable makes isEnabled return false")
        func testBindHotkeyDisable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.eval("hk.disable()")
            harness.expectTrue("hk.isEnabled() === false")
            #expect(!harness.hasException)
        }

        @Test("onPressed is settable after bindHotkey")
        func testBindHotkeyCallbackSettable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.eval("hk.onPressed = () => {}")
            #expect(!harness.hasException)
        }

        // MARK: - Memory Leak Tests

        @Test("Active HSEventTap is released after shutdown")
        func testEventTapDoesNotLeakAfterReload() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSEventTapModule.self, as: "eventtap")
                // Create and start the tap. start() sets selfRetain=self (if Accessibility is
                // granted, creating a real CGEventTap) or immediately clears it (if not). Either
                // way, shutdown() → destroy() → stop() clears selfRetain and the module's strong
                // taps array, freeing the tap regardless of whether it actually captured events.
                harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(e) { return true }, true)")
                harness.eval("tap.start()")
                if let obj = harness.evalValue("tap")?.toObjectOf(HSEventTap.self) as? HSEventTap {
                    tracker.track(obj)
                }
                harness.eval("tap = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
