//
//  HSDockIconIntegrationTests.swift
//  Hammerspoon 2Tests
//

import AppKit
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.dockicon tests")
@MainActor
struct HSDockIconTests {

    private static func makeHarness() -> (JSTestHarness, HSDockIconModule) {
        let harness = JSTestHarness()
        harness.loadModule(HSDockIconModule.self, as: "dockicon")
        let module = harness.evalValue("hs.dockicon")?.toObjectOf(HSDockIconModule.self) as! HSDockIconModule
        return (harness, module)
    }

    // MARK: - Suite 1: API structure

    @Suite("hs.dockicon API structure tests")
    @MainActor
    struct HSDockIconStructureTests {

        @Test("hs.dockicon is an object")
        func testModuleIsObject() {
            let (harness, _) = makeHarness()
            #expect(harness.evalTypeOf("hs.dockicon") == "object")
        }

        @Test("setMenu is a function")
        func testSetMenuIsFunction() {
            let (harness, _) = makeHarness()
            #expect(harness.evalTypeOf("hs.dockicon.setMenu") == "function")
        }

        @Test("setMenu with an unsupported value doesn't throw, and sets no menu")
        func testSetMenuRejectsOtherValues() {
            let (harness, module) = makeHarness()
            harness.eval("hs.dockicon.setMenu('nope')")
            #expect(!harness.hasException)
            #expect(module.makeDockMenu() == nil)
        }
    }

    // MARK: - Suite 2: Menu building

    @Suite("hs.dockicon menu tests")
    @MainActor
    struct HSDockIconMenuTests {

        @Test("There are no extra items until a menu is set")
        func testNoMenuByDefault() {
            let (_, module) = makeHarness()
            #expect(module.makeDockMenu() == nil)
        }

        @Test("An array menu builds items, separators and submenus")
        func testStaticMenu() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                hs.dockicon.setMenu([
                    { title: 'A', checked: true },
                    { title: '-' },
                    { title: 'B', disabled: true },
                    { title: 'Sub', menu: [{ title: 'C' }] },
                    { notATitle: true },
                ])
            """)
            #expect(!harness.hasException)
            let menu = try #require(module.makeDockMenu())
            #expect(menu.items.map(\.title) == ["A", "", "B", "Sub"])
            #expect(menu.items[0].state == .on)
            #expect(menu.items[1].isSeparatorItem)
            #expect(menu.items[2].isEnabled == false)
            #expect(menu.items[3].submenu?.items.map(\.title) == ["C"])
        }

        @Test("Choosing an entry of an array menu calls its function, every time the menu opens")
        func testStaticMenuCallsFunction() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var chosen = []
                hs.dockicon.setMenu([{ title: 'A', fn: () => chosen.push('A') }, { title: 'B', fn: () => chosen.push('B') }])
            """)
            try #require(module.makeDockMenu()).performActionForItem(at: 1)
            try #require(module.makeDockMenu()).performActionForItem(at: 0)
            #expect(harness.evalString("chosen.join(',')") == "B,A")
            #expect(!harness.hasException)
        }

        @Test("A menu function is called each time the menu opens, with the modifiers")
        func testDynamicMenu() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var opened = 0
                var chosen = []
                var receivedModifiers = null
                hs.dockicon.setMenu((modifiers) => {
                    receivedModifiers = modifiers
                    opened++
                    return [{ title: 'Open ' + opened, fn: () => chosen.push(opened) }]
                })
            """)
            let first = try #require(module.makeDockMenu())
            #expect(first.items.map(\.title) == ["Open 1"])
            harness.expectTrue("Array.isArray(receivedModifiers)")

            let second = try #require(module.makeDockMenu())
            #expect(second.items.map(\.title) == ["Open 2"])
            second.performActionForItem(at: 0)
            #expect(harness.evalString("chosen.join(',')") == "2")
            #expect(!harness.hasException)
        }

        @Test("A menu function that doesn't return an array gives no extra items")
        func testDynamicMenuBadReturn() {
            let (harness, module) = makeHarness()
            harness.eval("hs.dockicon.setMenu(() => 'nope')")
            #expect(module.makeDockMenu() == nil)
            harness.eval("hs.dockicon.setMenu(() => { throw new Error('boom') })")
            #expect(module.makeDockMenu() == nil)
        }

        @Test("Setting null removes the menu and disconnects its functions")
        func testSetMenuNull() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var chosen = []
                hs.dockicon.setMenu([{ title: 'A', fn: () => chosen.push('A') }])
            """)
            let menu = try #require(module.makeDockMenu())
            harness.eval("hs.dockicon.setMenu(null)")
            #expect(module.makeDockMenu() == nil)
            menu.performActionForItem(at: 0)
            #expect(harness.evalInt("chosen.length") == 0)
        }

        @Test("Setting a menu from inside a menu entry uses the menu set last")
        func testSetMenuWhileReadingEntries() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var chosen = []
                hs.dockicon.setMenu([
                    { get title() { hs.dockicon.setMenu([{ title: 'Inner', fn: () => chosen.push('inner') }]); return 'Outer' },
                      fn: () => chosen.push('outer') },
                ])
            """)
            let menu = try #require(module.makeDockMenu())
            #expect(menu.items.map(\.title) == ["Inner"])
            menu.performActionForItem(at: 0)
            #expect(harness.evalString("chosen.join(',')") == "inner")
            #expect(!harness.hasException)
        }

        @Test("An array menu set from inside a menu function replaces it straight away, whatever the function returns",
              arguments: ["[{ title: 'Old', fn: () => chosen.push('old') }]", "undefined", "'nope'"])
        func testSetMenuFromMenuFunction(returnValue: String) throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var chosen = []
                hs.dockicon.setMenu(() => {
                    hs.dockicon.setMenu([{ title: 'Replacement', fn: () => chosen.push('replacement') }])
                    return \(returnValue)
                })
            """)
            let menu = try #require(module.makeDockMenu())
            #expect(menu.items.map(\.title) == ["Replacement"])
            menu.performActionForItem(at: 0)
            #expect(harness.evalString("chosen.join(',')") == "replacement")
            #expect(!harness.hasException)
        }

        @Test("Shutting down removes the menu and disconnects its functions")
        func testShutdown() throws {
            let (harness, module) = makeHarness()
            harness.eval("""
                var chosen = []
                hs.dockicon.setMenu(() => [{ title: 'A', fn: () => chosen.push('A') }])
            """)
            let menu = try #require(module.makeDockMenu())
            module.shutdown()
            #expect(module.makeDockMenu() == nil)
            menu.performActionForItem(at: 0)
            #expect(harness.evalInt("chosen.length") == 0)
        }
    }

    // MARK: - Memory Leak Tests

    @Test("The module and its menu are released after shutdown")
    func testModuleDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let (harness, module) = Self.makeHarness()
            harness.eval("hs.dockicon.setMenu(() => [{ title: 'Leak test', fn: function() {} }])")
            if let menu = module.makeDockMenu() {
                tracker.track(menu)
            }
            tracker.track(module)
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
