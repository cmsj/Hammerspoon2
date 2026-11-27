//
//  HSWindowFilterIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import AXSwift
@testable import Hammerspoon_2

/// A window's state, with every field defaulted to an ordinary visible, unfocused window
private func windowState(
    id: Int = 1,
    appName: String = "Example",
    bundleID: String? = "com.example.app",
    title: String = "Document",
    subrole: String? = "AXStandardWindow",
    frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
    screenUUID: String? = "SCREEN-1",
    screenName: String? = "Built-in Display",
    isMinimized: Bool = false,
    isAppHidden: Bool = false,
    isFullscreen: Bool = false,
    hasTitlebar: Bool = true,
    isOnCurrentSpace: Bool = true,
    isFocused: Bool = false,
    isAppActive: Bool = false
) -> WindowState {
    WindowState(id: id, pid: 1234, appName: appName, bundleID: bundleID, title: title, subrole: subrole, frame: frame,
                screenUUID: screenUUID, screenName: screenName, isMinimized: isMinimized, isAppHidden: isAppHidden,
                isFullscreen: isFullscreen, hasTitlebar: hasTitlebar, isOnCurrentSpace: isOnCurrentSpace,
                isFocused: isFocused, isAppActive: isAppActive)
}

@Suite("hs.windowfilter tests")
struct HSWindowFilterIntegrationTests {

    // MARK: - Events from state changes

    @Suite("hs.windowfilter events from window changes")
    struct HSWindowFilterEventDiffTests {
        private func changes(_ old: WindowState?, _ new: WindowState?) -> [HSWindowFilterEvent] {
            HSWindowFilterEvent.changes(from: old, to: new)
        }

        @Test("a new visible, focused window is created, then becomes visible, in the current Space, on screen and focused")
        func testCreated() {
            #expect(changes(nil, windowState(isFocused: true)) == [
                .windowCreated, .windowVisible, .windowInCurrentSpace, .windowOnScreen, .windowFocused,
            ])
        }

        @Test("a new minimized window on another Space is created minimized, and counts as in the current Space")
        func testCreatedMinimized() {
            #expect(changes(nil, windowState(isMinimized: true, isOnCurrentSpace: false)) == [
                .windowCreated, .windowMinimized, .windowInCurrentSpace,
            ])
        }

        @Test("a destroyed window loses everything it had, then is destroyed")
        func testDestroyed() {
            #expect(changes(windowState(isFocused: true), nil) == [
                .windowUnfocused, .windowNotOnScreen, .windowNotInCurrentSpace, .windowNotVisible, .windowDestroyed,
            ])
        }

        @Test("minimizing the focused window unfocuses it and takes it off screen before saying it was minimized")
        func testMinimized() {
            let old = windowState(isFocused: true)
            var new = old
            new.isMinimized = true
            new.isFocused = false
            #expect(changes(old, new) == [.windowUnfocused, .windowNotOnScreen, .windowNotVisible, .windowMinimized])
            #expect(changes(new, old) == [.windowUnminimized, .windowVisible, .windowOnScreen, .windowFocused])
        }

        @Test("a window focused while its application is hidden only gains focus once it's unhidden")
        func testFocusedWhileHidden() {
            let hidden = windowState(isAppHidden: true)
            var activated = hidden
            activated.isFocused = true
            activated.isAppActive = true
            #expect(changes(hidden, activated).isEmpty)

            var unhidden = activated
            unhidden.isAppHidden = false
            #expect(changes(activated, unhidden) == [.windowUnhidden, .windowVisible, .windowOnScreen, .windowFocused])
        }

        @Test("hiding an application hides its windows; a window on another Space only stops being visible")
        func testHidden() {
            let old = windowState(isOnCurrentSpace: false)
            var new = old
            new.isAppHidden = true
            // Hidden windows count as in every Space
            #expect(changes(old, new) == [.windowNotVisible, .windowHidden, .windowInCurrentSpace])
        }

        @Test("switching away from a window's Space takes it off screen and out of the current Space")
        func testSpaceChange() {
            let old = windowState()
            var new = old
            new.isOnCurrentSpace = false
            #expect(changes(old, new) == [.windowNotOnScreen, .windowNotInCurrentSpace])
            #expect(changes(new, old) == [.windowInCurrentSpace, .windowOnScreen])
        }

        @Test("going fullscreen reports fullscreened, then moved")
        func testFullscreen() {
            let old = windowState()
            var new = old
            new.isFullscreen = true
            new.frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
            #expect(changes(old, new) == [.windowFullscreened, .windowMoved])
        }

        @Test("a new title is a title change, and nothing changing is no event")
        func testTitleAndNoChange() {
            let old = windowState()
            var new = old
            new.title = "Other"
            #expect(changes(old, new) == [.windowTitleChanged])
            #expect(changes(old, old).isEmpty)
        }

        @Test("every event a window change can produce is a known event name")
        func testEventNames() {
            #expect(HSWindowFilterEvent.allNames.count == 23)
            #expect(Set(HSWindowFilterEvent.allNames).count == 23)
        }
    }

    // MARK: - The set of allowed windows

    @Suite("hs.windowfilter allowed-window bookkeeping")
    struct HSWindowFilterMembershipTests {
        private typealias Emission = WindowFilterMembership.Emission

        @Test("a window that becomes allowed is announced before its own events, then hasWindow and windowsChanged")
        func testFirstWindowAllowed() {
            var membership = WindowFilterMembership()
            let emissions = membership.process(windowID: 5, events: [.windowCreated, .windowVisible], isAllowed: true)
            #expect(emissions == [
                Emission(event: .windowAllowed, windowID: 5),
                Emission(event: .windowCreated, windowID: 5),
                Emission(event: .windowVisible, windowID: 5),
                Emission(event: .hasWindow, windowID: 5),
                Emission(event: .windowsChanged, windowID: 5),
            ])
            #expect(membership.allowed == [5])
        }

        @Test("a second allowed window doesn't repeat hasWindow")
        func testSecondWindowAllowed() {
            var membership = WindowFilterMembership()
            membership.reset(allowed: [1])
            let emissions = membership.process(windowID: 5, events: [.windowCreated], isAllowed: true)
            #expect(emissions.map(\.event) == [.windowAllowed, .windowCreated, .windowsChanged])
            #expect(emissions.last?.windowID == 1)
        }

        @Test("a window that stops being allowed still delivers the events that caused it, then is rejected")
        func testLastWindowRejected() {
            var membership = WindowFilterMembership()
            membership.reset(allowed: [5])
            let emissions = membership.process(windowID: 5, events: [.windowNotVisible, .windowMinimized], isAllowed: false)
            #expect(emissions == [
                Emission(event: .windowNotVisible, windowID: 5),
                Emission(event: .windowMinimized, windowID: 5),
                Emission(event: .windowsChanged, windowID: nil),
                Emission(event: .windowRejected, windowID: 5),
                Emission(event: .hasNoWindows, windowID: 5),
            ])
            #expect(!membership.hasWindow)
        }

        @Test("hasNoWindows only comes once the last allowed window has gone")
        func testRejectedWithOthersLeft() {
            var membership = WindowFilterMembership()
            membership.reset(allowed: [1, 5])
            let emissions = membership.process(windowID: 5, events: [.windowDestroyed], isAllowed: false)
            #expect(emissions.map(\.event) == [.windowDestroyed, .windowsChanged, .windowRejected])
            #expect(membership.hasWindow)
        }

        @Test("a window found late is recorded silently, so its later events are delivered")
        func testSilentlyRecordedWindow() {
            var membership = WindowFilterMembership()
            membership.record(windowID: 7, isAllowed: true)
            #expect(membership.allowed == [7])
            #expect(membership.hasWindow)
            #expect(membership.process(windowID: 7, events: [.windowDestroyed], isAllowed: false).map(\.event)
                    == [.windowDestroyed, .windowsChanged, .windowRejected, .hasNoWindows])
        }

        @Test("windows that were never allowed produce nothing, and allowed ones just pass their events on")
        func testUnchangedMembership() {
            var membership = WindowFilterMembership()
            membership.reset(allowed: [1])
            #expect(membership.process(windowID: 9, events: [.windowMoved], isAllowed: false).isEmpty)
            #expect(membership.process(windowID: 1, events: [.windowMoved], isAllowed: true) == [Emission(event: .windowMoved, windowID: 1)])
        }
    }

    // MARK: - Rules

    @Suite("hs.windowfilter rules")
    struct HSWindowFilterRuleTests {
        private let roles: Set<String> = ["AXStandardWindow", "AXDialog", "AXSystemDialog"]

        /// Parses `js` (an expression) as a set of rules
        private func rules(_ js: String) throws -> WindowFilterRules {
            let harness = JSTestHarness()
            let value = try #require(harness.evalValue("(\(js))"))
            return try WindowFilterRules.parse(value)
        }

        /// The error parsing `js` as rules gives, or nil if it parses
        private func parseError(_ js: String) -> String? {
            let harness = JSTestHarness()
            guard let value = harness.evalValue("(\(js))") else { return "no value" }
            do {
                _ = try WindowFilterRules.parse(value)
                return nil
            } catch {
                return error.message
            }
        }

        private func allows(_ js: String, _ state: WindowState) throws -> Bool {
            try rules(js).allows(state, allowedRoles: roles)
        }

        @Test("no rules allows every window with a standard role, visible or not")
        func testEmptyRules() throws {
            #expect(try allows("{}", windowState()))
            #expect(try allows("{}", windowState(isMinimized: true)))
            #expect(try !allows("{}", windowState(subrole: "AXFloatingWindow")))
            #expect(try !allows("{}", windowState(subrole: nil)))
        }

        @Test("true allows visible windows, false allows nothing")
        func testBooleanRules() throws {
            #expect(try allows("{ default: true }", windowState()))
            #expect(try !allows("{ default: true }", windowState(isAppHidden: true)))
            #expect(try !allows("{ default: false }", windowState()))
        }

        @Test("an application's rule replaces the default, matching its bundle ID before its name")
        func testAppRules() throws {
            #expect(try allows("{ default: false, apps: { Example: true } }", windowState()))
            #expect(try !allows("{ default: true, apps: { Example: false } }", windowState()))
            // The app rule replaces the default rather than adding to it
            #expect(try allows("{ default: { visible: true }, apps: { Example: {} } }", windowState(isMinimized: true)))
            #expect(try !allows("{ apps: { 'com.example.app': false, Example: true } }", windowState()))
        }

        @Test("every window must pass the override rule, which allows any subrole unless it says otherwise")
        func testOverride() throws {
            #expect(try !allows("{ override: { fullscreen: false }, apps: { Example: true } }", windowState(isFullscreen: true)))
            #expect(try allows("{ override: { fullscreen: false }, default: { allowRoles: '*' } }", windowState(subrole: "AXFloatingWindow")))
            #expect(try !allows("{ override: false }", windowState()))
        }

        @Test("visible and currentSpace follow Hammerspoon 1's table: minimized and hidden windows are in every Space")
        func testVisibleAndCurrentSpace() throws {
            let here = windowState()
            let elsewhere = windowState(isOnCurrentSpace: false)
            let minimizedElsewhere = windowState(isMinimized: true, isOnCurrentSpace: false)

            #expect(try allows("{ default: { currentSpace: true } }", here))
            #expect(try !allows("{ default: { currentSpace: true } }", elsewhere))
            #expect(try allows("{ default: { currentSpace: true } }", minimizedElsewhere))
            #expect(try !allows("{ default: { currentSpace: true, visible: true } }", minimizedElsewhere))
            #expect(try allows("{ default: { currentSpace: false } }", elsewhere))
            #expect(try !allows("{ default: { currentSpace: false } }", minimizedElsewhere))
        }

        @Test("focused, activeApplication, fullscreen and hasTitlebar compare with the window")
        func testFlags() throws {
            #expect(try allows("{ default: { focused: true } }", windowState(isFocused: true)))
            #expect(try !allows("{ default: { focused: true } }", windowState()))
            #expect(try allows("{ default: { activeApplication: false } }", windowState()))
            #expect(try !allows("{ default: { activeApplication: false } }", windowState(isAppActive: true)))
            #expect(try allows("{ default: { hasTitlebar: false } }", windowState(hasTitlebar: false)))
        }

        @Test("allowTitles takes a minimum length, exact titles or RegExps; rejectTitles rejects matches")
        func testTitles() throws {
            #expect(try !allows("{ default: { allowTitles: 1 } }", windowState(title: "")))
            #expect(try allows("{ default: { allowTitles: 1 } }", windowState(title: "A")))
            #expect(try allows("{ default: { allowTitles: ['Preferences', 'Console'] } }", windowState(title: "Console")))
            // Strings match exactly, not as substrings
            #expect(try !allows("{ default: { allowTitles: 'Console' } }", windowState(title: "Web Console")))
            #expect(try allows("{ default: { allowTitles: /console$/i } }", windowState(title: "Web Console")))
            #expect(try !allows("{ default: { rejectTitles: [/^Untitled/] } }", windowState(title: "Untitled 3")))
            #expect(try allows("{ default: { rejectTitles: [/^Untitled/] } }", windowState(title: "Notes")))
        }

        @Test("regions match windows mostly inside them, or covering most of them, and only apply to visible windows")
        func testRegions() throws {
            let window = windowState(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            #expect(try allows("{ default: { allowRegions: { x: 0, y: 0, w: 60, h: 100 } } }", window))
            // Less than half the window is in this region, and it covers less than half of it
            #expect(try !allows("{ default: { allowRegions: { x: 60, y: 0, w: 100, h: 100 } } }", window))
            // Covering most of a small region counts too
            #expect(try allows("{ default: { allowRegions: [{ x: 10, y: 10, w: 10, h: 10 }] } }", window))
            #expect(try !allows("{ default: { rejectRegions: new HSRect(0, 0, 60, 100) } }", window))
            #expect(try allows("{ default: { allowRegions: { x: 500, y: 500, w: 10, h: 10 } } }", windowState(isMinimized: true)))
        }

        @Test("screens match by name or UUID")
        func testScreens() throws {
            #expect(try allows("{ default: { allowScreens: 'Built-in Display' } }", windowState()))
            #expect(try allows("{ default: { allowScreens: ['OTHER', 'SCREEN-1'] } }", windowState()))
            #expect(try !allows("{ default: { rejectScreens: 'SCREEN-1' } }", windowState()))
            #expect(try !allows("{ default: { allowScreens: 'OTHER' } }", windowState()))
        }

        @Test("allowRoles takes a subrole, a list, or '*' for anything")
        func testRoles() throws {
            #expect(try allows("{ default: { allowRoles: 'AXFloatingWindow' } }", windowState(subrole: "AXFloatingWindow")))
            #expect(try !allows("{ default: { allowRoles: 'AXFloatingWindow' } }", windowState()))
            #expect(try allows("{ default: { allowRoles: '*' } }", windowState(subrole: nil)))
        }

        @Test("mistakes are reported, naming where they are", arguments: [
            ("[]", "rules must be an object"),
            ("{ defualt: true }", "unknown key 'defualt' (expected override, default, apps or sortOrder)"),
            ("{ default: { visibel: true } }", "default has an unknown condition 'visibel'"),
            ("{ apps: { Safari: { visible: 'yes' } } }", "apps['Safari'].visible must be true or false"),
            ("{ default: { allowTitles: /a/y } }", "default.allowTitles: the 'y' flag of /a/y isn't supported (only i, m and s are)"),
            ("{ default: { allowTitles: 1.5 } }", "default.allowTitles must be a whole number of characters, a string, a RegExp, or an array of them"),
            ("{ default: { allowTitles: 1e19 } }", "default.allowTitles must be a whole number of characters, a string, a RegExp, or an array of them"),
            ("{ default: { allowTitles: Infinity } }", "default.allowTitles must be a whole number of characters, a string, a RegExp, or an array of them"),
            ("{ default: 3 }", "default must be true, false, or an object of conditions"),
            ("{ sortOrder: 'newest' }", "sortOrder must be one of 'focusedLast', 'focused', 'createdLast', 'created'"),
        ])
        func testErrors(js: String, message: String) {
            #expect(parseError(js) == message)
        }
    }

    // MARK: - JS API

    @Suite("hs.windowfilter JS API")
    struct HSWindowFilterAPITests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWindowFilterModule.self, as: "windowfilter")
            return harness
        }

        @Test("create() makes a filter from rules, application names, or a function")
        func testCreateForms() {
            let harness = makeHarness()
            harness.eval("""
                var fromRules = hs.windowfilter.create({ default: false, apps: { Safari: true } });
                var fromName = hs.windowfilter.create("Safari");
                var fromNames = hs.windowfilter.create(["Safari", "Mail"]);
                var fromFunction = hs.windowfilter.create(win => true);
                var fromDefault = hs.windowfilter.create();
                """)
            #expect(!harness.hasException)
            #expect(harness.evalString("fromRules.typeName") == "HSWindowFilter")
            #expect(harness.evalString("JSON.stringify(fromName.rules)") == #"{"default":false,"apps":{"Safari":{"visible":true}},"sortOrder":"focusedLast"}"#)
            #expect(harness.evalString("Object.keys(fromNames.rules.apps).join()") == "Mail,Safari")
            harness.expectTrue("fromFunction.rules === null")
            harness.expectTrue("fromDefault.rules.apps.Spotlight === false")
        }

        @Test("create() throws for rules it can't use")
        func testCreateThrows() {
            let harness = makeHarness()
            #expect(harness.evalString("(() => { try { hs.windowfilter.create({ visible: true }); return 'no exception' } catch (e) { return e.message } })()")
                    == "hs.windowfilter.create(): unknown key 'visible' (expected override, default, apps or sortOrder)")
            #expect(harness.evalString("(() => { try { hs.windowfilter.create([1]); return 'no exception' } catch (e) { return e.message } })()")
                    == "hs.windowfilter.create(): an array of rules must only contain application names or bundle IDs")
        }

        @Test("rules round-trip through create(), including RegExps, regions and roles")
        func testRulesRoundTrip() {
            let harness = makeHarness()
            harness.eval("""
                var original = hs.windowfilter.create({
                    override: { currentSpace: true },
                    default: { visible: true, allowTitles: 1, rejectTitles: [/^Untitled/i, 'Scratch'] },
                    apps: { Terminal: { allowRegions: { x: 0, y: 0, w: 10, h: 20 }, allowRoles: ['AXDialog'] }, Finder: false },
                    sortOrder: 'createdLast',
                });
                var copy = hs.windowfilter.create(original.rules);
                """)
            #expect(!harness.hasException)
            #expect(harness.evalString("JSON.stringify(copy.rules)") == harness.evalString("JSON.stringify(original.rules)"))
            harness.expectTrue("copy.rules.default.rejectTitles[0] instanceof RegExp && copy.rules.default.rejectTitles[0].flags === 'i'")
            harness.expectTrue("copy.rules.apps.Terminal.allowRegions[0].h === 20")
            #expect(harness.evalString("copy.sortOrder") == "createdLast")
        }

        @Test("the rule setters change one part of the rules, and throw for bad rules")
        func testSetters() {
            let harness = makeHarness()
            harness.eval("""
                var wf = hs.windowfilter.create({})
                    .setDefaultRule({ visible: true })
                    .setAppRule("Safari", false)
                    .setAppRule("Mail", { allowTitles: 1 })
                    .setOverrideRule({ fullscreen: false })
                    .rejectApp("Notes")
                    .allowApp("Music");
                wf.setAppRule("Mail", null);
                """)
            #expect(!harness.hasException)
            #expect(harness.evalString("JSON.stringify(wf.rules)") == #"{"override":{"fullscreen":false},"default":{"visible":true},"apps":{"Music":{"visible":true},"Notes":false,"Safari":false},"sortOrder":"focusedLast"}"#)
            harness.expectFalse("wf.isAppAllowed('Safari')")
            harness.expectTrue("wf.isAppAllowed('Pages')")
            #expect(harness.evalString("(() => { try { wf.setAppRule('Mail', 3); return 'no exception' } catch (e) { return e.message } })()")
                    == "HSWindowFilter.setAppRule(): rule must be true, false, or an object of conditions")
        }

        @Test("setCurrentSpace() changes only the override rule's currentSpace")
        func testSetCurrentSpace() {
            let harness = makeHarness()
            harness.eval("var wf = hs.windowfilter.create({ override: { fullscreen: false } }).setCurrentSpace(true)")
            #expect(harness.evalString("JSON.stringify(wf.rules.override)") == #"{"currentSpace":true,"fullscreen":false}"#)
            harness.eval("wf.setCurrentSpace(null)")
            #expect(harness.evalString("JSON.stringify(wf.rules.override)") == #"{"fullscreen":false}"#)
        }

        @Test("the default filters are shared, and currentSpaceFilter copies the default filter with a currentSpace override")
        func testDefaultFilters() {
            let harness = makeHarness()
            harness.eval("hs.windowfilter.defaultFilter.rejectApp('Cool New Launcher')")
            harness.expectTrue("hs.windowfilter.defaultFilter === hs.windowfilter.defaultFilter")
            harness.expectTrue("hs.windowfilter.currentSpaceFilter.rules.override.currentSpace === true")
            harness.expectTrue("hs.windowfilter.currentSpaceFilter.rules.apps['Cool New Launcher'] === false")
            harness.expectTrue("hs.windowfilter.create().rules.apps['Cool New Launcher'] === false")
            harness.expectFalse("hs.windowfilter.defaultFilter.isAppAllowed('Spotlight')")
        }

        @Test("currentSpaceFilter keeps a default filter override that rejects everything")
        func testCurrentSpaceFilterKeepsRejection() {
            let harness = makeHarness()
            harness.eval("hs.windowfilter.defaultFilter.setOverrideRule(false)")
            harness.expectTrue("hs.windowfilter.currentSpaceFilter.rules.override === false")
            harness.expectFalse("hs.windowfilter.currentSpaceFilter.isAppAllowed('Safari')")
            #expect(!harness.hasException)
        }

        @Test("duplicate() makes an independent copy")
        func testDuplicate() {
            let harness = makeHarness()
            harness.eval("""
                var a = hs.windowfilter.create({ default: true });
                var b = a.duplicate().rejectApp("Safari");
                """)
            harness.expectTrue("a !== b")
            harness.expectTrue("a.isAppAllowed('Safari') && !b.isAppAllowed('Safari')")
        }

        @Test("sortOrder only accepts known orders")
        func testSortOrder() {
            let harness = makeHarness()
            harness.eval("var wf = hs.windowfilter.create({}); wf.sortOrder = 'created'")
            #expect(harness.evalString("wf.sortOrder") == "created")
            #expect(harness.evalString("(() => { try { wf.sortOrder = 'newest'; return 'no exception' } catch (e) { return e.message } })()")
                    == "HSWindowFilter.sortOrder must be one of 'focusedLast', 'focused', 'createdLast', 'created'")
            #expect(harness.evalString("wf.sortOrder") == "created")
        }

        @Test("a filter made from a function has no rules to change")
        func testPredicateFilterRules() {
            let harness = makeHarness()
            harness.eval("var wf = hs.windowfilter.create(win => true)")
            harness.expectTrue("wf.isAppAllowed('Anything')")
            #expect(harness.evalString("(() => { try { wf.rejectApp('Safari'); wf.setAppRule('Safari', false); return 'no exception' } catch (e) { return e.message } })()")
                    == "HSWindowFilter.rejectApp(): a filter made from a function has no rules")
        }

        @Test("allowedWindowRoles can be read and replaced")
        func testAllowedWindowRoles() {
            let harness = makeHarness()
            #expect(harness.evalString("hs.windowfilter.allowedWindowRoles.join()") == "AXDialog,AXStandardWindow,AXSystemDialog")
            harness.eval("hs.windowfilter.allowedWindowRoles = ['AXStandardWindow', 'AXFloatingWindow']")
            #expect(harness.evalString("hs.windowfilter.allowedWindowRoles.join()") == "AXFloatingWindow,AXStandardWindow")
        }

        @Test("on() throws for an unknown event, and pause()/resume() are reflected in isPaused")
        func testOnAndPause() {
            let harness = makeHarness()
            harness.eval("var wf = hs.windowfilter.create({})")
            #expect(harness.evalString("(() => { try { wf.on('windowCreatd', () => {}); return 'no exception' } catch (e) { return 'threw' } })()") == "threw")
            harness.expectTrue("wf.pause().isPaused === true")
            harness.expectTrue("wf.resume().isPaused === false")
            #expect(!harness.hasException)
        }

        @Test("inaccessibleApplications() returns an array of applications")
        func testInaccessibleApplicationsShape() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.windowfilter.inaccessibleApplications())")
            harness.expectTrue("hs.windowfilter.inaccessibleApplications().every(app => app instanceof HSApplication)")
            #expect(!harness.hasException)
        }

        @Test("the module's on() accepts inaccessibleApplication, throws for an unknown event, and off() stops watching")
        func testModuleOnOff() {
            let harness = makeHarness()
            #expect(harness.evalString("(() => { try { hs.windowfilter.on('inaccessibleApp', () => {}); return 'no exception' } catch (e) { return 'threw' } })()") == "threw")
            harness.eval("var fn = app => {}; hs.windowfilter.on('inaccessibleApplication', fn)")
            #expect(!harness.hasException)
            harness.eval("hs.windowfilter.off('inaccessibleApplication', fn)")
            #expect(!harness.hasException)
        }

        /// A titled window of Hammerspoon's own, on screen, and its HSWindow. Requests to
        /// Hammerspoon's own process are answered in-process, so this needs no Accessibility
        /// permission.
        @MainActor
        private func makeOwnWindow(title: String) throws -> (NSWindow, HSWindow) {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 150),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            window.orderFrontRegardless()

            var value: CFTypeRef?
            let app = AXUIElementCreateApplication(getpid())
            try #require(unsafe AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success)
            let elements = try #require(value as? [AXUIElement]).map { UIElement($0) }
            let element = try #require(elements.first { Int(WindowEnumerator.windowID(of: $0)) == window.windowNumber })
            return (window, AXObjectCache.shared.window(element: element, app: .current, id: window.windowNumber))
        }

        @Test("isWindowAllowed() judges Hammerspoon's own windows by the filter's rules")
        @MainActor
        func testOwnWindowsFollowTheRules() throws {
            let (window, ownWindow) = try makeOwnWindow(title: "Hammerspoon's own window")
            defer { window.orderOut(nil) }

            let harness = makeHarness()
            harness.context.setObject(ownWindow, forKeyedSubscript: "ownWindow" as NSString)
            harness.expectTrue("hs.windowfilter.create(win => true).isWindowAllowed(ownWindow)")
            harness.expectFalse("hs.windowfilter.create(win => false).isWindowAllowed(ownWindow)")
            harness.expectTrue("hs.windowfilter.create({ default: { allowRoles: '*' } }).isWindowAllowed(ownWindow)")
            #expect(!harness.hasException)
        }

        // filter.on() needs Accessibility permission, even for Hammerspoon's own windows
        @Test("a filter reports Hammerspoon's own windows being created, moved, retitled and destroyed",
              .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"))
        @MainActor
        func testOwnWindowEvents() async throws {
            let harness = makeHarness()
            harness.eval("""
                var wf = hs.windowfilter.create(win => win.pid === \(getpid()));
                var events = [];
                var record = (win, appName, event) => events.push(event + ":" + (win ? win.id : null));
                for (const name of ['windowCreated', 'windowMoved', 'windowTitleChanged', 'windowDestroyed']) wf.on(name, record);
                """)
            #expect(!harness.hasException)
            defer {
                harness.eval("for (const name of ['windowCreated', 'windowMoved', 'windowTitleChanged', 'windowDestroyed']) wf.off(name, record)")
            }

            let (window, _) = try makeOwnWindow(title: "Own window for a filter")
            defer { window.orderOut(nil) }
            func saw(_ event: String) -> Bool {
                harness.eval("events.includes('\(event):\(window.windowNumber)')") as? Bool == true
            }

            #expect(await harness.waitForAsync(timeout: 3) { saw("windowCreated") })
            window.setFrameOrigin(NSPoint(x: 160, y: 160))
            #expect(await harness.waitForAsync(timeout: 3) { saw("windowMoved") })
            window.title = "Own window, retitled"
            #expect(await harness.waitForAsync(timeout: 3) { saw("windowTitleChanged") })
            window.orderOut(nil)
            #expect(await harness.waitForAsync(timeout: 3) { saw("windowDestroyed") })
            #expect(!harness.hasException)
        }
    }

    // MARK: - Accessibility refusals

    @Suite("hs.windowfilter applications that turn Accessibility off")
    struct HSWindowFilterRefusalTests {
        @Test("only kAXErrorAPIDisabled while Hammerspoon is trusted is final", arguments: [
            (AXError.apiDisabled, true, true),
            (AXError.apiDisabled, false, false),
            (AXError.cannotComplete, true, false),
            (AXError.notImplemented, true, false),
            (AXError.failure, true, false),
        ])
        func testFinalRefusal(error: AXError, isTrusted: Bool, isFinal: Bool) {
            #expect(WindowTracker.isFinalRefusal(error, isTrusted: isTrusted) == isFinal)
        }
    }

    // MARK: - Real windows

    @Suite("hs.windowfilter with real windows", .serialized,
           .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"),
           .testApp)
    struct HSWindowFilterLiveTests {
        init() async {
            await JSTestHarness.drainMainActorQueue()
        }

        /// A harness with `wf`, a filter of the test app's windows (by PID, since other suites run
        /// their own copies of it), recording its events in `events` as "event:windowID"
        private func makeHarness(rule: String = "win.pid === testAppPID") -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWindowFilterModule.self, as: "windowfilter")
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            harness.eval("""
                var wf = hs.windowfilter.create(win => \(rule));
                var events = [];
                var record = (win, appName, event) => events.push(event + ":" + (win ? win.id : null));
                """)
            return harness
        }

        private func listen(_ harness: JSTestHarness, to names: [String]) {
            for name in names {
                harness.eval("wf.on('\(name)', record)")
            }
            #expect(!harness.hasException)
        }

        @Test("windows() and isWindowAllowed() include the test app's window")
        func testWindows() {
            let harness = makeHarness()
            harness.eval("""
                var wins = wf.windows();
                var appWin = hs.application.fromPID(testAppPID).allWindows[0];
                """)
            harness.expectTrue("wins.length >= 1 && wins.every(w => w.pid === testAppPID)")
            harness.expectTrue("wf.isWindowAllowed(appWin)")
            harness.expectFalse("hs.windowfilter.create(win => false).isWindowAllowed(appWin)")
            #expect(!harness.hasException)
        }

        @Test("a rules filter allows the test app's window by its application's name")
        func testRulesFilterWindows() {
            let harness = makeHarness()
            harness.eval("""
                var appWin = hs.application.fromPID(testAppPID).allWindows[0];
                var byName = hs.windowfilter.create([hs.application.fromPID(testAppPID).name]);
                """)
            harness.expectTrue("byName.isWindowAllowed(appWin)")
            harness.expectTrue("byName.windows().some(w => w.id === appWin.id)")
            harness.expectFalse("byName.duplicate().rejectApp(hs.application.fromPID(testAppPID).name).isWindowAllowed(appWin)")
            #expect(!harness.hasException)
        }

        @Test("a new window is allowed before it's created, and rejected after it's destroyed")
        func testCreatedAndDestroyed() async {
            let harness = makeHarness()
            defer { TestAppControl.closeWindows() }
            listen(harness, to: ["windowAllowed", "windowCreated", "windowDestroyed", "windowRejected"])

            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.some(e => e.startsWith('windowCreated'))") as? Bool == true })
            harness.eval("var newID = Number(events.find(e => e.startsWith('windowCreated')).split(':')[1])")
            #expect(harness.evalString("events.filter(e => e.endsWith(':' + newID)).slice(0, 2).join()")
                    == "windowAllowed:\(harness.evalInt("newID") ?? -1),windowCreated:\(harness.evalInt("newID") ?? -1)")

            TestAppControl.closeWindows()
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.includes('windowRejected:' + newID)") as? Bool == true })
            #expect(harness.evalString("events.filter(e => e.endsWith(':' + newID)).slice(-2).join()")
                    == "windowDestroyed:\(harness.evalInt("newID") ?? -1),windowRejected:\(harness.evalInt("newID") ?? -1)")
            harness.eval("wf.off('windowAllowed', record); wf.off('windowCreated', record); wf.off('windowDestroyed', record); wf.off('windowRejected', record)")
        }

        @Test("moving a window and changing its title are reported once they settle")
        func testMovedAndTitleChanged() async {
            let harness = makeHarness()
            defer { TestAppControl.closeWindows() }
            listen(harness, to: ["windowMoved", "windowTitleChanged"])
            harness.eval("""
                var appWin = hs.application.fromPID(testAppPID).allWindows[0];
                var start = appWin.position;
                appWin.position = new HSPoint(start.x + 30, start.y + 20);
                """)
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.includes('windowMoved:' + appWin.id)") as? Bool == true })

            harness.eval("appWin.position = start")

            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("wf.windows().length") ?? 0 >= 2 })
            TestAppControl.retitleWindows(to: "Retitled by \(#function)")
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.some(e => e.startsWith('windowTitleChanged:'))") as? Bool == true })
            harness.eval("wf.off('windowMoved', record); wf.off('windowTitleChanged', record)")
        }

        /// macOS reports every window of a hidden application as an AXDialog. A window read while
        /// its application is hidden (here, because its title changed) has to be read again once
        /// the application is unhidden, or it keeps that subrole (#485).
        @Test("a standard window read while its application is hidden is allowed again by its subrole once it's unhidden")
        func testUnhiddenWindowSubroleIsReadAgain() async {
            let harness = makeHarness()
            harness.eval("var app = hs.application.fromPID(testAppPID)")
            defer {
                harness.eval("app.unhide()")
                TestAppControl.closeWindows()
            }
            listen(harness, to: ["windowCreated", "windowHidden", "windowTitleChanged"])
            harness.eval("var byRole = hs.windowfilter.create({ default: false, apps: { [app.name]: { allowRoles: 'AXStandardWindow' } } })")

            // Only the windows openWindow() opens can be retitled
            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.some(e => e.startsWith('windowCreated'))") as? Bool == true })
            harness.eval("var newID = Number(events.find(e => e.startsWith('windowCreated')).split(':')[1])")
            harness.eval("var newWin = () => app.allWindows.find(w => w.id === newID)")
            harness.expectTrue("newWin().subrole === 'AXStandardWindow' && byRole.isWindowAllowed(newWin())")

            harness.eval("app.hide()")
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.includes('windowHidden:' + newID)") as? Bool == true })
            TestAppControl.retitleWindows(to: "Retitled while hidden by \(#function)")
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.includes('windowTitleChanged:' + newID)") as? Bool == true })
            // A hidden application's windows are AXDialogs
            harness.expectFalse("byRole.isWindowAllowed(newWin())")
            // Hiding can come with a screen change (at least in a VM), whose refresh of every window
            // would read this one again by chance if it came after unhiding
            try? await Task.sleep(for: .seconds(1))

            harness.eval("app.unhide()")
            #expect(await harness.waitForAsync(timeout: 3) {
                harness.eval("newWin().subrole === 'AXStandardWindow' && byRole.isWindowAllowed(newWin()) && byRole.windows().some(w => w.id === newID)") as? Bool == true
            })
            harness.eval("wf.off('windowCreated', record); wf.off('windowHidden', record); wf.off('windowTitleChanged', record)")
            #expect(!harness.hasException)
        }

        @Test("a window and its application are the same objects wherever they come from")
        func testSameObjects() async {
            let harness = makeHarness()
            defer { TestAppControl.closeWindows() }
            harness.eval("var created = null; var onCreated = win => { created = win }; wf.on('windowCreated', onCreated)")
            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("created !== null") as? Bool == true })

            // Compared natively: JS identity of bridged objects is unreliable across the many
            // short-lived virtual machines in the test process
            func object(_ script: String) -> AnyObject? {
                harness.evalValue(script)?.toObject() as AnyObject?
            }
            let window = object("created")
            #expect(window != nil)
            #expect(object("wf.windows().find(w => w.id === created.id)") === window)
            #expect(object("hs.application.fromPID(testAppPID).allWindows.find(w => w.id === created.id)") === window)

            let application = object("created.application")
            #expect(application != nil)
            #expect(object("created.application") === application)
            #expect(object("hs.application.fromPID(testAppPID)") === application)
            harness.eval("wf.off('windowCreated', onCreated)")
            #expect(!harness.hasException)
        }

        @Test("a window that goes without a notification is found gone by the next sweep")
        func testSweepFindsLostWindow() async throws {
            let harness = makeHarness()
            defer { TestAppControl.closeWindows() }
            listen(harness, to: ["windowCreated", "windowDestroyed"])
            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.eval("events.some(e => e.startsWith('windowCreated'))") as? Bool == true })
            let newID = try #require(harness.evalInt("Number(events.find(e => e.startsWith('windowCreated')).split(':')[1])"))

            WindowTracker.shared.stopListening(toWindowWithID: newID)
            TestAppControl.closeWindows()
            try await Task.sleep(for: .milliseconds(500))
            // Without its notification, the window is still thought to exist
            harness.expectFalse("events.includes('windowDestroyed:\(newID)')")

            WindowTracker.shared.sweep()
            harness.expectTrue("events.includes('windowDestroyed:\(newID)')")
            harness.expectFalse("wf.windows().some(w => w.id === \(newID))")
            harness.eval("wf.off('windowCreated', record); wf.off('windowDestroyed', record)")
        }

        @Test("a filter with listeners keeps working after it's dropped and garbage is collected")
        func testUnreferencedFilterKeepsWorking() async {
            let harness = makeHarness()
            defer { TestAppControl.closeWindows() }
            harness.eval("var created = 0")
            autoreleasepool {
                _ = harness.eval("void hs.windowfilter.create(win => win.pid === testAppPID).on('windowCreated', () => { created++ })")
            }
            harness.eval("wf = null")
            harness.collectGarbage()

            TestAppControl.openWindow()
            #expect(await harness.waitForAsync(timeout: 3) { harness.evalInt("created") ?? 0 > 0 })
        }

        @Test("a filter whose listeners were removed is garbage collected")
        func testFilterWithoutListenersIsCollected() async {
            let harness = makeHarness()
            weak var filter: HSWindowFilter?
            autoreleasepool {
                harness.eval("var fn = () => {}; wf.on('windowCreated', fn)")
                filter = harness.evalValue("wf")?.toObjectOf(HSWindowFilter.self) as? HSWindowFilter
                harness.eval("wf.off('windowCreated', fn); wf = null")
            }
            harness.collectGarbage()
            #expect(filter == nil)
        }

        @Test("a listening filter is released after shutdown, and stops watching the app")
        func testFilterDoesNotLeakAfterReload() throws {
            let pid = try #require(TestAppControl.pid)
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = makeHarness()
                harness.eval("wf.on('windowFocused', record)")
                if let filter = harness.evalValue("wf")?.toObjectOf(HSWindowFilter.self) as? HSWindowFilter {
                    tracker.track(filter)
                }
                #expect(AXObserverHub.shared.hasObserver(for: pid))
                harness.eval("wf = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
            // This suite's copy of the test app is watched by nothing else, so its observer only
            // goes once the shared window tracker has stopped and released its registrations
            #expect(!AXObserverHub.shared.hasObserver(for: pid))
        }

        @Test("the test app isn't inaccessible, with or without anything watching")
        func testTestAppIsNotInaccessible() {
            let harness = makeHarness()
            let script = "hs.windowfilter.inaccessibleApplications().some(app => app.pid === testAppPID)"
            harness.expectFalse(script)
            harness.eval("var fn = app => {}; hs.windowfilter.on('inaccessibleApplication', fn)")
            harness.expectFalse(script)
            harness.eval("hs.windowfilter.off('inaccessibleApplication', fn)")
            #expect(!harness.hasException)
        }

        @Test("a module listening for inaccessible applications watches windows, and stops after shutdown")
        func testModuleListenerStopsAfterReload() throws {
            let pid = try #require(TestAppControl.pid)
            autoreleasepool {
                let harness = makeHarness()
                harness.eval("hs.windowfilter.on('inaccessibleApplication', app => {})")
                #expect(!harness.hasException)
                #expect(AXObserverHub.shared.hasObserver(for: pid))
                harness.shutdownForLeakTest()
            }
            #expect(!AXObserverHub.shared.hasObserver(for: pid))
        }
    }
}
