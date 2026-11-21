//
//  HSScreenModule.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

// MARK: - JavaScript API

/// Inspect and control the displays attached to the system.
///
/// ## Obtaining screens
///
/// ```javascript
/// const all    = hs.screen.all();   // [HSScreen, ...]
/// const main   = hs.screen.main();   // screen containing the focused window
/// const primary = hs.screen.primary(); // screen with the global menu bar
/// ```
///
/// ## Navigation
///
/// ```javascript
/// const right = hs.screen.main().toEast();
/// if (right) console.log("Screen to the right:", right.name);
/// ```
///
/// ## Display modes
///
/// ```javascript
/// const s = hs.screen.primary();
/// console.log(s.mode);
/// // → { width: 1440, height: 900, scale: 2, frequency: 60 }
///
/// s.setMode(1920, 1080, 1, 60);
/// ```
///
/// ## Screenshots
///
/// ```javascript
/// hs.screen.main().snapshot()
///     .then(img => img.saveToFile("/tmp/screen.png"));
/// ```
///
/// ## Watching for display changes
///
/// ```javascript
/// hs.screen.on('change', () => {
///     console.log("Display configuration changed:", hs.screen.all().length, "screens");
/// });
/// ```
///
/// ## Spaces
///
/// Each screen has its own ordered list of spaces (Mission Control's desktops and fullscreen
/// apps), and shows one of them at a time: its *current* space. Every space belongs to exactly
/// one screen. The *focused* space is the current space of whichever screen has keyboard focus.
/// So a screen has `spaces` and a `currentSpace`, every `HSSpace` knows its `screen`, and a
/// window knows its `spaces` and can `moveToSpace()`.
///
/// This relies on "Displays have separate Spaces" being turned on in System Settings → Desktop &
/// Dock, which is macOS's default. If it's off, macOS treats all your screens as one, so every
/// screen reports the same spaces, which belong to the primary screen.
///
/// Spaces are identified by numeric IDs, which last as long as the space does. Each space also
/// has a UUID, which macOS keeps across logins, so to find the same space in a later session,
/// save its `uuid` and look it up with `hs.screen.spaceForUUID()`.
///
/// > Warning: macOS has no public API for Spaces. Hammerspoon uses private functions from
/// > Apple's SkyLight framework, which Apple can change or remove in any macOS update without
/// > notice. If that happens, Spaces features may stop working or return wrong results.
/// > `hs.screen.spacesAvailable()` reports whether the private functions could be found at all,
/// > but it can't detect one whose behaviour has changed.
///
/// Adding, removing, and switching spaces works by briefly opening Mission Control and clicking
/// its buttons through the Accessibility API, since only macOS itself can make those changes.
/// These need Accessibility permission, return Promises, and visibly open Mission Control. They
/// depend on Mission Control's undocumented internal UI, so they can break in a macOS update too.
/// Moving a window to another space doesn't need Mission Control.
///
/// ```javascript
/// // Switch the main screen to its next space
/// const spaces = hs.screen.main().spaces
/// const index = spaces.findIndex(s => s.isCurrent)
/// spaces[(index + 1) % spaces.length].goto()
///
/// // Add a desktop, then remove it again
/// hs.screen.main().addSpace()
///     .then(space => space.remove())
///     .catch(err => console.error(err))
///
/// // Send the focused window to the main screen's last desktop
/// const desktops = hs.screen.main().spaces.filter(s => s.type === "desktop")
/// hs.window.focusedWindow().moveToSpace(desktops[desktops.length - 1])
///
/// // Watch for screens switching space
/// hs.screen.on('spaceChange', ({ screen, from, to }) => {
///     console.log(screen.name + " switched to space " + to.id)
/// })
/// ```
@objc protocol HSScreenModuleAPI: JSExport {
    /// All connected screens.
    /// - Returns: An array of HSScreen objects
    /// - Example:
    /// ```js
    /// const screens = hs.screen.all()
    /// screens.forEach(s => console.log(s.name))
    /// ```
    @objc func all() -> [HSScreen]

    /// The screen that currently contains the focused window, or the screen
    /// with the keyboard focus if no window is focused.
    ///
    /// - Returns: An HSScreen object or `null` if no main screen can be determined.
    /// - Example:
    /// ```js
    /// const main = hs.screen.main()
    /// console.log(main && main.name)
    /// ```
    @objc func main() -> HSScreen?

    /// The primary display — the one that contains the global menu bar.
    ///
    /// - Returns: An HSScreen object or `null` if no primary screen can be determined.
    /// - Example:
    /// ```js
    /// const s = hs.screen.primary()
    /// console.log(s && s.frame)
    /// ```
    @objc func primary() -> HSScreen?

    // MARK: Spaces

    /// Whether the private macOS functions Spaces support relies on could be found. If this is
    /// `false`, every Spaces property and function returns an empty or failure result.
    ///
    /// A `true` result does not guarantee every function works - it only means none of them
    /// have been removed. Apple can still change how they behave.
    /// - Returns: `true` if the private SkyLight functions are available, otherwise `false`
    /// - Example:
    /// ```js
    /// if (!hs.screen.spacesAvailable()) {
    ///     console.error("Spaces aren't supported on this version of macOS")
    /// }
    /// ```
    @objc func spacesAvailable() -> Bool

    /// Whether each screen has its own spaces ("Displays have separate Spaces" in System
    /// Settings → Desktop & Dock). Hammerspoon expects it to be on, which is macOS's default. If
    /// it's off, all screens share one set of spaces.
    /// - Returns: `true` if each screen has its own spaces
    /// - Example:
    /// ```js
    /// if (!hs.screen.screensHaveSeparateSpaces()) {
    ///     console.warn("Turn on 'Displays have separate Spaces' for per-screen spaces")
    /// }
    /// ```
    @objc func screensHaveSeparateSpaces() -> Bool

    /// Every space on every screen, screen by screen, each in Mission Control's order. Screens
    /// are in the order macOS lists them, which is also the order Mission Control numbers
    /// desktops in.
    /// - Returns: An array of HSSpace objects
    /// - Example:
    /// ```js
    /// const fullscreen = hs.screen.allSpaces().filter(s => s.type === "fullscreen")
    /// console.log(fullscreen.length + " fullscreen apps")
    /// ```
    @objc func allSpaces() -> [HSSpace]

    /// The focused space: the space showing on the screen with keyboard focus
    /// - Returns: The focused HSSpace, or `null` if it can't be found
    /// - Example:
    /// ```js
    /// console.log("Focused space: " + hs.screen.focusedSpace().id)
    /// ```
    @objc func focusedSpace() -> HSSpace?

    /// Finds a space by its ID
    /// - Parameter id: The space's ID
    /// - Returns: The HSSpace, or `null` if there's no space with that ID
    /// - Example:
    /// ```js
    /// const space = hs.screen.spaceForID(3)
    /// if (space) space.goto()
    /// ```
    @objc func spaceForID(_ id: Int) -> HSSpace?

    /// Finds a space by its UUID. Unlike IDs, macOS keeps space UUIDs across logins, so this
    /// is how to find a space you saved in an earlier session.
    /// - Parameter uuid: The space's UUID
    /// - Returns: The HSSpace, or `null` if there's no space with that UUID
    /// - Example:
    /// ```js
    /// const workUUID = hs.settings.get("workSpace")
    /// const work = workUUID ? hs.screen.spaceForUUID(workUUID) : null
    /// ```
    @objc func spaceForUUID(_ uuid: String) -> HSSpace?

    // MARK: Mission Control

    /// The names Mission Control shows for each space, such as "Desktop 2" or "Safari". This
    /// opens Mission Control briefly to read them, and needs Accessibility permission. For a
    /// desktop's number without opening Mission Control, use `HSSpace.desktopNumber`.
    /// - Returns: {Promise<Record<string, string>>} A Promise that resolves to an object mapping
    ///   each space's ID to its name, or rejects with the reason they couldn't be read
    /// - Example:
    /// ```js
    /// hs.screen.missionControlNames().then(names => {
    ///     for (const space of hs.screen.allSpaces()) {
    ///         console.log(space.id + " is " + names[space.id])
    ///     }
    /// })
    /// ```
    @objc func missionControlNames() -> JSPromise?

    /// Opens Mission Control, and keeps it open until `closeMissionControl()`, even across other
    /// Spaces operations that use it. Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control is fully open, or
    ///   rejects with the reason it couldn't be opened
    /// - Example:
    /// ```js
    /// hs.screen.openMissionControl()
    ///     .then(() => hs.timer.doAfter(2, () => hs.screen.closeMissionControl()))
    /// ```
    @objc func openMissionControl() -> JSPromise?

    /// Closes Mission Control, if it's open. Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control has fully closed,
    ///   or rejects with the reason it couldn't be closed
    /// - Example:
    /// ```js
    /// hs.screen.closeMissionControl()
    /// ```
    @objc func closeMissionControl() -> JSPromise?

    /// Toggles Mission Control, like pressing its key. This returns straight away; use
    /// `openMissionControl()` or `closeMissionControl()` to know when it has finished.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "m", () => hs.screen.toggleMissionControl())
    /// ```
    @objc func toggleMissionControl()

    /// Toggles App Exposé (the current app's windows, on every space), like its trackpad gesture
    /// - Example:
    /// ```js
    /// hs.screen.toggleAppExpose()
    /// ```
    @objc func toggleAppExpose()

    /// Toggles Launchpad
    /// - Example:
    /// ```js
    /// hs.screen.toggleLaunchpad()
    /// ```
    @objc func toggleLaunchpad()

    /// Toggles Show Desktop, which moves every window aside to reveal the desktop
    /// - Example:
    /// ```js
    /// hs.screen.toggleShowDesktop()
    /// ```
    @objc func toggleShowDesktop()

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.screen.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSScreenEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.screen.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Implementation

/// Events emitted by hs.screen's watcher
nonisolated enum HSScreenEvent: String, HSEventName {
    case change
    case spaceChange
}

@_documentation(visibility: private)
@MainActor
@objc class HSScreenModule: NSObject, HSModuleAPI, HSScreenModuleAPI {
    var moduleName = "hs.screen"
    let engineID: UUID

    @objc var _watcherEmitter: JSFunction?
    @objc var _eventNames: [String] { HSScreenEvent.allNames }
    @objc var on: JSFunction?
    @objc var off: JSFunction?
    @objc var once: JSFunction?
    private var watcherCallback: JSCallback?
    private var watcherObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    /// Each managed display's current space when the watcher last looked, to tell which screen
    /// switched space
    private var lastCurrentSpaces: [String: HSSkyLight.SpaceID] = [:]

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = all().count
        return "<\(moduleName): \(n) display\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func all() -> [HSScreen] {
        NSScreen.screens.map { HSScreen(screen: $0) }
    }

    @objc func main() -> HSScreen? {
        guard let main = NSScreen.main else { return nil }
        return HSScreen(screen: main)
    }

    @objc func primary() -> HSScreen? {
        // NSScreen.screens[0] is always the primary display on macOS.
        guard let primary = NSScreen.screens.first else { return nil }
        return HSScreen(screen: primary)
    }

    // MARK: - Spaces

    @objc func spacesAvailable() -> Bool {
        HSSkyLight.shared != nil
    }

    @objc func screensHaveSeparateSpaces() -> Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    @objc func allSpaces() -> [HSSpace] {
        HSSpaces.shared.allSpaces()
    }

    @objc func focusedSpace() -> HSSpace? {
        guard let active = HSSkyLight.shared?.activeSpace, HSSpaces.shared.locate(active) != nil else { return nil }
        return HSSpace(id: active)
    }

    @objc func spaceForID(_ id: Int) -> HSSpace? {
        HSSpaces.shared.space(withID: id)
    }

    @objc func spaceForUUID(_ uuid: String) -> HSSpace? {
        guard !uuid.isEmpty else { return nil }
        let spaces = (HSSkyLight.shared?.managedDisplays() ?? []).flatMap(\.spaces)
        return spaces.first { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }.map { HSSpace(id: $0.id) }
    }

    // MARK: - Mission Control

    @objc func missionControlNames() -> JSPromise? {
        HSSpaces.shared.missionControlNames()
    }

    @objc func openMissionControl() -> JSPromise? {
        HSSpaces.shared.openMissionControl()
    }

    @objc func closeMissionControl() -> JSPromise? {
        HSSpaces.shared.closeMissionControl()
    }

    @objc func toggleMissionControl() {
        HSDockNotification.send(.missionControl)
    }

    @objc func toggleAppExpose() {
        HSDockNotification.send(.appExpose)
    }

    @objc func toggleLaunchpad() {
        HSDockNotification.send(.launchpad)
    }

    @objc func toggleShowDesktop() {
        HSDockNotification.send(.showDesktop)
    }

    // MARK: - Watcher

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("hs.screen._addWatcher: already watching — refusing second subscription")
            return false
        }
        watcherCallback = JSCallback(value: callback, owner: self)

        watcherObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireWatcherEvent() }
        }

        // Spaces are optional: without SkyLight, there are just no spaceChange events
        if HSSkyLight.shared != nil {
            lastCurrentSpaces = HSSpaces.shared.currentSpaces()
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.activeSpaceDidChange() }
            }
        }

        AKDebug("hs.screen._addWatcher: started")
        return true
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }

        if let observer = watcherObserver {
            NotificationCenter.default.removeObserver(observer)
            watcherObserver = nil
        }
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        lastCurrentSpaces = [:]
        watcherCallback?.detach(from: self)
        watcherCallback = nil

        AKDebug("hs.screen._removeWatcher: stopped")
    }

    private func fireWatcherEvent() {
        _ = watcherCallback?.call(withArguments: [HSScreenEvent.change.rawValue])
    }

    /// macOS only says that some space changed, so compare each display's current space with the
    /// last we saw, and report each screen that switched
    private func activeSpaceDidChange() {
        let current = HSSpaces.shared.currentSpaces()
        let previous = lastCurrentSpaces
        lastCurrentSpaces = current

        for (identifier, to) in current.sorted(by: { $0.key < $1.key }) where previous[identifier] != to {
            let details: [String: Any] = [
                "screen": HSSpaces.screen(forDisplayIdentifier: identifier).orNSNull,
                "from": previous[identifier].map { HSSpace(id: $0) }.orNSNull,
                "to": HSSpace(id: to),
            ]
            _ = watcherCallback?.call(withArguments: [HSScreenEvent.spaceChange.rawValue, details])
        }
    }
}
