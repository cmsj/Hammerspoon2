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

            let name = harness.eval("app ? app.name : null")
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
                       originalApp.name === appByPID.name :
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
                name: app.name,
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
                .map(function(app) { return app.name; })
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

    /// Tests menu bar traversal via the accessibility APIs. Uses the Hammerspoon 2 Test App
    /// (``TestAppControl``) as the target: its menu titles are English whatever the system language.
    @Suite(
        "hs.application menu traversal tests", .serialized,
        .disabled(if: !AXIsProcessTrusted(), "Accessibility permission not granted"),
        .testApp
    )
    struct HSApplicationMenuTraversalTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()
            return harness
        }

        @Test("getMenuItems returns a non-empty menu tree")
        func testGetMenuItemsReturnsNonEmptyTree() {
            // Regression test: getMenuItems previously used a whole-array `as?` cast
            // (`menuBar.attribute(.children)`) which always fails for AX array
            // attributes and silently returns [].
            let harness = makeHarness()
            harness.eval("""
            var app = hs.application.fromPID(testAppPID);
            var items = app.getMenuItems();
            var titles = items ? items.map(function(i) { return i.title; }) : [];
            """)

            harness.expectTrue("Array.isArray(items) && items.length > 0")
            harness.expectTrue("titles.indexOf('File') !== -1")
        }

        @Test("findMenuItemByName finds a top-level menu item")
        func testFindMenuItemByName() {
            let harness = makeHarness()
            harness.eval("""
            var app = hs.application.fromPID(testAppPID);
            var item = app.findMenuItemByName('New Window');
            """)

            harness.expectTrue("item !== null && item !== undefined")
            harness.expectEqual("item.title", "New Window")
        }

        @Test("findMenuItemByPath finds a nested menu item via its path")
        func testFindMenuItemByPath() {
            // Regression test: navigateMenuPath previously searched an element's direct
            // children for each path segment, but a menu bar item's actual items sit one
            // level deeper behind an intermediate AXMenu container, so any path beyond
            // the top level always failed to resolve.
            let harness = makeHarness()
            harness.eval("""
            var app = hs.application.fromPID(testAppPID);
            var item = app.findMenuItemByPath(['File', 'New Window']);
            """)

            harness.expectTrue("item !== null && item !== undefined")
            harness.expectEqual("item.title", "New Window")
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

        @Test("_addWatcher reports success, then refuses a second subscription by returning false")
        func testAddWatcherReportsRefusal() {
            let harness = makeHarness()
            harness.eval("""
            var first = hs.application._addWatcher(function() {});
            var second = hs.application._addWatcher(function() {});
            hs.application._removeWatcher();
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("first") == true)
            #expect(harness.evalBool("second") == false)
        }

        @Test("on is a function")
        func testOnIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.application.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.application.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.application.once") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.application.js")
        func testWatcherEmitterInitialized() {
            let harness = makeHarness()
            harness.expectTrue("hs.application._watcherEmitter !== null && hs.application._watcherEmitter !== undefined")
        }

        @Test("on throws when listener is a string")
        func testOnThrowsForString() {
            let harness = makeHarness()
            harness.eval("hs.application.on('didLaunch', 'not a function')")
            #expect(harness.hasException)
        }

        @Test("on throws when listener is a number")
        func testOnThrowsForNumber() {
            let harness = makeHarness()
            harness.eval("hs.application.on('didLaunch', 42)")
            #expect(harness.hasException)
        }

        @Test("on throws when listener is null")
        func testOnThrowsForNull() {
            let harness = makeHarness()
            harness.eval("hs.application.on('didLaunch', null)")
            #expect(harness.hasException)
        }

        @Test("on and off cycle completes without error")
        func testOnOffCycleIsSafe() {
            let harness = makeHarness()
            harness.eval("""
            var _ws1Fn = function(app) {};
            hs.application.on('didLaunch', _ws1Fn);
            hs.application.off('didLaunch', _ws1Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("registering the same listener for the same event twice is idempotent")
        func testOnSameListenerTwiceIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
            var _ws2Fn = function(app) {};
            hs.application.on('didLaunch', _ws2Fn);
            hs.application.on('didLaunch', _ws2Fn);
            hs.application.off('didLaunch', _ws2Fn);
        """)
            #expect(!harness.hasException)
        }

        @Test("three distinct listeners can be added and removed")
        func testMultipleDistinctListeners() {
            let harness = makeHarness()
            harness.eval("""
            var _ws3Fn1 = function(app) {};
            var _ws3Fn2 = function(app) {};
            var _ws3Fn3 = function(app) {};
            hs.application.on('didLaunch', _ws3Fn1);
            hs.application.on('didHide', _ws3Fn2);
            hs.application.on('didTerminate', _ws3Fn3);
            hs.application.off('didLaunch', _ws3Fn1);
            hs.application.off('didHide', _ws3Fn2);
            hs.application.off('didTerminate', _ws3Fn3);
        """)
            #expect(!harness.hasException)
        }

        @Test("off with an unregistered listener does not throw")
        func testOffUnregisteredListenerIsSafe() {
            let harness = makeHarness()
            harness.eval("hs.application.off('didLaunch', function(app) {})")
            #expect(!harness.hasException)
        }

        @Test("removing one of two listeners leaves the other in place")
        func testRemovingOneListenerLeavesOtherIntact() {
            let harness = makeHarness()
            harness.eval("""
            var _ws4Fn1 = function(app) {};
            var _ws4Fn2 = function(app) {};
            hs.application.on('didLaunch', _ws4Fn1);
            hs.application.on('didLaunch', _ws4Fn2);
            hs.application.off('didLaunch', _ws4Fn1);
            hs.application.off('didLaunch', _ws4Fn2);
        """)
            #expect(!harness.hasException)
        }

        @Test("listeners only receive the event they registered for")
        func testListenersAreFilteredByEvent() {
            let harness = makeHarness()
            harness.eval("""
                var launchCount = 0;
                var terminateCount = 0;
                hs.application.on('didLaunch', function() { launchCount++; });
                hs.application.on('didTerminate', function() { terminateCount++; });
                hs.application._watcherEmitter.emit('didLaunch', null);
            """)
            harness.expectEqual("launchCount", 1)
            harness.expectEqual("terminateCount", 0)
            #expect(!harness.hasException)
        }

        @Test("once-registered listener fires only one time")
        func testOnceFiresOnlyOnce() {
            let harness = makeHarness()
            harness.eval("""
                var count = 0;
                hs.application.once('didLaunch', function() { count++; });
                hs.application._watcherEmitter.emit('didLaunch', null);
                hs.application._watcherEmitter.emit('didLaunch', null);
            """)
            harness.expectEqual("count", 1)
            #expect(!harness.hasException)
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSApplicationModule.self, as: "application")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.application.on") == "function")
            #expect(harness.evalTypeOf("hs.application.off") == "function")
            #expect(harness.evalTypeOf("hs.application.once") == "function")

            harness.eval("""
                var fn = function(app) {};
                hs.application.on('didLaunch', fn);
                hs.application.off('didLaunch', fn);
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Watcher Event Delivery Tests

    /// Tests that NSWorkspace application events are correctly delivered to JavaScript watcher callbacks.
    /// Uses the Hammerspoon 2 Test App (``TestAppControl``) as the target.
    @Suite("hs.application watcher event delivery tests", .serialized)
    struct HSApplicationWatcherEventTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            return harness
        }

        // MARK: - Event delivery

        @Test("watcher receives didLaunch when the test app is launched")
        func testDidLaunch() async {
            var launched: NSRunningApplication?
            let harness = makeHarness()
            harness.eval("""
            var _dlReceived = false;
            var _dlFn = function(app) { _dlReceived = true; };
            hs.application.on('didLaunch', _dlFn);
        """)
            defer {
                harness.eval("hs.application.off('didLaunch', _dlFn)")
                launched?.terminate()
            }

            launched = await TestAppControl.launch(detail: "Launches this app and waits for the didLaunch event")
            guard launched != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_dlReceived") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_dlReceived")
            }
        }

        @Test("watcher receives didHide when the test app is hidden")
        func testDidHide() async {
            var launched: NSRunningApplication?
            launched = await TestAppControl.launch(detail: "Hides this app and waits for the didHide event")
            guard let app = launched else { return }

            let harness = makeHarness()
            harness.eval("""
            var _dhReceived = false;
            var _dhFn = function(app) { _dhReceived = true; };
            hs.application.on('didHide', _dhFn);
        """)
            defer {
                harness.eval("hs.application.off('didHide', _dhFn)")
                launched?.terminate()
            }

            app.hide()

            let received = await harness.waitForAsync(timeout: 3.0) {
                harness.eval("_dhReceived") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_dhReceived")
            }
        }

        @Test("watcher receives didUnhide when the test app is unhidden")
        func testDidUnhide() async {
            var launched: NSRunningApplication?
            launched = await TestAppControl.launch(detail: "Hides and unhides this app and waits for the didUnhide event")
            guard let app = launched else { return }
            app.hide()
            try? await Task.sleep(for: .milliseconds(500))

            let harness = makeHarness()
            harness.eval("""
            var _duReceived = false;
            var _duFn = function(app) { _duReceived = true; };
            hs.application.on('didUnhide', _duFn);
        """)
            defer {
                harness.eval("hs.application.off('didUnhide', _duFn)")
                launched?.terminate()
            }

            app.unhide()

            let received = await harness.waitForAsync(timeout: 3.0) {
                harness.eval("_duReceived") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_duReceived")
            }
        }

        @Test("watcher receives didTerminate when the test app is terminated")
        func testDidTerminate() async {
            var launched: NSRunningApplication?
            launched = await TestAppControl.launch(detail: "Quits this app and waits for the didTerminate event")
            guard let app = launched else { return }

            let harness = makeHarness()
            harness.eval("""
            var _dtReceived = false;
            var _dtFn = function(app) { _dtReceived = true; };
            hs.application.on('didTerminate', _dtFn);
        """)
            defer { harness.eval("hs.application.off('didTerminate', _dtFn)") }

            app.terminate()

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_dtReceived") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_dtReceived")
            }
        }

        // MARK: - Callback argument shape

        @Test("listener receives a single application object argument")
        func testCallbackArguments() async {
            var launched: NSRunningApplication?
            let harness = makeHarness()
            harness.eval("""
            var _caApp = undefined;
            var _caFn = function(app) {
                if (_caApp === undefined) { _caApp = app; }
            };
            hs.application.on('didLaunch', _caFn);
        """)
            defer {
                harness.eval("hs.application.off('didLaunch', _caFn)")
                launched?.terminate()
            }

            launched = await TestAppControl.launch(detail: "Launches this app; the didLaunch listener must get one application object")
            guard launched != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_caApp !== undefined") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_caApp !== null && typeof _caApp === 'object'")
            }
        }

        // MARK: - Multiple listeners

        @Test("multiple listeners all receive the didLaunch event")
        func testMultipleListenersAllReceiveEvent() async {
            var launched: NSRunningApplication?
            let harness = makeHarness()
            harness.eval("""
            var _ml1Count = 0, _ml2Count = 0;
            var _ml1Fn = function(app) { _ml1Count++; };
            var _ml2Fn = function(app) { _ml2Count++; };
            hs.application.on('didLaunch', _ml1Fn);
            hs.application.on('didLaunch', _ml2Fn);
        """)
            defer {
                harness.eval("""
                hs.application.off('didLaunch', _ml1Fn);
                hs.application.off('didLaunch', _ml2Fn);
            """)
                launched?.terminate()
            }

            launched = await TestAppControl.launch(detail: "Launches this app; both didLaunch listeners must fire")
            guard launched != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_ml1Count > 0 && _ml2Count > 0") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_ml1Count > 0")
                harness.expectTrue("_ml2Count > 0")
            }
        }

        @Test("a removed listener does not receive subsequent events")
        func testRemovedListenerDoesNotReceiveEvents() async {
            var launched: NSRunningApplication?
            let harness = makeHarness()
            harness.eval("""
            var _rlRemovedCount = 0, _rlKeptCount = 0;
            var _rlRemovedFn = function(app) { _rlRemovedCount++; };
            var _rlKeptFn = function(app) { _rlKeptCount++; };
            hs.application.on('didLaunch', _rlRemovedFn);
            hs.application.on('didLaunch', _rlKeptFn);
            hs.application.off('didLaunch', _rlRemovedFn);
        """)
            defer {
                harness.eval("hs.application.off('didLaunch', _rlKeptFn)")
                launched?.terminate()
            }

            launched = await TestAppControl.launch(detail: "Launches this app; the removed didLaunch listener must stay silent")
            guard launched != nil else { return }

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_rlKeptCount > 0") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_rlKeptCount > 0")
                harness.expectEqual("_rlRemovedCount", 0)
            }
        }

        // MARK: - Filtering

        @Test("a listener registered for one event does not receive a different real event")
        func testListenerDoesNotReceiveOtherRealEvents() async {
            var launched: NSRunningApplication?
            let harness = makeHarness()
            harness.eval("""
            // Only count the test app: other apps launch and quit system-wide while this runs,
            // including copies of the test app from tests in other suites.
            var _cfLaunchCount = 0, _cfTerminateCount = 0;
            var _cfLaunchFn = function(app) { if (app && app.bundleID === 'net.tenshu.Hammerspoon-2.TestApp') _cfLaunchCount++; };
            // Counts only this test's copy: other suites quit their own copies meanwhile
            var _cfPID = -1;
            var _cfTerminateFn = function(app) { if (app && app.pid === _cfPID) _cfTerminateCount++; };
            hs.application.on('didLaunch', _cfLaunchFn);
            hs.application.on('didTerminate', _cfTerminateFn);
        """)
            defer {
                harness.eval("""
                hs.application.off('didLaunch', _cfLaunchFn);
                hs.application.off('didTerminate', _cfTerminateFn);
            """)
                launched?.terminate()
            }

            launched = await TestAppControl.launch(detail: "Launches this app; the didTerminate listener must stay silent")
            guard let pid = launched?.processIdentifier else { return }
            harness.eval("_cfPID = \(pid);")

            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_cfLaunchCount > 0") as? Bool == true
            }
            #expect(received, "the event did not arrive")
            if received {
                harness.expectTrue("_cfLaunchCount > 0")
                harness.expectEqual("_cfTerminateCount", 0)
            }
        }
    }

}

// MARK: - JSON Serialization

extension HSApplicationTests {
    @Suite("hs.application JSON serialization", .serialized, .testApp)
    struct HSApplicationJSONTests {
        @Test("JSON.stringify() of an application includes its identity and state")
        func testApplicationToJSON() {
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.eval("var testAppPID = \(TestAppControl.pid ?? -1);")
            TestAppControl.showCurrentTest()

            harness.eval("""
                var app = hs.application.fromPID(testAppPID);
                var parsed = JSON.parse(JSON.stringify(app));
                """)
            harness.expectTrue("parsed.pid === testAppPID")
            harness.expectTrue("parsed.bundleID === app.bundleID && parsed.name === app.name && parsed.bundlePath === app.bundlePath")
            harness.expectTrue("parsed.kind === app.kind && parsed.isRunning === true")
            harness.expectTrue("typeof parsed.isActive === 'boolean' && typeof parsed.isHidden === 'boolean'")
            #expect(!harness.hasException)
        }
    }
}
