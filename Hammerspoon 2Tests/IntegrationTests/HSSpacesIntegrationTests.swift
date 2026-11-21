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
/// screen for a few seconds, so on a real Mac they only run when asked for explicitly:
/// `TEST_RUNNER_HS_TEST_MISSION_CONTROL=1 xcodebuild test ...`. They always run in an hs2vm VM,
/// where there's nobody's screen to take over.
private nonisolated func canDriveMissionControl() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return canInspectOwnWindows() && (environment["HS_TEST_MISSION_CONTROL"] != nil || environment["HS2_VM"] != nil)
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

/// Runs `body`, then (whether it passed or not) waits for any Mission Control work it left
/// queued, switches each display back to the space it started on, removes any desktops it added
/// and closes Mission Control, so a failure can't leave the machine changed for later tests.
/// `harness` must have hs.spaces loaded.
@MainActor
private func withSpacesRestored(in harness: JSTestHarness, _ body: () async throws -> Void) async throws {
    harness.eval("""
        var __startSpaces = hs.spaces.allSpaces().map(s => s.id);
        var __startCurrent = hs.spaces.displays().map(d => d.currentSpace.id);
    """)
    let result: Result<Void, any Error>
    do {
        try await body()
        result = .success(())
    } catch {
        result = .failure(error)
    }

    // Queued behind anything still running, so this waits for it to finish
    _ = await settle("hs.spaces.closeMissionControl()", in: harness, timeout: 60)
    harness.eval("""
        var __current = hs.spaces.displays().map(d => d.currentSpace.id);
        var __back = __startCurrent.filter(id => !__current.includes(id));
        var __added = hs.spaces.allSpaces().filter(s => !__startSpaces.includes(s.id));
    """)
    let restore = """
        Promise.allSettled([...__back.map(id => hs.spaces.spaceForID(id).goto()), ...__added.map(s => s.remove())])
    """
    _ = await settle(restore, in: harness, timeout: 60)
    _ = await settle("hs.spaces.closeMissionControl()", in: harness, timeout: 20)
    try result.get()
}

/// Integration tests for hs.spaces.
///
/// Everything here reads the real Spaces configuration of the machine running the tests, so
/// assertions are about invariants that hold for any configuration rather than specific
/// values. Adding, removing, and switching spaces visibly drives Mission Control, so they're
/// only exercised with invalid input unless HS_TEST_MISSION_CONTROL is set (see
/// canDriveMissionControl()).
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

    // MARK: - Displays and spaces

    @Suite("hs.spaces query tests",
           .disabled(if: !isSkyLightAvailable(), "SkyLight is unavailable"))
    struct HSSpacesQueryTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.loadModule(HSScreenModule.self, as: "screen")
            return harness
        }

        @Test("displays() each have spaces, one of which is current")
        func testDisplays() {
            let harness = makeHarness()
            harness.eval("var displays = hs.spaces.displays()")
            harness.expectTrue("displays.length >= 1")
            harness.expectTrue("displays.every(d => d.spaces.length >= 1)")
            harness.expectTrue("displays.every(d => d.spaces.filter(s => s.isCurrent).length === 1)")
            harness.expectTrue("displays.every(d => d.spaces.some(s => s.id === d.currentSpace.id))")
            #expect(!harness.hasException)
        }

        @Test("With separate spaces, there's one display per screen, and each is its screen")
        func testDisplaysMatchScreens() throws {
            try #require(NSScreen.screensHaveSeparateSpaces)
            let harness = makeHarness()
            #expect(harness.evalString("hs.spaces.displays().map(d => d.uuid).sort().join()")
                    == harness.evalString("hs.screen.all().map(s => s.uuid).sort().join()"))
            harness.expectTrue("hs.spaces.displays().every(d => d.screen.uuid === d.uuid)")
            #expect(!harness.hasException)
        }

        @Test("displayForScreen() finds each screen's display")
        func testDisplayForScreen() {
            let harness = makeHarness()
            harness.expectTrue("""
                hs.screen.all().every(s => {
                    const d = hs.spaces.displayForScreen(s);
                    return d !== null && (d.uuid === s.uuid || !hs.spaces.screensHaveSeparateSpaces());
                })
            """)
            #expect(!harness.hasException)
        }

        @Test("allSpaces() is every display's spaces, in order")
        func testAllSpaces() {
            let harness = makeHarness()
            #expect(harness.evalString("hs.spaces.allSpaces().map(s => s.id).join()")
                    == harness.evalString("hs.spaces.displays().flatMap(d => d.spaces).map(s => s.id).join()"))
        }

        @Test("Every space knows its display, type and UUID, and can be looked up again")
        func testSpaceProperties() {
            let harness = makeHarness()
            harness.eval("var spaces = hs.spaces.allSpaces()")
            harness.expectTrue("spaces.every(s => s.exists)")
            harness.expectTrue("spaces.every(s => ['desktop', 'fullscreen', 'unknown'].includes(s.type))")
            harness.expectTrue("spaces.every(s => s.display.spaces.some(o => o.id === s.id))")
            // A new account's first desktop has no UUID
            harness.expectTrue("spaces.every(s => s.uuid === null || /^[0-9A-F-]{36}$/i.test(s.uuid))")
            harness.expectTrue("spaces.every(s => hs.spaces.spaceForID(s.id).id === s.id)")
            harness.expectTrue("spaces.filter(s => s.uuid).every(s => hs.spaces.spaceForUUID(s.uuid).id === s.id)")
            harness.expectTrue("spaces.filter(s => s.uuid).every(s => hs.spaces.spaceForUUID(s.uuid.toLowerCase()).id === s.id)")
            #expect(!harness.hasException)
        }

        @Test("Desktops are numbered from 1 across all displays, and fullscreen spaces aren't numbered")
        func testDesktopNumbers() {
            let harness = makeHarness()
            harness.eval("var spaces = hs.spaces.allSpaces()")
            harness.expectTrue("""
                JSON.stringify(spaces.filter(s => s.type === 'desktop').map(s => s.desktopNumber))
                    === JSON.stringify(spaces.filter(s => s.type === 'desktop').map((s, i) => i + 1))
            """)
            harness.expectTrue("spaces.filter(s => s.type !== 'desktop').every(s => s.desktopNumber === null)")
            #expect(!harness.hasException)
        }

        @Test("focusedSpace() is focused and current on its display")
        func testFocusedSpace() {
            let harness = makeHarness()
            harness.eval("var focused = hs.spaces.focusedSpace()")
            harness.expectTrue("focused.isFocused && focused.isCurrent")
            harness.expectTrue("focused.display.currentSpace.id === focused.id")
            #expect(harness.evalInt("hs.spaces.allSpaces().filter(s => s.isFocused).length") == 1)
            #expect(!harness.hasException)
        }

        @Test("windowIDs() returns an array of window IDs")
        func testWindowIDs() {
            let harness = makeHarness()
            harness.eval("var ids = hs.spaces.focusedSpace().windowIDs()")
            harness.expectTrue("Array.isArray(ids)")
            harness.expectTrue("ids.every(id => typeof id === 'number' && id > 0)")
            #expect(!harness.hasException)
        }

        @Test("toJSON() describes spaces and displays")
        func testToJSON() {
            let harness = makeHarness()
            harness.eval("""
                var space = JSON.parse(JSON.stringify(hs.spaces.focusedSpace()));
                var display = JSON.parse(JSON.stringify(hs.spaces.focusedSpace().display));
            """)
            harness.expectTrue("space.id === hs.spaces.focusedSpace().id && space.isFocused === true")
            harness.expectTrue("space.display === display.uuid")
            harness.expectTrue("display.spaces.includes(space.id) && display.currentSpace === space.id")
            #expect(!harness.hasException)
        }

        @Test("Unknown spaces and windows aren't found",
              arguments: ["0", "-1", "999999999"])
        func testUnknownIDs(id: String) {
            let harness = makeHarness()
            harness.expectTrue("hs.spaces.spaceForID(\(id)) === null")
            harness.expectTrue("hs.spaces.spacesForWindowID(\(id)).length === 0")
            #expect(!harness.hasException)
        }

        @Test("spaceForUUID() doesn't find unknown UUIDs")
        func testUnknownUUID() {
            let harness = makeHarness()
            harness.expectTrue("hs.spaces.spaceForUUID('00000000-0000-0000-0000-000000000000') === null")
            harness.expectTrue("hs.spaces.spaceForUUID('') === null")
            #expect(!harness.hasException)
        }

        @Test("Moving a window that doesn't exist rejects")
        func testMoveUnknownWindow() async {
            let harness = makeHarness()
            let result = await settle("hs.spaces.focusedSpace().moveWindowID(999999999)", in: harness)
            #expect(result?.hasPrefix("rejected:HSSpace.moveWindowID(): ") == true, "got \(result ?? "nothing")")
        }
    }

    // MARK: - Windows

    @Suite("hs.spaces window tests",
           .serialized,
           .disabled(if: !canInspectOwnWindows(), "SkyLight unavailable or Accessibility not granted"))
    struct HSSpacesWindowTests {
        /// Shows a window owned by the test process and exposes it to JS as `testWin`
        private func withTestWindow(_ body: (JSTestHarness) async -> Void) async throws {
            let title = "hs.spaces test \(UUID().uuidString)"
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            window.orderFrontRegardless()
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))

            let app = try #require(Application(NSRunningApplication.current))
            let elements: [UIElement] = (try? app.windows()) ?? []
            let element = try #require(elements.first { (try? $0.attribute(.title) as String?) == title })

            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.context.setObject(HSWindow(element: element, app: .current), forKeyedSubscript: "testWin" as NSString)
            await body(harness)
        }

        @Test("spacesForWindow() and windowIDs() agree about a window")
        func testWindowSpaces() async throws {
            try await withTestWindow { harness in
                harness.eval("var spaces = hs.spaces.spacesForWindow(testWin)")
                harness.expectTrue("spaces.length === 1")
                harness.expectTrue("spaces[0].windowIDs().includes(testWin.id)")
                #expect(harness.evalString("hs.spaces.spacesForWindowID(testWin.id).map(s => s.id).join()")
                        == harness.evalString("spaces.map(s => s.id).join()"))
                #expect(!harness.hasException)
            }
        }

        @Test("Moving a window to the space it's on resolves straight away")
        func testMoveToSameSpace() async throws {
            try await withTestWindow { harness in
                let result = await settle("hs.spaces.spacesForWindow(testWin)[0].moveWindow(testWin)", in: harness)
                #expect(result == "resolved:undefined")
            }
        }
    }

    // MARK: - Mission Control

    @Suite("hs.spaces Mission Control tests",
           .serialized,
           .disabled(if: !canDriveMissionControl(), "Set TEST_RUNNER_HS_TEST_MISSION_CONTROL=1 to run (takes over the screen)"))
    struct HSSpacesMissionControlTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            return harness
        }

        /// Adds a desktop to the last display and stores it in JS as `added`, with the display as
        /// `display`, its space IDs before as `before`, and the space it was showing as `original`
        private func addDesktop(in harness: JSTestHarness) async throws {
            harness.eval("""
                var display = hs.spaces.displays()[hs.spaces.displays().length - 1];
                var original = display.currentSpace;
                var before = display.spaces.map(s => s.id);
                var added = null;
            """)
            let result = try #require(await settle("display.addSpace().then(s => { added = s; return s.id })", in: harness))
            try #require(result.hasPrefix("resolved:"), "got \(result)")
        }

        @Test("A desktop can be added, switched to and back, and removed")
        func testAddGotoRemove() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                try await addDesktop(in: harness)
                harness.expectTrue("!before.includes(added.id)")
                harness.expectTrue("display.spaces[display.spaces.length - 1].id === added.id")
                #expect(harness.evalString("added.type") == "desktop")
                harness.expectTrue("added.display.uuid === display.uuid")

                #expect(await settle("added.goto()", in: harness) == "resolved:undefined")
                harness.expectTrue("added.isCurrent && display.currentSpace.id === added.id")

                #expect(await settle("original.goto()", in: harness) == "resolved:undefined")
                harness.expectTrue("original.isCurrent && !added.isCurrent")

                #expect(await settle("added.remove()", in: harness) == "resolved:undefined")
                harness.expectTrue("!added.exists && added.type === null && added.display === null")
                #expect(harness.evalString("display.spaces.map(s => s.id).join()") == harness.evalString("before.join()"))
                let again = await settle("added.goto()", in: harness)
                #expect(again?.hasPrefix("rejected:HSSpace.goto(): ") == true, "got \(again ?? "nothing")")
                #expect(!harness.hasException)
            }
        }

        @Test("The change event says which display switched, and from and to which space")
        func testChangeEvent() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                try await addDesktop(in: harness)
                harness.eval("""
                    var changes = [];
                    hs.spaces.on('change', ({ display, from, to }) => changes.push([display.uuid, from && from.id, to.id]));
                """)
                #expect(await settle("added.goto()", in: harness) == "resolved:undefined")
                _ = await harness.waitForAsync(timeout: 2) { harness.evalInt("changes.length") ?? 0 > 0 }
                #expect(harness.evalString("JSON.stringify(changes)")
                        == harness.evalString("JSON.stringify([[display.uuid, original.id, added.id]])"))
                #expect(!harness.hasException)
            }
        }

        @Test("The desktop a display is showing can't be removed")
        func testRemoveCurrent() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                try await addDesktop(in: harness)
                #expect(await settle("added.goto()", in: harness) == "resolved:undefined")
                let result = await settle("added.remove()", in: harness)
                #expect(result?.hasPrefix("rejected:HSSpace.remove(): ") == true, "got \(result ?? "nothing")")
                harness.expectTrue("added.exists")
            }
        }

        @Test("Another app's window can be moved to another desktop")
        func testMoveOtherAppsWindow() async throws {
            let app = try #require(await TestAppControl.launch(detail: "hs.spaces moves this window to another desktop"))
            defer { app.terminate() }
            let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            let window = try #require(windowList.first {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
            }?[kCGWindowNumber as String] as? Int)

            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("var win = \(window)")
                try await addDesktop(in: harness)
                harness.expectTrue("hs.spaces.spacesForWindowID(win)[0].id !== added.id")

                #expect(await settle("added.moveWindowID(win)", in: harness) == "resolved:undefined")
                #expect(harness.evalString("hs.spaces.spacesForWindowID(win).map(s => s.id).join()") == harness.evalString("String(added.id)"))
                harness.expectTrue("added.windowIDs().includes(win)")
                harness.expectTrue("!original.windowIDs().includes(win)")

                #expect(await settle("original.moveWindowID(win)", in: harness) == "resolved:undefined")
                harness.expectTrue("original.windowIDs().includes(win)")
                #expect(!harness.hasException)
            }
        }

        @Test("A fullscreen space is reported as one, and windows can't be moved into or out of it")
        func testFullscreenSpace() async throws {
            let app = try #require(await TestAppControl.launch(detail: "hs.spaces checks this app's fullscreen space"))
            defer { app.terminate() }
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("var fullscreen = null; var desktop = hs.spaces.focusedSpace();")
                TestAppControl.openFullScreenWindow(in: app.processIdentifier)
                let appeared = await harness.waitForAsync(timeout: 5) {
                    harness.evalBool("(fullscreen = hs.spaces.allSpaces().find(s => s.type === 'fullscreen' && s.windowIDs().length > 0) || null) !== null") == true
                }
                try #require(appeared, "the test app's fullscreen space didn't appear")
                harness.expectTrue("fullscreen.desktopNumber === null")
                harness.eval("var win = fullscreen.windowIDs()[0]")

                let into = await settle("fullscreen.moveWindowID(win)", in: harness)
                #expect(into?.hasPrefix("rejected:HSSpace.moveWindowID(): windows can only be moved to a desktop") == true,
                        "got \(into ?? "nothing")")
                let outOf = await settle("desktop.moveWindowID(win)", in: harness)
                #expect(outOf?.hasPrefix("rejected:HSSpace.moveWindowID(): ") == true && outOf?.hasSuffix("is in a fullscreen space, so it can't be moved") == true,
                        "got \(outOf ?? "nothing")")
                #expect(!harness.hasException)

                // Quitting the app removes its space; wait for that so later tests see a normal setup
                app.terminate()
                _ = await harness.waitForAsync(timeout: 5) { harness.evalBool("fullscreen.exists") == false }
            }
        }

        @Test("missionControlNames() names every space, and agrees with desktopNumber")
        func testNames() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                // At least two desktops, so Mission Control numbers them
                try await addDesktop(in: harness)
                let result = try #require(await settle("hs.spaces.missionControlNames().then(n => JSON.stringify(n))", in: harness))
                try #require(result.hasPrefix("resolved:"), "got \(result)")
                harness.eval("var names = \(result.dropFirst("resolved:".count)); var all = hs.spaces.allSpaces();")
                harness.expectTrue("all.every(s => typeof names[s.id] === 'string' && names[s.id].length > 0)")
                // Mission Control's own "Desktop N" titles end with the same numbers desktopNumber computes
                harness.eval("var desktops = all.filter(s => s.type === 'desktop')")
                #expect(harness.evalString("desktops.map(s => names[s.id].split(' ').pop()).join()")
                        == harness.evalString("desktops.map(s => s.desktopNumber).join()"),
                        "names: \(result)")
                #expect(await isMissionControlClosed())
                #expect(!harness.hasException)
            }
        }

        @Test("openMissionControl() keeps Mission Control open across other operations until closeMissionControl()")
        func testOpenAndClose() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                #expect(await settle("hs.spaces.openMissionControl()", in: harness) == "resolved:undefined")
                #expect(HSMissionControl.isOpen)
                #expect(await settle("hs.spaces.missionControlNames()", in: harness)?.hasPrefix("resolved:") == true)
                #expect(HSMissionControl.isOpen)
                #expect(await settle("hs.spaces.closeMissionControl()", in: harness) == "resolved:undefined")
                #expect(await isMissionControlClosed())
                #expect(!harness.hasException)
            }
        }

        @Test("toggleMissionControl() opens and closes Mission Control")
        func testToggleMissionControl() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("hs.spaces.toggleMissionControl()")
                let opened = (try? await HSMissionControl.waitUntil("not open") { HSMissionControl.isOpen }) != nil
                harness.eval("hs.spaces.toggleMissionControl()")
                #expect(opened)
                #expect(await isMissionControlClosed())
                #expect(!harness.hasException)
            }
        }

        /// Waits for Mission Control to finish closing
        private func isMissionControlClosed() async -> Bool {
            (try? await HSMissionControl.waitUntil("not closed") { HSMissionControl.isClosed }) != nil
        }

        @Test("Mission Control operations queue rather than overlap")
        func testOperationsQueue() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("var display = hs.spaces.displays()[0]; var before = display.spaces.map(s => s.id); var added = [];")

                // Fire both adds without waiting, then both removes
                let both = "Promise.all([display.addSpace(), display.addSpace()]).then(s => { added = s; return s.length })"
                #expect(await settle(both, in: harness, timeout: 20) == "resolved:2")
                harness.expectTrue("added[0].id !== added[1].id")

                #expect(await settle("Promise.all(added.map(s => s.remove()))", in: harness, timeout: 20) == "resolved:,")
                #expect(harness.evalString("display.spaces.map(s => s.id).join()") == harness.evalString("before.join()"))
                #expect(!harness.hasException)
            }
        }
    }

    // MARK: - Memory

    @Test("Spaces and displays are released after shutdown")
    func testObjectsDoNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSSpacesModule.self, as: "spaces")
            harness.eval("""
                var space = hs.spaces.focusedSpace();
                var display = hs.spaces.displays()[0];
                var spaces = display ? display.spaces : [];
                hs.spaces.on('change', () => {});
            """)
            if let space = harness.evalValue("space")?.toObjectOf(HSSpace.self) as? HSSpace {
                tracker.track(space)
            }
            if let display = harness.evalValue("display")?.toObjectOf(HSSpacesDisplay.self) as? HSSpacesDisplay {
                tracker.track(display)
            }
            harness.eval("space = null; display = null; spaces = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
