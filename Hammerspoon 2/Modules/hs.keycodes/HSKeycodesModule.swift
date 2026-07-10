//
//  HSKeycodesModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Carbon
import AppKit

// MARK: - Module API protocol

/// Access information about the current keyboard layout and input sources, and respond to changes.
///
/// ## Reading the current layout
///
/// ```js
/// console.log("Layout: " + hs.keycodes.currentLayout())
/// console.log("Source ID: " + hs.keycodes.currentSourceID())
/// ```
///
/// ## Key code mapping
///
/// ```js
/// // Look up a keycode by name
/// const code = hs.keycodes.map["a"]    // e.g. 0 on ANSI US
/// // Look up a name by keycode
/// const name = hs.keycodes.map["0"]   // e.g. "a"
/// ```
///
/// ## Switching layouts
///
/// ```js
/// hs.keycodes.setLayout("British")
/// ```
///
/// ## Watching for input source changes
///
/// ```js
/// hs.keycodes.addWatcher(() => {
///     console.log("Switched to: " + hs.keycodes.currentLayout())
/// })
/// ```
@objc protocol HSKeycodesModuleAPI: JSExport {

    // MARK: Key Map

    /// A bidirectional mapping between key names and their macOS virtual key codes.
    ///
    /// Entries exist for both directions: look up a name to get its integer keycode, or look
    /// up a keycode (as a string) to get the key name. The map is rebuilt automatically
    /// whenever the keyboard input source changes.
    ///
    /// Named keys include:
    /// - **Characters**: derived from the active keyboard layout via `UCKeyTranslate` (falls back to ANSI US)
    /// - **Function keys**: `f1`–`f20`
    /// - **Navigation**: `home`, `end`, `pageup`, `pagedown`, `left`, `right`, `up`, `down`
    /// - **Numpad**: `pad0`–`pad9`, `pad.`, `pad+`, `pad-`, `pad*`, `pad/`, `pad=`, `padenter`, `padclear`
    /// - **Modifiers**: `cmd`, `shift`, `ctrl`, `alt`, `rightshift`, `rightalt`, `rightctrl`, `fn`, `capslock`
    /// - **Control**: `return`, `tab`, `space`, `delete`, `forwarddelete`, `escape`, `help`
    /// - **Media**: `volup`, `voldown`, `mute`
    /// - Example:
    /// ```js
    /// const code = hs.keycodes.map["return"]  // 36
    /// const name = hs.keycodes.map["36"]      // "return"
    /// const aCode = hs.keycodes.map["a"]      // keycode for 'a' in current layout
    /// ```
    var map: [String: Any] { get }

    // MARK: Current Source Queries

    /// Returns the localized name of the current keyboard layout.
    ///
    /// Uses the base keyboard layout, which is the underlying layout even when an input
    /// method (such as a CJK input method) is also active.
    /// - Returns: The display name of the active layout (e.g. `"U.S."`, `"British"`), or `null`.
    /// - Example:
    /// ```js
    /// console.log("Layout: " + hs.keycodes.currentLayout())
    /// ```
    func currentLayout() -> String?

    /// Returns the localized name of the active input method, or `null` if none is active.
    ///
    /// Input methods are distinct from keyboard layouts. They provide complex character
    /// composition such as CJK input. Returns `null` when using a plain keyboard layout
    /// with no input method overlay.
    /// - Returns: The display name of the active input method (e.g. `"Hiragana"`), or `null`.
    /// - Example:
    /// ```js
    /// const m = hs.keycodes.currentMethod()
    /// if (m) console.log("Input method: " + m)
    /// ```
    func currentMethod() -> String?

    /// Returns the reverse-DNS identifier of the currently selected keyboard input source.
    ///
    /// - Returns: A string such as `"com.apple.keylayout.US"`, or `null` if unavailable.
    /// - Example:
    /// ```js
    /// console.log("Source ID: " + hs.keycodes.currentSourceID())
    /// ```
    func currentSourceID() -> String?

    // MARK: Available Sources

    /// Returns the localized names of all currently enabled keyboard layouts.
    ///
    /// - Returns: An array of layout name strings (e.g. `["U.S.", "British", "French"]`).
    /// - Example:
    /// ```js
    /// hs.keycodes.layouts().forEach(l => console.log(l))
    /// ```
    func layouts() -> [String]

    /// Returns the localized names of all currently enabled input methods.
    ///
    /// - Returns: An array of input method name strings. May be empty if none are enabled.
    /// - Example:
    /// ```js
    /// hs.keycodes.methods().forEach(m => console.log(m))
    /// ```
    func methods() -> [String]

    // MARK: Source Switching

    /// Switches the active keyboard layout to the one with the given localized name.
    ///
    /// - Parameter layoutName: The localized name of the layout to activate (e.g. `"U.S."`).
    ///   Use `layouts()` to enumerate valid names.
    /// - Returns: `true` if the layout was found and selected, `false` otherwise.
    /// - Example:
    /// ```js
    /// if (!hs.keycodes.setLayout("U.S.")) console.log("Layout not found")
    /// ```
    func setLayout(_ layoutName: String) -> Bool

    /// Switches the active input method to the one with the given localized name.
    ///
    /// - Parameter methodName: The localized name of the input method to activate.
    ///   Use `methods()` to enumerate valid names.
    /// - Returns: `true` if the method was found and selected, `false` otherwise.
    /// - Example:
    /// ```js
    /// hs.keycodes.setMethod("Hiragana")
    /// ```
    func setMethod(_ methodName: String) -> Bool

    /// Switches the active input source to the one with the given reverse-DNS identifier.
    ///
    /// - Parameter sourceID: The input source ID to activate (e.g. `"com.apple.keylayout.British"`).
    ///   Use `currentSourceID()` to see the current value.
    /// - Returns: `true` if the source was found and selected, `false` otherwise.
    /// - Example:
    /// ```js
    /// hs.keycodes.setSourceID("com.apple.keylayout.British")
    /// ```
    func setSourceID(_ sourceID: String) -> Bool

    // MARK: Watcher (Pattern A)

    /// Registers a listener that fires whenever the keyboard input source changes.
    ///
    /// The listener is called with no arguments. Read `currentLayout()`, `currentSourceID()`,
    /// or `map` inside the callback to inspect the new state.
    ///
    /// The OS subscription starts lazily on the first listener and is released automatically
    /// when the last listener is removed via `removeWatcher`.
    /// - Parameter listener: {() => void} A function called when the input source changes.
    /// - Example:
    /// ```js
    /// hs.keycodes.addWatcher(() => {
    ///     console.log("Now using: " + hs.keycodes.currentLayout())
    /// })
    /// ```
    func addWatcher(_ listener: JSFunction)

    /// Removes a previously registered input source change listener.
    ///
    /// - Parameter listener: The function originally passed to `addWatcher`.
    /// - Example:
    /// ```js
    /// const handler = () => console.log("changed")
    /// hs.keycodes.addWatcher(handler)
    /// hs.keycodes.removeWatcher(handler)
    /// ```
    func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSKeycodesModule: NSObject, HSModuleAPI, HSKeycodesModuleAPI {
    var name = "hs.keycodes"
    let engineID: UUID

    // MARK: - Key map
    private var _cachedMap: [String: Any] = [:]

    var map: [String: Any] {
        return _cachedMap
    }

    // MARK: - Watcher (Pattern A)
    @objc var _watcherEmitter: JSFunction? = nil
    private var watcherCallback: JSFunction?
    private var sourceChangeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        _cachedMap = buildKeyMap()
        let notificationName = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        sourceChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceDidChange() }
        }
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        if let obs = sourceChangeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            sourceChangeObserver = nil
        }
        watcherCallback = nil
        _watcherEmitter = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Key map

    func buildKeyMap() -> [String: Any] {
        var result: [String: Any] = [:]

        // Add all static named keys first (these win over dynamic character mappings)
        for (keyName, keyCode) in HSKeycodesModule.namedKeys {
            result[keyName] = keyCode
            result[String(keyCode)] = keyName
        }

        // Add per-layout character mappings from UCKeyTranslate
        addLayoutCharacterMappings(to: &result)

        return result
    }

    private func addLayoutCharacterMappings(to result: inout [String: Any]) {
        guard let source = unsafe TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            applyFallbackCharacterMappings(to: &result)
            return
        }

        guard let rawPtr = unsafe TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            applyFallbackCharacterMappings(to: &result)
            AKWarning("hs.keycodes: No UCHR data for current layout; using ANSI US fallback for character keys")
            return
        }

        let cfData = unsafe Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue()
        guard let bytePtr = unsafe CFDataGetBytePtr(cfData) else {
            applyFallbackCharacterMappings(to: &result)
            return
        }

        let layoutPtr = unsafe UnsafeRawPointer(bytePtr).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())

        for keyCode in UInt16(0)...UInt16(127) {
            // This is an ugly hack to work around an unexplained change in macOS12, where keycodes 93 and 94 are now included in kTISPropertyUnicodeKeyLayoutData
            if keyCode == 93 || keyCode == 94 { continue }

            var deadKeyState: UInt32 = 0
            var unicodeChars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0

            let status = unsafe UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &actualLength,
                &unicodeChars
            )

            guard status == noErr, actualLength > 0, unicodeChars[0] != 0x0010 else { continue }

            let charStr = String(decoding: unicodeChars.prefix(actualLength), as: UTF16.self).lowercased()
            let keyCodeInt = Int(keyCode)

            // Only add if neither direction is already covered by a named key
            if result[charStr] == nil && result[String(keyCodeInt)] == nil {
                result[charStr] = keyCodeInt
                result[String(keyCodeInt)] = charStr
            }
        }
    }

    private func applyFallbackCharacterMappings(to result: inout [String: Any]) {
        for (keyName, keyCode) in HSKeycodesModule.ansiUSCharacterMap {
            if result[keyName] == nil {
                result[keyName] = keyCode
                result[String(keyCode)] = keyName
            }
        }
    }

    // MARK: - Current source queries

    func currentLayout() -> String? {
        guard let source = unsafe TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return tisStringProperty(of: source, key: kTISPropertyLocalizedName)
    }

    func currentMethod() -> String? {
        guard let source = unsafe TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }

        guard let category = tisStringProperty(of: source, key: kTISPropertyInputSourceCategory),
              category == (kTISCategoryKeyboardInputSource as String) else { return nil }

        guard let type = tisStringProperty(of: source, key: kTISPropertyInputSourceType),
              type == (kTISTypeKeyboardInputMode as String) else { return nil }

        return tisStringProperty(of: source, key: kTISPropertyLocalizedName)
    }

    func currentSourceID() -> String? {
        guard let source = unsafe TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return tisStringProperty(of: source, key: kTISPropertyInputSourceID)
    }

    // MARK: - Available sources

    func layouts() -> [String] {
        return inputSources(ofType: kTISTypeKeyboardLayout as String).compactMap {
            tisStringProperty(of: $0, key: kTISPropertyLocalizedName)
        }
    }

    func methods() -> [String] {
        return inputSources(ofType: kTISTypeKeyboardInputMode as String).compactMap {
            tisStringProperty(of: $0, key: kTISPropertyLocalizedName)
        }
    }

    // MARK: - Source switching

    func setLayout(_ layoutName: String) -> Bool {
        return selectInputSource(where: kTISPropertyLocalizedName, equals: layoutName,
                                 ofType: kTISTypeKeyboardLayout as String)
    }

    func setMethod(_ methodName: String) -> Bool {
        return selectInputSource(where: kTISPropertyLocalizedName, equals: methodName,
                                 ofType: kTISTypeKeyboardInputMode as String)
    }

    func setSourceID(_ sourceID: String) -> Bool {
        guard let listRef = unsafe TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return false }

        for i in 0..<CFArrayGetCount(listRef) {
            guard let ptr = unsafe CFArrayGetValueAtIndex(listRef, i) else { continue }
            let source = unsafe Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
            if tisStringProperty(of: source, key: kTISPropertyInputSourceID) == sourceID {
                let status = TISSelectInputSource(source)
                if status == noErr {
                    AKTrace("hs.keycodes.setSourceID: selected \(sourceID)")
                    return true
                }
                AKError("hs.keycodes.setSourceID: TISSelectInputSource failed (\(status))")
                return false
            }
        }

        AKWarning("hs.keycodes.setSourceID: no source found with ID '\(sourceID)'")
        return false
    }

    // MARK: - Watcher (Pattern A)

    func addWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard watcherCallback == nil else {
            AKWarning("hs.keycodes._addWatcher: already watching — refusing second subscription")
            return
        }
        watcherCallback = callback
        AKTrace("hs.keycodes._addWatcher: started")
    }

    @objc func _removeWatcher() {
        watcherCallback = nil
        AKTrace("hs.keycodes._removeWatcher: stopped")
    }

    // MARK: - Private helpers

    private func inputSourceDidChange() {
        _cachedMap = buildKeyMap()
        _ = watcherCallback?.call(withArguments: [])
    }

    private func tisStringProperty(of source: TISInputSource, key: CFString) -> String? {
        guard let ptr = unsafe TISGetInputSourceProperty(source, key) else { return nil }
        return (unsafe Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue()) as String
    }

    private func inputSources(ofType type: String) -> [TISInputSource] {
        guard let listRef = unsafe TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        var result: [TISInputSource] = []
        for i in 0..<CFArrayGetCount(listRef) {
            guard let ptr = unsafe CFArrayGetValueAtIndex(listRef, i) else { continue }
            let source = unsafe Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
            guard let category = tisStringProperty(of: source, key: kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String) else { continue }
            guard let sourceType = tisStringProperty(of: source, key: kTISPropertyInputSourceType),
                  sourceType == type else { continue }
            result.append(source)
        }
        return result
    }

    private func selectInputSource(where propertyKey: CFString, equals value: String, ofType type: String) -> Bool {
        let candidates = inputSources(ofType: type)
        for source in candidates {
            if tisStringProperty(of: source, key: propertyKey) == value {
                let status = TISSelectInputSource(source)
                if status == noErr {
                    AKTrace("hs.keycodes: selected input source '\(value)'")
                    return true
                }
                AKError("hs.keycodes: TISSelectInputSource('\(value)') failed (\(status))")
                return false
            }
        }
        AKWarning("hs.keycodes: no input source found matching '\(value)'")
        return false
    }
}

// MARK: - Static key tables

extension HSKeycodesModule {
    // Named special keys: (name, Carbon keycode).
    // These take precedence over any UCKeyTranslate-derived character mappings.
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

        // Symbol word aliases (convenient alternatives to the character forms in ansiUSCharacterMap)
        ("minus",        kVK_ANSI_Minus),         // same as "-"
        ("equal",        kVK_ANSI_Equal),          // same as "="
        ("leftbracket",  kVK_ANSI_LeftBracket),   // same as "["
        ("rightbracket", kVK_ANSI_RightBracket),  // same as "]"
        ("backslash",    kVK_ANSI_Backslash),      // same as "\\"
        ("semicolon",    kVK_ANSI_Semicolon),      // same as ";"
        ("quote",        kVK_ANSI_Quote),           // same as "'"
        ("comma",        kVK_ANSI_Comma),           // same as ","
        ("period",       kVK_ANSI_Period),          // same as "."
        ("slash",        kVK_ANSI_Slash),           // same as "/"
        ("grave",        kVK_ANSI_Grave),           // same as "`"
    ]

    // ANSI US fallback for character keys when the layout provides no UCHR data.
    // Based on Carbon.framework Events.h for the standard ANSI US layout.
    static let ansiUSCharacterMap: [(String, Int)] = [
        ("a", kVK_ANSI_A), ("s", kVK_ANSI_S), ("d", kVK_ANSI_D), ("f", kVK_ANSI_F),
        ("h", kVK_ANSI_H), ("g", kVK_ANSI_G), ("z", kVK_ANSI_Z), ("x", kVK_ANSI_X),
        ("c", kVK_ANSI_C), ("v", kVK_ANSI_V), ("b", kVK_ANSI_B), ("q", kVK_ANSI_Q),
        ("w", kVK_ANSI_W), ("e", kVK_ANSI_E), ("r", kVK_ANSI_R), ("y", kVK_ANSI_Y),
        ("t", kVK_ANSI_T),
        ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
        ("6", kVK_ANSI_6), ("5", kVK_ANSI_5), ("=", kVK_ANSI_Equal),
        ("9", kVK_ANSI_9), ("7", kVK_ANSI_7), ("-", kVK_ANSI_Minus),
        ("8", kVK_ANSI_8), ("0", kVK_ANSI_0),
        ("]", kVK_ANSI_RightBracket), ("o", kVK_ANSI_O), ("u", kVK_ANSI_U),
        ("[", kVK_ANSI_LeftBracket),  ("i", kVK_ANSI_I), ("p", kVK_ANSI_P),
        ("l", kVK_ANSI_L), ("j", kVK_ANSI_J), ("'", kVK_ANSI_Quote),
        ("k", kVK_ANSI_K), (";", kVK_ANSI_Semicolon),
        ("\\", kVK_ANSI_Backslash), (",", kVK_ANSI_Comma),
        ("/", kVK_ANSI_Slash), ("n", kVK_ANSI_N), ("m", kVK_ANSI_M),
        (".", kVK_ANSI_Period), ("`", kVK_ANSI_Grave),
    ]
}
