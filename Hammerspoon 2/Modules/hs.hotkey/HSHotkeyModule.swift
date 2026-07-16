//
//  HSHotkeyModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Carbon

// MARK: - Declare our JavaScript API

/// Module for creating and managing system-wide hotkeys
@objc protocol HSHotkeyModuleAPI: JSExport {
    /// Bind a hotkey
    /// - Parameters:
    ///   - mods: An array of modifier key strings (e.g., `["cmd", "shift"]`). Supported names:
    ///     `cmd` / `command` / `⌘`, `shift` / `⇧`, `alt` / `option` / `⌥`, `ctrl` / `control` / `⌃`.
    ///   - key: The key name or character (e.g., "a", "space", "return", "f1")
    ///   - callbackPressed: {(() => void) | null} A JavaScript function to call when the hotkey is pressed, or null for no callback
    ///   - callbackReleased: {(() => void) | null} A JavaScript function to call when the hotkey is released, or null for no callback
    /// - Returns: A hotkey object, or null if binding failed
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd","shift"], "h", () => {
    ///     console.log("Hello!")
    /// }, null)
    /// ```
    @objc func bind(_ mods: [String], _ key: String, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkey?

    /// Bind a hotkey with a message description
    /// - Parameters:
    ///   - mods: An array of modifier key strings
    ///   - key: The key name or character
    ///   - message: A description of what this hotkey does (currently unused, for future features)
    ///   - callbackPressed: {(() => void) | null} A JavaScript function to call when the hotkey is pressed, or null for no callback
    ///   - callbackReleased: {(() => void) | null} A JavaScript function to call when the hotkey is released, or null for no callback
    /// - Returns: A hotkey object, or null if binding failed
    /// - Example:
    /// ```js
    /// hs.hotkey.bindSpec(["cmd"], "space", "Spotlight-like", () => {
    ///     console.log("pressed")
    /// }, null)
    /// ```
    @objc(bindSpec:::::)
    func bindSpec(_ mods: [String], _ key: String, _ message: String?, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkey?

    /// Get the system-wide mapping of key names to key codes
    /// - Returns: A dictionary mapping key names to numeric key codes
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.getKeyCodeMap())
    /// ```
    @objc func getKeyCodeMap() -> [String: UInt32]

    /// Get the mapping of modifier names to modifier flags
    /// - Returns: A dictionary mapping modifier names to their numeric values
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.getModifierMap())
    /// ```
    @objc func getModifierMap() -> [String: UInt32]

    /// Create a new modal hotkey group, optionally entered via a trigger key combination
    /// - Parameters:
    ///   - mods: Modifier keys for the trigger hotkey (e.g. `["cmd", "shift"]`), or an empty array for no trigger
    ///   - key: Key name for the trigger hotkey (e.g. `"h"`), or an empty string for no trigger
    /// - Returns: A new modal object. If a non-empty key is given but cannot be resolved, a warning is logged and the modal is returned without a trigger.
    /// - Example:
    /// ```js
    /// // Modal with a Cmd+H trigger — pressing it calls enter() automatically
    /// const m = hs.hotkey.createModal(['cmd'], 'h')
    /// m.bind(['shift'], 'j', () => console.log('shift-j pressed'), null)
    /// m.enterFn = () => console.log('modal entered')
    /// m.exitFn  = () => console.log('modal exited')
    ///
    /// // Modal with no trigger — enter/exit manually
    /// const m2 = hs.hotkey.createModal([], '')
    /// m2.enter()
    /// ```
    @objc func createModal(_ mods: [String], _ key: String) -> HSHotkeyModal
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHotkeyModule: NSObject, HSModuleAPI, HSHotkeyModuleAPI {
    var name = "hs.hotkey"
    let engineID: UUID

    // Weak refs: disabled/dropped hotkeys can be GC'd.
    private var activeHotkeys = HSWeakObjectSet<HSHotkey>()

    // Modal groups.
    private var modals = HSWeakObjectSet<HSHotkeyModal>()

    // MARK: - Module lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for modal in modals.allObjects {
            modal.destroy()
        }
        modals.removeAllObjects()

        for hotkey in activeHotkeys.allObjects {
            hotkey.destroy()
        }
        activeHotkeys.removeAllObjects()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Hotkey binding

    @objc func bind(_ mods: [String], _ key: String, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkey? {
        return bindSpec(mods, key, nil, callbackPressed, callbackReleased)
    }

    @objc func bindSpec(_ mods: [String], _ key: String, _ message: String?, _ callbackPressed: JSFunction, _ callbackReleased: JSFunction) -> HSHotkey? {
        guard let modifierFlags = parseModifiers(mods) else {
            AKError("hs.hotkey.bind: Invalid modifiers")
            return nil
        }
        guard let keyCode = keyNameToKeyCode(key) else {
            AKError("hs.hotkey.bind: Unknown key '\(key)'")
            return nil
        }
        guard callbackPressed.isFunction || callbackPressed.isNull else {
            AKError("hs.hotkey.bind: callbackPressed must be either a function or null")
            return nil
        }
        guard callbackReleased.isFunction || callbackReleased.isNull else {
            AKError("hs.hotkey.bind: callbackReleased must be either a function or null")
            return nil
        }

        let hotkey = HSHotkey(
            keyCode: keyCode,
            modifiers: modifierFlags,
            callbackPressed: callbackPressed.isNull ? nil : callbackPressed,
            callbackReleased: callbackReleased.isNull ? nil : callbackReleased
        )

        guard hotkey.enable() else {
            AKError("hs.hotkey.bindSpec(): failed to enable hotkey")
            hotkey.destroy()
            return nil
        }

        activeHotkeys.add(hotkey)
        return hotkey
    }

    // MARK: - Modal creation

    @objc func createModal(_ mods: [String], _ key: String) -> HSHotkeyModal {
        let modal = HSHotkeyModal(mods: mods, key: key, hotkeyModule: self)
        modals.add(modal)
        return modal
    }

    // MARK: - Internal helpers used by HSHotkeyModal

    /// Create an HSHotkey without enabling it. Used by HSHotkeyModal.bind() and the trigger hotkey.
    func makeHotkey(mods: [String], key: String, callbackPressed: JSFunction?, callbackReleased: JSFunction?) -> HSHotkey? {
        guard let modifierFlags = parseModifiers(mods) else { return nil }
        guard let keyCode = keyNameToKeyCode(key) else { return nil }
        return HSHotkey(keyCode: keyCode, modifiers: modifierFlags,
                        callbackPressed: callbackPressed, callbackReleased: callbackReleased)
    }

    // MARK: - Helper methods

    @objc func getKeyCodeMap() -> [String: UInt32] {
        return KeyCodeMapper.keyMap
    }

    @objc func getModifierMap() -> [String: UInt32] {
        return ModifierMapper.modifierMap
    }

    private func parseModifiers(_ mods: [String]) -> UInt32? {
        var flags: UInt32 = 0
        for mod in mods {
            guard let flag = ModifierMapper.parse(mod) else {
                AKError("hs.hotkey: Unknown modifier '\(mod)'")
                return nil
            }
            flags |= flag
        }
        return flags
    }

    private func keyNameToKeyCode(_ key: String) -> UInt32? {
        let lower = key.lowercased()
        if let code = KeyCodeMapper.keyMap[lower] { return code }
        return nil
    }
}

// MARK: - Modifier Mapping

private struct ModifierMapper {
    static func parse(_ name: String) -> UInt32? {
        switch name.lowercased() {
        case "cmd", "command", "⌘":   return UInt32(cmdKey)
        case "ctrl", "control", "⌃":  return UInt32(controlKey)
        case "alt", "option", "⌥":   return UInt32(optionKey)
        case "shift", "⇧":            return UInt32(shiftKey)
        default:                       return nil
        }
    }

    static let modifierMap: [String: UInt32] = [
        "cmd":     UInt32(cmdKey),
        "command": UInt32(cmdKey),
        "⌘":       UInt32(cmdKey),
        "ctrl":    UInt32(controlKey),
        "control": UInt32(controlKey),
        "⌃":       UInt32(controlKey),
        "alt":     UInt32(optionKey),
        "option":  UInt32(optionKey),
        "⌥":       UInt32(optionKey),
        "shift":   UInt32(shiftKey),
        "⇧":       UInt32(shiftKey),
    ]
}

// MARK: - Key Code Mapping

private struct KeyCodeMapper {
    static let keyMap: [String: UInt32] = [
        // Letters
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02,
        "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04,
        "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
        "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23,
        "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
        "y": 0x10, "z": 0x06,

        // Numbers
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
        "8": 0x1C, "9": 0x19,

        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A,
        "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,

        // Special keys
        "space": 0x31,
        "return": 0x24,
        "tab": 0x30,
        "delete": 0x33,
        "forwarddelete": 0x75,
        "escape": 0x35,
        "help": 0x72,
        "home": 0x73,
        "end": 0x77,
        "pageup": 0x74,
        "pagedown": 0x79,

        // Arrow keys
        "left": 0x7B,
        "right": 0x7C,
        "down": 0x7D,
        "up": 0x7E,

        // Symbols and punctuation
        "minus": 0x1B, "-": 0x1B,
        "equal": 0x18, "=": 0x18,
        "leftbracket": 0x21, "[": 0x21,
        "rightbracket": 0x1E, "]": 0x1E,
        "backslash": 0x2A, "\\": 0x2A,
        "semicolon": 0x29, ";": 0x29,
        "quote": 0x27, "'": 0x27,
        "comma": 0x2B, ",": 0x2B,
        "period": 0x2F, ".": 0x2F,
        "slash": 0x2C, "/": 0x2C,
        "grave": 0x32, "`": 0x32,

        // Keypad
        "pad0": 0x52, "pad1": 0x53, "pad2": 0x54, "pad3": 0x55,
        "pad4": 0x56, "pad5": 0x57, "pad6": 0x58, "pad7": 0x59,
        "pad8": 0x5B, "pad9": 0x5C,
        "pad*": 0x43, "pad+": 0x45, "pad/": 0x4B, "pad-": 0x4E,
        "pad=": 0x51, "pad.": 0x41,
        "padclear": 0x47, "padenter": 0x4C,
    ]
}
