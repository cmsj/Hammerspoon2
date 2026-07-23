//
//  HSMouseIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.mouse tests")
struct HSMouseTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.mouse API structure tests")
    struct HSMouseStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMouseModule.self, as: "mouse")
            return harness
        }

        // MARK: Position functions

        @Test("absolutePosition is a function")
        func testAbsolutePositionIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.absolutePosition === 'function'")
        }

        @Test("setAbsolutePosition is a function")
        func testSetAbsolutePositionIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.setAbsolutePosition === 'function'")
        }

        @Test("getRelativePosition is a function")
        func testGetRelativePositionIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.getRelativePosition === 'function'")
        }

        @Test("setRelativePosition is a function")
        func testSetRelativePositionIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.setRelativePosition === 'function'")
        }

        // MARK: Screen functions

        @Test("getCurrentScreen is a function")
        func testGetCurrentScreenIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.getCurrentScreen === 'function'")
        }

        // MARK: Device functions

        @Test("count is a function")
        func testCountIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.count === 'function'")
        }

        @Test("names is a function")
        func testNamesIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.names === 'function'")
        }

        // MARK: Settings functions

        @Test("trackingSpeed is a function")
        func testTrackingSpeedIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.trackingSpeed === 'function'")
        }

        @Test("setTrackingSpeed is a function")
        func testSetTrackingSpeedIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.setTrackingSpeed === 'function'")
        }

        @Test("scrollDirection is a function")
        func testScrollDirectionIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.scrollDirection === 'function'")
        }

        // MARK: Cursor functions

        @Test("currentCursorType is a function")
        func testCurrentCursorTypeIsFunction() {
            makeHarness().expectTrue("typeof hs.mouse.currentCursorType === 'function'")
        }
    }

    // MARK: - Suite 2: Behaviour

    @Suite("hs.mouse behaviour tests")
    struct HSMouseBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMouseModule.self, as: "mouse")
            return harness
        }

        // MARK: absolutePosition

        @Test("absolutePosition() returns an object with x and y numbers")
        func testAbsolutePositionShape() {
            let harness = makeHarness()
            harness.eval("var pos = hs.mouse.absolutePosition()")
            harness.expectTrue("typeof pos === 'object' && pos !== null")
            harness.expectTrue("typeof pos.x === 'number'")
            harness.expectTrue("typeof pos.y === 'number'")
            #expect(!harness.hasException)
        }

        @Test("absolutePosition() x is non-negative")
        func testAbsolutePositionXNonNegative() {
            let harness = makeHarness()
            harness.eval("var pos = hs.mouse.absolutePosition()")
            harness.expectTrue("pos.x >= 0")
            #expect(!harness.hasException)
        }

        @Test("absolutePosition() y is non-negative")
        func testAbsolutePositionYNonNegative() {
            let harness = makeHarness()
            harness.eval("var pos = hs.mouse.absolutePosition()")
            harness.expectTrue("pos.y >= 0")
            #expect(!harness.hasException)
        }

        // MARK: setAbsolutePosition

        @Test("setAbsolutePosition() does not throw")
        func testSetAbsolutePositionDoesNotThrow() {
            let harness = makeHarness()
            let before = harness.evalValue("hs.mouse.absolutePosition()")?.toDictionary()
            harness.eval("hs.mouse.setAbsolutePosition(hs.mouse.absolutePosition().x, hs.mouse.absolutePosition().y)")
            #expect(!harness.hasException)
            _ = before
        }

        // MARK: getRelativePosition

        @Test("getRelativePosition() returns an object or null")
        func testGetRelativePositionShape() {
            let harness = makeHarness()
            harness.eval("var rel = hs.mouse.getRelativePosition()")
            harness.expectTrue("rel === null || (typeof rel === 'object' && typeof rel.x === 'number' && typeof rel.y === 'number')")
            #expect(!harness.hasException)
        }

        // MARK: count

        @Test("count() returns a non-negative integer")
        func testCountNonNegative() {
            let harness = makeHarness()
            harness.eval("var n = hs.mouse.count()")
            harness.expectTrue("typeof n === 'number' && n >= 0 && Math.floor(n) === n")
            #expect(!harness.hasException)
        }

        @Test("count(true) >= count(false)")
        func testCountIncludesInternalIsLargerOrEqual() {
            let harness = makeHarness()
            harness.eval("var external = hs.mouse.count(false)")
            harness.eval("var all = hs.mouse.count(true)")
            harness.expectTrue("all >= external")
            #expect(!harness.hasException)
        }

        // MARK: names

        @Test("names() returns an array")
        func testNamesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.mouse.names())")
            #expect(!harness.hasException)
        }

        @Test("names() length matches count()")
        func testNamesLengthMatchesCount() {
            let harness = makeHarness()
            harness.eval("var n = hs.mouse.count()")
            harness.eval("var names = hs.mouse.names()")
            harness.expectTrue("names.length === n")
            #expect(!harness.hasException)
        }

        @Test("names(true) length matches count(true)")
        func testNamesIncludeInternalLengthMatchesCount() {
            let harness = makeHarness()
            harness.eval("var n = hs.mouse.count(true)")
            harness.eval("var names = hs.mouse.names(true)")
            harness.expectTrue("names.length === n")
            #expect(!harness.hasException)
        }

        @Test("names() elements are non-empty strings")
        func testNamesElementsAreStrings() {
            let harness = makeHarness()
            harness.eval("var names = hs.mouse.names(true)")
            harness.expectTrue("names.every(function(n) { return typeof n === 'string' && n.length > 0 })")
            #expect(!harness.hasException)
        }

        // MARK: scrollDirection

        @Test("scrollDirection() returns 'natural' or 'normal'")
        func testScrollDirectionIsValidString() {
            let harness = makeHarness()
            harness.eval("var dir = hs.mouse.scrollDirection()")
            harness.expectTrue("dir === 'natural' || dir === 'normal'")
            #expect(!harness.hasException)
        }

        // MARK: trackingSpeed

        @Test("trackingSpeed() returns a number")
        func testTrackingSpeedIsNumber() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.mouse.trackingSpeed() === 'number'")
            #expect(!harness.hasException)
        }

        // MARK: currentCursorType

        @Test("currentCursorType() returns a non-empty string")
        func testCurrentCursorTypeIsString() {
            let harness = makeHarness()
            harness.eval("var ct = hs.mouse.currentCursorType()")
            harness.expectTrue("typeof ct === 'string' && ct.length > 0")
            #expect(!harness.hasException)
        }

        @Test("currentCursorType() returns a known type name or 'unknown'")
        func testCurrentCursorTypeIsKnownValue() {
            let harness = makeHarness()
            harness.eval("""
                var ct = hs.mouse.currentCursorType()
                var known = ['arrow','iBeam','crosshair','closedHand','openHand','pointingHand',
                             'resizeLeft','resizeRight','resizeLeftRight','resizeUp','resizeDown',
                             'resizeUpDown','iBeamCursorForVerticalLayout','operationNotAllowed',
                             'dragLink','dragCopy','contextualMenu','unknown']
            """)
            harness.expectTrue("known.indexOf(ct) !== -1")
            #expect(!harness.hasException)
        }

        // MARK: getCurrentScreen

        @Test("getCurrentScreen() returns an object or null")
        func testGetCurrentScreenReturnsObjectOrNull() {
            let harness = makeHarness()
            harness.eval("var s = hs.mouse.getCurrentScreen()")
            harness.expectTrue("s === null || typeof s === 'object'")
            #expect(!harness.hasException)
        }

        @Test("getCurrentScreen() result has name property when not null")
        func testGetCurrentScreenHasName() {
            let harness = makeHarness()
            harness.eval("var s = hs.mouse.getCurrentScreen()")
            harness.expectTrue("s === null || typeof s.name === 'string'")
            #expect(!harness.hasException)
        }

        // MARK: setRelativePosition

        @Test("setRelativePosition() does not throw")
        func testSetRelativePositionDoesNotThrow() {
            let harness = makeHarness()
            // Get current relative position and set it back — net zero movement
            harness.eval("""
                var rel = hs.mouse.getRelativePosition()
                if (rel !== null) {
                    hs.mouse.setRelativePosition(rel.x, rel.y)
                }
            """)
            #expect(!harness.hasException)
        }
    }
}
