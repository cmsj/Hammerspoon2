//
//  MenuShortcut.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// The keyboard shortcut shown next to a menu item, parsed from the `shortcut` field of a JS menu item object.
///
/// The field is either a string of modifier symbols followed by a key, written as the menu shows it (e.g. `"⇧⌘N"`,
/// or `"F"` for no modifiers), or an object with the modifiers and key spelled out
/// (e.g. `{ mods: ["cmd", "shift"], key: "n" }`). Keys and modifiers use the same names as `hs.hotkey`. It isn't a hotkey: AppKit only matches it while the menu is open (and the Dock, which draws
/// `hs.dockicon`'s menu itself, ignores it altogether).
@MainActor
struct MenuShortcut: Equatable {
    /// Why a `shortcut` field couldn't be used, for logging.
    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    /// The key, as `NSMenuItem.keyEquivalent` takes it
    let keyEquivalent: String
    /// The modifier keys, as `NSMenuItem.keyEquivalentModifierMask` takes them
    let modifiers: NSEvent.ModifierFlags

    /// Parses the value of a menu item object's `shortcut` field, as converted from JS by `JSValue.toObject()`.
    /// - Throws: `ParseError` if the value isn't a string or a `{ mods, key }` object, or names an unknown key or modifier.
    init(parsing value: Any) throws(ParseError) {
        let keyValue: Any?
        if let dictionary = value as? [String: Any] {
            keyValue = dictionary["key"]
            var modifiers: NSEvent.ModifierFlags = []
            if let modsValue = dictionary["mods"], !(modsValue is NSNull) {
                guard let mods = modsValue as? [Any] else {
                    throw ParseError(description: "expected mods to be an array of modifier names")
                }
                for mod in mods {
                    guard let name = mod as? String, let flag = Self.modifierFlag(named: name) else {
                        throw ParseError(description: "unknown modifier '\(mod)'")
                    }
                    modifiers.insert(flag)
                }
            }
            self.modifiers = modifiers
        } else if let string = value as? String {
            // Leading modifier symbols, in any order, then the key
            var modifiers: NSEvent.ModifierFlags = []
            var rest = Substring(string)
            while let first = rest.first, "⌘⇧⌥⌃".contains(first), let flag = Self.modifierFlag(named: String(first)) {
                modifiers.insert(flag)
                rest = rest.dropFirst()
            }
            guard !rest.isEmpty else {
                throw ParseError(description: "expected a key after the modifier symbols")
            }
            keyValue = String(rest)
            self.modifiers = modifiers
        } else {
            throw ParseError(description: "expected a string like \"⇧⌘N\", or an object with mods and key")
        }

        guard let key = KeyArgument(keyValue) else {
            throw ParseError(description: "expected a key name or key code")
        }
        guard let keyEquivalent = Self.menuKeyEquivalent(for: key) else {
            throw ParseError(description: "\(key.logDescription) can't be used as a menu shortcut")
        }
        self.keyEquivalent = keyEquivalent
    }

    /// The shortcut as SwiftUI's `.keyboardShortcut()` takes it
    var keyboardShortcut: KeyboardShortcut {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        // SwiftUI spells the Delete key as DEL, where NSMenuItem wants backspace
        let key: KeyEquivalent = keyEquivalent == Self.backspace ? .delete : KeyEquivalent(Character(keyEquivalent))
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }

    // MARK: - Names

    private static func modifierFlag(named name: String) -> NSEvent.ModifierFlags? {
        switch name.lowercased() {
        case "cmd", "command", "⌘": .command
        case "ctrl", "control", "⌃": .control
        case "alt", "option", "⌥": .option
        case "shift", "⇧": .shift
        default: nil
        }
    }

    /// The key equivalent for a key name or key code, or nil for keys a menu can't show (e.g. modifiers,
    /// keypad and media keys).
    private static func menuKeyEquivalent(for key: KeyArgument) -> String? {
        let name: String
        switch key {
        case .name(let keyName):
            name = keyName.lowercased()
        case .keyCode(let code):
            guard let keyName = KeyboardLayout.shared.keyCodes.name(forKeyCode: code) else { return nil }
            name = keyName
        }
        if let special = specialKeys[name] {
            return special
        }
        let character = KeyCodeTable.characterAliases[name] ?? name
        guard character.count == 1 else { return nil }
        return character
    }

    private static let backspace = "\u{8}"

    /// The character AppKit uses for a function key, e.g. `NSF1FunctionKey`. These are all valid scalars, in a
    /// private-use area.
    private static func functionKey(_ code: Int) -> String {
        String(UnicodeScalar(UInt16(code)).map(Character.init) ?? " ")
    }

    /// Named keys that don't type a character, mapped to the key equivalents AppKit draws as their symbols.
    private static let specialKeys: [String: String] = {
        var keys: [String: String] = [
            // swiftlint:disable colon
            "return":        "\r",
            "padenter":      "\u{3}",
            "tab":           "\t",
            "space":         " ",
            "delete":        backspace,
            "escape":        "\u{1B}",
            "forwarddelete": functionKey(NSDeleteFunctionKey),
            "help":          functionKey(NSHelpFunctionKey),
            "home":          functionKey(NSHomeFunctionKey),
            "end":           functionKey(NSEndFunctionKey),
            "pageup":        functionKey(NSPageUpFunctionKey),
            "pagedown":      functionKey(NSPageDownFunctionKey),
            "left":          functionKey(NSLeftArrowFunctionKey),
            "right":         functionKey(NSRightArrowFunctionKey),
            "up":            functionKey(NSUpArrowFunctionKey),
            "down":          functionKey(NSDownArrowFunctionKey),
            // swiftlint:enable colon
        ]
        for number in 1...20 {
            keys["f\(number)"] = functionKey(NSF1FunctionKey + number - 1)
        }
        return keys
    }()
}
