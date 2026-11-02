//
//  HSSpacesModule.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

// MARK: - JavaScript API

/// Inspect and control Spaces (Mission Control's virtual desktops).
///
/// > Warning: macOS has no public API for Spaces. This module uses private functions from
/// > Apple's SkyLight framework, which Apple can change or remove in any macOS update without
/// > notice. If that happens, parts of this module may stop working, return wrong results, or
/// > (in the worst case) misbehave. `hs.spaces.isAvailable()` reports whether the private
/// > functions could be found at all, but it cannot detect one whose behaviour has changed.
///
/// Adding, removing, and switching spaces works by briefly opening Mission Control and pressing
/// its buttons through the Accessibility API, since only the Dock can make those changes. These
/// functions need Accessibility permission, return Promises, and visibly open Mission Control.
/// They also depend on Mission Control's undocumented internal UI, so they can break in a macOS
/// update too.
///
/// Spaces are identified by numeric IDs. These are stable for the lifetime of a space, but are
/// not the "Desktop 1", "Desktop 2", etc. numbers Mission Control shows, and a space that is
/// removed and re-added gets a new ID. Displays are identified by their UUID, matching
/// `HSScreen.uuid`.
///
/// ## Inspecting spaces
///
/// ```javascript
/// console.log("Focused space: " + hs.spaces.focusedSpace())
///
/// const all = hs.spaces.allSpaces()   // { "<screen uuid>": [spaceID, ...], ... }
/// for (const uuid in all) {
///     console.log(uuid + " has " + all[uuid].length + " spaces")
/// }
/// ```
///
/// ## Switching spaces
///
/// ```javascript
/// const spaces = hs.spaces.spacesForScreen()
/// const next = spaces[(spaces.indexOf(hs.spaces.activeSpaceOnScreen()) + 1) % spaces.length]
/// await hs.spaces.gotoSpace(next)
/// ```
///
/// ## Adding and removing spaces
///
/// ```javascript
/// const id = await hs.spaces.addSpaceToScreen()
/// // ...later...
/// await hs.spaces.removeSpace(id)
/// ```
///
/// ## Watching for space changes
///
/// ```javascript
/// hs.spaces.on('change', () => {
///     console.log("Now on space " + hs.spaces.focusedSpace())
/// })
/// ```
@objc protocol HSSpacesModuleAPI: JSExport {
    /// Whether the private macOS functions this module relies on could be found. If this is
    /// `false`, every other function in the module returns an empty or failure result.
    ///
    /// A `true` result does not guarantee every function works - it only means none of them
    /// have been removed. Apple can still change how they behave.
    /// - Returns: `true` if the private SkyLight functions are available, otherwise `false`
    /// - Example:
    /// ```js
    /// if (!hs.spaces.isAvailable()) {
    ///     console.error("hs.spaces doesn't work on this version of macOS")
    /// }
    /// ```
    @objc func isAvailable() -> Bool

    /// Whether each display has its own set of spaces ("Displays have separate Spaces" in the
    /// Desktop & Dock section of System Settings). When this is off, all displays share a single
    /// set of spaces, which are reported against the primary display.
    /// - Returns: `true` if displays have separate spaces, otherwise `false`
    /// - Example:
    /// ```js
    /// console.log("Separate spaces: " + hs.spaces.screensHaveSeparateSpaces())
    /// ```
    @objc func screensHaveSeparateSpaces() -> Bool

    /// The ID of the space that currently has keyboard focus - the active space on the display
    /// containing the focused window.
    /// - Returns: A space ID, or `0` if it can't be determined
    /// - Example:
    /// ```js
    /// console.log("Focused space: " + hs.spaces.focusedSpace())
    /// ```
    @objc func focusedSpace() -> Int

    /// Every space on every display.
    /// - Returns: {Record<string, number[]>} An object mapping each display's UUID to an array of its space IDs, in Mission Control order
    /// - Example:
    /// ```js
    /// const all = hs.spaces.allSpaces()
    /// for (const uuid in all) {
    ///     console.log(uuid + ": " + all[uuid].join(", "))
    /// }
    /// ```
    @objc func allSpaces() -> [String: [Int]]

    /// The space currently shown on each display.
    /// - Returns: {Record<string, number>} An object mapping each display's UUID to the ID of the space currently shown on it
    /// - Example:
    /// ```js
    /// const active = hs.spaces.activeSpaces()
    /// for (const uuid in active) {
    ///     console.log(uuid + " is showing space " + active[uuid])
    /// }
    /// ```
    @objc func activeSpaces() -> [String: Int]

    /// The spaces on a display.
    /// - Parameter screen?: The display to inspect. Defaults to the main screen (see `hs.screen.main()`)
    /// - Returns: An array of space IDs, in Mission Control order. Empty if the display can't be found
    /// - Example:
    /// ```js
    /// const spaces = hs.spaces.spacesForScreen(hs.screen.primary())
    /// console.log("Primary display has " + spaces.length + " spaces")
    /// ```
    @objc func spacesForScreen(_ screen: HSScreen?) -> [Int]

    /// The space currently shown on a display.
    /// - Parameter screen?: The display to inspect. Defaults to the main screen (see `hs.screen.main()`)
    /// - Returns: {number | null} A space ID, or `null` if the display can't be found
    /// - Example:
    /// ```js
    /// console.log("Main screen is showing space " + hs.spaces.activeSpaceOnScreen())
    /// ```
    @objc func activeSpaceOnScreen(_ screen: HSScreen?) -> NSNumber?

    /// What kind of space a space is.
    /// - Parameter spaceID: The ID of the space to inspect
    /// - Returns: {"user" | "fullscreen" | "system" | "unknown" | null} `"user"` for a regular desktop, `"fullscreen"` for a space holding a fullscreen or Split View app, `"system"` for a space macOS uses internally, `"unknown"` for any other kind, or `null` if no such space exists
    /// - Example:
    /// ```js
    /// console.log(hs.spaces.spaceType(hs.spaces.focusedSpace()))
    /// ```
    @objc func spaceType(_ spaceID: Int) -> String?

    /// The display a space belongs to.
    /// - Parameter spaceID: The ID of the space to inspect
    /// - Returns: An HSScreen object, or `null` if no such space exists or its display can't be found
    /// - Example:
    /// ```js
    /// const screen = hs.spaces.spaceScreen(hs.spaces.focusedSpace())
    /// console.log(screen && screen.name)
    /// ```
    @objc func spaceScreen(_ spaceID: Int) -> HSScreen?

    /// The spaces a window is on. This is usually a single space, but windows set to appear on
    /// all desktops are on all of them.
    /// - Parameter window: The window to inspect
    /// - Returns: An array of space IDs. Empty if the window can't be found
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// if (win) console.log("Focused window is on " + hs.spaces.windowSpaces(win).join(", "))
    /// ```
    @objc func windowSpaces(_ window: HSWindow) -> [Int]

    /// The spaces a window is on, looked up by its window ID. Use this for the IDs
    /// `windowsForSpace()` returns, since windows on other spaces often have no HSWindow object.
    /// - Parameter windowID: The ID of the window to inspect (see `HSWindow.id`)
    /// - Returns: An array of space IDs. Empty if the window can't be found
    /// - Example:
    /// ```js
    /// for (const id of hs.spaces.windowsForSpace(hs.spaces.focusedSpace())) {
    ///     console.log("Window " + id + " is on " + hs.spaces.windowSpacesForID(id).join(", "))
    /// }
    /// ```
    @objc func windowSpacesForID(_ windowID: Int) -> [Int]

    /// The windows on a space, including spaces that aren't currently visible.
    ///
    /// This returns window IDs rather than HSWindow objects, because macOS often won't hand out
    /// the accessibility objects HSWindow is built on for windows on other spaces. Compare them
    /// with `HSWindow.id` to find the corresponding HSWindow objects. Only regular windows are
    /// included, not menus, panels floating above other windows, and so on.
    /// - Parameter spaceID: The ID of the space to inspect
    /// - Returns: An array of window IDs. Empty if no such space exists
    /// - Example:
    /// ```js
    /// const ids = hs.spaces.windowsForSpace(hs.spaces.focusedSpace())
    /// const wins = hs.window.allWindows().filter(w => ids.includes(w.id))
    /// wins.forEach(w => console.log(w.title))
    /// ```
    @objc func windowsForSpace(_ spaceID: Int) -> [Int]

    /// Switch a display to one of its spaces, by opening Mission Control and clicking the space.
    /// The display is the one the space belongs to. Requires Accessibility permission.
    /// - Parameter spaceID: The ID of the space to switch to
    /// - Returns: {Promise<void>} A Promise that resolves once the display is showing the space, or rejects with the reason it couldn't be switched to
    /// - Example:
    /// ```js
    /// const spaces = hs.spaces.spacesForScreen()
    /// hs.spaces.gotoSpace(spaces[0]).catch(err => console.error(err))
    /// ```
    @objc func gotoSpace(_ spaceID: Int) -> JSPromise?

    /// Add a new desktop to a display, by opening Mission Control and clicking its "add desktop"
    /// button. The new desktop goes after the display's existing spaces. Mission Control is closed
    /// again afterwards, unless it was already open. Requires Accessibility permission.
    /// - Parameter screen?: The display to add a desktop to. Defaults to the main screen (see `hs.screen.main()`)
    /// - Returns: {Promise<number>} A Promise that resolves to the new space's ID, or rejects with the reason it couldn't be added
    /// - Example:
    /// ```js
    /// hs.spaces.addSpaceToScreen(hs.screen.primary())
    ///     .then(id => console.log("Added space " + id))
    ///     .catch(err => console.error(err))
    /// ```
    @objc func addSpaceToScreen(_ screen: HSScreen?) -> JSPromise?

    /// Remove a desktop, by opening Mission Control and clicking the desktop's close button. Any
    /// windows on it move to another desktop, as when you remove one yourself. Mission Control is
    /// closed again afterwards, unless it was already open. Requires Accessibility permission.
    ///
    /// Fullscreen spaces can't be removed this way (take the app out of fullscreen instead), and
    /// neither can the last desktop on a display.
    /// - Parameter spaceID: The ID of the space to remove
    /// - Returns: {Promise<void>} A Promise that resolves once the space has gone, or rejects with the reason it couldn't be removed
    /// - Example:
    /// ```js
    /// const spaces = hs.spaces.spacesForScreen()
    /// hs.spaces.removeSpace(spaces[spaces.length - 1]).catch(err => console.error(err))
    /// ```
    @objc func removeSpace(_ spaceID: Int) -> JSPromise?

    /// The raw description of every display and space that macOS's window server keeps, as
    /// returned by the private SkyLight function `SLSCopyManagedDisplaySpaces`. The rest of this
    /// module is built on it. It's provided for exploring and debugging: its layout is undocumented
    /// and can change in any macOS update.
    /// - Returns: {Record<string, any>[]} An array with one object per display, or an empty array if hs.spaces is unavailable
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.spaces.managedDisplaySpaces(), null, 2))
    /// ```
    @objc func managedDisplaySpaces() -> [[String: Any]]

    // MARK: Mission Control

    /// The names Mission Control shows for each space ("Desktop 1", or the app names of a
    /// fullscreen space), read by briefly opening Mission Control. These are for showing to people;
    /// every other function in this module identifies spaces by ID. Mission Control is closed again
    /// afterwards, unless it was already open. Requires Accessibility permission.
    /// - Returns: {Promise<Record<string, Record<string, string>>>} A Promise that resolves to an object mapping each display's UUID to an object mapping its space IDs to their names, or rejects with the reason they couldn't be read
    /// - Example:
    /// ```js
    /// hs.spaces.missionControlSpaceNames().then(names => {
    ///     for (const uuid in names) {
    ///         for (const id in names[uuid]) console.log(id + ": " + names[uuid][id])
    ///     }
    /// }).catch(err => console.error(err))
    /// ```
    @objc func missionControlSpaceNames() -> JSPromise?

    /// Open Mission Control, if it isn't already open.
    ///
    /// `gotoSpace()`, `addSpaceToScreen()`, `removeSpace()` and `missionControlSpaceNames()` each
    /// open Mission Control themselves and close it afterwards, but leave it open if it already
    /// was. So to make several changes with a single trip into Mission Control, open it first and
    /// close it once they've all finished. Requires Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control is fully open, or rejects with the reason it couldn't be opened
    /// - Example:
    /// ```js
    /// async function addTwoDesktops() {
    ///     await hs.spaces.openMissionControl()
    ///     try {
    ///         await hs.spaces.addSpaceToScreen()
    ///         await hs.spaces.addSpaceToScreen()
    ///     } finally {
    ///         await hs.spaces.closeMissionControl()
    ///     }
    /// }
    /// addTwoDesktops().catch(err => console.error(err))
    /// ```
    @objc func openMissionControl() -> JSPromise?

    /// Close Mission Control, if it's open. Requires Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control has fully closed, or rejects with the reason it couldn't be closed
    /// - Example:
    /// ```js
    /// hs.spaces.closeMissionControl().catch(err => console.error(err))
    /// ```
    @objc func closeMissionControl() -> JSPromise?

    /// Show or hide Mission Control, as its keyboard shortcut, hot corner or trackpad gesture does.
    ///
    /// This returns straight away, before Mission Control has finished opening or closing. Use
    /// `openMissionControl()` and `closeMissionControl()` instead to find out when it has.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "up", () => hs.spaces.toggleMissionControl())
    /// ```
    @objc func toggleMissionControl()

    /// Show or hide App Exposé (all the windows of the frontmost app), as its keyboard shortcut,
    /// hot corner or trackpad gesture does.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "down", () => hs.spaces.toggleAppExpose())
    /// ```
    @objc func toggleAppExpose()

    /// Show or hide Launchpad (called Apps on macOS 26 and later), as its keyboard shortcut, hot
    /// corner or trackpad gesture does.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "l", () => hs.spaces.toggleLaunchpad())
    /// ```
    @objc func toggleLaunchpad()

    /// Move every window aside to show the desktop, or put them back, as the Show Desktop keyboard
    /// shortcut, hot corner or trackpad gesture does.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "d", () => hs.spaces.toggleShowDesktop())
    /// ```
    @objc func toggleShowDesktop()

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.spaces.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSSpacesEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.spaces.js. They must be real, pre-declared properties (not
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

/// Events emitted by hs.spaces's watcher
nonisolated enum HSSpacesEvent: String, HSEventName {
    case change
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpacesModule: NSObject, HSModuleAPI, HSSpacesModuleAPI {
    var moduleName = "hs.spaces"
    let engineID: UUID

    /// SkyLight's managed display identifier when all displays share one set of spaces
    private static let sharedSpacesDisplayIdentifier = "Main"

    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSSpacesEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var watcherCallback: JSCallback?
    private var watcherObserver: NSObjectProtocol?

    /// Mission Control operations in flight, so shutdown() can cancel them. Each one waits for the
    /// previous one to finish, since they'd otherwise fight over opening and closing Mission Control.
    private var missionControlTasks: [UUID: Task<Void, Never>] = [:]
    private var lastMissionControlTask: Task<Void, Never>?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        for task in missionControlTasks.values {
            task.cancel()
        }
        missionControlTasks.removeAll()
        lastMissionControlTask = nil
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
        guard let skyLight = HSSkyLight.shared else {
            return "<\(moduleName): unavailable>"
        }
        let n = skyLight.managedDisplays().reduce(0) { $0 + $1.spaces.count }
        return "<\(moduleName): \(n) space\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Helpers

    /// The UUID of the screen a managed display identifier refers to. When displays share
    /// spaces, SkyLight reports them all as one display called "Main" - attribute that to the
    /// primary screen.
    private func screenUUID(forDisplayIdentifier identifier: String) -> String {
        if identifier == Self.sharedSpacesDisplayIdentifier, let primary = NSScreen.screens.first {
            return HSScreen(screen: primary).uuid
        }
        return identifier
    }

    /// The managed display a screen belongs to, defaulting to the main screen
    private func managedDisplay(for screen: HSScreen?) -> HSSkyLight.ManagedDisplay? {
        guard let skyLight = HSSkyLight.shared else { return nil }
        guard let uuid = screen?.uuid ?? NSScreen.main.map({ HSScreen(screen: $0).uuid }) else { return nil }

        let displays = skyLight.managedDisplays()
        return displays.first { $0.identifier == uuid }
            ?? displays.first { $0.identifier == Self.sharedSpacesDisplayIdentifier }
    }

    /// `spaceID` as a SkyLight space ID, if it names a space that currently exists. SkyLight
    /// happily answers questions about made-up space IDs, so every input is checked first.
    private func existingSpace(_ spaceID: Int) -> HSSkyLight.SpaceID? {
        guard let skyLight = HSSkyLight.shared, let space = HSSkyLight.SpaceID(exactly: spaceID) else { return nil }
        let exists = skyLight.managedDisplays().contains { $0.spaces.contains(space) }
        return exists ? space : nil
    }

    private func windowID(_ id: Int) -> CGWindowID? {
        guard let id = CGWindowID(exactly: id), id != 0 else { return nil }
        return id
    }

    // MARK: - Spaces

    @objc func isAvailable() -> Bool {
        HSSkyLight.shared != nil
    }

    @objc func screensHaveSeparateSpaces() -> Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    @objc func focusedSpace() -> Int {
        guard let skyLight = HSSkyLight.shared else { return 0 }
        return Int(clamping: skyLight.activeSpace)
    }

    @objc func allSpaces() -> [String: [Int]] {
        guard let skyLight = HSSkyLight.shared else { return [:] }
        var result: [String: [Int]] = [:]
        for display in skyLight.managedDisplays() {
            result[screenUUID(forDisplayIdentifier: display.identifier)] = display.spaces.map { Int(clamping: $0) }
        }
        return result
    }

    @objc func activeSpaces() -> [String: Int] {
        guard let skyLight = HSSkyLight.shared else { return [:] }
        var result: [String: Int] = [:]
        for display in skyLight.managedDisplays() {
            if let current = display.currentSpace {
                result[screenUUID(forDisplayIdentifier: display.identifier)] = Int(clamping: current)
            }
        }
        return result
    }

    @objc func spacesForScreen(_ screen: HSScreen?) -> [Int] {
        managedDisplay(for: screen)?.spaces.map { Int(clamping: $0) } ?? []
    }

    @objc func activeSpaceOnScreen(_ screen: HSScreen?) -> NSNumber? {
        guard let current = managedDisplay(for: screen)?.currentSpace else { return nil }
        return NSNumber(value: Int(clamping: current))
    }

    @objc func spaceType(_ spaceID: Int) -> String? {
        guard let skyLight = HSSkyLight.shared, let space = existingSpace(spaceID) else { return nil }
        switch HSSkyLight.SpaceKind(rawValue: skyLight.type(of: space)) {
        case .user: return "user"
        case .fullscreen: return "fullscreen"
        case .system: return "system"
        case nil: return "unknown"
        }
    }

    @objc func spaceScreen(_ spaceID: Int) -> HSScreen? {
        guard let skyLight = HSSkyLight.shared,
              let space = existingSpace(spaceID),
              let identifier = skyLight.displayIdentifier(for: space) else { return nil }

        let uuid = screenUUID(forDisplayIdentifier: identifier)
        return NSScreen.screens.lazy.map { HSScreen(screen: $0) }.first { $0.uuid == uuid }
    }

    // MARK: - Windows

    @objc func windowSpaces(_ window: HSWindow) -> [Int] {
        windowSpacesForID(window.id)
    }

    @objc func windowSpacesForID(_ windowID: Int) -> [Int] {
        guard let skyLight = HSSkyLight.shared, let id = self.windowID(windowID) else { return [] }
        return skyLight.spaces(forWindow: id).map { Int(clamping: $0) }
    }

    @objc func windowsForSpace(_ spaceID: Int) -> [Int] {
        guard let skyLight = HSSkyLight.shared, let space = existingSpace(spaceID) else { return [] }

        // SkyLight lists every window on the space, including menus, the menu bar, panels, etc.
        // Keep only those in the normal window layer, which is what users mean by "windows".
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let normalWindows = Set(info.compactMap { window -> CGWindowID? in
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })

        return skyLight.windows(onSpace: space)
            .filter { normalWindows.contains($0) }
            .map { Int($0) }
    }

    // MARK: - Actions

    @objc func gotoSpace(_ spaceID: Int) -> JSPromise? {
        runInMissionControl("gotoSpace") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            let (space, display) = try self.spaceAndDisplay(spaceID)
            guard display.currentSpace != space else { return nil }

            let bar = try await self.openSpacesBar(for: display)
            try HSMissionControl.press(bar.spaceButtons[display.spaces.firstIndex(of: space)!])

            // Clicking a space closes Mission Control. Wait for it to finish animating away too, so
            // nothing toggles Mission Control again mid-animation.
            try await HSMissionControl.waitUntil("macOS did not switch to space \(spaceID)") {
                skyLight.managedDisplays().first { $0.identifier == display.identifier }?.currentSpace == space
                    && HSMissionControl.isClosed
            }
            return nil
        }
    }

    @objc func addSpaceToScreen(_ screen: HSScreen?) -> JSPromise? {
        runInMissionControl("addSpaceToScreen") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            guard let display = self.managedDisplay(for: screen) else { throw HSMissionControl.Failure("no such screen") }

            let bar = try await self.openSpacesBar(for: display)
            guard let addButton = bar.addButton else { throw HSMissionControl.Failure("Mission Control has no add desktop button") }
            try HSMissionControl.press(addButton)

            let existing = Set(display.spaces)
            var added: HSSkyLight.SpaceID?
            try await HSMissionControl.waitUntil("macOS did not add a space") {
                added = skyLight.managedDisplays().first { $0.identifier == display.identifier }?.spaces.first { !existing.contains($0) }
                return added != nil
            }
            return added.map { Int(clamping: $0) }
        }
    }

    @objc func removeSpace(_ spaceID: Int) -> JSPromise? {
        runInMissionControl("removeSpace") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            let (space, display) = try self.spaceAndDisplay(spaceID)
            guard skyLight.type(of: space) == HSSkyLight.SpaceKind.user.rawValue else {
                throw HSMissionControl.Failure("space \(spaceID) is not a desktop")
            }
            let userSpaces = display.spaces.filter { skyLight.type(of: $0) == HSSkyLight.SpaceKind.user.rawValue }
            guard userSpaces.count > 1 else { throw HSMissionControl.Failure("space \(spaceID) is the only desktop on its display") }

            let bar = try await self.openSpacesBar(for: display)
            let button = bar.spaceButtons[display.spaces.firstIndex(of: space)!]
            // Removing is destructive, so double check this really is the right button: Mission
            // Control numbers desktops (but not fullscreen spaces) from 1 in its titles
            let expectedNumber = userSpaces.firstIndex(of: space)! + 1
            if let number = HSMissionControl.desktopNumber(of: button), number != expectedNumber {
                throw HSMissionControl.Failure("Mission Control's desktop \(number) doesn't look like space \(spaceID) (desktop \(expectedNumber)); not removing it")
            }
            guard HSMissionControl.actions(of: button).contains(HSMissionControl.removeDesktopAction) else {
                throw HSMissionControl.Failure("Mission Control won't remove space \(spaceID)")
            }
            try HSMissionControl.perform(HSMissionControl.removeDesktopAction, on: button)

            try await HSMissionControl.waitUntil("macOS did not remove space \(spaceID)") {
                !skyLight.managedDisplays().contains { $0.spaces.contains(space) }
            }
            return nil
        }
    }

    /// Runs `operation` once any earlier Mission Control operation has finished, settling the
    /// returned Promise with its result. Failures reject with "hs.spaces.<name>(): <reason>".
    /// Whether it succeeds or not, Mission Control is closed afterwards unless it was already open
    /// or `leaveOpen` is set (switching spaces closes it regardless, as clicking a space always does).
    private func runInMissionControl(_ name: String,
                                     leaveOpen: Bool = false,
                                     _ operation: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard HSSkyLight.shared != nil else {
            return context.createRejectedPromise(with: "hs.spaces.\(name)(): hs.spaces is unavailable on this version of macOS")
        }
        guard AXIsProcessTrusted() else {
            return context.createRejectedPromise(with: "hs.spaces.\(name)(): Accessibility permission is required")
        }

        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            let id = UUID()
            let previous = self.lastMissionControlTask
            let task = Task { [weak self] in
                await previous?.value
                defer { self?.missionControlTasks[id] = nil }

                let result: Result<Any?, any Error>
                // Stays nil if the task was cancelled (or never settled) before reading the state,
                // in which case Mission Control is left alone
                var wasOpen: Bool?
                do {
                    try Task.checkCancellation()
                    // Let any opening/closing animation finish first, or it's unclear which it'll end up as
                    try await HSMissionControl.waitUntilSettled()
                    wasOpen = HSMissionControl.isOpen
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                if wasOpen == false && !leaveOpen {
                    do {
                        try await HSMissionControl.close()
                    } catch {
                        AKWarning("hs.spaces.\(name)(): \(error.localizedDescription)")
                    }
                }

                switch result {
                case .success(let value):
                    // A nil result would reach JS as null - Promise<void> should give undefined
                    holder.resolveWith(value ?? JSValue(undefinedIn: context))
                case .failure(is CancellationError):
                    // The module is shutting down - the Promise's context is going away with it
                    break
                case .failure(let error):
                    AKWarning("hs.spaces.\(name)(): \(error.localizedDescription)")
                    holder.rejectWithMessage("hs.spaces.\(name)(): \(error.localizedDescription)")
                }
            }
            self.missionControlTasks[id] = task
            self.lastMissionControlTask = task
        }
    }

    /// The SkyLight space for `spaceID` and the managed display holding it
    private func spaceAndDisplay(_ spaceID: Int) throws -> (HSSkyLight.SpaceID, HSSkyLight.ManagedDisplay) {
        guard let space = existingSpace(spaceID),
              let display = HSSkyLight.shared?.managedDisplays().first(where: { $0.spaces.contains(space) }) else {
            throw HSMissionControl.Failure("no such space: \(spaceID)")
        }
        return (space, display)
    }

    /// Opens Mission Control and finds the Spaces bar for `display`
    private func openSpacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        try await HSMissionControl.open()
        return try await spacesBar(for: display)
    }

    /// The Spaces bar for `display`, once Mission Control is open
    private func spacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        let uuid = screenUUID(forDisplayIdentifier: display.identifier)
        guard let screen = NSScreen.screens.lazy.map({ HSScreen(screen: $0) }).first(where: { $0.uuid == uuid }) else {
            throw HSMissionControl.Failure("no screen for display \(display.identifier)")
        }
        return try await HSMissionControl.spacesBar(for: screen.displayID, expectedCount: display.spaces.count)
    }

    @objc func managedDisplaySpaces() -> [[String: Any]] {
        HSSkyLight.shared?.rawManagedDisplaySpaces() ?? []
    }

    // MARK: - Mission Control

    @objc func missionControlSpaceNames() -> JSPromise? {
        runInMissionControl("missionControlSpaceNames") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            try await HSMissionControl.open()

            var result: [String: [String: String]] = [:]
            for display in skyLight.managedDisplays() {
                let bar = try await self.spacesBar(for: display)
                var names: [String: String] = [:]
                for (space, button) in zip(display.spaces, bar.spaceButtons) {
                    names[String(space)] = HSMissionControl.name(of: button)
                }
                result[self.screenUUID(forDisplayIdentifier: display.identifier)] = names
            }
            return result
        }
    }

    @objc func openMissionControl() -> JSPromise? {
        runInMissionControl("openMissionControl", leaveOpen: true) {
            try await HSMissionControl.open()
            return nil
        }
    }

    @objc func closeMissionControl() -> JSPromise? {
        runInMissionControl("closeMissionControl") {
            try await HSMissionControl.close()
            return nil
        }
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
            AKWarning("hs.spaces._addWatcher: already watching — refusing second subscription")
            return false
        }
        watcherCallback = JSCallback(value: callback, owner: self)

        watcherObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireWatcherEvent() }
        }

        AKDebug("hs.spaces._addWatcher: started")
        return true
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }

        if let observer = watcherObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            watcherObserver = nil
        }
        watcherCallback?.detach(from: self)
        watcherCallback = nil

        AKDebug("hs.spaces._removeWatcher: stopped")
    }

    private func fireWatcherEvent() {
        _ = watcherCallback?.call(withArguments: [HSSpacesEvent.change.rawValue])
    }
}
