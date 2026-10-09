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
    ///   - key: {string | number} The key: a name or character (e.g. "a", "space", "return", "f1"), resolved
    ///     through the current keyboard layout (see `hs.keycodes.map`), or a numeric virtual key code, which
    ///     always means the same physical key
    ///   - onPressed: {(() => void) | null} A JavaScript function to call when the hotkey is pressed, or null for no callback
    ///   - onReleased?: {(() => void) | null} A JavaScript function to call when the hotkey is released, or null/omitted for no callback
    ///   - onRepeat?: {(() => void) | null} A JavaScript function to call repeatedly while the hotkey is held down, or null/omitted for no repeat
    /// - Returns: A hotkey object, or null if binding failed (including when none of the callbacks is a function — at least one is required)
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd","shift"], "h", () => {
    ///     console.log("Hello!")
    /// }, null, () => console.log("still held"))
    /// ```
    @objc func bind(_ mods: [String], _ key: Any?, _ onPressed: JSFunction, _ onReleased: JSFunction, _ onRepeat: JSFunction) -> HSHotkey?

    /// Get the mapping of key names to key codes that hotkeys use, following the current keyboard layout
    /// - Returns: A dictionary mapping key names to numeric key codes (the same as `hs.keycodes.map`)
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.getKeyCodeMap()["w"])  // 13 on US, 43 on Dvorak
    /// ```
    @objc func getKeyCodeMap() -> [String: Int]

    /// Get the mapping of modifier names to modifier flags
    /// - Returns: A dictionary mapping modifier names to their numeric values
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.getModifierMap())
    /// ```
    @objc func getModifierMap() -> [String: UInt32]

    /// Create a hotkey without enabling it
    /// - Parameters:
    ///   - mods: An array of modifier key strings (e.g., `["cmd", "shift"]`). Supported names:
    ///     `cmd` / `command` / `⌘`, `shift` / `⇧`, `alt` / `option` / `⌥`, `ctrl` / `control` / `⌃`.
    ///   - key: {string | number} The key: a name or character (e.g. "a", "space", "return", "f1"), resolved
    ///     through the current keyboard layout (see `hs.keycodes.map`), or a numeric virtual key code, which
    ///     always means the same physical key
    ///   - onPressed: {(() => void) | null} A JavaScript function to call when the hotkey is pressed, or null for no callback
    ///   - onReleased?: {(() => void) | null} A JavaScript function to call when the hotkey is released, or null/omitted for no callback
    ///   - onRepeat?: {(() => void) | null} A JavaScript function to call repeatedly while the hotkey is held down, or null/omitted for no repeat
    /// - Returns: A hotkey object, or null if creation failed. Call `.enable()` to activate it.
    /// - Example:
    /// ```js
    /// const hk = hs.hotkey.create(["cmd","shift"], "h", () => {
    ///     console.log("Hello!")
    /// })
    /// hk.enable()
    /// ```
    @objc func create(_ mods: [String], _ key: Any?, _ onPressed: JSFunction, _ onReleased: JSFunction, _ onRepeat: JSFunction) -> HSHotkey?

    /// Get a list of all currently-enabled hotkeys
    /// - Returns: An array of objects, each with `mods`, `key`, `keyCode`, `message` and `enabled` fields
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.getHotkeys())
    /// ```
    @objc func getHotkeys() -> [[String: Any]]

    /// Check whether macOS itself has already claimed a key combination (e.g. for Spotlight, screenshots, etc.)
    /// - Parameters:
    ///   - mods: An array of modifier key strings
    ///   - key: {string | number} A key name or character, or a numeric virtual key code
    /// - Returns: An object with `keyCode`, `mods` and `enabled` fields if the combination is system-assigned, otherwise null
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.systemAssigned(["cmd","space"], "space"))
    /// ```
    @objc func systemAssigned(_ mods: [String], _ key: Any?) -> [String: Any]?

    /// Check whether a key combination is available to be bound (i.e. not already claimed by macOS)
    /// - Parameters:
    ///   - mods: An array of modifier key strings
    ///   - key: {string | number} A key name or character, or a numeric virtual key code
    /// - Returns: True if the combination can be bound, otherwise False
    /// - Example:
    /// ```js
    /// console.log(hs.hotkey.assignable(["cmd","shift"], "h"))
    /// ```
    @objc func assignable(_ mods: [String], _ key: Any?) -> Bool

    /// Disable and remove every hotkey currently bound to a key combination
    /// - Parameters:
    ///   - mods: An array of modifier key strings
    ///   - key: {string | number} A key name or character, or a numeric virtual key code
    /// - Example:
    /// ```js
    /// hs.hotkey.deleteAll(["cmd","shift"], "h")
    /// ```
    @objc func deleteAll(_ mods: [String], _ key: Any?)

    /// Disable every hotkey currently bound to a key combination, without removing them
    /// - Parameters:
    ///   - mods: An array of modifier key strings
    ///   - key: {string | number} A key name or character, or a numeric virtual key code
    /// - Example:
    /// ```js
    /// hs.hotkey.disableAll(["cmd","shift"], "h")
    /// ```
    @objc func disableAll(_ mods: [String], _ key: Any?)

    /// {number} Duration in seconds for the on-screen toast shown when a hotkey with a
    /// `message` set fires. Default is 1.
    /// - Example:
    /// ```js
    /// hs.hotkey.alertDuration = 3
    /// ```
    @objc var alertDuration: Double { get set }

    /// {boolean} Whether hotkeys bound with a key name move to a different key when the keyboard
    /// layout changes, so that they stay on the key that types that character. Default is true.
    ///
    /// For example, a hotkey bound to `"w"` is on the key US-ANSI calls `W` while a US layout is
    /// active, and moves to the key US-ANSI calls `,` when you switch to Dvorak, since that's where
    /// Dvorak types `w`. Hotkeys bound with a numeric key code never move.
    ///
    /// When false, a hotkey stays on whichever key its name resolved to when it was created, as in
    /// Hammerspoon v1. Setting this back to true moves existing hotkeys to the current layout.
    /// If the new layout doesn't type a hotkey's character and the character has no US-ANSI
    /// position either, the hotkey stays where it is and a warning is logged.
    /// - Example:
    /// ```js
    /// // Keep hotkeys on fixed physical keys, whatever layout is active
    /// hs.hotkey.followsKeyboardLayout = false
    /// ```
    @objc var followsKeyboardLayout: Bool { get set }

    /// SKIP_DOCS
    @objc var createModal: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var bindSpec: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var showHotkeys: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHotkeyModule: NSObject, HSModuleAPI, HSHotkeyModuleAPI {
    var moduleName = "hs.hotkey"
    let engineID: UUID

    // Weak refs: disabled/dropped hotkeys can be GC'd.
    private var activeHotkeys = HSWeakObjectSet<HSHotkey>()

    // MARK: - Swift-retained storage for JS-defined functions
    @objc var createModal: JSFunction? = nil
    @objc var bindSpec: JSFunction? = nil
    @objc var showHotkeys: JSFunction? = nil

    @objc var alertDuration: Double = 1.0

    @objc var followsKeyboardLayout: Bool = true {
        didSet {
            if followsKeyboardLayout && !oldValue {
                moveHotkeysToCurrentLayout()
            }
        }
    }

    private var layoutChangeObserver: NSObjectProtocol?

    // MARK: - Module lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        self.alertDuration = 1.0
        layoutChangeObserver = NotificationCenter.default.addObserver(
            forName: KeyboardLayout.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Posted on the main thread by KeyboardLayout
            MainActor.assumeIsolated {
                guard let self, self.followsKeyboardLayout else { return }
                self.moveHotkeysToCurrentLayout()
            }
        }
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        if let layoutChangeObserver {
            NotificationCenter.default.removeObserver(layoutChangeObserver)
            self.layoutChangeObserver = nil
        }
        createModal = nil
        bindSpec = nil
        showHotkeys = nil

        for hotkey in activeHotkeys.allObjects {
            hotkey.destroy()
        }
        activeHotkeys.removeAllObjects()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = activeHotkeys.allObjects.count
        return "<\(moduleName): \(n) bound hotkey\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Hotkey binding

    @objc func bind(_ mods: [String], _ key: Any?, _ onPressed: JSFunction, _ onReleased: JSFunction, _ onRepeat: JSFunction) -> HSHotkey? {
        // bind() enables the hotkey immediately, so a hotkey with no callbacks at all would
        // silently claim the key combination and do nothing. Require at least one callback.
        // (create() stays permissive so callers can build a hotkey and assign callbacks later.)
        guard onPressed.isFunction || onReleased.isFunction || onRepeat.isFunction else {
            AKError("hs.hotkey.bind: at least one of onPressed, onReleased, or onRepeat must be a function")
            return nil
        }

        guard let hotkey = create(mods, key, onPressed, onReleased, onRepeat) else { return nil }

        guard hotkey.enable() else {
            AKError("hs.hotkey.bind(): failed to enable hotkey: " + mods.joined(separator: ",") + ", " + (KeyArgument(key)?.logDescription ?? "?"))
            hotkey.destroy()
            activeHotkeys.remove(hotkey)
            return nil
        }

        return hotkey
    }

    // MARK: - Hotkey creation (without enabling)

    @objc func create(_ mods: [String], _ key: Any?, _ onPressed: JSFunction, _ onReleased: JSFunction, _ onRepeat: JSFunction) -> HSHotkey? {
        guard let modifierFlags = parseModifiers(mods) else {
            AKError("hs.hotkey.create: Invalid modifiers")
            return nil
        }
        guard let keyArgument = KeyArgument(key) else {
            AKError("hs.hotkey.create: key must be a key name or a numeric key code")
            return nil
        }
        guard let keyCode = keyCode(for: keyArgument) else {
            AKError("hs.hotkey.create: Unknown key \(keyArgument.logDescription)")
            return nil
        }
        guard onPressed.isFunction || onPressed.isNull else {
            AKError("hs.hotkey.create: onPressed must be either a function or null")
            return nil
        }
        guard onReleased.isFunction || onReleased.isNull || onReleased.isUndefined else {
            AKError("hs.hotkey.create: onReleased must be either a function, null, or omitted")
            return nil
        }
        guard onRepeat.isFunction || onRepeat.isNull || onRepeat.isUndefined else {
            AKError("hs.hotkey.create: onRepeat must be either a function, null, or omitted")
            return nil
        }

        let hotkey = HSHotkey(
            keyCode: keyCode,
            modifiers: modifierFlags,
            mods: mods,
            key: keyArgument,
            onPressed: onPressed.isFunction ? onPressed : nil,
            onReleased: onReleased.isFunction ? onReleased : nil,
            onRepeat: onRepeat.isFunction ? onRepeat : nil
        )

        activeHotkeys.add(hotkey)
        return hotkey
    }

    // MARK: - Introspection & management

    @objc func getHotkeys() -> [[String: Any]] {
        return activeHotkeys.allObjects
            .filter { $0.isEnabled() }
            .map { hotkey in
                [
                    "mods": hotkey.mods,
                    "key": hotkey.key,
                    "keyCode": hotkey.keyCode,
                    "message": hotkey.message ?? NSNull(),
                    "enabled": hotkey.isEnabled(),
                ]
            }
    }

    @objc func systemAssigned(_ mods: [String], _ key: Any?) -> [String: Any]? {
        guard let modifierFlags = parseModifiers(mods) else {
            AKError("hs.hotkey.systemAssigned: Invalid modifiers")
            return nil
        }
        guard let keyCode = keyCode(forArgument: key) else {
            AKError("hs.hotkey.systemAssigned: Unknown key")
            return nil
        }

        var symbolicHotKeysRef: Unmanaged<CFArray>?
        guard unsafe CopySymbolicHotKeys(&symbolicHotKeysRef) == noErr,
              let symbolicHotKeys = unsafe symbolicHotKeysRef?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        // macOS sets bit 1<<17 (kMenuFKeyModifier-adjacent Fn bit) on symbolic hotkey
        // modifiers that we never set ourselves, so mask it out before comparing.
        let fnBit: UInt32 = 1 << 17

        for entry in symbolicHotKeys {
            guard let entryEnabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool, entryEnabled,
                  let entryCode = entry[kHISymbolicHotKeyCode as String] as? UInt32,
                  let entryMods = entry[kHISymbolicHotKeyModifiers as String] as? UInt32 else {
                continue
            }
            if entryCode == keyCode && (entryMods & ~fnBit) == modifierFlags {
                return ["keyCode": entryCode, "mods": entryMods, "enabled": entryEnabled]
            }
        }
        return nil
    }

    @objc func assignable(_ mods: [String], _ key: Any?) -> Bool {
        guard let modifierFlags = parseModifiers(mods) else {
            AKError("hs.hotkey.assignable: Invalid modifiers")
            return false
        }
        guard let keyCode = keyCode(forArgument: key) else {
            AKError("hs.hotkey.assignable: Unknown key")
            return false
        }

        var probeRef: EventHotKeyRef?
        let probeID = EventHotKeyID(signature: OSType(("HMSP" as NSString).fourCharCode), id: HotkeyManager.shared.nextID)
        let status = unsafe RegisterEventHotKey(keyCode, modifierFlags, probeID, GetEventDispatcherTarget(), 0, &probeRef)
        guard status == noErr else { return false }
        if unsafe probeRef != nil {
            unsafe UnregisterEventHotKey(probeRef)
        }
        return true
    }

    @objc func deleteAll(_ mods: [String], _ key: Any?) {
        forEachMatchingHotkey(mods, key) { $0.destroy() }
    }

    @objc func disableAll(_ mods: [String], _ key: Any?) {
        forEachMatchingHotkey(mods, key) { $0.disable() }
    }

    private func forEachMatchingHotkey(_ mods: [String], _ key: Any?, _ body: (HSHotkey) -> Void) {
        guard let modifierFlags = parseModifiers(mods), let keyCode = keyCode(forArgument: key) else {
            AKError("hs.hotkey: Invalid mods or key")
            return
        }
        for hotkey in activeHotkeys.allObjects where hotkey.matches(keyCode: keyCode, modifiers: modifierFlags) {
            body(hotkey)
        }
    }

    // MARK: - Helper methods

    @objc func getKeyCodeMap() -> [String: Int] {
        return KeyboardLayout.shared.keyCodes.codesByName
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

    private func keyCode(for key: KeyArgument) -> UInt32? {
        key.resolve(in: KeyboardLayout.shared.keyCodes).map(UInt32.init)
    }

    private func keyCode(forArgument key: Any?) -> UInt32? {
        KeyArgument(key).flatMap(keyCode(for:))
    }

    // MARK: - Keyboard layout changes

    /// Moves every hotkey bound by key name onto the key that types its character in the current layout.
    private func moveHotkeysToCurrentLayout() {
        let keyCodes = KeyboardLayout.shared.keyCodes
        var moved: [(hotkey: HSHotkey, wasEnabled: Bool)] = []

        // Unregister everything that moves before registering anything on its new key: two
        // hotkeys can swap keys (e.g. "w" and "," between US and Dvorak), and Carbon refuses to
        // register a combination that's still held by the other one.
        for hotkey in activeHotkeys.allObjects {
            guard case .name(let name) = hotkey.keyArgument else { continue }
            guard let newCode = keyCodes.keyCode(forName: name) else {
                AKWarning("hs.hotkey: layout '\(keyCodes.layoutName)' has no key for '\(name)'; leaving that hotkey on key code \(hotkey.keyCode)")
                continue
            }
            guard newCode != hotkey.keyCode else { continue }
            let wasEnabled = hotkey.isEnabled()
            hotkey.disable()
            hotkey.changeKeyCode(UInt32(newCode))
            moved.append((hotkey, wasEnabled))
            AKDebug("hs.hotkey: moved '\(name)' to key code \(newCode) for layout '\(keyCodes.layoutName)'")
        }

        for (hotkey, wasEnabled) in moved where wasEnabled {
            if !hotkey.enable() {
                AKError("hs.hotkey: \(hotkey.keyArgument.logDescription) is now disabled: it couldn't be registered on key code \(hotkey.keyCode) after the keyboard layout changed")
            }
        }
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
