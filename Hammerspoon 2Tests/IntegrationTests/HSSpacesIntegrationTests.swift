//
//  HSSpacesIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import AXSwift
@testable import Hammerspoon_2

/// Whether the SkyLight framework loads at all. This is evaluated from test traits, outside the
/// main actor, so it can't ask HSSkyLight itself; isAvailable() is checked against it below.
private nonisolated func isSkyLightAvailable() -> Bool {
    unsafe dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) != nil
}

private nonisolated func canInspectOwnWindows() -> Bool {
    isSkyLightAvailable() && AXIsProcessTrusted()
}

/// The Mission Control tests add, switch to, and remove a real desktop, which takes over the
/// screen for a few seconds, so they only run when asked for explicitly:
/// `TEST_RUNNER_HS_TEST_MISSION_CONTROL=1 xcodebuild test ...`
private nonisolated func canDriveMissionControl() -> Bool {
    canInspectOwnWindows() && ProcessInfo.processInfo.environment["HS_TEST_MISSION_CONTROL"] != nil
}

/// Evaluates the JS expression `promise` in `harness` and waits for it to settle. Returns
/// "resolved:<value>" or "rejected:<reason>", or nil if it didn't settle within `timeout`.
@MainActor
private func settle(_ promise: String, in harness: JSTestHarness, timeout: TimeInterval = 10) async -> String? {
    harness.eval("""
        var __settled = undefined;
        (\(promise)).then(v => { __settled = 'resolved:' + v }, e => { __settled = 'rejected:' + e });
    """)
    _ = await harness.waitForAsync(timeout: timeout) { harness.evalTypeOf("__settled") == "string" }
    return harness.evalString("__settled")
}

/// Integration tests for hs.spaces.
///
/// Everything here reads the real Spaces configuration of the machine running the tests, so
/// assertions are about invariants that hold for any configuration rather than specific
/// values. Adding, removing, and switching spaces visibly drives Mission Control, so they're
/// only exercised with invalid input unless HS_TEST_MISSION_CONTROL is set (see
/// canDriveMissionControl()). `moveWindowToSpace()` is only exercised with a window the test
/// creates, and only onto the space it's already on.
@Suite("hs.spaces tests", .serialized)
struct HSSpacesTests {

    init() async {
        await JSTestHarness.drainMainActorQueue()
    }

    // MARK: - API structure

    @Suite("hs.spaces API structure tests")
    struct HSSpacesStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            return harness
        }

        @Test("_watcherEmitter is initialized by hs.spaces.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.spaces._watcherEmitter !== null && hs.spaces._watcherEmitter !== undefined"
            )
        }

        @Test("on/off/once are installed by hs.spaces.js")
        func testWatcherFunctions() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.spaces.on") == "function")
            #expect(harness.evalTypeOf("hs.spaces.off") == "function")
            #expect(harness.evalTypeOf("hs.spaces.once") == "function")
        }

        @Test("on() rejects unknown event names")
        func testOnRejectsUnknownEvent() {
            let harness = makeHarness()
            harness.eval("hs.spaces.on('bogus', () => {})")
            harness.expectException()
        }

        @Test("on() and off() a change listener without throwing")
        func testOnOffChange() {
            let harness = makeHarness()
            harness.eval("""
                var listener = () => {};
                hs.spaces.on('change', listener);
                hs.spaces.off('change', listener);
            """)
            #expect(!harness.hasException)
        }

        @Test("isAvailable() matches whether SkyLight loaded")
        func testIsAvailable() {
            #expect(makeHarness().evalBool("hs.spaces.isAvailable()") == isSkyLightAvailable())
        }

        @Test("screensHaveSeparateSpaces() matches NSScreen")
        func testScreensHaveSeparateSpaces() {
            #expect(makeHarness().evalBool("hs.spaces.screensHaveSeparateSpaces()") == NSScreen.screensHaveSeparateSpaces)
        }
    }

    // MARK: - Space queries

    @Suite("hs.spaces query tests",
           .disabled(if: !isSkyLightAvailable(), "SkyLight is unavailable"))
    struct HSSpacesQueryTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.loadModule(HSScreenModule.self, as: "screen")
            return harness
        }

        /// Every space ID allSpaces() reports, flattened
        private let allIDs = "Object.values(hs.spaces.allSpaces()).flat()"

        @Test("focusedSpace() is a known space")
        func testFocusedSpaceIsKnown() {
            let harness = makeHarness()
            harness.expectTrue("hs.spaces.focusedSpace() > 0")
            harness.expectTrue("\(allIDs).includes(hs.spaces.focusedSpace())")
        }

        @Test("allSpaces() has an entry for every screen")
        func testAllSpacesCoversScreens() {
            let harness = makeHarness()
            harness.eval("var all = hs.spaces.allSpaces()")
            harness.expectTrue("Object.keys(all).length >= 1")
            harness.expectTrue("Object.values(all).every(ids => Array.isArray(ids) && ids.length >= 1)")
            if NSScreen.screensHaveSeparateSpaces {
                harness.expectTrue("hs.screen.all().every(s => Array.isArray(all[s.uuid]))")
            }
            #expect(!harness.hasException)
        }

        @Test("activeSpaces() picks one space from each display")
        func testActiveSpacesAreOnTheirDisplay() {
            let harness = makeHarness()
            harness.eval("""
                var all = hs.spaces.allSpaces();
                var active = hs.spaces.activeSpaces();
            """)
            harness.expectTrue("Object.keys(active).length === Object.keys(all).length")
            harness.expectTrue("Object.keys(active).every(uuid => all[uuid].includes(active[uuid]))")
            #expect(!harness.hasException)
        }

        @Test("spacesForScreen() defaults to the main screen")
        func testSpacesForScreenDefault() {
            let harness = makeHarness()
            harness.expectTrue("""
                JSON.stringify(hs.spaces.spacesForScreen()) === JSON.stringify(hs.spaces.spacesForScreen(hs.screen.main()))
            """)
            harness.expectTrue("hs.spaces.spacesForScreen().length >= 1")
        }

        @Test("activeSpaceOnScreen() is one of that screen's spaces")
        func testActiveSpaceOnScreen() {
            let harness = makeHarness()
            harness.expectTrue("""
                hs.screen.all().every(s => hs.spaces.spacesForScreen(s).includes(hs.spaces.activeSpaceOnScreen(s)))
            """)
        }

        @Test("spaceType() of every space is a known kind")
        func testSpaceTypes() {
            let harness = makeHarness()
            harness.expectTrue("""
                \(allIDs).every(id => ["user", "fullscreen", "system", "unknown"].includes(hs.spaces.spaceType(id)))
            """)
        }

        @Test("spaceScreen() of the active space on each screen is that screen")
        func testSpaceScreen() {
            let harness = makeHarness()
            harness.expectTrue("""
                hs.screen.all().every(s => {
                    const screen = hs.spaces.spaceScreen(hs.spaces.activeSpaceOnScreen(s));
                    return screen !== undefined && (screen.uuid === s.uuid || !hs.spaces.screensHaveSeparateSpaces());
                })
            """)
        }

        @Test("windowsForSpace() returns an array of window IDs")
        func testWindowsForSpace() {
            let harness = makeHarness()
            harness.eval("var ids = hs.spaces.windowsForSpace(hs.spaces.focusedSpace())")
            harness.expectTrue("Array.isArray(ids)")
            harness.expectTrue("ids.every(id => typeof id === 'number' && id > 0)")
            #expect(!harness.hasException)
        }

        @Test("Unknown space IDs are rejected without throwing",
              arguments: ["0", "-1", "999999999"])
        func testUnknownSpaces(id: String) {
            let harness = makeHarness()
            harness.expectTrue("hs.spaces.spaceType(\(id)) === undefined")
            harness.expectTrue("hs.spaces.spaceScreen(\(id)) === undefined")
            harness.expectTrue("hs.spaces.windowsForSpace(\(id)).length === 0")
            #expect(!harness.hasException)
        }

        @Test("gotoSpace() and removeSpace() reject unknown space IDs",
              arguments: ["gotoSpace", "removeSpace"])
        func testMissionControlRejectsUnknownSpaces(function: String) async {
            let harness = makeHarness()
            harness.expectTrue("hs.spaces.\(function)(999999999) instanceof Promise")
            let result = await settle("hs.spaces.\(function)(999999999)", in: harness)
            #expect(result?.hasPrefix("rejected:hs.spaces.\(function)():") == true, "got \(result ?? "nothing")")
        }
    }

    // MARK: - Windows

    @Suite("hs.spaces window tests",
           .serialized,
           .disabled(if: !canInspectOwnWindows(), "SkyLight unavailable or Accessibility not granted"))
    struct HSSpacesWindowTests {
        /// Shows a window owned by the test process and exposes it to JS as `testWin`
        private func withTestWindow(_ body: (JSTestHarness) -> Void) throws {
            let title = "hs.spaces test \(UUID().uuidString)"
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            window.orderFrontRegardless()
            defer { window.close() }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

            let app = try #require(Application(NSRunningApplication.current))
            let elements: [UIElement] = (try? app.windows()) ?? []
            let element = try #require(elements.first { (try? $0.attribute(.title) as String?) == title })

            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.context.setObject(HSWindow(element: element, app: .current), forKeyedSubscript: "testWin" as NSString)
            body(harness)
        }

        @Test("windowSpaces() and windowsForSpace() agree about a window")
        func testWindowSpaces() throws {
            try withTestWindow { harness in
                harness.eval("var spaces = hs.spaces.windowSpaces(testWin)")
                harness.expectTrue("spaces.length >= 1")
                harness.expectTrue("hs.spaces.windowsForSpace(spaces[0]).includes(testWin.id)")
                #expect(!harness.hasException)
            }
        }

        @Test("moveWindowToSpace() onto the window's own space succeeds")
        func testMoveToCurrentSpace() throws {
            try withTestWindow { harness in
                #expect(harness.evalBool("hs.spaces.moveWindowToSpace(testWin, hs.spaces.windowSpaces(testWin)[0])") == true)
                #expect(!harness.hasException)
            }
        }

        @Test("moveWindowToSpace() rejects an unknown space")
        func testMoveToUnknownSpace() throws {
            try withTestWindow { harness in
                #expect(harness.evalBool("hs.spaces.moveWindowToSpace(testWin, 999999999)") == false)
                #expect(!harness.hasException)
            }
        }
    }

    // MARK: - Mission Control

    @Suite("hs.spaces Mission Control tests",
           .serialized,
           .disabled(if: !canDriveMissionControl(), "Set TEST_RUNNER_HS_TEST_MISSION_CONTROL=1 to run (takes over the screen)"))
    struct HSSpacesMissionControlTests {
        @Test("A desktop can be added, switched to and back, and removed")
        func testAddGotoRemove() async throws {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.loadModule(HSScreenModule.self, as: "screen")
            harness.eval("""
                var screen = hs.screen.all()[hs.screen.all().length - 1];
                var original = hs.spaces.activeSpaceOnScreen(screen);
                var before = hs.spaces.spacesForScreen(screen);
            """)

            let added = try #require(await settle("hs.spaces.addSpaceToScreen(screen)", in: harness))
            try #require(added.hasPrefix("resolved:"), "got \(added)")
            harness.eval("var added = \(added.dropFirst("resolved:".count))")
            harness.expectTrue("!before.includes(added)")
            harness.expectTrue("hs.spaces.spacesForScreen(screen).includes(added)")
            #expect(harness.evalString("hs.spaces.spaceType(added)") == "user")

            #expect(await settle("hs.spaces.gotoSpace(added)", in: harness) == "resolved:undefined")
            harness.expectTrue("hs.spaces.activeSpaceOnScreen(screen) === added")

            #expect(await settle("hs.spaces.gotoSpace(original)", in: harness) == "resolved:undefined")
            harness.expectTrue("hs.spaces.activeSpaceOnScreen(screen) === original")

            #expect(await settle("hs.spaces.removeSpace(added)", in: harness) == "resolved:undefined")
            harness.expectTrue("JSON.stringify(hs.spaces.spacesForScreen(screen)) === JSON.stringify(before)")
            #expect(!harness.hasException)
        }

        @Test("Mission Control operations queue rather than overlap")
        func testOperationsQueue() async throws {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.loadModule(HSScreenModule.self, as: "screen")
            harness.eval("var screen = hs.screen.all()[hs.screen.all().length - 1]; var before = hs.spaces.spacesForScreen(screen);")

            // Fire both adds without waiting, then both removes
            let both = "Promise.all([hs.spaces.addSpaceToScreen(screen), hs.spaces.addSpaceToScreen(screen)])"
            let added = try #require(await settle(both, in: harness, timeout: 20))
            try #require(added.hasPrefix("resolved:"), "got \(added)")
            harness.eval("var added = [\(added.dropFirst("resolved:".count))]")
            harness.expectTrue("added.length === 2 && added[0] !== added[1]")

            #expect(await settle("Promise.all(added.map(id => hs.spaces.removeSpace(id)))", in: harness, timeout: 20) == "resolved:,")
            harness.expectTrue("JSON.stringify(hs.spaces.spacesForScreen(screen)) === JSON.stringify(before)")
            #expect(!harness.hasException)
        }
    }
}
