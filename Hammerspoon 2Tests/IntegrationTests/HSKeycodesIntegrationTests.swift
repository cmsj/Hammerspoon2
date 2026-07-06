//
//  HSKeycodesIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.keycodes tests")
struct HSKeycodesTests {

    // MARK: - API structure

    @Suite("hs.keycodes API structure tests")
    struct HSKeycodesStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeycodesModule.self, as: "keycodes")
            return harness
        }

        @Test("map is an object")
        func testMapIsObject() {
            makeHarness().expectTrue("typeof hs.keycodes.map === 'object' && hs.keycodes.map !== null")
        }

        @Test("currentLayout is a function")
        func testCurrentLayoutIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.currentLayout === 'function'")
        }

        @Test("currentMethod is a function")
        func testCurrentMethodIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.currentMethod === 'function'")
        }

        @Test("currentSourceID is a function")
        func testCurrentSourceIDIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.currentSourceID === 'function'")
        }

        @Test("layouts is a function")
        func testLayoutsIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.layouts === 'function'")
        }

        @Test("methods is a function")
        func testMethodsIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.methods === 'function'")
        }

        @Test("setLayout is a function")
        func testSetLayoutIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.setLayout === 'function'")
        }

        @Test("setMethod is a function")
        func testSetMethodIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.setMethod === 'function'")
        }

        @Test("setSourceID is a function")
        func testSetSourceIDIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.setSourceID === 'function'")
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.addWatcher === 'function'")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.keycodes.removeWatcher === 'function'")
        }

        @Test("_watcherEmitter is initialized by hs.keycodes.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.keycodes._watcherEmitter !== null && hs.keycodes._watcherEmitter !== undefined"
            )
        }
    }

    // MARK: - Key map content

    @Suite("hs.keycodes map tests")
    struct HSKeycodesMapTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeycodesModule.self, as: "keycodes")
            return harness
        }

        @Test("map contains named special keys")
        func testMapContainsSpecialKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['return'] === 36")
            harness.expectTrue("hs.keycodes.map['tab'] === 48")
            harness.expectTrue("hs.keycodes.map['space'] === 49")
            harness.expectTrue("hs.keycodes.map['delete'] === 51")
            harness.expectTrue("hs.keycodes.map['escape'] === 53")
            harness.expectTrue("hs.keycodes.map['capslock'] === 57")
            harness.expectTrue("hs.keycodes.map['forwarddelete'] === 117")
            harness.expectTrue("hs.keycodes.map['help'] === 114")
            #expect(!harness.hasException)
        }

        @Test("map contains navigation keys")
        func testMapContainsNavigationKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['home'] === 115")
            harness.expectTrue("hs.keycodes.map['end'] === 119")
            harness.expectTrue("hs.keycodes.map['pageup'] === 116")
            harness.expectTrue("hs.keycodes.map['pagedown'] === 121")
            harness.expectTrue("hs.keycodes.map['left'] === 123")
            harness.expectTrue("hs.keycodes.map['right'] === 124")
            harness.expectTrue("hs.keycodes.map['down'] === 125")
            harness.expectTrue("hs.keycodes.map['up'] === 126")
            #expect(!harness.hasException)
        }

        @Test("map contains function keys f1-f20")
        func testMapContainsFunctionKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['f1'] === 122")
            harness.expectTrue("hs.keycodes.map['f2'] === 120")
            harness.expectTrue("hs.keycodes.map['f3'] === 99")
            harness.expectTrue("hs.keycodes.map['f12'] === 111")
            harness.expectTrue("hs.keycodes.map['f20'] === 90")
            #expect(!harness.hasException)
        }

        @Test("map contains modifier keys")
        func testMapContainsModifierKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['cmd'] === 55")
            harness.expectTrue("hs.keycodes.map['shift'] === 56")
            harness.expectTrue("hs.keycodes.map['alt'] === 58")
            harness.expectTrue("hs.keycodes.map['ctrl'] === 59")
            harness.expectTrue("hs.keycodes.map['fn'] === 63")
            harness.expectTrue("hs.keycodes.map['rightshift'] === 60")
            harness.expectTrue("hs.keycodes.map['rightalt'] === 61")
            harness.expectTrue("hs.keycodes.map['rightctrl'] === 62")
            #expect(!harness.hasException)
        }

        @Test("map contains numpad keys")
        func testMapContainsNumpadKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['pad0'] === 82")
            harness.expectTrue("hs.keycodes.map['pad9'] === 92")
            harness.expectTrue("hs.keycodes.map['padenter'] === 76")
            harness.expectTrue("hs.keycodes.map['pad+'] === 69")
            harness.expectTrue("hs.keycodes.map['pad-'] === 78")
            harness.expectTrue("hs.keycodes.map['pad*'] === 67")
            harness.expectTrue("hs.keycodes.map['pad/'] === 75")
            harness.expectTrue("hs.keycodes.map['pad.'] === 65")
            harness.expectTrue("hs.keycodes.map['padclear'] === 71")
            #expect(!harness.hasException)
        }

        @Test("map contains media keys")
        func testMapContainsMediaKeys() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.map['volup'] === 72")
            harness.expectTrue("hs.keycodes.map['voldown'] === 73")
            harness.expectTrue("hs.keycodes.map['mute'] === 74")
            #expect(!harness.hasException)
        }

        @Test("map is bidirectional for named keys")
        func testMapIsBidirectional() {
            let harness = makeHarness()
            // return → 36, so map["36"] should be "return"
            harness.expectTrue("hs.keycodes.map['36'] === 'return'")
            harness.expectTrue("hs.keycodes.map['48'] === 'tab'")
            harness.expectTrue("hs.keycodes.map['122'] === 'f1'")
            harness.expectTrue("hs.keycodes.map['55'] === 'cmd'")
            #expect(!harness.hasException)
        }

        @Test("map contains character key entries")
        func testMapContainsCharacterKeys() {
            let harness = makeHarness()
            // On any layout there should be entries for letter keys.
            // We can't assert specific values (layout-dependent), but entries must exist.
            harness.expectTrue("Object.keys(hs.keycodes.map).length > 100")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Current source queries

    @Suite("hs.keycodes source query tests")
    struct HSKeycodesSourceQueryTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeycodesModule.self, as: "keycodes")
            return harness
        }

        @Test("currentLayout returns a non-empty string")
        func testCurrentLayoutReturnsString() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.keycodes.currentLayout() === 'string'")
            harness.expectTrue("hs.keycodes.currentLayout().length > 0")
            #expect(!harness.hasException)
        }

        @Test("currentSourceID returns a reverse-DNS string")
        func testCurrentSourceIDReturnsDNSString() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.keycodes.currentSourceID() === 'string'")
            harness.expectTrue("hs.keycodes.currentSourceID().includes('.')")
            #expect(!harness.hasException)
        }

        @Test("currentMethod returns string or null without throwing")
        func testCurrentMethodReturnsStringOrNull() {
            let harness = makeHarness()
            harness.eval("var m = hs.keycodes.currentMethod()")
            // currentMethod() returns String? — nil bridges to null (or undefined in
            // some test contexts); use loose equality so both are accepted.
            harness.expectTrue("m == null || typeof m === 'string'")
            #expect(!harness.hasException)
        }

        @Test("layouts returns a non-empty array of strings")
        func testLayoutsReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.keycodes.layouts())")
            harness.expectTrue("hs.keycodes.layouts().length > 0")
            harness.expectTrue("typeof hs.keycodes.layouts()[0] === 'string'")
            #expect(!harness.hasException)
        }

        @Test("methods returns an array without throwing")
        func testMethodsReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.keycodes.methods())")
            #expect(!harness.hasException)
        }

        @Test("currentLayout is included in layouts()")
        func testCurrentLayoutInLayouts() {
            let harness = makeHarness()
            harness.expectTrue("hs.keycodes.layouts().includes(hs.keycodes.currentLayout())")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Source switching

    @Suite("hs.keycodes source switching tests")
    struct HSKeycodesSourceSwitchingTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeycodesModule.self, as: "keycodes")
            return harness
        }

        @Test("setLayout with invalid name returns false")
        func testSetLayoutInvalidName() {
            let harness = makeHarness()
            harness.expectFalse("hs.keycodes.setLayout('NonExistentLayout_XYZ_123')")
            #expect(!harness.hasException)
        }

        @Test("setMethod with invalid name returns false")
        func testSetMethodInvalidName() {
            let harness = makeHarness()
            harness.expectFalse("hs.keycodes.setMethod('NonExistentMethod_XYZ_123')")
            #expect(!harness.hasException)
        }

        @Test("setSourceID with invalid ID returns false")
        func testSetSourceIDInvalid() {
            let harness = makeHarness()
            harness.expectFalse("hs.keycodes.setSourceID('com.invalid.source.id.xyz')")
            #expect(!harness.hasException)
        }

        @Test("setLayout with current layout returns true")
        func testSetLayoutCurrentLayout() {
            let harness = makeHarness()
            // Setting to the already-active layout should succeed
            harness.expectTrue("""
                (function() {
                    var layout = hs.keycodes.currentLayout();
                    if (!layout) return false;
                    return hs.keycodes.setLayout(layout);
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("setSourceID with current sourceID returns true")
        func testSetSourceIDCurrent() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var id = hs.keycodes.currentSourceID();
                    if (!id) return false;
                    return hs.keycodes.setSourceID(id);
                })()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Static key table consistency

    @Suite("hs.keycodes static table tests")
    struct HSKeycodesStaticTableTests {

        @Test("namedKeys has no duplicate names")
        func testNoduplicateNames() {
            let names = HSKeycodesModule.namedKeys.map { $0.0 }
            let uniqueNames = Set(names)
            #expect(names.count == uniqueNames.count, "Duplicate names found in namedKeys")
        }

        @Test("namedKeys has no duplicate keycodes")
        func testNoDuplicateKeycodes() {
            let codes = HSKeycodesModule.namedKeys.map { $0.1 }
            let uniqueCodes = Set(codes)
            #expect(codes.count == uniqueCodes.count, "Duplicate keycodes found in namedKeys")
        }

        @Test("ansiUSCharacterMap has no duplicate names")
        func testAnsiNoduplicateNames() {
            let names = HSKeycodesModule.ansiUSCharacterMap.map { $0.0 }
            let uniqueNames = Set(names)
            #expect(names.count == uniqueNames.count, "Duplicate names found in ansiUSCharacterMap")
        }

        @Test("ansiUSCharacterMap has no duplicate keycodes")
        func testAnsiNoDuplicateCodes() {
            let codes = HSKeycodesModule.ansiUSCharacterMap.map { $0.1 }
            let uniqueCodes = Set(codes)
            #expect(codes.count == uniqueCodes.count, "Duplicate codes found in ansiUSCharacterMap")
        }

        @Test("buildKeyMap produces bidirectional entries for all named keys")
        func testBuildKeyMapBidirectional() {
            let module = HSKeycodesModule(engineID: UUID())
            let keyMap = module.buildKeyMap()

            for (name, code) in HSKeycodesModule.namedKeys {
                #expect(keyMap[name] as? Int == code,
                        "Expected map[\"\(name)\"] == \(code)")
                #expect(keyMap[String(code)] as? String == name,
                        "Expected map[\"\(code)\"] == \"\(name)\"")
            }
        }

        @Test("buildKeyMap produces a non-empty map")
        func testBuildKeyMapNonEmpty() {
            let module = HSKeycodesModule(engineID: UUID())
            let keyMap = module.buildKeyMap()
            #expect(keyMap.count > 100, "Key map should contain more than 100 entries")
        }
    }

    // MARK: - Watcher pattern

    @Suite("hs.keycodes watcher tests")
    struct HSKeycodesWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeycodesModule.self, as: "keycodes")
            return harness
        }

        @Test("addWatcher with non-function throws")
        func testAddWatcherNonFunction() {
            let harness = makeHarness()
            harness.eval("hs.keycodes.addWatcher('not a function')")
            harness.expectException()
        }

        @Test("addWatcher and removeWatcher do not throw with a valid function")
        func testAddRemoveWatcherValid() {
            let harness = makeHarness()
            harness.eval("""
                var handler = function() {};
                hs.keycodes.addWatcher(handler);
                hs.keycodes.removeWatcher(handler);
            """)
            #expect(!harness.hasException)
        }

        @Test("registering the same listener twice does not throw")
        func testDuplicateListenerIgnored() {
            let harness = makeHarness()
            harness.eval("""
                var handler = function() {};
                hs.keycodes.addWatcher(handler);
                hs.keycodes.addWatcher(handler);
                hs.keycodes.removeWatcher(handler);
            """)
            #expect(!harness.hasException)
        }
    }
}
