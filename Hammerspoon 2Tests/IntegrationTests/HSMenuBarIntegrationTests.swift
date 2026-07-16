//
//  HSMenuBarIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.menubar tests")
struct HSMenuBarTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.menubar API structure tests")
    struct HSMenuBarStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            return harness
        }

        @Test("hs.menubar is an object")
        func testModuleIsObject() {
            makeHarness().expectTrue("typeof hs.menubar === 'object'")
        }

        @Test("create is a function")
        func testCreateIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create === 'function'")
        }

        @Test("create(true) returns an object")
        func testCreateReturnsObject() {
            let harness = makeHarness()
            harness.eval("var item = hs.menubar.create(true)")
            harness.expectTrue("typeof item === 'object'")
            #expect(!harness.hasException)
        }

        @Test("HSMenuBarItem.typeName is HSMenuBarItem")
        func testTypeName() {
            makeHarness().expectEqual("hs.menubar.create(true).typeName", "HSMenuBarItem")
        }

        @Test("setTitle is a function")
        func testSetTitleIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).setTitle === 'function'")
        }

        @Test("setClickCallback is a function")
        func testSetClickCallbackIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).setClickCallback === 'function'")
        }

        @Test("show is a function")
        func testShowIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).show === 'function'")
        }

        @Test("hide is a function")
        func testHideIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).hide === 'function'")
        }

        @Test("isVisible is a function")
        func testIsVisibleIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).isVisible === 'function'")
        }

        @Test("destroy is a function")
        func testDestroyIsFunction() {
            makeHarness().expectTrue("typeof hs.menubar.create(true).destroy === 'function'")
        }

        @Test("title property is gettable and settable")
        func testTitleRoundtrip() {
            let harness = makeHarness()
            harness.eval("var item = hs.menubar.create(true); item.title = 'Hello'")
            harness.expectEqual("item.title", "Hello")
            #expect(!harness.hasException)
        }

        @Test("create(true) starts hidden — isVisible() returns false")
        func testCreateHiddenIsNotVisible() {
            let harness = makeHarness()
            harness.eval("var item = hs.menubar.create(true)")
            harness.expectTrue("item.isVisible() === false")
            #expect(!harness.hasException)
        }

        @Test("show() makes item visible — isVisible() returns true")
        func testShowMakesVisible() {
            let harness = makeHarness()
            harness.eval("var item = hs.menubar.create(true); item.show()")
            harness.expectTrue("item.isVisible() === true")
            harness.eval("item.destroy()")
            #expect(!harness.hasException)
        }

        @Test("destroy() does not throw")
        func testDestroyDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.menubar.create(true).destroy()")
            #expect(!harness.hasException)
        }

        @Test("setClickCallback does not throw")
        func testSetClickCallbackDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.menubar.create(true).setClickCallback(function() {})")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory Leak Tests

    @Test("Active HSMenuBarItem is released after shutdown")
    func testMenuBarItemDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            // Create a hidden item, set title and click callback (exercising JSCallback),
            // then show() to make it an active NSStatusItem in the menu bar.
            // shutdown() → destroy() removes the NSStatusItem and detaches all callbacks.
            harness.eval("""
                var item = hs.menubar.create(true)
                item.setTitle('HS2 Leak Test')
                item.setClickCallback(function() {})
                item.show()
            """)
            if let obj = harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem {
                tracker.track(obj)
            }
            harness.eval("item = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
