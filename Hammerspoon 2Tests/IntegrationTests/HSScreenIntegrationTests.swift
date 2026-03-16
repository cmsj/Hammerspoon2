//
//  HSScreenIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.screen module.
///
/// These tests verify screen inspection and navigation on whatever displays
/// are attached at test time.  Display-configuration mutations (setMode,
/// setOrigin, setPrimary, mirrorOf, mirrorStop) are intentionally **not**
/// tested here to avoid disrupting the developer's desktop during a test run.
@Suite(.serialized) struct HSScreenIntegrationTests {

    init() async {
        await JSTestHarness.drainMainActorQueue()
    }

    // MARK: - Module API Tests

    @Test("hs.screen is accessible as an object")
    func testModuleAccess() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.expectTrue("typeof hs.screen === 'object'")
    }

    @Test("hs.screen exposes all expected functions")
    func testModuleFunctions() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.expectTrue("typeof hs.screen.all === 'function'")
        harness.expectTrue("typeof hs.screen.main === 'function'")
        harness.expectTrue("typeof hs.screen.primary === 'function'")
    }

    // MARK: - all / main / primary

    @Test("all() returns a non-empty array")
    func testAllScreensIsNonEmpty() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var screens = hs.screen.all();")
        harness.expectTrue("Array.isArray(screens)")
        harness.expectTrue("screens.length >= 1")
    }

    @Test("main() returns an HSScreen object")
    func testMainScreenReturnsObject() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.main();")
        harness.expectTrue("s !== null && s !== undefined")
        harness.expectTrue("typeof s === 'object'")
    }

    @Test("primary() returns an HSScreen object")
    func testPrimaryScreenReturnsObject() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.primary();")
        harness.expectTrue("s !== null && s !== undefined")
        harness.expectTrue("typeof s === 'object'")
    }

    // MARK: - Identity Properties

    @Test("Screen id is a positive integer")
    func testScreenID() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.primary();")
        harness.expectTrue("typeof s.id === 'number' && s.id > 0")
    }

    @Test("Screen name is a non-empty string")
    func testScreenName() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.primary();")
        harness.expectTrue("typeof s.name === 'string' && s.name.length > 0")
    }

    @Test("Screen uuid is a non-empty string")
    func testScreenUUID() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.primary();")
        harness.expectTrue("typeof s.uuid === 'string' && s.uuid.length > 0")
    }

    // MARK: - Geometry

    @Test("frame returns an object with x, y, w, h")
    func testFrameStructure() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var f = hs.screen.primary().frame;")
        harness.expectTrue("f !== null && f !== undefined")
        harness.expectTrue("'x' in f && 'y' in f && 'w' in f && 'h' in f")
        harness.expectTrue("typeof f.w === 'number' && f.w > 0")
        harness.expectTrue("typeof f.h === 'number' && f.h > 0")
    }

    @Test("fullFrame returns an object with x, y, w, h")
    func testFullFrameStructure() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var f = hs.screen.primary().fullFrame;")
        harness.expectTrue("f !== null && f !== undefined")
        harness.expectTrue("'x' in f && 'y' in f && 'w' in f && 'h' in f")
        harness.expectTrue("typeof f.w === 'number' && f.w > 0")
        harness.expectTrue("typeof f.h === 'number' && f.h > 0")
    }

    @Test("fullFrame area is >= frame area (frame excludes menu bar/dock)")
    func testFullFrameLargerThanFrame() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var ff = s.fullFrame;
        var f  = s.frame;
        var ffArea = ff.w * ff.h;
        var fArea  = f.w  * f.h;
        """)
        harness.expectTrue("ffArea >= fArea")
    }

    @Test("position returns an object with x and y")
    func testPositionStructure() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var p = hs.screen.primary().position;")
        harness.expectTrue("p !== null && p !== undefined")
        harness.expectTrue("'x' in p && 'y' in p")
        harness.expectTrue("typeof p.x === 'number' && typeof p.y === 'number'")
    }

    // MARK: - Display Modes

    @Test("mode returns an object with required keys")
    func testCurrentModeStructure() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var m = hs.screen.primary().mode;")
        harness.expectTrue("m !== null && m !== undefined")
        harness.expectTrue("'width' in m && 'height' in m && 'scale' in m && 'frequency' in m")
        harness.expectTrue("m.width > 0 && m.height > 0")
        harness.expectTrue("m.scale >= 1")
        harness.expectTrue("m.frequency > 0")
    }

    @Test("availableModes returns a non-empty array")
    func testAvailableModes() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var modes = hs.screen.primary().availableModes;")
        harness.expectTrue("Array.isArray(modes) && modes.length >= 1")
        harness.expectTrue("'width' in modes[0] && 'height' in modes[0]")
    }

    @Test("mode is contained in availableModes")
    func testCurrentModeInAvailableModes() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var cur = s.mode;
        var modes = s.availableModes;
        var found = modes.some(function(m) {
            return m.width === cur.width && m.height === cur.height && m.scale === cur.scale;
        });
        """)
        harness.expectTrue("found")
    }

    // MARK: - Rotation

    @Test("rotation returns a number (0, 90, 180, or 270)")
    func testRotation() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var r = hs.screen.primary().rotation;")
        harness.expectTrue("typeof r === 'number'")
        harness.expectTrue("r === 0 || r === 90 || r === 180 || r === 270")
    }

    @Test("setting rotation to the current value does not throw")
    func testSetRotationNoOp() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        // Re-applying the current rotation is a safe no-op and must not throw.
        harness.eval("""
        var s = hs.screen.primary();
        s.rotation = s.rotation;
        """)
        #expect(!harness.hasException, "Setting rotation to its current value should not throw a JS exception")
    }

    @Test("setting rotation to an invalid value does not throw")
    func testSetRotationInvalidValue() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("hs.screen.primary().rotation = 45;")
        #expect(!harness.hasException, "Setting an invalid rotation angle should not throw a JS exception")
    }

    // MARK: - Navigation

    @Test("next() returns an HSScreen object")
    func testNext() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var n = hs.screen.primary().next();")
        harness.expectTrue("n !== null && n !== undefined")
        harness.expectTrue("typeof n === 'object'")
        harness.expectTrue("typeof n.id === 'number'")
    }

    @Test("previous() returns an HSScreen object")
    func testPrevious() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var p = hs.screen.primary().previous();")
        harness.expectTrue("p !== null && p !== undefined")
        harness.expectTrue("typeof p.id === 'number'")
    }

    @Test("next() of previous() round-trips to the same screen")
    func testNextPreviousRoundTrip() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var roundTripped = s.next().previous().id === s.id;
        """)
        harness.expectTrue("roundTripped")
    }

    @Test("Single screen: next() and previous() return the same screen")
    func testSingleScreenNavigation() {
        // This test is only meaningful when exactly one screen is attached.
        // We check the invariant regardless: on any count of screens,
        // iterating next() N times (N = all().length) returns to origin.
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var screens = hs.screen.all();
        var s = screens[0];
        var cur = s;
        for (var i = 0; i < screens.length; i++) {
            cur = cur.next();
        }
        var backToStart = cur.id === s.id;
        """)
        harness.expectTrue("backToStart")
    }

    @Test("toEast/toWest/toNorth/toSouth are functions")
    func testDirectionalFunctions() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var s = hs.screen.primary();")
        harness.expectTrue("typeof s.toEast === 'function'")
        harness.expectTrue("typeof s.toWest === 'function'")
        harness.expectTrue("typeof s.toNorth === 'function'")
        harness.expectTrue("typeof s.toSouth === 'function'")
    }

    @Test("Directional methods return null or an HSScreen")
    func testDirectionalReturnTypes() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var east  = s.toEast();
        var west  = s.toWest();
        var north = s.toNorth();
        var south = s.toSouth();
        function isScreenOrNull(v) {
            return v === null || (typeof v === 'object' && typeof v.id === 'number');
        }
        var allValid = isScreenOrNull(east) && isScreenOrNull(west) &&
                       isScreenOrNull(north) && isScreenOrNull(south);
        """)
        harness.expectTrue("allValid")
    }

    // MARK: - Coordinate Conversion

    @Test("absoluteToLocal() offsets a rect by the screen origin")
    func testAbsoluteToLocal() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var origin = s.position;
        var absRect = new HSRect(origin.x + 10, origin.y + 20, 100, 50);
        var local = s.absoluteToLocal(absRect);
        """)
        harness.expectTrue("local !== null")
        harness.expectEqual("local.x", 10.0)
        harness.expectEqual("local.y", 20.0)
        harness.expectEqual("local.w", 100.0)
        harness.expectEqual("local.h", 50.0)
    }

    @Test("localToAbsolute() is the inverse of absoluteToLocal()")
    func testLocalToAbsoluteRoundTrip() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("""
        var s = hs.screen.primary();
        var orig = new HSRect(100, 200, 300, 400);
        var local = s.absoluteToLocal(orig);
        var back  = s.localToAbsolute(local);
        var roundTripped = Math.abs(back.x - orig.x) < 0.001 &&
                           Math.abs(back.y - orig.y) < 0.001 &&
                           Math.abs(back.w - orig.w) < 0.001 &&
                           Math.abs(back.h - orig.h) < 0.001;
        """)
        harness.expectTrue("roundTripped")
    }

    @Test("absoluteToLocal() returns null for non-HSRect input")
    func testAbsoluteToLocalInvalidInput() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var result = hs.screen.primary().absoluteToLocal('not a rect');")
        harness.expectTrue("result === null || result === undefined")
    }

    // MARK: - Desktop Image

    @Test("desktopImage returns a string or null")
    func testDesktopImage() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("var img = hs.screen.primary().desktopImage;")
        harness.expectTrue("img === null || typeof img === 'string'")
    }

    @Test("setting desktopImage to a nonexistent path does not throw")
    func testSetDesktopImageMissingFile() {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")

        harness.eval("hs.screen.primary().desktopImage = '/nonexistent/wallpaper.jpg';")
        #expect(!harness.hasException, "Setting invalid desktopImage path should not throw a JS exception")
    }
}
