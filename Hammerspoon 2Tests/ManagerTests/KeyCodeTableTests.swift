//
//  KeyCodeTableTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import Carbon
@testable import Hammerspoon_2

/// Builds the table for one of Apple's built-in layouts. These are always installed, even when
/// not enabled, so the tests don't depend on (or change) the machine's active layout.
private func table(_ sourceID: String) throws -> KeyCodeTable {
    try #require(KeyCodeTable.forInputSource(id: sourceID), "\(sourceID) should be installed")
}

private nonisolated let usLayout = "com.apple.keylayout.US"
private nonisolated let dvorakLayout = "com.apple.keylayout.Dvorak"
private nonisolated let frenchLayout = "com.apple.keylayout.French"

@Suite("KeyCodeTable tests")
struct KeyCodeTableTests {

    @Suite("Resolving names through a layout")
    struct ResolutionTests {

        @Test("US layout puts characters on their ANSI keys")
        func testUSLayout() throws {
            let us = try table(usLayout)
            #expect(us.keyCode(forName: "w") == kVK_ANSI_W)
            #expect(us.keyCode(forName: "s") == kVK_ANSI_S)
            #expect(us.keyCode(forName: ",") == kVK_ANSI_Comma)
            #expect(us.name(forKeyCode: kVK_ANSI_W) == "w")
        }

        @Test("Dvorak resolves letters to the keys that type them (issue #270)")
        func testDvorakLetters() throws {
            let dvorak = try table(dvorakLayout)
            #expect(dvorak.keyCode(forName: "w") == kVK_ANSI_Comma)
            #expect(dvorak.keyCode(forName: "s") == kVK_ANSI_Semicolon)
            #expect(dvorak.keyCode(forName: "v") == kVK_ANSI_Period)
            #expect(dvorak.keyCode(forName: "z") == kVK_ANSI_Slash)
            #expect(dvorak.keyCode(forName: "r") == kVK_ANSI_O)
            #expect(dvorak.keyCode(forName: ",") == kVK_ANSI_W)
        }

        @Test("Dvorak names key codes by the character they type")
        func testDvorakNames() throws {
            let dvorak = try table(dvorakLayout)
            #expect(dvorak.name(forKeyCode: kVK_ANSI_Comma) == "w")
            #expect(dvorak.name(forKeyCode: kVK_ANSI_Semicolon) == "s")
            #expect(dvorak.name(forKeyCode: kVK_ANSI_W) == ",")
        }

        @Test("Lookups are case-insensitive")
        func testCaseInsensitive() throws {
            let dvorak = try table(dvorakLayout)
            #expect(dvorak.keyCode(forName: "W") == kVK_ANSI_Comma)
            #expect(dvorak.keyCode(forName: "RETURN") == kVK_Return)
        }

        @Test("Punctuation words mean the character, wherever the layout puts it")
        func testCharacterAliasesFollowLayout() throws {
            let us = try table(usLayout)
            let dvorak = try table(dvorakLayout)
            #expect(us.keyCode(forName: "comma") == kVK_ANSI_Comma)
            #expect(dvorak.keyCode(forName: "comma") == kVK_ANSI_W)
            #expect(dvorak.keyCode(forName: "semicolon") == dvorak.keyCode(forName: ";"))
        }

        @Test("Named keys don't move between layouts", arguments: [usLayout, dvorakLayout, frenchLayout])
        func testNamedKeysAreFixed(sourceID: String) throws {
            let layout = try table(sourceID)
            #expect(layout.keyCode(forName: "return") == kVK_Return)
            #expect(layout.keyCode(forName: "f1") == kVK_F1)
            #expect(layout.keyCode(forName: "pad0") == kVK_ANSI_Keypad0)
            #expect(layout.name(forKeyCode: kVK_Return) == "return")
        }

        @Test("Characters the layout doesn't type fall back to their US-ANSI key")
        func testANSIFallback() throws {
            let french = try table(frenchLayout)
            // AZERTY types "&" on the 1 key, and "1" only with shift
            #expect(french.keyCode(forName: "&") == kVK_ANSI_1)
            #expect(french.keyCode(forName: "1") == kVK_ANSI_1)
            // ...but letters it does type stay where AZERTY puts them
            #expect(french.keyCode(forName: "a") == kVK_ANSI_Q)
        }

        @Test("Unknown names resolve to nil")
        func testUnknownName() throws {
            #expect(try table(usLayout).keyCode(forName: "notakey") == nil)
        }
    }

    @Suite("Exported maps")
    struct MapTests {

        @Test("Digit characters map to their keys, not to the key codes with the same number")
        func testDigitsDontCollideWithKeyCodes() throws {
            let us = try table(usLayout)
            #expect(us.codesByName["0"] == kVK_ANSI_0)
            #expect(us.codesByName["1"] == kVK_ANSI_1)
            #expect(us.namesByCode["0"] == "a")
            #expect(us.namesByCode["1"] == "s")
        }

        @Test("Dvorak's map has every letter (issue #270)")
        func testDvorakMapHasAllLetters() throws {
            let dvorak = try table(dvorakLayout)
            for letter in "abcdefghijklmnopqrstuvwxyz" {
                let name = String(letter)
                let code = try #require(dvorak.codesByName[name], "map is missing \(name)")
                #expect(dvorak.namesByCode[String(code)] == name)
            }
        }

        @Test("Every name in the map resolves to the code the map gives", arguments: [usLayout, dvorakLayout, frenchLayout])
        func testMapAgreesWithResolution(sourceID: String) throws {
            let layout = try table(sourceID)
            for (name, code) in layout.codesByName {
                #expect(layout.keyCode(forName: name) == code, "\(name)")
            }
        }

        @Test("Named keys win the code-to-name direction")
        func testNamedKeysInNames() throws {
            let us = try table(usLayout)
            #expect(us.namesByCode[String(kVK_Return)] == "return")
            #expect(us.namesByCode[String(kVK_RightCommand)] == "rightcmd")
        }
    }

    @Suite("Static tables")
    struct StaticTableTests {

        @Test("namedKeys has no duplicate names or key codes")
        func testNamedKeysUnique() {
            let names = KeyCodeTable.namedKeys.map(\.0)
            let codes = KeyCodeTable.namedKeys.map(\.1)
            #expect(Set(names).count == names.count)
            #expect(Set(codes).count == codes.count)
        }

        @Test("ansiUSCharacters has no duplicate characters or key codes")
        func testANSIUnique() {
            let names = KeyCodeTable.ansiUSCharacters.map(\.0)
            let codes = KeyCodeTable.ansiUSCharacters.map(\.1)
            #expect(Set(names).count == names.count)
            #expect(Set(codes).count == codes.count)
        }

        @Test("Named keys and layout-dependent keys don't overlap")
        func testNamedKeysAreNotLayoutDependent() {
            let named = Set(KeyCodeTable.namedKeys.map(\.1))
            #expect(named.isDisjoint(with: KeyCodeTable.layoutDependentKeyCodes))
        }

        @Test("Punctuation words don't shadow named keys")
        func testAliasesDontShadowNamedKeys() {
            let named = Set(KeyCodeTable.namedKeys.map(\.0))
            #expect(named.isDisjoint(with: KeyCodeTable.characterAliases.keys))
        }
    }

    @Suite("Key arguments from JavaScript")
    struct KeyArgumentTests {

        @Test("Strings are names, including numeric strings")
        func testStrings() {
            #expect(KeyArgument("w") == .name("w"))
            #expect(KeyArgument("1") == .name("1"))
        }

        @Test("Integral numbers are key codes")
        func testNumbers() {
            #expect(KeyArgument(NSNumber(value: 0)) == .keyCode(0))
            #expect(KeyArgument(NSNumber(value: 13)) == .keyCode(13))
        }

        @Test("Booleans, fractions, negatives, empty strings and nil are rejected")
        func testRejected() {
            #expect(KeyArgument(kCFBooleanTrue as NSNumber) == nil)
            #expect(KeyArgument(NSNumber(value: 1.5)) == nil)
            #expect(KeyArgument(NSNumber(value: -1)) == nil)
            #expect(KeyArgument("") == nil)
            #expect(KeyArgument(nil) == nil)
        }
    }
}
