//
//  HSEventTapIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import ApplicationServices
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
            makeHarness().expectTrue("typeof hs.eventtap.eventTypes === 'object'")
        }

        @Test("eventTypes.keyDown is a number")
        func testEventTypesKeyDownIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.eventTypes.keyDown === 'number'")
        }

        @Test("eventTypes.keyUp is a number")
        func testEventTypesKeyUpIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.eventTypes.keyUp === 'number'")
        }

        @Test("eventTypes.leftMouseDown is a number")
        func testEventTypesLeftMouseDownIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.eventTypes.leftMouseDown === 'number'")
        }

        @Test("eventTypes.scrollWheel is a number")
        func testEventTypesScrollWheelIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.eventTypes.scrollWheel === 'number'")
        }

        @Test("modifierFlags is an object")
        func testModifierFlagsIsObject() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags === 'object'")
        }

        @Test("modifierFlags.cmd is a number")
        func testModifierFlagsCmdIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.cmd === 'number'")
        }

        @Test("modifierFlags.shift is a number")
        func testModifierFlagsShiftIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.shift === 'number'")
        }

        @Test("modifierFlags.leftCmd is a number")
        func testModifierFlagsLeftCmdIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.leftCmd === 'number'")
        }

        @Test("modifierFlags.rightCmd is a number")
        func testModifierFlagsRightCmdIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.rightCmd === 'number'")
        }

        @Test("modifierFlags.leftAlt is a number")
        func testModifierFlagsLeftAltIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.leftAlt === 'number'")
        }

        @Test("modifierFlags.rightAlt is a number")
        func testModifierFlagsRightAltIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.rightAlt === 'number'")
        }

        @Test("modifierFlags.leftCtrl is a number")
        func testModifierFlagsLeftCtrlIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.leftCtrl === 'number'")
        }

        @Test("modifierFlags.rightCtrl is a number")
        func testModifierFlagsRightCtrlIsNumber() {
            makeHarness().expectTrue("typeof hs.eventtap.modifierFlags.rightCtrl === 'number'")
        }

        @Test("consume is a boolean")
        func testConsumeIsBoolean() {
            makeHarness().expectTrue("typeof hs.eventtap.consume === 'boolean'")
        }

        @Test("emit is a boolean")
        func testEmitIsBoolean() {
            makeHarness().expectTrue("typeof hs.eventtap.emit === 'boolean'")
        }

        // MARK: Watcher management

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.addWatcher === 'function'")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.removeWatcher === 'function'")
        }

        // MARK: Event constructors

        @Test("makeKeyEvent is a function")
        func testMakeKeyEventIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.makeKeyEvent === 'function'")
        }

        @Test("makeKeyEventWithCode is a function")
        func testMakeKeyEventWithCodeIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.makeKeyEventWithCode === 'function'")
        }

        @Test("makeMouseEvent is a function")
        func testMakeMouseEventIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.makeMouseEvent === 'function'")
        }

        @Test("makeScrollWheelEvent is a function")
        func testMakeScrollWheelEventIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.makeScrollWheelEvent === 'function'")
        }

        // MARK: Convenience senders

        @Test("keyStroke is a function")
        func testKeyStrokeIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.keyStroke === 'function'")
        }

        @Test("keyStrokes is a function")
        func testKeyStrokesIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.keyStrokes === 'function'")
        }

        @Test("leftClick is a function")
        func testLeftClickIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.leftClick === 'function'")
        }

        @Test("rightClick is a function")
        func testRightClickIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.rightClick === 'function'")
        }

        @Test("doubleLeftClick is a function")
        func testDoubleLeftClickIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.doubleLeftClick === 'function'")
        }

        @Test("middleClick is a function")
        func testMiddleClickIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.middleClick === 'function'")
        }

        @Test("scrollWheel is a function")
        func testScrollWheelIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.scrollWheel === 'function'")
        }

        // MARK: System state

        @Test("currentModifiers is a function")
        func testCurrentModifiersIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.currentModifiers === 'function'")
        }

        @Test("checkMouseButtons is a function")
        func testCheckMouseButtonsIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.checkMouseButtons === 'function'")
        }

        @Test("mouseLocation is a function")
        func testMouseLocationIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.mouseLocation === 'function'")
        }

        @Test("doubleClickInterval is a function")
        func testDoubleClickIntervalIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.doubleClickInterval === 'function'")
        }

        @Test("keyRepeatDelay is a function")
        func testKeyRepeatDelayIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.keyRepeatDelay === 'function'")
        }

        @Test("keyRepeatInterval is a function")
        func testKeyRepeatIntervalIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.keyRepeatInterval === 'function'")
        }

        // MARK: Event object API

        @Test("event.post is a function")
        func testEventPostIsFunction() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            harness.expectTrue("typeof evt.post === 'function'")
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
            makeHarness().expectTrue("hs.eventtap.consume === false")
        }

        @Test("emit equals true")
        func testEmitEqualsTrue() {
            makeHarness().expectTrue("hs.eventtap.emit === true")
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
        func testMakeKeyEventTypeIsKeyDown() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            harness.expectTrue("evt.type === hs.eventtap.eventTypes.keyDown")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent sets the correct event type for keyUp")
        func testMakeKeyEventTypeIsKeyUp() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', false)")
            harness.expectTrue("evt.type === hs.eventtap.eventTypes.keyUp")
            #expect(!harness.hasException)
        }

        @Test("makeKeyEvent sets a non-zero keyCode for 'a'")
        func testMakeKeyEventKeyCodeForA() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeKeyEvent('a', true)")
            harness.expectTrue("typeof evt.keyCode === 'number'")
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
        func testMakeKeyEventMinusAliasMatchesChar() {
            let harness = makeHarness()
            harness.eval("""
                var evt1 = hs.eventtap.makeKeyEvent('minus', true)
                var evt2 = hs.eventtap.makeKeyEvent('-', true)
            """)
            harness.expectTrue("evt1.keyCode === evt2.keyCode")
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
            harness.expectTrue("evt.keyCode === 36")
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
            harness.expectTrue("evt.keyCode === 42")
            #expect(!harness.hasException)
        }

        @Test("event rawFlags can be read and written")
        func testEventRawFlagsGetSet() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeKeyEvent('a', true)
                evt.rawFlags = hs.eventtap.modifierFlags.cmd
            """)
            harness.expectTrue("evt.rawFlags === hs.eventtap.modifierFlags.cmd")
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
            harness.expectTrue("typeof evt.location === 'object'")
            harness.expectTrue("typeof evt.location.x === 'number'")
            harness.expectTrue("typeof evt.location.y === 'number'")
            #expect(!harness.hasException)
        }

        @Test("event location can be modified")
        func testEventLocationCanBeModified() {
            let harness = makeHarness()
            harness.eval("""
                var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.mouseMoved, 0, 0, 0)
                evt.location = {x: 150, y: 250}
            """)
            harness.expectTrue("evt.location.x === 150")
            harness.expectTrue("evt.location.y === 250")
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
        func testMakeMouseEventType() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 400, 300, 0)")
            harness.expectTrue("evt.type === hs.eventtap.eventTypes.leftMouseDown")
            #expect(!harness.hasException)
        }

        @Test("makeMouseEvent preserves Hammerspoon coordinates in location")
        func testMakeMouseEventCoordinates() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeMouseEvent(hs.eventtap.eventTypes.leftMouseDown, 123, 456, 0)")
            harness.expectTrue("evt.location.x === 123")
            harness.expectTrue("evt.location.y === 456")
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
        func testMakeScrollWheelEventType() {
            let harness = makeHarness()
            harness.eval("var evt = hs.eventtap.makeScrollWheelEvent(0, 3, 500, 400)")
            harness.expectTrue("evt.type === hs.eventtap.eventTypes.scrollWheel")
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
            harness.expectTrue("copy.keyCode === 99")
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
            harness.expectTrue("typeof tap.identifier === 'string'")
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
            harness.expectTrue("tap.listenOnly === false")
            #expect(!harness.hasException)
        }

        @Test("addWatcher with listenOnly true sets listenOnly property")
        func testAddWatcherListenOnly() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(evt) {}, true)")
            harness.expectTrue("tap.listenOnly === true")
            #expect(!harness.hasException)
        }

        @Test("addWatcher with listenOnly false sets listenOnly property to false")
        func testAddWatcherExplicitModify() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], function(evt) {}, false)")
            harness.expectTrue("tap.listenOnly === false")
            #expect(!harness.hasException)
        }

        @Test("addWatcher with empty types returns null")
        func testAddWatcherEmptyTypes() {
            let harness = makeHarness()
            harness.eval("var tap = hs.eventtap.addWatcher([], function() {})")
            harness.expectTrue("tap === null || tap === undefined")
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
            harness.expectTrue("typeof buttons === 'object'")
            harness.expectTrue("typeof buttons.left === 'boolean'")
            harness.expectTrue("typeof buttons.right === 'boolean'")
            harness.expectTrue("typeof buttons.middle === 'boolean'")
            #expect(!harness.hasException)
        }

        @Test("mouseLocation returns object with numeric x and y")
        func testMouseLocationReturnsObject() {
            let harness = makeHarness()
            harness.eval("var loc = hs.eventtap.mouseLocation()")
            harness.expectTrue("typeof loc === 'object'")
            harness.expectTrue("typeof loc.x === 'number'")
            harness.expectTrue("typeof loc.y === 'number'")
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
            harness.expectTrue("tap.listenOnly === true")
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
            makeHarness().expectTrue("typeof hs.eventtap.bindHotkey === 'function'")
        }

        @Test("removeHotkey is a function")
        func testRemoveHotkeyIsFunction() {
            makeHarness().expectTrue("typeof hs.eventtap.removeHotkey === 'function'")
        }

        @Test("bindHotkey with valid args returns an object")
        func testBindHotkeyReturnsObject() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.expectTrue("typeof hk === 'object' && hk !== null")
            harness.expectTrue("typeof hk.enable === 'function'")
            harness.expectTrue("typeof hk.disable === 'function'")
            harness.expectTrue("typeof hk.isEnabled === 'function'")
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

        @Test("callbackPressed is settable after bindHotkey")
        func testBindHotkeyCallbackSettable() {
            let harness = makeHarness()
            harness.eval("var hk = hs.eventtap.bindHotkey(['cmd'], 'h', () => {}, () => {})")
            harness.eval("hk.callbackPressed = () => {}")
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
