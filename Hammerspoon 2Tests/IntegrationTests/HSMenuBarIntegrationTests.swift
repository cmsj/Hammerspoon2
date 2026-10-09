//
//  HSMenuBarIntegrationTests.swift
//  Hammerspoon 2Tests
//

import AppKit
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
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar") == "object")
        }

        @Test("create is a function")
        func testCreateIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create") == "function")
        }

        @Test("create(true) returns an object")
        func testCreateReturnsObject() {
            let harness = makeHarness()
            harness.eval("var item = hs.menubar.create(true)")
            #expect(harness.evalTypeOf("item") == "object")
            #expect(!harness.hasException)
        }

        @Test("HSMenuBarItem.typeName is HSMenuBarItem")
        func testTypeName() {
            makeHarness().expectEqual("hs.menubar.create(true).typeName", "HSMenuBarItem")
        }

        @Test("setIcon is a function")
        func testSetIconIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).setIcon") == "function")
        }

        @Test("setClickCallback is a function")
        func testSetClickCallbackIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).setClickCallback") == "function")
        }

        @Test("show is a function")
        func testShowIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).show") == "function")
        }

        @Test("hide is a function")
        func testHideIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).hide") == "function")
        }

        @Test("isVisible is a function")
        func testIsVisibleIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).isVisible") == "function")
        }

        @Test("destroy is a function")
        func testDestroyIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).destroy") == "function")
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

        @Test("popUpMenu is a function")
        func testPopUpMenuIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.menubar.create(true).popUpMenu") == "function")
        }

        @Test("popUpMenu with a non-array does not throw")
        func testPopUpMenuRejectsNonArray() {
            let harness = makeHarness()
            harness.eval("hs.menubar.create(true).popUpMenu('nope')")
            #expect(!harness.hasException)
        }

        @Test("setClickCallback does not throw")
        func testSetClickCallbackDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("hs.menubar.create(true).setClickCallback(function() {})")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2: Click and menu arguments

    @Suite("hs.menubar click and menu argument tests")
    @MainActor
    struct HSMenuBarArgumentTests {

        private func mouseEvent(_ type: NSEvent.EventType, buttonNumber: Int = 0,
                                modifiers: NSEvent.ModifierFlags = [], windowNumber: Int = 0) throws -> NSEvent {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 5, y: 5), modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            // mouseEvent(with:...) always carries button number 0; real right/other clicks don't.
            guard buttonNumber != 0 else { return event }
            let cgEvent = try #require(event.cgEvent)
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            return try #require(NSEvent(cgEvent: cgEvent))
        }

        @Test("Each mouse button is named correctly", arguments: [
            (NSEvent.EventType.leftMouseUp, 0, NSEvent.ModifierFlags(), "left"),
            (.leftMouseUp, 0, NSEvent.ModifierFlags.control, "right"),
            (.leftMouseUp, 0, NSEvent.ModifierFlags.command, "left"),
            (.rightMouseUp, 1, NSEvent.ModifierFlags(), "right"),
            (.otherMouseUp, 2, NSEvent.ModifierFlags(), "middle"),
            (.otherMouseUp, 3, NSEvent.ModifierFlags(), "button4"),
            (.otherMouseUp, 4, NSEvent.ModifierFlags(), "button5"),
        ])
        func testButtonNames(type: NSEvent.EventType, buttonNumber: Int,
                             modifiers: NSEvent.ModifierFlags, expected: String) throws {
            let event = try mouseEvent(type, buttonNumber: buttonNumber, modifiers: modifiers)
            #expect(HSMenuBarItem.buttonName(for: event) == expected)
        }

        @Test("Modifiers are named as hs.eventtap names them")
        func testModifierNames() throws {
            let event = try mouseEvent(.leftMouseUp, modifiers: [.command, .option])
            let names = HSMenuBarItem.modifierNames(for: event)
            #expect(names.contains("cmd"))
            #expect(names.contains("alt"))
            #expect(!names.contains("shift"))
        }

        @Test("A dynamic menu function receives the modifiers as an array")
        func testMenuFunctionReceivesModifiers() throws {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            harness.eval("""
                var received = null
                var item = hs.menubar.create(true)
                item.setMenu((modifiers) => { received = modifiers; return [{ title: 'A' }, { title: 'B' }] })
            """)
            let item = try #require(harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem)
            let menu = NSMenu()
            item.populateDynamicMenu(menu)
            #expect(menu.items.map(\.title) == ["A", "B"])
            harness.expectTrue("Array.isArray(received)")
            #expect(!harness.hasException)
            item.destroy()
        }
    }

    // MARK: - Suite 3: Menu building and pop-up menus

    @Suite("hs.menubar menu building tests")
    @MainActor
    struct HSMenuBarMenuBuildingTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            return harness
        }

        private func item(in harness: JSTestHarness) throws -> HSMenuBarItem {
            try #require(harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem)
        }

        /// Chooses the menu entry at `index`, as AppKit does when the user picks it.
        private func choose(_ index: Int, in menu: NSMenu) {
            menu.performActionForItem(at: index)
        }

        @Test("Choosing a pop-up menu entry calls its function")
        func testPopUpMenuEntryCallsFunction() throws {
            let harness = makeHarness()
            harness.eval("""
                var chosen = []
                var item = hs.menubar.create(true)
            """)
            let item = try item(in: harness)
            defer { item.destroy() }
            let entries = try #require(harness.evalValue("""
                [{ title: 'A', fn: () => chosen.push('A') }, { title: '-' }, { title: 'B', fn: () => chosen.push('B') }]
            """))
            let menu = try #require(item.makePopUpMenu(from: entries))
            #expect(menu.items.count == 3)
            choose(2, in: menu)
            choose(0, in: menu)
            #expect(harness.evalString("chosen.join(',')") == "B,A")
            #expect(!harness.hasException)
        }

        @Test("A pop-up menu doesn't disturb the attached menu's functions")
        func testPopUpMenuKeepsAttachedMenuFunctions() throws {
            let harness = makeHarness()
            harness.eval("""
                var chosen = []
                var item = hs.menubar.create(true)
                item.setMenu([{ title: 'Attached', fn: () => chosen.push('attached') }])
            """)
            let item = try item(in: harness)
            defer { item.destroy() }
            let attached = try #require(item.attachedMenu)
            for _ in 0..<2 {
                let entries = try #require(harness.evalValue("[{ title: 'Popped', fn: () => chosen.push('popped') }]"))
                choose(0, in: try #require(item.makePopUpMenu(from: entries)))
            }
            choose(0, in: attached)
            #expect(harness.evalString("chosen.join(',')") == "popped,popped,attached")
        }

        @Test("Destroying the item disconnects its pop-up menu's functions")
        func testDestroyDisconnectsPopUpMenu() throws {
            let harness = makeHarness()
            harness.eval("""
                var chosen = []
                var item = hs.menubar.create(true)
            """)
            let item = try item(in: harness)
            let entries = try #require(harness.evalValue("[{ title: 'A', fn: () => chosen.push('A') }]"))
            let menu = try #require(item.makePopUpMenu(from: entries))
            item.destroy()
            choose(0, in: menu)
            #expect(harness.evalInt("chosen.length") == 0)
        }

        /// A menu entry's properties are read with JavaScript, which can do anything to the item meanwhile.
        @Test("Destroying the item from inside a menu entry doesn't crash", arguments: ["static", "dynamic", "popUp"])
        func testDestroyWhileReadingEntries(kind: String) throws {
            let harness = makeHarness()
            harness.eval("""
                var chosen = []
                var item = hs.menubar.create(true)
                function entries() {
                    return [
                        { title: 'A', fn: () => chosen.push('A') },
                        { get title() { item.destroy(); return 'B' }, fn: () => chosen.push('B') },
                    ]
                }
            """)
            let item = try item(in: harness)
            switch kind {
            case "static":
                harness.eval("item.setMenu(entries())")
                #expect(item.attachedMenu == nil)
            case "dynamic":
                harness.eval("item.setMenu(entries)")
                item.populateDynamicMenu(NSMenu())
            default:
                #expect(item.makePopUpMenu(from: try #require(harness.evalValue("entries()"))) == nil)
            }
            #expect(!harness.hasException)
        }

        @Test("Setting another menu from inside a menu entry keeps the outer menu's functions")
        func testSetMenuWhileReadingEntries() throws {
            let harness = makeHarness()
            harness.eval("""
                var chosen = []
                var item = hs.menubar.create(true)
                item.setMenu([
                    { get title() { item.setMenu([{ title: 'Inner', fn: () => chosen.push('inner') }]); return 'Outer' },
                      fn: () => chosen.push('outer') },
                ])
            """)
            let item = try item(in: harness)
            defer { item.destroy() }
            let menu = try #require(item.attachedMenu)
            #expect(menu.items.map(\.title) == ["Outer"])
            choose(0, in: menu)
            #expect(harness.evalString("chosen.join(',')") == "outer")
        }
    }

    // MARK: - Suite 4: End-to-end click delivery

    /// Sends real mouse events to a visible status item's button, so AppKit's own button tracking decides
    /// which clicks reach the callback.
    @Suite("hs.menubar click delivery tests", .serialized)
    @MainActor
    struct HSMenuBarClickDeliveryTests {

        private func event(_ type: NSEvent.EventType, buttonNumber: Int, modifiers: NSEvent.ModifierFlags,
                           window: NSWindow, location: NSPoint) throws -> NSEvent {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            guard buttonNumber != 0 else { return event }
            let cgEvent = try #require(event.cgEvent)
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            return try #require(NSEvent(cgEvent: cgEvent))
        }

        private func click(_ button: NSStatusBarButton, down: NSEvent.EventType, up: NSEvent.EventType,
                           buttonNumber: Int, modifiers: NSEvent.ModifierFlags = []) async throws {
            let window = try #require(button.window)
            let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            // The button's mouse-down tracking loop pulls the mouse-up from the queue, so queue it first.
            NSApp.postEvent(try event(up, buttonNumber: buttonNumber, modifiers: modifiers,
                                      window: window, location: location), atStart: false)
            window.sendEvent(try event(down, buttonNumber: buttonNumber, modifiers: modifiers,
                                       window: window, location: location))
            try await Task.sleep(for: .milliseconds(50))
        }

        @Test("Left, Ctrl and right clicks all reach the click callback")
        func testClicksReachCallback() async throws {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            harness.eval("""
                var clicks = []
                var item = hs.menubar.create()
                item.title = 'HS2 Click Test'
                item.setClickCallback((button, modifiers) => clicks.push(button + ':' + modifiers.includes('ctrl')))
            """)
            let item = try #require(harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem)
            defer { item.destroy() }
            let button = try #require(item.button)
            // Let the new status item settle into the menu bar before clicking it.
            try await Task.sleep(for: .milliseconds(250))

            try await click(button, down: .leftMouseDown, up: .leftMouseUp, buttonNumber: 0)
            try await click(button, down: .leftMouseDown, up: .leftMouseUp, buttonNumber: 0, modifiers: .control)
            try await click(button, down: .rightMouseDown, up: .rightMouseUp, buttonNumber: 1)

            #expect(harness.evalString("clicks.join(',')") == "left:false,right:true,right:false")
            #expect(!harness.hasException)
        }

        /// Middle and other button events never reach a status item's window: the item sees them through event
        /// monitors instead, so these feed it events the way its monitors do.
        private func otherButtonEvent(_ type: CGEventType, button: Int, at location: CGPoint) throws -> NSEvent {
            let mouseButton = try #require(CGMouseButton(rawValue: UInt32(button)))
            let cgEvent = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                                               mouseCursorPosition: location, mouseButton: mouseButton))
            return try #require(NSEvent(cgEvent: cgEvent))
        }

        @Test("Middle and other button clicks over the item reach the click callback")
        func testOtherButtonClicks() async throws {
            let harness = JSTestHarness()
            harness.loadModule(HSMenuBarModule.self, as: "menubar")
            harness.eval("""
                var clicks = []
                var item = hs.menubar.create()
                item.title = 'HS2 Other Click Test'
                item.setClickCallback((button) => clicks.push(button))
            """)
            let item = try #require(harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem)
            defer { item.destroy() }
            try await Task.sleep(for: .milliseconds(250))
            let frame = try #require(item.itemScreenFrame())
            let inside = CGPoint(x: frame.midX, y: frame.midY)
            let outside = CGPoint(x: frame.midX, y: frame.maxY + 200)

            for button in [2, 3] {
                item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseDown, button: button, at: inside))
                item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseUp, button: button, at: inside))
            }
            // Pressed elsewhere and released over the item, and the reverse: neither is a click on the item
            item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseDown, button: 2, at: outside))
            item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseUp, button: 2, at: inside))
            item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseDown, button: 2, at: inside))
            item.handleOtherButtonEvent(try otherButtonEvent(.otherMouseUp, button: 2, at: outside))

            #expect(harness.evalString("clicks.join(',')") == "middle,button4")
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
                item.title = 'HS2 Leak Test'
                item.setClickCallback(function() {})
                item.setMenu(() => [{ title: 'Leak test', fn: function() {} }])
                item.show()
                var popUpEntries = [{ title: 'Pop-up leak test', fn: function() {} }]
            """)
            if let obj = harness.evalValue("item")?.toObjectOf(HSMenuBarItem.self) as? HSMenuBarItem {
                obj.populateDynamicMenu(NSMenu())
                if let entries = harness.evalValue("popUpEntries") {
                    _ = obj.makePopUpMenu(from: entries)
                }
                tracker.track(obj)
            }
            harness.eval("item = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
