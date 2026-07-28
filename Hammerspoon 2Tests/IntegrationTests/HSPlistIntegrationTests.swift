//
//  HSPlistIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Chris Jones on 24/07/2026.
//

import Testing
import JavaScriptCore
import Foundation
@testable import Hammerspoon_2

@Suite("hs.plist tests")
struct HSPlistTests {

    // MARK: - Suite 1: API Structure

    @Suite("hs.plist API structure tests")
    struct HSPlistStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSPlistModule.self, as: "plist")
            return harness
        }

        @Test("fromFile is a function")
        func testFromFileIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.plist.fromFile") == "function")
        }

        @Test("fromString is a function")
        func testFromStringIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.plist.fromString") == "function")
        }

        @Test("toFile is a function")
        func testToFileIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.plist.toFile") == "function")
        }

        @Test("toString is a function")
        func testToStringIsFunction() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.plist.toString") == "function")
        }

        @Test("fromFile with nonexistent path returns null without throwing")
        func testFromFileMissingFileReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.plist.fromFile('/nonexistent/path/to/file.plist')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("fromString with non-plist input returns null without throwing")
        func testFromStringInvalidReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.plist.fromString('this is not a plist')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("toFile to invalid directory returns false without throwing")
        func testToFileInvalidDirectoryReturnsFalse() {
            let harness = makeHarness()
            harness.eval("var r = hs.plist.toFile('/nonexistent/dir/foo.plist', { key: 'val' })")
            #expect(harness.evalBool("r") == false)
            #expect(!harness.hasException)
        }

        @Test("toString returns a non-empty string for a valid object")
        func testToStringReturnsString() {
            let harness = makeHarness()
            harness.eval("var r = hs.plist.toString({ key: 'value' })")
            #expect(harness.evalTypeOf("r") == "string")
            harness.expectTrue("r.length > 0")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2: Read / Write Behaviour

    @Suite("hs.plist read/write tests", .serialized)
    struct HSPlistReadWriteTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSPlistModule.self, as: "plist")
            return harness
        }

        private func tempPath() -> String {
            NSTemporaryDirectory() + "hs_plist_test_\(UUID().uuidString).plist"
        }

        // MARK: XML round-trips

        @Test("string value round-trips through toFile/fromFile (XML)")
        func testStringRoundTripXML() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { greeting: 'hello' })")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            #expect(harness.evalString("data.greeting") == "hello")
            #expect(!harness.hasException)
        }

        @Test("number value round-trips through toFile/fromFile (XML)")
        func testNumberRoundTripXML() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { count: 42, ratio: 3.14 })")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            #expect(harness.evalInt("data.count") == 42)
            harness.expectTrue("Math.abs(data.ratio - 3.14) < 0.001")
            #expect(!harness.hasException)
        }

        @Test("boolean values round-trip through toFile/fromFile (XML)")
        func testBooleanRoundTripXML() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { active: true, disabled: false })")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            #expect(harness.evalBool("data.active") == true)
            #expect(harness.evalBool("data.disabled") == false)
            #expect(!harness.hasException)
        }

        @Test("array value round-trips through toFile/fromFile (XML)")
        func testArrayRoundTripXML() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { items: ['a', 'b', 'c'] })")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            harness.expectTrue("Array.isArray(data.items)")
            #expect(harness.evalInt("data.items.length") == 3)
            #expect(harness.evalString("data.items[0]") == "a")
            #expect(harness.evalString("data.items[2]") == "c")
            #expect(!harness.hasException)
        }

        @Test("nested object round-trips through toFile/fromFile (XML)")
        func testNestedObjectRoundTripXML() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { nested: { x: 1, y: 2 } })")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            #expect(harness.evalTypeOf("data.nested") == "object")
            #expect(harness.evalInt("data.nested.x") == 1)
            #expect(harness.evalInt("data.nested.y") == 2)
            #expect(!harness.hasException)
        }

        @Test("toFile returns true on success")
        func testToFileReturnsTrue() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("var result = hs.plist.toFile('\(path)', { key: 'value' })")
            #expect(harness.evalBool("result") == true)
            #expect(!harness.hasException)
        }

        // MARK: Binary round-trips

        @Test("dictionary round-trips through toFile/fromFile (binary format)")
        func testRoundTripBinary() {
            let path = tempPath()
            defer { try? FileManager.default.removeItem(atPath: path) }

            let harness = makeHarness()
            harness.eval("hs.plist.toFile('\(path)', { name: 'Hammerspoon', version: 2 }, true)")
            harness.eval("var data = hs.plist.fromFile('\(path)')")
            #expect(harness.evalString("data.name") == "Hammerspoon")
            #expect(harness.evalInt("data.version") == 2)
            #expect(!harness.hasException)
        }

        // MARK: toString / fromString

        @Test("toString produces valid XML containing plist markers")
        func testToStringXMLContent() {
            let harness = makeHarness()
            harness.eval("var xml = hs.plist.toString({ key: 'value' })")
            harness.expectTrue("xml.includes('<?xml')")
            harness.expectTrue("xml.includes('<plist')")
            harness.expectTrue("xml.includes('key')")
            harness.expectTrue("xml.includes('value')")
            #expect(!harness.hasException)
        }

        @Test("toString with binary=true produces a base64 string, not XML")
        func testToStringBinaryIsBase64() {
            let harness = makeHarness()
            harness.eval("var b64 = hs.plist.toString({ key: 'value' }, true)")
            #expect(harness.evalTypeOf("b64") == "string")
            harness.expectTrue("b64.length > 0")
            harness.expectFalse("b64.includes('<?xml')")
            #expect(!harness.hasException)
        }

        @Test("round-trip through toString then fromString")
        func testToStringFromStringRoundTrip() {
            let harness = makeHarness()
            harness.eval("""
                var xml = hs.plist.toString({ name: 'Hammerspoon', count: 99, flag: true })
                var data = hs.plist.fromString(xml)
            """)
            harness.expectTrue("data !== null && data !== undefined")
            #expect(harness.evalString("data.name") == "Hammerspoon")
            #expect(harness.evalInt("data.count") == 99)
            #expect(harness.evalBool("data.flag") == true)
            #expect(!harness.hasException)
        }
    }
}
