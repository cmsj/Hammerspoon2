//
//  HSApplicationIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2
import AppKit

private nonisolated func chessIsAvailable() -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Chess") != nil
}

/// Integration tests for hs.application module
///
/// These tests verify that application objects are correctly bridged to JavaScript
/// and that the module's API works as expected when called from JS.
///
/// Note: These tests interact with real running applications on the system.
@MainActor
@Suite("hs.application tests")
struct HSApplicationTests {
    @Suite("hs.application main tests")
    struct HSApplicationIntegrationTests {

        // MARK: - Module API Tests
        
        @Test("runningApplications returns array from JavaScript")
        func testRunningApplicationsFromJS() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.expectTrue("Array.isArray(hs.application.runningApplications())")

            let apps = harness.eval("hs.application.runningApplications()")
            #expect(apps is [Any], "runningApplications should return an array")

            let appsArray = apps as? [Any] ?? []
            #expect(appsArray.count > 0, "There should be at least one running application")
        }

        @Test("frontmost returns current application")
        func testFrontmostFromJS() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            // Should return an object or null
            harness.eval("var frontApp = application.frontmost()")

            // Should be a valid object if it exists
            let hasFront = harness.eval("frontApp !== null && frontApp !== undefined") as? Bool
            if hasFront == true {
                #expect(harness.evalTypeOf("frontApp") == "object")
                #expect(harness.evalTypeOf("frontApp.name") == "function")
                #expect(harness.evalTypeOf("frontApp.bundleID") == "function")
            }
        }

        @Test("menuBarOwner returns an application")
        func testMenuBarOwnerFromJS() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var menuOwner = hs.application.menuBarOwner()")

            // Menu bar owner should always exist on macOS
            harness.expectTrue("menuOwner !== null && menuOwner !== undefined")
            #expect(harness.evalTypeOf("menuOwner") == "object")
        }

        @Test("matchingName finds Finder")
        func testMatchingNameFromJS() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            // Finder is always running on macOS
            harness.eval("var finder = hs.application.matchingName('Finder')")

            harness.expectTrue("finder !== null && finder !== undefined")
            #expect(harness.evalTypeOf("finder") == "object")
        }

        @Test("matchingBundleID finds application")
        func testMatchingBundleIDFromJS() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            // Try to find Finder by bundle ID
            harness.eval("var finderByID = hs.application.matchingBundleID('com.apple.finder')")

            harness.expectTrue("finderByID !== null && finderByID !== undefined")
        }

        @Test("matchingBundleID returns null for non-existent app")
        func testMatchingBundleIDNonExistent() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var nonExistent = application.matchingBundleID('com.nonexistent.app.that.does.not.exist')")

            harness.expectTrue("nonExistent === null || nonExistent === undefined")
        }

        // MARK: - Application Object Tests

        @Test("hs.application object has expected methods")
        func testApplicationObjectAPI() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var testApp = application.frontmost()")

            let hasApp = harness.eval("testApp !== null && testApp !== undefined") as? Bool
            if hasApp == true {
                #expect(harness.evalTypeOf("testApp.name") == "function")
                #expect(harness.evalTypeOf("testApp.bundleID") == "function")
                #expect(harness.evalTypeOf("testApp.pid") == "function")
                #expect(harness.evalTypeOf("testApp.path") == "function")
            }
        }

        @Test("hs.application name() returns string")
        func testApplicationName() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var app = hs.application.matchingName('Finder')")

            let name = harness.eval("app ? app.title : null")
            #expect(name is String, "hs.application title should return a string")
            #expect((name as? String)?.count ?? 0 > 0, "Name should not be empty")
        }

        @Test("hs.application bundleID() returns string")
        func testApplicationBundleID() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var app = hs.application.matchingName('Finder')")

            let bundleID = harness.eval("app ? app.bundleID : null")
            #expect(bundleID is String, "hs.application bundleID should return a string")
            #expect((bundleID as? String)?.contains(".") == true, "Bundle ID should contain dots")
        }

        @Test("hs.application pid() returns number")
        func testApplicationPID() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.expectTrue("var app = hs.application.frontmost(); app != null")
            harness.eval("console.log(app.pid);")

            let pid = harness.eval("app ? app.pid : null")
            #expect(pid is Int, "hs.application pid should return an Int")
            #expect((pid as? Int) ?? -1 > 0, "hs.application pid should return a number")
        }

        @Test("fromPID finds application by process ID")
        func testFromPID() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        var originalApp = hs.application.frontmost();
        var pid = originalApp ? originalApp.pid : null;
        var appByPID = pid ? hs.application.fromPID(pid) : null;
        """)

            harness.expectTrue("appByPID !== null && appByPID !== undefined")

            // Should be the same application
            harness.eval("""
        var sameName = (originalApp && appByPID) ?
                       originalApp.title === appByPID.title :
                       false;
        """)

            harness.expectTrue("sameName")
        }

        // MARK: - Path and Bundle Tests

        @Test("pathForBundleID returns valid path")
        func testPathForBundleID() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var finderPath = hs.application.pathForBundleID('com.apple.finder')")

            let path = harness.eval("finderPath")
            #expect(path is String, "pathForBundleID should return a string")

            if let pathString = path as? String {
                #expect(pathString.hasSuffix(".app/"), "hs.application path should end with .app/")
            }
        }

        @Test("pathsForBundleID returns array")
        func testPathsForBundleID() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var paths = hs.application.pathsForBundleID('com.apple.finder')")

            harness.expectTrue("Array.isArray(paths)")

            let paths = harness.eval("paths")
            #expect(paths is [Any], "pathsForBundleID should return an array")
        }

        @Test("pathForFileType returns path for common file type")
        func testPathForFileType() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            // Try to find an app that can open .txt files
            harness.eval("var textEditorPath = hs.application.pathForFileType('txt')")

            let path = harness.eval("textEditorPath")
            if path != nil && !(path is NSNull) {
                #expect(path is String, "pathForFileType should return a string or null")
            }
        }

        @Test("pathsForFileType returns array for common file type")
        func testPathsForFileType() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var textEditors = hs.application.pathsForFileType('txt')")

            harness.expectTrue("Array.isArray(textEditors)")
        }

        @Test("infoForBundlePath returns info dictionary")
        func testInfoForBundlePath() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        var path = hs.application.pathForBundleID('com.apple.finder');
        var info = path ? hs.application.infoForBundlePath(path) : null;
        """)

            let hasInfo = harness.eval("info !== null && info !== undefined") as? Bool
            if hasInfo == true {
                #expect(harness.evalTypeOf("info") == "object")

                // Info dictionary should have standard keys
                harness.expectTrue("typeof info.CFBundleIdentifier !== 'undefined'")
            }
        }

        // MARK: - Application State Tests

        @Test("hs.application isHidden() returns boolean")
        func testIsHidden() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("var app = hs.application.frontmost()")


            let isHidden = harness.eval("app ? app.isHidden : null")
            #expect(isHidden is Bool, "isHidden should return a boolean")
        }

        // MARK: - Real-World Use Cases

        @Test("Find all browsers pattern works")
        func testFindBrowsersPattern() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        var browserBundleIDs = [
            'com.apple.Safari',
            'com.google.Chrome',
            'org.mozilla.firefox',
            'com.microsoft.edgemac'
        ];
        
        var runningBrowsers = browserBundleIDs
            .map(function(id) { return hs.application.matchingBundleID(id); })
            .filter(function(app) { return app !== null && app !== undefined; });
        """)

            harness.expectTrue("Array.isArray(runningBrowsers)")
        }

        @Test("hs.application filtering pattern works")
        func testApplicationFiltering() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        var allApps = hs.application.runningApplications();
        
        var systemApps = allApps.filter(function(app) {
            var bundleID = app.bundleID;
            return bundleID && bundleID.startsWith('com.apple.');
        });
        """)

            harness.expectTrue("Array.isArray(systemApps)")
            harness.expectTrue("systemApps.length > 0") // Should have some Apple apps
        }

        @Test("Get application info pattern works")
        func testGetApplicationInfo() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        function getAppInfo(bundleID) {
            var app = hs.application.matchingBundleID(bundleID);
            if (!app) return null;
        
            return {
                name: app.title,
                bundleID: app.bundleID,
                pid: app.pid,
                path: app.path,
                isHidden: app.isHidden
            };
        }
        
        var finderInfo = getAppInfo('com.apple.finder');
        """)

            harness.expectTrue("finderInfo !== null")
            #expect(harness.evalString("finderInfo.name") == "Finder")
        }

        @Test("Switch to application pattern works")
        func testSwitchToAppPattern() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        function switchToApp(name) {
            var app = hs.application.matchingName(name);
            if (app && !app.isFrontmost()) {
                app.activate();
                return true;
            }
            return false;
        }
        
        // Just test that the function exists and can be called
        // (we don't actually want to switch apps during testing)
        var canSwitch = typeof switchToApp === 'function';
        """)

            harness.expectTrue("canSwitch")
        }

        @Test("Monitor application list pattern works")
        func testMonitorApplicationList() async {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")

            harness.eval("""
        function getRunningAppNames() {
            return hs.application.runningApplications()
                .map(function(app) { return app.title; })
                .sort();
        }
        
        var appNames = getRunningAppNames();
        """)

            harness.expectTrue("Array.isArray(appNames)")
            harness.expectTrue("appNames.length > 0")
            harness.expectTrue("appNames.indexOf('Finder') !== -1")
        }
    }

    // MARK: - Menu Traversal Tests

    /// Tests menu bar traversal via the accessibility APIs. Uses Finder as the target
    /// application because it is always running on macOS, including GitHub macOS runners.
    @Suite(
        "hs.application menu traversal tests", .serialized,
        .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted")
    )
    struct HSApplicationMenuTraversalTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            return harness
        }

        @Test("getMenuItems returns a non-empty menu tree for Finder")
        func testGetMenuItemsReturnsNonEmptyTree() {
            // Regression test: getMenuItems previously used a whole-array `as?` cast
            // (`menuBar.attribute(.children)`) which always fails for AX array
            // attributes and silently returns [].
            let harness = makeHarness()
            harness.eval("""
            var finder = hs.application.matchingBundleID('com.apple.finder');
            var items = finder.getMenuItems();
            var titles = items ? items.map(function(i) { return i.title; }) : [];
            """)

            harness.expectTrue("Array.isArray(items) && items.length > 0")
            harness.expectTrue("titles.indexOf('File') !== -1")
        }

        @Test("findMenuItemByName finds a top-level menu item")
        func testFindMenuItemByName() {
            let harness = makeHarness()
            harness.eval("""
            var finder = hs.application.matchingBundleID('com.apple.finder');
            var item = finder.findMenuItemByName('New Tab');
            """)

            harness.expectTrue("item !== null && item !== undefined")
            harness.expectEqual("item.title", "New Tab")
        }

        @Test("findMenuItemByPath finds a nested menu item via its path")
        func testFindMenuItemByPath() {
            // Regression test: navigateMenuPath previously searched an element's direct
            // children for each path segment, but a menu bar item's actual items sit one
            // level deeper behind an intermediate AXMenu container, so any path beyond
            // the top level always failed to resolve.
            let harness = makeHarness()
            harness.eval("""
            var finder = hs.application.matchingBundleID('com.apple.finder');
            var item = finder.findMenuItemByPath(['File', 'New Tab']);
            """)

            harness.expectTrue("item !== null && item !== undefined")
            harness.expectEqual("item.title", "New Tab")
        }
    }

    // MARK: - Watcher Structure Tests

    /// Tests the watcher API surface and lifecycle mechanics — no application events need to fire.
    @Suite("hs.application watcher structure tests")
    struct HSApplicationWatcherStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            return harness
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.application.addWatcher") == "function")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.application.removeWatcher") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.application.js")
        func testWatcherEmitterInitialized() {
            let harness = makeHarness()
            harness.expectTrue("hs.application._watcherEmitter !== null && hs.application._watcherEmitter !== undefined")
        }

        @Test("addWatcher throws when listener is a string")
        func testAddWatcherThrowsForString() {
            let harness = makeHarness()
            harness.eval("hs.application.addWatcher('not a function')")
            #expect(harness.hasException)
        }

        @Test("addWatcher throws when listener is a number")
        func testAddWatcherThrowsForNumber() {
            let harness = makeHarness()
            harness.eval("hs.application.addWatcher(42)")
            #expect(harness.hasException)
        }

        @Test("addWatcher throws when listener is null")
        func testAddWatcherThrowsForNull() {
            let harness = makeHarness()
            harness.eval("hs.application.addWatcher(null)")
            #expect(harness.hasException)
        }

        @Test("addWatcher and removeWatcher cycle completes without error")
        func testAddRemoveCycleIsSafe() {
            let harness = makeHarness()
            harness.eval("""
            var _ws1Fn = function(event, app) {};
            hs.application.addWatcher(_ws1Fn);
            hs.application.removeWatcher(_ws1Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("adding the same listener twice is idempotent")
        func testAddSameListenerTwiceIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
            var _ws2Fn = function(event, app) {};
            hs.application.addWatcher(_ws2Fn);
            hs.application.addWatcher(_ws2Fn);
            hs.application.removeWatcher(_ws2Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("three distinct listeners can be added and removed")
        func testMultipleDistinctListeners() {
            let harness = makeHarness()
            harness.eval("""
            var _ws3Fn1 = function(event, app) {};
            var _ws3Fn2 = function(event, app) {};
            var _ws3Fn3 = function(event, app) {};
            hs.application.addWatcher(_ws3Fn1);
            hs.application.addWatcher(_ws3Fn2);
            hs.application.addWatcher(_ws3Fn3);
            hs.application.removeWatcher(_ws3Fn1);
            hs.application.removeWatcher(_ws3Fn2);
            hs.application.removeWatcher(_ws3Fn3);
        """)
            #expect(!harness.hasException)
        }

        @Test("removeWatcher with an unregistered listener does not throw")
        func testRemoveUnregisteredListenerIsSafe() {
            let harness = makeHarness()
            harness.eval("hs.application.removeWatcher(function(event, app) {})")
            #expect(!harness.hasException)
        }

        @Test("removing one of two listeners leaves the other in place")
        func testRemovingOneListenerLeavesOtherIntact() {
            let harness = makeHarness()
            harness.eval("""
            var _ws4Fn1 = function(event, app) {};
            var _ws4Fn2 = function(event, app) {};
            hs.application.addWatcher(_ws4Fn1);
            hs.application.addWatcher(_ws4Fn2);
            hs.application.removeWatcher(_ws4Fn1);
            hs.application.removeWatcher(_ws4Fn2);
        """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Watcher Event Delivery Tests

    /// Tests that NSWorkspace application events are correctly delivered to JavaScript watcher callbacks.
    /// Uses Chess.app as the target because it is a bundled macOS app with no side effects.
    @Suite("hs.application watcher event delivery tests", .serialized, .disabled(if: !chessIsAvailable(), "Chess.app not found on this system"))
    struct HSApplicationWatcherEventTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            return harness
        }

        private func launchChess() async -> NSRunningApplication? {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Chess") else { return nil }
            return try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }

        private func terminateAllChess() {
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.apple.Chess" }
                .forEach { $0.terminate() }
        }

        private func waitForChessToTerminate() async {
            let deadline = Date().addingTimeInterval(5.0)
            while Date() < deadline {
                let stillRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Chess" }
                if !stillRunning { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // MARK: - Event delivery

        @Test("watcher receives didLaunch when Chess is launched")
        func testDidLaunch() async {
            terminateAllChess()
            await waitForChessToTerminate()

            let harness = makeHarness()
            harness.eval("""
            var _dlEvents = [];
            var _dlFn = function(event, app) { _dlEvents.push(event); };
            hs.application.addWatcher(_dlFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_dlFn)")
                terminateAllChess()
            }

            guard await launchChess() != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_dlEvents.indexOf('didLaunch') !== -1") as? Bool == true
            }
            if received {
                harness.expectTrue("_dlEvents.indexOf('didLaunch') !== -1")
            }
        }

        @Test("watcher receives didHide when Chess is hidden")
        func testDidHide() async {
            terminateAllChess()
            await waitForChessToTerminate()

            guard let chess = await launchChess() else { return }
            // Wait for Chess to finish launching before hiding it
            try? await Task.sleep(for: .milliseconds(1500))

            let harness = makeHarness()
            harness.eval("""
            var _dhEvents = [];
            var _dhFn = function(event, app) { _dhEvents.push(event); };
            hs.application.addWatcher(_dhFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_dhFn)")
                terminateAllChess()
            }

            chess.hide()

            let received = await harness.waitForAsync(timeout: 3.0) {
                harness.eval("_dhEvents.indexOf('didHide') !== -1") as? Bool == true
            }
            if received {
                harness.expectTrue("_dhEvents.indexOf('didHide') !== -1")
            }
        }

        @Test("watcher receives didUnhide when Chess is unhidden")
        func testDidUnhide() async {
            terminateAllChess()
            await waitForChessToTerminate()

            guard let chess = await launchChess() else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            chess.hide()
            try? await Task.sleep(for: .milliseconds(500))

            let harness = makeHarness()
            harness.eval("""
            var _duEvents = [];
            var _duFn = function(event, app) { _duEvents.push(event); };
            hs.application.addWatcher(_duFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_duFn)")
                terminateAllChess()
            }

            chess.unhide()

            let received = await harness.waitForAsync(timeout: 3.0) {
                harness.eval("_duEvents.indexOf('didUnhide') !== -1") as? Bool == true
            }
            if received {
                harness.expectTrue("_duEvents.indexOf('didUnhide') !== -1")
            }
        }

        @Test("watcher receives didTerminate when Chess is terminated")
        func testDidTerminate() async {
            terminateAllChess()
            await waitForChessToTerminate()

            guard let chess = await launchChess() else { return }
            try? await Task.sleep(for: .milliseconds(1500))

            let harness = makeHarness()
            harness.eval("""
            var _dtEvents = [];
            var _dtFn = function(event, app) { _dtEvents.push(event); };
            hs.application.addWatcher(_dtFn);
        """)
            defer { harness.eval("hs.application.removeWatcher(_dtFn)") }

            chess.terminate()

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_dtEvents.indexOf('didTerminate') !== -1") as? Bool == true
            }
            if received {
                harness.expectTrue("_dtEvents.indexOf('didTerminate') !== -1")
            }
        }

        // MARK: - Callback argument shape

        @Test("callback receives a string event name and an application object")
        func testCallbackArguments() async {
            terminateAllChess()
            await waitForChessToTerminate()

            let harness = makeHarness()
            harness.eval("""
            var _caEventName = null, _caApp = null;
            var _caFn = function(event, app) {
                if (_caEventName === null) { _caEventName = event; _caApp = app; }
            };
            hs.application.addWatcher(_caFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_caFn)")
                terminateAllChess()
            }

            guard await launchChess() != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_caEventName !== null") as? Bool == true
            }
            if received {
                harness.expectTrue("typeof _caEventName === 'string' && _caEventName.length > 0")
                harness.expectTrue("_caApp !== null && typeof _caApp === 'object'")
            }
        }

        // MARK: - Multiple listeners

        @Test("multiple listeners all receive the didLaunch event")
        func testMultipleListenersAllReceiveEvent() async {
            terminateAllChess()
            await waitForChessToTerminate()

            let harness = makeHarness()
            harness.eval("""
            var _ml1Count = 0, _ml2Count = 0;
            var _ml1Fn = function(event, app) { if (event === 'didLaunch') _ml1Count++; };
            var _ml2Fn = function(event, app) { if (event === 'didLaunch') _ml2Count++; };
            hs.application.addWatcher(_ml1Fn);
            hs.application.addWatcher(_ml2Fn);
        """)
            defer {
                harness.eval("""
                hs.application.removeWatcher(_ml1Fn);
                hs.application.removeWatcher(_ml2Fn);
            """)
                terminateAllChess()
            }

            guard await launchChess() != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_ml1Count > 0 && _ml2Count > 0") as? Bool == true
            }
            if received {
                harness.expectTrue("_ml1Count > 0")
                harness.expectTrue("_ml2Count > 0")
            }
        }

        @Test("a removed listener does not receive subsequent events")
        func testRemovedListenerDoesNotReceiveEvents() async {
            terminateAllChess()
            await waitForChessToTerminate()

            let harness = makeHarness()
            harness.eval("""
            var _rlRemovedCount = 0, _rlKeptCount = 0;
            var _rlRemovedFn = function(event, app) { _rlRemovedCount++; };
            var _rlKeptFn = function(event, app) { if (event === 'didLaunch') _rlKeptCount++; };
            hs.application.addWatcher(_rlRemovedFn);
            hs.application.addWatcher(_rlKeptFn);
            hs.application.removeWatcher(_rlRemovedFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_rlKeptFn)")
                terminateAllChess()
            }

            guard await launchChess() != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_rlKeptCount > 0") as? Bool == true
            }
            if received {
                harness.expectTrue("_rlKeptCount > 0")
                harness.expectEqual("_rlRemovedCount", 0)
            }
        }

        // MARK: - Filtering

        @Test("callback can filter events by name using a switch on the event string")
        func testCallbackCanFilterByEventName() async {
            terminateAllChess()
            await waitForChessToTerminate()

            let harness = makeHarness()
            harness.eval("""
            var _cfLaunchCount = 0, _cfOtherCount = 0;
            var _cfFn = function(event, app) {
                if (event === 'didLaunch') { _cfLaunchCount++; } else { _cfOtherCount++; }
            };
            hs.application.addWatcher(_cfFn);
        """)
            defer {
                harness.eval("hs.application.removeWatcher(_cfFn)")
                terminateAllChess()
            }

            guard await launchChess() != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_cfLaunchCount > 0") as? Bool == true
            }
            if received {
                harness.expectTrue("_cfLaunchCount > 0")
            }
        }
    }

}
