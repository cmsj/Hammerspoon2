//
//  HSUIIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.ui tests", .serialized)
struct HSUITests {

    // MARK: - Suite 1: API structure

    @Suite("hs.ui API structure tests")
    struct HSUIStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("hs.ui is an object")
        func testModuleIsObject() {
            makeHarness().expectTrue("typeof hs.ui === 'object'")
        }

        @Test("window is a function")
        func testWindowIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.window === 'function'")
        }

        @Test("alert is a function")
        func testAlertIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.alert === 'function'")
        }

        @Test("dialog is a function")
        func testDialogIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.dialog === 'function'")
        }

        @Test("textPrompt is a function")
        func testTextPromptIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.textPrompt === 'function'")
        }

        @Test("filePicker is a function")
        func testFilePickerIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.filePicker === 'function'")
        }

        @Test("string is a function")
        func testStringIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.string === 'function'")
        }

        @Test("window() returns an object")
        func testWindowReturnsObject() {
            let harness = makeHarness()
            harness.eval("var w = hs.ui.window({x: 0, y: 0, w: 100, h: 100})")
            harness.expectTrue("typeof w === 'object'")
            #expect(!harness.hasException)
        }

        @Test("HSUIWindow.typeName is HSUIWindow")
        func testWindowTypeName() {
            makeHarness().expectEqual(
                "hs.ui.window({x: 0, y: 0, w: 100, h: 100}).typeName",
                "HSUIWindow"
            )
        }

        @Test("HSUIWindow has show function")
        func testWindowShowIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.window({x:0, y:0, w:100, h:100}).show === 'function'")
        }

        @Test("HSUIWindow has close function")
        func testWindowCloseIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.window({x:0, y:0, w:100, h:100}).close === 'function'")
        }

        @Test("alert() returns an object")
        func testAlertReturnsObject() {
            let harness = makeHarness()
            harness.eval("var a = hs.ui.alert('Test')")
            harness.expectTrue("typeof a === 'object'")
            #expect(!harness.hasException)
        }

        @Test("HSUIAlert.typeName is HSUIAlert")
        func testAlertTypeName() {
            makeHarness().expectEqual("hs.ui.alert('Test').typeName", "HSUIAlert")
        }

        @Test("dialog() returns an object")
        func testDialogReturnsObject() {
            let harness = makeHarness()
            harness.eval("var d = hs.ui.dialog('Test')")
            harness.expectTrue("typeof d === 'object'")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory Leak Tests
    //
    // HSUIWindow, HSUIAlert, and HSUIDialog register themselves in strong dictionaries
    // inside HSUIModule when show() is called, so they stay alive until shutdown()
    // explicitly calls close() and clears those dictionaries.

    @Test("Shown HSUIWindow is released after shutdown")
    func testWindowDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        // autoreleasepool {} (not do {}) ensures JSValues returned by harness.eval()
        // are drained here rather than in the outer test-runner pool. JSValue holds a
        // strong reference to its JSContext, so unreleased JSValues from eval() calls
        // would keep the JSContext alive after the harness goes out of scope, preventing
        // the JSC bridge from releasing HSUIWindow.
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            // show() registers the window in HSUIModule.activeWindows (strong dictionary).
            // Without shutdown(), the window would be held alive by the module even after
            // the JS reference is dropped. shutdown() calls close() on each window and
            // then clears activeWindows, releasing the strong ref.
            // Content is required — show() guards on rootElement being set.
            harness.eval("""
                var w = hs.ui.window({x: 0, y: 0, w: 100, h: 100})
                w.text("HS2 Leak Test").show()
            """)
            if let obj = harness.evalValue("w")?.toObjectOf(HSUIWindow.self) as? HSUIWindow {
                tracker.track(obj)
            }
            harness.eval("w = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks(timeout: 1.0)
    }

    @Test("Shown HSUIAlert is released after shutdown")
    func testAlertDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        // See testWindowDoesNotLeakAfterReload for why autoreleasepool {} is used here.
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            // A 60-second duration prevents auto-dismiss from racing with the shutdown.
            // show() registers the alert in HSUIModule.activeAlerts (strong dictionary);
            // shutdown() calls close() and clears activeAlerts.
            harness.eval("""
                var a = hs.ui.alert('HS2 Leak Test')
                a.duration(60).show()
            """)
            if let obj = harness.evalValue("a")?.toObjectOf(HSUIAlert.self) as? HSUIAlert {
                tracker.track(obj)
            }
            harness.eval("a = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks(timeout: 1.0)
    }

    @Test("Shown HSUIDialog is released after shutdown")
    func testDialogDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        // See testWindowDoesNotLeakAfterReload for why autoreleasepool {} is used here.
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            // show() creates a non-modal NSWindow and registers the dialog in
            // HSUIModule.activeDialogs (strong dictionary); shutdown() calls close()
            // and clears activeDialogs.
            harness.eval("""
                var d = hs.ui.dialog('HS2 Leak Test')
                d.show()
            """)
            if let obj = harness.evalValue("d")?.toObjectOf(HSUIDialog.self) as? HSUIDialog {
                tracker.track(obj)
            }
            harness.eval("d = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks(timeout: 1.0)
    }
}
