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
/// Key codes identify physical keys, while characters depend on the keyboard layout. `map` and
/// `names` follow the current layout, so on Dvorak `map["w"]` is the key code of the key that
/// types `w` there.
///
/// ```js
/// // Look up a keycode by name
/// const code = hs.keycodes.map["a"]    // e.g. 0 on ANSI US
/// // Look up a name by keycode
/// const name = hs.keycodes.names[0]    // e.g. "a"
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
/// hs.keycodes.on('change', () => {
///     console.log("Switched to: " + hs.keycodes.currentLayout())
/// })
/// ```
@objc protocol HSKeycodesModuleAPI: JSExport {

    // MARK: Key Map

    /// A mapping from key names to macOS virtual key codes, following the current keyboard layout.
    ///
    /// This is the same mapping `hs.hotkey` and `hs.eventtap` use to turn a key name into a key
    /// code. For the reverse direction, use `names`. The map is rebuilt automatically whenever
    /// the keyboard input source changes.
    ///
    /// Names include:
    /// - **Characters**: every character the current layout types with no modifiers held. Characters
    ///   the layout doesn't type (e.g. `1` on AZERTY) map to their US-ANSI key position.
    /// - **Punctuation words**: `minus`, `equal`, `leftbracket`, `rightbracket`, `backslash`,
    ///   `semicolon`, `quote`, `comma`, `period`, `slash`, `grave`. Each is the key that types that
    ///   character in the current layout, so `comma` and `,` are always the same key.
    /// - **Function keys**: `f1`–`f20`
    /// - **Navigation**: `home`, `end`, `pageup`, `pagedown`, `left`, `right`, `up`, `down`
    /// - **Numpad**: `pad0`–`pad9`, `pad.`, `pad+`, `pad-`, `pad*`, `pad/`, `pad=`, `padenter`, `padclear`
    /// - **Modifiers**: `cmd`, `rightcmd`, `shift`, `ctrl`, `alt`, `rightshift`, `rightalt`, `rightctrl`, `fn`, `capslock`
    /// - **Control**: `return`, `tab`, `space`, `delete`, `forwarddelete`, `escape`, `help`
    /// - **Media**: `volup`, `voldown`, `mute`
    /// - **JIS**: `yen`, `underscore`, `pad,`, `eisu`, `kana`
    /// - Example:
    /// ```js
    /// const code = hs.keycodes.map["return"]  // 36
    /// const wCode = hs.keycodes.map["w"]      // 13 on US, 43 on Dvorak
    /// const one = hs.keycodes.map["1"]        // 18: the key that types 1, not key code 1
    /// ```
    var map: [String: Int] { get }

    /// A mapping from macOS virtual key codes to key names, following the current keyboard layout.
    ///
    /// The reverse of `map`. Each key code maps to its fixed name if it has one (e.g. `return`,
    /// `f1`), otherwise to the character the current layout types on it. Key codes with neither
    /// are absent. JavaScript object keys are strings, so `names[36]` and `names["36"]` are the same.
    /// - Example:
    /// ```js
    /// console.log(hs.keycodes.names[36])   // "return"
    /// console.log(hs.keycodes.names[13])   // "w" on US, "," on Dvorak
    ///
    /// hs.eventtap.addWatcher(["keyDown"], (e) => {
    ///     console.log("Pressed: " + hs.keycodes.names[e.keyCode])
    ///     return false
    /// })
    /// ```
    var names: [String: String] { get }

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

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.keycodes.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSKeycodesEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.keycodes.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Module implementation

/// Events emitted by hs.keycodes's watcher
nonisolated enum HSKeycodesEvent: String, HSEventName {
    case change
}

@_documentation(visibility: private)
@MainActor
@objc class HSKeycodesModule: NSObject, HSModuleAPI, HSKeycodesModuleAPI {
    var moduleName = "hs.keycodes"
    let engineID: UUID

    // MARK: - Key map
    private(set) var map: [String: Int] = [:]
    private(set) var names: [String: String] = [:]

    // MARK: - Watcher
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSKeycodesEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var watcherCallback: JSFunction?
    private var sourceChangeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        rebuildMaps()
        let notificationName = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        sourceChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceDidChange() }
        }
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        if let obs = sourceChangeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            sourceChangeObserver = nil
        }
        watcherCallback = nil
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): \(map.count) key mapping\(map.count == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Key map

    private func rebuildMaps() {
        let keyCodes = KeyboardLayout.shared.keyCodes
        map = keyCodes.codesByName
        names = keyCodes.namesByCode
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
                    AKDebug("hs.keycodes.setSourceID: selected \(sourceID)")
                    return true
                }
                AKError("hs.keycodes.setSourceID: TISSelectInputSource failed (\(status))")
                return false
            }
        }

        AKWarning("hs.keycodes.setSourceID: no source found with ID '\(sourceID)'")
        return false
    }

    // MARK: - Watcher

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("hs.keycodes._addWatcher: already watching — refusing second subscription")
            return false
        }
        watcherCallback = callback
        AKDebug("hs.keycodes._addWatcher: started")
        return true
    }

    @objc func _removeWatcher() {
        watcherCallback = nil
        AKDebug("hs.keycodes._removeWatcher: stopped")
    }

    // MARK: - Private helpers

    private func inputSourceDidChange() {
        // Refresh the shared table first: its own observer of this notification may not have run yet.
        KeyboardLayout.shared.refresh()
        rebuildMaps()
        _ = watcherCallback?.call(withArguments: [HSKeycodesEvent.change.rawValue])
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
                    AKDebug("hs.keycodes: selected input source '\(value)'")
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
