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
/// queued, switches each screen back to the space it started on, removes any desktops it added
/// and closes Mission Control, so a failure can't leave the machine changed for later tests.
/// `harness` must have hs.screen loaded.
@MainActor
private func withSpacesRestored(in harness: JSTestHarness, _ body: () async throws -> Void) async throws {
    harness.eval("""
        var __startSpaces = hs.screen.allSpaces().map(s => s.id);
        var __startCurrent = hs.screen.allSpaces().filter(s => s.isCurrent).map(s => s.id);
    """)
    let result: Result<Void, any Error>
    do {
        try await body()
        result = .success(())
    } catch {
        result = .failure(error)
    }

    // Queued behind anything still running, so this waits for it to finish
    _ = await settle("hs.screen.closeMissionControl()", in: harness, timeout: 60)
    harness.eval("""
        var __current = hs.screen.allSpaces().filter(s => s.isCurrent).map(s => s.id);
        var __back = __startCurrent.filter(id => !__current.includes(id));
        var __added = hs.screen.allSpaces().filter(s => !__startSpaces.includes(s.id));
    """)
    let restore = """
        Promise.allSettled([...__back.map(id => hs.screen.spaceForID(id).goto()), ...__added.map(s => s.remove())])
    """
    _ = await settle(restore, in: harness, timeout: 60)
    _ = await settle("hs.screen.closeMissionControl()", in: harness, timeout: 20)
    try result.get()
}

/// Integration tests for Spaces, which hs.screen, hs.window and their HSScreen, HSWindow and
/// HSSpace objects share.
///
/// Everything here reads the real Spaces configuration of the machine running the tests, so
/// assertions are about invariants that hold for any configuration rather than specific
/// values. Adding, removing, and switching spaces visibly drives Mission Control, so they're
/// only exercised with invalid input unless HS_TEST_MISSION_CONTROL is set (see
/// canDriveMissionControl()).
@Suite("Spaces tests", .serialized)
struct HSSpacesTests {

    init() async {
        await JSTestHarness.drainMainActorQueue()
    }

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSScreenModule.self, as: "screen")
        harness.loadModule(HSWindowModule.self, as: "window")
        return harness
    }

    // MARK: - API structure

    @Suite("Spaces API structure tests")
    struct HSSpacesStructureTests {
        @Test("on() and off() a spaceChange listener without throwing")
        func testOnOffSpaceChange() {
            let harness = makeHarness()
            harness.eval("""
                var listener = () => {};
                hs.screen.on('spaceChange', listener);
                hs.screen.off('spaceChange', listener);
            """)
            #expect(!harness.hasException)
        }

        @Test("spacesAvailable() matches whether SkyLight loaded")
        func testSpacesAvailable() {
            #expect(makeHarness().evalBool("hs.screen.spacesAvailable()") == isSkyLightAvailable())
        }

        @Test("screensHaveSeparateSpaces() matches NSScreen")
        func testScreensHaveSeparateSpaces() {
            #expect(makeHarness().evalBool("hs.screen.screensHaveSeparateSpaces()") == NSScreen.screensHaveSeparateSpaces)
        }
    }

    // MARK: - Screens and spaces

    @Suite("Spaces query tests",
           .disabled(if: !isSkyLightAvailable(), "SkyLight is unavailable"))
    struct HSSpacesQueryTests {
        @Test("Every screen has spaces, one of which is current")
        func testScreenSpaces() {
            let harness = makeHarness()
            harness.eval("var screens = hs.screen.all()")
            harness.expectTrue("screens.every(s => s.spaces.length >= 1)")
            harness.expectTrue("screens.every(s => s.spaces.filter(o => o.isCurrent).length === 1)")
            harness.expectTrue("screens.every(s => s.spaces.some(o => o.id === s.currentSpace.id))")
            #expect(!harness.hasException)
        }

        @Test("With separate spaces, allSpaces() is every screen's spaces, each on its own screen")
        func testAllSpacesAreScreensSpaces() throws {
            try #require(NSScreen.screensHaveSeparateSpaces)
            let harness = makeHarness()
            #expect(harness.evalString("hs.screen.allSpaces().map(s => s.id).sort().join()")
                    == harness.evalString("hs.screen.all().flatMap(s => s.spaces).map(s => s.id).sort().join()"))
            harness.expectTrue("hs.screen.all().every(s => s.spaces.every(o => o.screen.uuid === s.uuid))")
            #expect(!harness.hasException)
        }

        @Test("Every space knows its screen, type and UUID, and can be looked up again")
        func testSpaceProperties() {
            let harness = makeHarness()
            harness.eval("var spaces = hs.screen.allSpaces()")
            harness.expectTrue("spaces.every(s => s.exists)")
            harness.expectTrue("spaces.every(s => ['desktop', 'fullscreen', 'unknown'].includes(s.type))")
            harness.expectTrue("spaces.every(s => s.screen.spaces.some(o => o.id === s.id))")
            // A new account's first desktop has no UUID
            harness.expectTrue("spaces.every(s => s.uuid === null || /^[0-9A-F-]{36}$/i.test(s.uuid))")
            harness.expectTrue("spaces.every(s => hs.screen.spaceForID(s.id).id === s.id)")
            harness.expectTrue("spaces.filter(s => s.uuid).every(s => hs.screen.spaceForUUID(s.uuid).id === s.id)")
            harness.expectTrue("spaces.filter(s => s.uuid).every(s => hs.screen.spaceForUUID(s.uuid.toLowerCase()).id === s.id)")
            #expect(!harness.hasException)
        }

        @Test("Desktops are numbered from 1 across all screens, and fullscreen spaces aren't numbered")
        func testDesktopNumbers() {
            let harness = makeHarness()
            harness.eval("var spaces = hs.screen.allSpaces()")
            harness.expectTrue("""
                JSON.stringify(spaces.filter(s => s.type === 'desktop').map(s => s.desktopNumber))
                    === JSON.stringify(spaces.filter(s => s.type === 'desktop').map((s, i) => i + 1))
            """)
            harness.expectTrue("spaces.filter(s => s.type !== 'desktop').every(s => s.desktopNumber === null)")
            #expect(!harness.hasException)
        }

        @Test("focusedSpace() is focused and current on its screen")
        func testFocusedSpace() {
            let harness = makeHarness()
            harness.eval("var focused = hs.screen.focusedSpace()")
            harness.expectTrue("focused.isFocused && focused.isCurrent")
            harness.expectTrue("focused.screen.currentSpace.id === focused.id")
            #expect(harness.evalInt("hs.screen.allSpaces().filter(s => s.isFocused).length") == 1)
            #expect(!harness.hasException)
        }

        @Test("windowIDs() returns an array of window IDs")
        func testWindowIDs() {
            let harness = makeHarness()
            harness.eval("var ids = hs.screen.focusedSpace().windowIDs()")
            harness.expectTrue("Array.isArray(ids)")
            harness.expectTrue("ids.every(id => typeof id === 'number' && id > 0)")
            #expect(!harness.hasException)
        }

        @Test("toJSON() describes a space")
        func testToJSON() {
            let harness = makeHarness()
            harness.eval("var focused = hs.screen.focusedSpace(); var space = JSON.parse(JSON.stringify(focused));")
            harness.expectTrue("space.id === focused.id && space.isFocused === true")
            harness.expectTrue("space.screen === focused.screen.uuid")
            #expect(!harness.hasException)
        }

        @Test("Unknown spaces and windows aren't found",
              arguments: ["0", "-1", "999999999"])
        func testUnknownIDs(id: String) {
            let harness = makeHarness()
            harness.expectTrue("hs.screen.spaceForID(\(id)) === null")
            harness.expectTrue("hs.window.spacesForID(\(id)).length === 0")
            #expect(!harness.hasException)
        }

        @Test("spaceForUUID() doesn't find unknown UUIDs")
        func testUnknownUUID() {
            let harness = makeHarness()
            harness.expectTrue("hs.screen.spaceForUUID('00000000-0000-0000-0000-000000000000') === null")
            harness.expectTrue("hs.screen.spaceForUUID('') === null")
            #expect(!harness.hasException)
        }

        @Test("Moving a window that doesn't exist rejects")
        func testMoveUnknownWindow() async {
            let harness = makeHarness()
            let result = await settle("hs.window.moveToSpaceForID(999999999, hs.screen.focusedSpace())", in: harness)
            #expect(result?.hasPrefix("rejected:hs.window.moveToSpaceForID(): ") == true, "got \(result ?? "nothing")")
        }
    }

    // MARK: - Windows

    @Suite("Spaces window tests",
           .serialized,
           .disabled(if: !canInspectOwnWindows(), "SkyLight unavailable or Accessibility not granted"))
    struct HSSpacesWindowTests {
        /// Shows a window owned by the test process and exposes it to JS as `testWin`
        private func withTestWindow(_ body: (JSTestHarness) async -> Void) async throws {
            let title = "Spaces test \(UUID().uuidString)"
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

            let harness = makeHarness()
            harness.context.setObject(HSWindow(element: element, app: .current), forKeyedSubscript: "testWin" as NSString)
            await body(harness)
        }

        @Test("A window's spaces and their windowIDs() agree about it")
        func testWindowSpaces() async throws {
            try await withTestWindow { harness in
                harness.eval("var spaces = testWin.spaces")
                harness.expectTrue("spaces.length === 1")
                harness.expectTrue("spaces[0].windowIDs().includes(testWin.id)")
                #expect(harness.evalString("hs.window.spacesForID(testWin.id).map(s => s.id).join()")
                        == harness.evalString("spaces.map(s => s.id).join()"))
                #expect(!harness.hasException)
            }
        }

        @Test("Moving a window to the space it's on resolves straight away")
        func testMoveToSameSpace() async throws {
            try await withTestWindow { harness in
                let result = await settle("testWin.moveToSpace(testWin.spaces[0])", in: harness)
                #expect(result == "resolved:undefined")
            }
        }
    }

    // MARK: - Mission Control

    @Suite("Spaces Mission Control tests",
           .serialized,
           .disabled(if: !canDriveMissionControl(), "Set TEST_RUNNER_HS_TEST_MISSION_CONTROL=1 to run (takes over the screen)"))
    struct HSSpacesMissionControlTests {
        /// Adds a desktop to the last screen and stores it in JS as `added`, with the screen as
        /// `screen`, its space IDs before as `before`, and the space it was showing as `original`
        private func addDesktop(in harness: JSTestHarness) async throws {
            harness.eval("""
                var screen = hs.screen.all()[hs.screen.all().length - 1];
                var original = screen.currentSpace;
                var before = screen.spaces.map(s => s.id);
                var added = null;
            """)
            let result = try #require(await settle("screen.addSpace().then(s => { added = s; return s.id })", in: harness))
            try #require(result.hasPrefix("resolved:"), "got \(result)")
        }

        @Test("A desktop can be added, switched to and back, and removed")
        func testAddGotoRemove() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                try await addDesktop(in: harness)
                harness.expectTrue("!before.includes(added.id)")
                harness.expectTrue("screen.spaces[screen.spaces.length - 1].id === added.id")
                #expect(harness.evalString("added.type") == "desktop")
                harness.expectTrue("added.screen.uuid === screen.uuid")

                #expect(await settle("added.goto()", in: harness) == "resolved:undefined")
                harness.expectTrue("added.isCurrent && screen.currentSpace.id === added.id")

                #expect(await settle("original.goto()", in: harness) == "resolved:undefined")
                harness.expectTrue("original.isCurrent && !added.isCurrent")

                #expect(await settle("added.remove()", in: harness) == "resolved:undefined")
                harness.expectTrue("!added.exists && added.type === null && added.screen === null")
                #expect(harness.evalString("screen.spaces.map(s => s.id).join()") == harness.evalString("before.join()"))
                let again = await settle("added.goto()", in: harness)
                #expect(again?.hasPrefix("rejected:HSSpace.goto(): ") == true, "got \(again ?? "nothing")")
                #expect(!harness.hasException)
            }
        }

        @Test("The spaceChange event says which screen switched, and from and to which space")
        func testChangeEvent() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                try await addDesktop(in: harness)
                harness.eval("""
                    var changes = [];
                    hs.screen.on('spaceChange', ({ screen: s, from, to }) => changes.push([s.uuid, from && from.id, to.id]));
                """)
                #expect(await settle("added.goto()", in: harness) == "resolved:undefined")
                _ = await harness.waitForAsync(timeout: 2) { harness.evalInt("changes.length") ?? 0 > 0 }
                #expect(harness.evalString("JSON.stringify(changes)")
                        == harness.evalString("JSON.stringify([[screen.uuid, original.id, added.id]])"))
                #expect(!harness.hasException)
            }
        }

        @Test("The desktop a screen is showing can't be removed")
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
            let app = try #require(await TestAppControl.launch(detail: "Hammerspoon moves this window to another desktop"))
            defer { app.terminate() }
            let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            let window = try #require(windowList.first {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
            }?[kCGWindowNumber as String] as? Int)

            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("var win = \(window)")
                try await addDesktop(in: harness)
                harness.expectTrue("hs.window.spacesForID(win)[0].id !== added.id")

                #expect(await settle("hs.window.moveToSpaceForID(win, added)", in: harness) == "resolved:undefined")
                #expect(harness.evalString("hs.window.spacesForID(win).map(s => s.id).join()") == harness.evalString("String(added.id)"))
                harness.expectTrue("added.windowIDs().includes(win)")
                harness.expectTrue("!original.windowIDs().includes(win)")

                #expect(await settle("hs.window.moveToSpaceForID(win, original)", in: harness) == "resolved:undefined")
                harness.expectTrue("original.windowIDs().includes(win)")
                #expect(!harness.hasException)
            }
        }

        @Test("A fullscreen space is reported as one, and windows can't be moved into or out of it")
        func testFullscreenSpace() async throws {
            let app = try #require(await TestAppControl.launch(detail: "Hammerspoon checks this app's fullscreen space"))
            defer { app.terminate() }
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("var fullscreen = null; var desktop = hs.screen.focusedSpace();")
                TestAppControl.openFullScreenWindow(in: app.processIdentifier)
                let appeared = await harness.waitForAsync(timeout: 5) {
                    harness.evalBool("(fullscreen = hs.screen.allSpaces().find(s => s.type === 'fullscreen' && s.windowIDs().length > 0) || null) !== null") == true
                }
                try #require(appeared, "the test app's fullscreen space didn't appear")
                harness.expectTrue("fullscreen.desktopNumber === null")
                harness.eval("var win = fullscreen.windowIDs()[0]")

                let into = await settle("hs.window.moveToSpaceForID(win, fullscreen)", in: harness)
                #expect(into?.hasPrefix("rejected:hs.window.moveToSpaceForID(): windows can only be moved to a desktop") == true,
                        "got \(into ?? "nothing")")
                let outOf = await settle("hs.window.moveToSpaceForID(win, desktop)", in: harness)
                #expect(outOf?.hasPrefix("rejected:hs.window.moveToSpaceForID(): ") == true && outOf?.hasSuffix("is in a fullscreen space, so it can't be moved") == true,
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
                let result = try #require(await settle("hs.screen.missionControlNames().then(n => JSON.stringify(n))", in: harness))
                try #require(result.hasPrefix("resolved:"), "got \(result)")
                harness.eval("var names = \(result.dropFirst("resolved:".count)); var all = hs.screen.allSpaces();")
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
                #expect(await settle("hs.screen.openMissionControl()", in: harness) == "resolved:undefined")
                #expect(HSMissionControl.isOpen)
                #expect(await settle("hs.screen.missionControlNames()", in: harness)?.hasPrefix("resolved:") == true)
                #expect(HSMissionControl.isOpen)
                #expect(await settle("hs.screen.closeMissionControl()", in: harness) == "resolved:undefined")
                #expect(await isMissionControlClosed())
                #expect(!harness.hasException)
            }
        }

        @Test("toggleMissionControl() opens and closes Mission Control")
        func testToggleMissionControl() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("hs.screen.toggleMissionControl()")
                let opened = (try? await HSMissionControl.waitUntil("not open") { HSMissionControl.isOpen }) != nil
                harness.eval("hs.screen.toggleMissionControl()")
                #expect(opened)
                #expect(await isMissionControlClosed())
                #expect(!harness.hasException)
            }
        }

        @Test("Shutting down while an operation is opening Mission Control still closes it")
        func testShutdownWhileOpeningClosesMissionControl() async throws {
            let harness = makeHarness()
            try await withSpacesRestored(in: harness) {
                harness.eval("hs.screen.missionControlNames()")
                // Cancel as soon as Mission Control starts appearing, while it's still animating open
                try await HSMissionControl.waitUntil("Mission Control did not start opening") { !HSMissionControl.isClosed }
                HSSpaces.shared.cancelOperations(in: harness.context)
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
                harness.eval("var screen = hs.screen.all()[0]; var before = screen.spaces.map(s => s.id); var added = [];")

                // Fire both adds without waiting, then both removes
                let both = "Promise.all([screen.addSpace(), screen.addSpace()]).then(s => { added = s; return s.length })"
                #expect(await settle(both, in: harness, timeout: 20) == "resolved:2")
                harness.expectTrue("added[0].id !== added[1].id")

                #expect(await settle("Promise.all(added.map(s => s.remove()))", in: harness, timeout: 20) == "resolved:,")
                #expect(harness.evalString("screen.spaces.map(s => s.id).join()") == harness.evalString("before.join()"))
                #expect(!harness.hasException)
            }
        }
    }

    // MARK: - Memory

    @Test("Spaces are released after shutdown")
    func testObjectsDoNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSScreenModule.self, as: "screen")
            harness.eval("""
                var space = hs.screen.focusedSpace();
                var spaces = hs.screen.main() ? hs.screen.main().spaces : [];
                hs.screen.on('spaceChange', () => {});
            """)
            if let space = harness.evalValue("space")?.toObjectOf(HSSpace.self) as? HSSpace {
                tracker.track(space)
            }
            harness.eval("space = null; spaces = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
