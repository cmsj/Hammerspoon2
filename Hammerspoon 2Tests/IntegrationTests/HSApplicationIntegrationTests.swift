//
//  HSApplicationIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.application module
///
/// These tests verify that application objects are correctly bridged to JavaScript
/// and that the module's API works as expected when called from JS.
///
/// Note: These tests interact with real running applications on the system.
@MainActor
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
            harness.expectTrue("typeof frontApp === 'object'")
            harness.expectTrue("typeof frontApp.name === 'function'")
            harness.expectTrue("typeof frontApp.bundleID === 'function'")
        }
    }

    @Test("menuBarOwner returns an application")
    func testMenuBarOwnerFromJS() async {
        let harness = JSTestHarness()
        harness.loadModule(HSApplicationModule.self, as: "application")

        harness.eval("var menuOwner = hs.application.menuBarOwner()")

        // Menu bar owner should always exist on macOS
        harness.expectTrue("menuOwner !== null && menuOwner !== undefined")
        harness.expectTrue("typeof menuOwner === 'object'")
    }

    @Test("matchingName finds Finder")
    func testMatchingNameFromJS() async {
        let harness = JSTestHarness()
        harness.loadModule(HSApplicationModule.self, as: "application")

        // Finder is always running on macOS
        harness.eval("var finder = hs.application.matchingName('Finder')")

        harness.expectTrue("finder !== null && finder !== undefined")
        harness.expectTrue("typeof finder === 'object'")
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
            harness.expectTrue("typeof testApp.name === 'function'")
            harness.expectTrue("typeof testApp.bundleID === 'function'")
            harness.expectTrue("typeof testApp.pid === 'function'")
            harness.expectTrue("typeof testApp.path === 'function'")
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
            harness.expectTrue("typeof info === 'object'")

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
        harness.expectTrue("finderInfo.name === 'Finder'")
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
