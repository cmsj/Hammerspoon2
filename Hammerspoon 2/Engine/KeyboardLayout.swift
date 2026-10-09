//
//  KeyboardLayout.swift
//  Hammerspoon 2
//

import Foundation
import Carbon

// MARK: - Key code table

/// A layout-aware mapping between key names and macOS virtual key codes.
///
/// Virtual key codes identify physical key positions (named after the US-ANSI keycaps), but the
/// character a key types depends on the active keyboard layout: on Dvorak, the key that types `w`
/// is the one US-ANSI calls `,`. Every module that turns a key name into a key code
/// (hs.keycodes, hs.hotkey, hs.eventtap, ...) resolves through this table, so they all agree.
///
/// Names resolve in this order:
/// 1. Named keys that never move between layouts (`return`, `f1`, `pad0`, `cmd`, ...)
/// 2. Word aliases for punctuation (`comma`, `semicolon`, ...), which are treated as the character
///    they name and resolved like any other character
/// 3. Characters typed by the layout, with no modifiers held
/// 4. The US-ANSI position of the character, for characters the layout doesn't type (e.g. `1` on
///    AZERTY, or `w` on a Cyrillic layout). This matches Hammerspoon v1.
nonisolated struct KeyCodeTable: Equatable, Sendable {
    /// Localized name of the layout this table was built from, for logging.
    let layoutName: String
    /// Character → key code for the characters the layout types. When two keys type the same
    /// character, the first in `layoutDependentKeyCodes` order wins.
    private let layoutCodes: [String: Int]
    /// Key code → character typed by that key in this layout.
    private let layoutCharacters: [Int: String]

    /// Builds a table from (key code, character) pairs, given in `layoutDependentKeyCodes` order.
    init(layoutName: String, characters: [(keyCode: Int, character: String)]) {
        var codes: [String: Int] = [:]
        var chars: [Int: String] = [:]
        for (keyCode, character) in characters {
            let character = character.lowercased()
            chars[keyCode] = character
            if codes[character] == nil {
                codes[character] = keyCode
            }
        }
        self.layoutName = layoutName
        self.layoutCodes = codes
        self.layoutCharacters = chars
    }

    /// A table for the US-ANSI layout, used when the current layout has no Unicode key layout data.
    static let ansiUS = KeyCodeTable(
        layoutName: "US-ANSI fallback",
        characters: ansiUSCharacters.map { (keyCode: $0.1, character: $0.0) }
    )

    // MARK: Lookups

    /// Returns the key code for a key name or character, or nil if nothing matches.
    ///
    /// Matching is case-insensitive.
    func keyCode(forName name: String) -> Int? {
        let lowered = name.lowercased()
        if let code = Self.namedKeyCodes[lowered] { return code }
        let character = Self.characterAliases[lowered] ?? lowered
        if let code = layoutCodes[character] { return code }
        return Self.ansiUSCodes[character]
    }

    /// Returns the canonical name of a key code: its fixed name (e.g. `return`) if it has one,
    /// otherwise the character the layout types on it. Returns nil for key codes with neither.
    func name(forKeyCode keyCode: Int) -> String? {
        if let name = Self.namedKeyNames[keyCode] { return name }
        return layoutCharacters[keyCode]
    }

    /// Every name `keyCode(forName:)` accepts, mapped to the key code it resolves to.
    var codesByName: [String: Int] {
        var result: [String: Int] = [:]
        for (name, code) in Self.namedKeys { result[name] = code }
        for (character, code) in Self.ansiUSCharacters { result[character] = code }
        for (character, code) in layoutCodes { result[character] = code }
        for alias in Self.characterAliases.keys {
            result[alias] = keyCode(forName: alias)
        }
        return result
    }

    /// Every key code that has a name, mapped to `name(forKeyCode:)`. Keys are the key codes as
    /// strings, since JavaScript object keys are always strings.
    var namesByCode: [String: String] {
        var result: [String: String] = [:]
        for (code, character) in layoutCharacters { result[String(code)] = character }
        for (name, code) in Self.namedKeys { result[String(code)] = name }
        return result
    }

    static func == (lhs: KeyCodeTable, rhs: KeyCodeTable) -> Bool {
        lhs.layoutName == rhs.layoutName && lhs.layoutCharacters == rhs.layoutCharacters
    }
}

// MARK: - Building tables from input sources

// Text Input Sources APIs must be called on the main thread.
@MainActor
extension KeyCodeTable {
    /// Builds a table for the current keyboard layout, falling back to US-ANSI if the layout
    /// has no Unicode key layout data.
    static func current() -> KeyCodeTable {
        guard let source = unsafe TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            AKWarning("KeyCodeTable: no current keyboard layout; using US-ANSI key positions")
            return .ansiUS
        }
        return KeyCodeTable(inputSource: source) ?? .ansiUS
    }

    /// Builds a table for an installed keyboard layout, whether or not it's enabled, e.g.
    /// `"com.apple.keylayout.Dvorak"`. Returns nil if no such layout exists.
    static func forInputSource(id: String) -> KeyCodeTable? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = unsafe TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
              CFArrayGetCount(list) > 0,
              let ptr = unsafe CFArrayGetValueAtIndex(list, 0) else { return nil }
        let source = unsafe Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
        return KeyCodeTable(inputSource: source)
    }

    /// Builds a table from an input source's Unicode key layout data, or returns nil if it has none.
    init?(inputSource source: TISInputSource) {
        let layoutName = unsafe TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            .map { unsafe Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"

        guard let rawPtr = unsafe TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            AKWarning("KeyCodeTable: layout '\(layoutName)' has no Unicode key layout data; using US-ANSI key positions")
            return nil
        }
        let data = unsafe Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue()
        guard let bytes = unsafe CFDataGetBytePtr(data) else { return nil }
        let layout = unsafe UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())

        var characters: [(keyCode: Int, character: String)] = []
        for keyCode in Self.layoutDependentKeyCodes {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            // Key down with no modifiers, as typed. NoDeadKeys makes a dead key report its own
            // character (e.g. `^` on French) rather than starting a composition.
            let status = unsafe UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, keyboardType,
                // The Mask, not the Bit: the Bit is the mask's bit position (0), so passing it
                // would request no options at all, and dead keys would type nothing.
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { continue }
            let character = String(decoding: chars.prefix(length), as: UTF16.self)
            // Skip control characters and whitespace; those keys are reached by their fixed names.
            guard character.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }) else { continue }
            characters.append((keyCode: keyCode, character: character))
        }

        self.init(layoutName: layoutName, characters: characters)
    }
}

// MARK: - Static key tables

nonisolated extension KeyCodeTable {
    /// Keys whose character depends on the layout, in priority order for when two of them type
    /// the same character. Matches Hammerspoon v1's list, minus the JIS keys, which have fixed names.
    static let layoutDependentKeyCodes: [Int] = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
        kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        kVK_ANSI_Grave, kVK_ANSI_Equal, kVK_ANSI_Minus, kVK_ANSI_RightBracket,
        kVK_ANSI_LeftBracket, kVK_ANSI_Quote, kVK_ANSI_Semicolon, kVK_ANSI_Backslash,
        kVK_ANSI_Comma, kVK_ANSI_Slash, kVK_ANSI_Period, kVK_ISO_Section,
    ]

    /// Keys with a fixed name, whatever the layout.
    static let namedKeys: [(String, Int)] = [
        // Control / editing
        ("return",        kVK_Return),        // 36
        ("tab",           kVK_Tab),           // 48
        ("space",         kVK_Space),         // 49
        ("delete",        kVK_Delete),        // 51 (backspace)
        ("escape",        kVK_Escape),        // 53
        ("forwarddelete", kVK_ForwardDelete), // 117
        ("help",          kVK_Help),          // 114
        ("capslock",      kVK_CapsLock),      // 57

        // Navigation
        ("home",     kVK_Home),       // 115
        ("end",      kVK_End),        // 119
        ("pageup",   kVK_PageUp),     // 116
        ("pagedown", kVK_PageDown),   // 121
        ("left",     kVK_LeftArrow),  // 123
        ("right",    kVK_RightArrow), // 124
        ("down",     kVK_DownArrow),  // 125
        ("up",       kVK_UpArrow),    // 126

        // Function keys
        ("f1",  kVK_F1),  // 122
        ("f2",  kVK_F2),  // 120
        ("f3",  kVK_F3),  // 99
        ("f4",  kVK_F4),  // 118
        ("f5",  kVK_F5),  // 96
        ("f6",  kVK_F6),  // 97
        ("f7",  kVK_F7),  // 98
        ("f8",  kVK_F8),  // 100
        ("f9",  kVK_F9),  // 101
        ("f10", kVK_F10), // 109
        ("f11", kVK_F11), // 103
        ("f12", kVK_F12), // 111
        ("f13", kVK_F13), // 105
        ("f14", kVK_F14), // 107
        ("f15", kVK_F15), // 113
        ("f16", kVK_F16), // 106
        ("f17", kVK_F17), // 64
        ("f18", kVK_F18), // 79
        ("f19", kVK_F19), // 80
        ("f20", kVK_F20), // 90

        // Media / volume
        ("volup",   kVK_VolumeUp),   // 72
        ("voldown", kVK_VolumeDown), // 73
        ("mute",    kVK_Mute),       // 74

        // Modifier keys
        ("cmd",        kVK_Command),      // 55
        ("rightcmd",   kVK_RightCommand), // 54
        ("shift",      kVK_Shift),        // 56
        ("alt",        kVK_Option),       // 58
        ("ctrl",       kVK_Control),      // 59
        ("rightshift", kVK_RightShift),   // 60
        ("rightalt",   kVK_RightOption),  // 61
        ("rightctrl",  kVK_RightControl), // 62
        ("fn",         kVK_Function),     // 63

        // Numpad
        ("pad.",     kVK_ANSI_KeypadDecimal),  // 65
        ("pad*",     kVK_ANSI_KeypadMultiply), // 67
        ("pad+",     kVK_ANSI_KeypadPlus),     // 69
        ("padclear", kVK_ANSI_KeypadClear),    // 71
        ("pad/",     kVK_ANSI_KeypadDivide),   // 75
        ("padenter", kVK_ANSI_KeypadEnter),    // 76
        ("pad-",     kVK_ANSI_KeypadMinus),    // 78
        ("pad=",     kVK_ANSI_KeypadEquals),   // 81
        ("pad0",     kVK_ANSI_Keypad0),        // 82
        ("pad1",     kVK_ANSI_Keypad1),        // 83
        ("pad2",     kVK_ANSI_Keypad2),        // 84
        ("pad3",     kVK_ANSI_Keypad3),        // 85
        ("pad4",     kVK_ANSI_Keypad4),        // 86
        ("pad5",     kVK_ANSI_Keypad5),        // 87
        ("pad6",     kVK_ANSI_Keypad6),        // 88
        ("pad7",     kVK_ANSI_Keypad7),        // 89
        ("pad8",     kVK_ANSI_Keypad8),        // 91
        ("pad9",     kVK_ANSI_Keypad9),        // 92

        // JIS keyboards
        ("yen",        kVK_JIS_Yen),          // 93
        ("underscore", kVK_JIS_Underscore),   // 94
        ("pad,",       kVK_JIS_KeypadComma),  // 95
        ("eisu",       kVK_JIS_Eisu),         // 102
        ("kana",       kVK_JIS_Kana),         // 104
    ]

    /// Word names for punctuation. Each means the character, wherever the layout puts it.
    static let characterAliases: [String: String] = [
        "minus":        "-",
        "equal":        "=",
        "leftbracket":  "[",
        "rightbracket": "]",
        "backslash":    "\\",
        "semicolon":    ";",
        "quote":        "'",
        "comma":        ",",
        "period":       ".",
        "slash":        "/",
        "grave":        "`",
    ]

    /// US-ANSI key positions, used for characters the current layout doesn't type.
    /// Based on Carbon.framework Events.h for the standard ANSI US layout.
    static let ansiUSCharacters: [(String, Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
        ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
        ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
        ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
        ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
        ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
        ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
        ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ("`", kVK_ANSI_Grave), ("=", kVK_ANSI_Equal), ("-", kVK_ANSI_Minus),
        ("]", kVK_ANSI_RightBracket), ("[", kVK_ANSI_LeftBracket), ("'", kVK_ANSI_Quote),
        (";", kVK_ANSI_Semicolon), ("\\", kVK_ANSI_Backslash), (",", kVK_ANSI_Comma),
        ("/", kVK_ANSI_Slash), (".", kVK_ANSI_Period), ("§", kVK_ISO_Section),
    ]

    private static let namedKeyCodes = Dictionary(uniqueKeysWithValues: namedKeys)
    private static let namedKeyNames = Dictionary(uniqueKeysWithValues: namedKeys.map { ($0.1, $0.0) })
    private static let ansiUSCodes = Dictionary(uniqueKeysWithValues: ansiUSCharacters)
}

// MARK: - Key arguments from JavaScript

/// A key as passed to a JS API: either a name/character resolved through the layout, or a raw
/// virtual key code that always means the same physical key.
nonisolated enum KeyArgument: Equatable, Sendable {
    case name(String)
    case keyCode(Int)

    /// Parses a JS key argument. JavaScriptCore delivers a JS string as a String and a JS number
    /// as an NSNumber, so the two are told apart by type; a numeric string like `"1"` is a name.
    /// Returns nil for anything else (booleans, non-integers, out-of-range numbers, empty strings).
    init?(_ value: Any?) {
        if let string = value as? String {
            guard !string.isEmpty, string != "undefined" else { return nil }
            self = .name(string)
        } else if let number = value as? NSNumber {
            // JS booleans also arrive as NSNumber (a CFBoolean)
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            guard double.rounded() == double, double >= 0, double <= Double(UInt16.max) else { return nil }
            self = .keyCode(Int(double))
        } else {
            return nil
        }
    }

    /// The key code this argument refers to in the given layout table, or nil for an unknown name.
    func resolve(in table: KeyCodeTable) -> Int? {
        switch self {
        case .name(let name): return table.keyCode(forName: name)
        case .keyCode(let code): return code
        }
    }

    /// The argument as JS should see it again: a string or a number.
    var jsValue: Any {
        switch self {
        case .name(let name): return name
        case .keyCode(let code): return code
        }
    }

    /// A description for log messages.
    var logDescription: String {
        switch self {
        case .name(let name): return "'\(name)'"
        case .keyCode(let code): return "key code \(code)"
        }
    }
}

// MARK: - Current layout

/// Tracks the current keyboard layout's `KeyCodeTable` and announces when it changes.
@MainActor
final class KeyboardLayout {
    static let shared = KeyboardLayout()

    /// Posted on the main thread, via NotificationCenter.default, after `keyCodes` changes.
    static let didChangeNotification = Notification.Name("HSKeyboardLayoutDidChange")

    /// The key code table for the current keyboard layout.
    private(set) var keyCodes: KeyCodeTable

    private init() {
        keyCodes = .current()
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        // Never removed: this object lives for the life of the app.
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardLayout.shared.refresh() }
        }
    }

    /// Rebuilds `keyCodes` from the current layout, posting `didChangeNotification` if it changed.
    /// Safe to call repeatedly; modules that react to input source changes themselves call this
    /// first, so they never see a stale table whichever notification observer runs first.
    func refresh() {
        replace(with: .current())
    }

    /// Replaces the table, posting `didChangeNotification` if it changed. Exposed for tests, which
    /// use it to simulate a layout switch without changing the system's layout.
    func replace(with table: KeyCodeTable) {
        guard table != keyCodes else { return }
        AKDebug("KeyboardLayout: key codes now follow '\(table.layoutName)'")
        keyCodes = table
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
