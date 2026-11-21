//
//  HSSpacesModule.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

// MARK: - JavaScript API

/// Inspect and control Spaces (Mission Control's desktops and fullscreen app spaces).
///
/// ## How Spaces work
///
/// Each display has its own ordered list of spaces, and shows one of them at a time: its
/// *current* space. Every space belongs to exactly one display. The *focused* space is the
/// current space of whichever display has keyboard focus. So this module is organised around
/// displays: `hs.spaces.displays()` gives you an `HSSpacesDisplay` for each one, which has its
/// `spaces` and its `currentSpace`, and every `HSSpace` knows its `display`.
///
/// This relies on "Displays have separate Spaces" being turned on in System Settings → Desktop &
/// Dock, which is macOS's default. If it's off, macOS treats all your displays as a single one,
/// and so does this module.
///
/// Spaces are identified by numeric IDs, which last as long as the space does. Each space also
/// has a UUID, which macOS keeps across logins, so to find the same space in a later session,
/// save its `uuid` and look it up with `hs.spaces.spaceForUUID()`.
///
/// > Warning: macOS has no public API for Spaces. This module uses private functions from
/// > Apple's SkyLight framework, which Apple can change or remove in any macOS update without
/// > notice. If that happens, parts of this module may stop working or return wrong results.
/// > `hs.spaces.isAvailable()` reports whether the private functions could be found at all, but
/// > it can't detect one whose behaviour has changed.
///
/// Adding, removing, and switching spaces works by briefly opening Mission Control and clicking
/// its buttons through the Accessibility API, since only macOS itself can make those changes.
/// These need Accessibility permission, return Promises, and visibly open Mission Control. They
/// depend on Mission Control's undocumented internal UI, so they can break in a macOS update too.
/// Moving a window to another space doesn't need Mission Control.
///
/// ## Inspecting spaces
///
/// ```javascript
/// for (const display of hs.spaces.displays()) {
///     console.log(display.screen.name + " is showing space " + display.currentSpace.id)
///     for (const space of display.spaces) {
///         console.log("  " + space.id + ": " + space.type)
///     }
/// }
/// ```
///
/// ## Switching spaces
///
/// ```javascript
/// // Switch the focused display to its next space
/// const display = hs.spaces.focusedSpace().display
/// const spaces = display.spaces
/// const index = spaces.findIndex(s => s.isCurrent)
/// spaces[(index + 1) % spaces.length].goto()
/// ```
///
/// ## Adding and removing desktops
///
/// ```javascript
/// hs.spaces.focusedSpace().display.addSpace()
///     .then(space => {
///         console.log("Added space " + space.id)
///         return space.remove()
///     })
///     .catch(err => console.error(err))
/// ```
///
/// ## Moving windows between spaces
///
/// ```javascript
/// // Send the focused window to the focused display's last desktop
/// const desktops = hs.spaces.focusedSpace().display.spaces.filter(s => s.type === "desktop")
/// desktops[desktops.length - 1].moveWindow(hs.window.focusedWindow())
/// ```
///
/// ## Watching for space changes
///
/// ```javascript
/// hs.spaces.on('change', ({ display, from, to }) => {
///     console.log(display.screen.name + " switched to space " + to.id)
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

    /// Whether each display has its own spaces ("Displays have separate Spaces" in System
    /// Settings → Desktop & Dock). This module expects it to be on, which is macOS's default.
    /// If it's off, all displays share one set of spaces, and `displays()` returns a single
    /// display.
    /// - Returns: `true` if each display has its own spaces
    /// - Example:
    /// ```js
    /// if (!hs.spaces.screensHaveSeparateSpaces()) {
    ///     console.warn("Turn on 'Displays have separate Spaces' for per-display spaces")
    /// }
    /// ```
    @objc func screensHaveSeparateSpaces() -> Bool

    /// Every display and its spaces, in the order macOS lists them, which is also the order
    /// Mission Control numbers desktops in
    /// - Returns: An array of HSSpacesDisplay objects
    /// - Example:
    /// ```js
    /// for (const display of hs.spaces.displays()) {
    ///     console.log(display.screen.name + ": " + display.spaces.length + " spaces")
    /// }
    /// ```
    @objc func displays() -> [HSSpacesDisplay]

    /// The display holding a screen's spaces
    /// - Parameter screen: The screen
    /// - Returns: The screen's HSSpacesDisplay, or `null` if macOS has no spaces for it
    /// - Example:
    /// ```js
    /// const display = hs.spaces.displayForScreen(hs.screen.main())
    /// console.log("The main screen has " + display.spaces.length + " spaces")
    /// ```
    @objc func displayForScreen(_ screen: HSScreen) -> HSSpacesDisplay?

    /// Every space on every display, display by display, each in Mission Control's order
    /// - Returns: An array of HSSpace objects
    /// - Example:
    /// ```js
    /// const fullscreen = hs.spaces.allSpaces().filter(s => s.type === "fullscreen")
    /// console.log(fullscreen.length + " fullscreen apps")
    /// ```
    @objc func allSpaces() -> [HSSpace]

    /// The focused space: the space showing on the display with keyboard focus
    /// - Returns: The focused HSSpace, or `null` if it can't be found
    /// - Example:
    /// ```js
    /// console.log("Focused space: " + hs.spaces.focusedSpace().id)
    /// ```
    @objc func focusedSpace() -> HSSpace?

    /// Finds a space by its ID
    /// - Parameter id: The space's ID
    /// - Returns: The HSSpace, or `null` if there's no space with that ID
    /// - Example:
    /// ```js
    /// const space = hs.spaces.spaceForID(3)
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
    /// const work = workUUID ? hs.spaces.spaceForUUID(workUUID) : null
    /// ```
    @objc func spaceForUUID(_ uuid: String) -> HSSpace?

    /// The spaces a window is on. That's usually one, but windows set to appear on every space
    /// are on all of them.
    /// - Parameter window: The window
    /// - Returns: An array of HSSpace objects, empty if the window isn't on any space
    /// - Example:
    /// ```js
    /// const spaces = hs.spaces.spacesForWindow(hs.window.focusedWindow())
    /// console.log("The focused window is on space " + spaces[0].id)
    /// ```
    @objc func spacesForWindow(_ window: HSWindow) -> [HSSpace]

    /// The spaces a window is on, by its ID. This is the same as `spacesForWindow()`, for
    /// windows you only have the ID of (such as those from `HSSpace.windowIDs()`).
    /// - Parameter windowID: The window's ID
    /// - Returns: An array of HSSpace objects, empty if there's no such window
    /// - Example:
    /// ```js
    /// const space = hs.spaces.allSpaces()[0]
    /// for (const id of space.windowIDs()) {
    ///     console.log(id + " is on " + hs.spaces.spacesForWindowID(id).length + " space(s)")
    /// }
    /// ```
    @objc func spacesForWindowID(_ windowID: Int) -> [HSSpace]

    /// The names Mission Control shows for each space, such as "Desktop 2" or "Safari". This
    /// opens Mission Control briefly to read them, and needs Accessibility permission. For a
    /// desktop's number without opening Mission Control, use `HSSpace.desktopNumber`.
    /// - Returns: {Promise<Record<string, string>>} A Promise that resolves to an object mapping
    ///   each space's ID to its name, or rejects with the reason they couldn't be read
    /// - Example:
    /// ```js
    /// hs.spaces.missionControlNames().then(names => {
    ///     for (const space of hs.spaces.allSpaces()) {
    ///         console.log(space.id + " is " + names[space.id])
    ///     }
    /// })
    /// ```
    @objc func missionControlNames() -> JSPromise?

    /// Opens Mission Control, and keeps it open until `closeMissionControl()`, even across other
    /// hs.spaces functions that use it. Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control is fully open, or
    ///   rejects with the reason it couldn't be opened
    /// - Example:
    /// ```js
    /// hs.spaces.openMissionControl()
    ///     .then(() => hs.timer.doAfter(2, () => hs.spaces.closeMissionControl()))
    /// ```
    @objc func openMissionControl() -> JSPromise?

    /// Closes Mission Control, if it's open. Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once Mission Control has fully closed,
    ///   or rejects with the reason it couldn't be closed
    /// - Example:
    /// ```js
    /// hs.spaces.closeMissionControl()
    /// ```
    @objc func closeMissionControl() -> JSPromise?

    /// Toggles Mission Control, like pressing its key. This returns straight away; use
    /// `openMissionControl()` or `closeMissionControl()` to know when it has finished.
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "alt"], "m", () => hs.spaces.toggleMissionControl())
    /// ```
    @objc func toggleMissionControl()

    /// Toggles App Exposé (the current app's windows, on every space), like its trackpad gesture
    /// - Example:
    /// ```js
    /// hs.spaces.toggleAppExpose()
    /// ```
    @objc func toggleAppExpose()

    /// Toggles Launchpad
    /// - Example:
    /// ```js
    /// hs.spaces.toggleLaunchpad()
    /// ```
    @objc func toggleLaunchpad()

    /// Toggles Show Desktop, which moves every window aside to reveal the desktop
    /// - Example:
    /// ```js
    /// hs.spaces.toggleShowDesktop()
    /// ```
    @objc func toggleShowDesktop()

    // MARK: - Watcher (private API consumed by hs.spaces.js)

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

    @objc var _watcherEmitter: JSFunction?
    @objc var _eventNames: [String] { HSSpacesEvent.allNames }
    @objc var on: JSFunction?
    @objc var off: JSFunction?
    @objc var once: JSFunction?
    private var watcherCallback: JSCallback?
    private var watcherObserver: NSObjectProtocol?
    /// Each display's current space when the watcher last looked, to tell which display changed
    private var lastCurrentSpaces: [String: HSSkyLight.SpaceID] = [:]

    /// Operations in flight, so shutdown() can cancel them
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// The most recent Mission Control operation. Each one waits for the previous one to finish,
    /// since they'd otherwise fight over opening and closing Mission Control.
    private var lastMissionControlTask: Task<Void, Never>?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
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

    // MARK: - Lookups (shared with HSSpace and HSSpacesDisplay)

    /// The UUID of the screen a managed display identifier refers to. When displays share
    /// spaces, SkyLight reports them all as one display called "Main" - attribute that to the
    /// primary screen.
    static func screenUUID(forDisplayIdentifier identifier: String) -> String {
        if identifier == HSSkyLight.sharedSpacesDisplayIdentifier, let primary = NSScreen.screens.first {
            return HSScreen(screen: primary).uuid
        }
        return identifier
    }

    func managedDisplay(withIdentifier identifier: String) -> HSSkyLight.ManagedDisplay? {
        HSSkyLight.shared?.managedDisplays().first { $0.identifier == identifier }
    }

    /// A space and the display it's on, if it exists. SkyLight happily answers questions about
    /// made-up space IDs, so everything is checked against the list of managed displays first.
    func locate(_ spaceID: HSSkyLight.SpaceID) -> (space: HSSkyLight.Space, display: HSSkyLight.ManagedDisplay)? {
        for display in HSSkyLight.shared?.managedDisplays() ?? [] {
            if let space = display.spaces.first(where: { $0.id == spaceID }) {
                return (space, display)
            }
        }
        return nil
    }

    /// Mission Control's "Desktop N" number for a desktop. It numbers desktops (not fullscreen
    /// spaces) from 1, carrying on from one display to the next in SkyLight's display order.
    func desktopNumber(of spaceID: HSSkyLight.SpaceID) -> Int? {
        let desktops = (HSSkyLight.shared?.managedDisplays() ?? [])
            .flatMap(\.spaces)
            .filter { $0.kind == .desktop }
        return desktops.firstIndex { $0.id == spaceID }.map { $0 + 1 }
    }

    /// The IDs of the ordinary windows on a space, front to back
    func windowIDs(onSpace spaceID: HSSkyLight.SpaceID) -> [Int] {
        guard let skyLight = HSSkyLight.shared, locate(spaceID) != nil else { return [] }

        // SkyLight lists every window on the space, including menus, the menu bar, panels, etc.
        // Keep only those in the normal window layer, which is what users mean by "windows".
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let normalWindows = Set(info.compactMap { window -> CGWindowID? in
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })

        return skyLight.windows(onSpace: spaceID)
            .filter { normalWindows.contains($0) }
            .map { Int($0) }
    }

    private func makeSpace(_ id: HSSkyLight.SpaceID) -> HSSpace {
        HSSpace(id: id, module: self)
    }

    // MARK: - Spaces

    @objc func isAvailable() -> Bool {
        HSSkyLight.shared != nil
    }

    @objc func screensHaveSeparateSpaces() -> Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    @objc func displays() -> [HSSpacesDisplay] {
        (HSSkyLight.shared?.managedDisplays() ?? []).map { HSSpacesDisplay(identifier: $0.identifier, module: self) }
    }

    @objc func displayForScreen(_ screen: HSScreen) -> HSSpacesDisplay? {
        let displays = HSSkyLight.shared?.managedDisplays() ?? []
        let uuid = screen.uuid
        let display = displays.first { $0.identifier == uuid }
            ?? displays.first { $0.identifier == HSSkyLight.sharedSpacesDisplayIdentifier }
        return display.map { HSSpacesDisplay(identifier: $0.identifier, module: self) }
    }

    @objc func allSpaces() -> [HSSpace] {
        (HSSkyLight.shared?.managedDisplays() ?? []).flatMap(\.spaces).map { makeSpace($0.id) }
    }

    @objc func focusedSpace() -> HSSpace? {
        guard let active = HSSkyLight.shared?.activeSpace, locate(active) != nil else { return nil }
        return makeSpace(active)
    }

    @objc func spaceForID(_ id: Int) -> HSSpace? {
        guard let spaceID = HSSkyLight.SpaceID(exactly: id), locate(spaceID) != nil else { return nil }
        return makeSpace(spaceID)
    }

    @objc func spaceForUUID(_ uuid: String) -> HSSpace? {
        guard !uuid.isEmpty else { return nil }
        let spaces = (HSSkyLight.shared?.managedDisplays() ?? []).flatMap(\.spaces)
        return spaces.first { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }.map { makeSpace($0.id) }
    }

    @objc func spacesForWindow(_ window: HSWindow) -> [HSSpace] {
        spacesForWindowID(window.id)
    }

    @objc func spacesForWindowID(_ windowID: Int) -> [HSSpace] {
        guard let skyLight = HSSkyLight.shared, let id = CGWindowID(exactly: windowID), id != 0 else { return [] }
        return skyLight.spaces(forWindow: id).filter { locate($0) != nil }.map(makeSpace)
    }

    // MARK: - Moving windows

    func moveWindow(_ windowID: Int, toSpace spaceID: HSSkyLight.SpaceID, function: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let name = "HSSpace.\(function)()"
        func reject(_ reason: String) -> JSPromise? {
            context.createRejectedPromise(with: "\(name): \(reason)")
        }

        guard let skyLight = HSSkyLight.shared else { return reject("hs.spaces is unavailable on this version of macOS") }
        guard let (target, _) = locate(spaceID) else { return reject("space \(spaceID) no longer exists") }
        guard target.kind == .desktop else { return reject("windows can only be moved to a desktop, not a fullscreen space") }
        guard let window = CGWindowID(exactly: windowID), window != 0 else { return reject("no such window: \(windowID)") }

        let sources = skyLight.spaces(forWindow: window)
        guard !sources.isEmpty else { return reject("window \(windowID) isn't on any space") }
        guard sources.count == 1 else { return reject("window \(windowID) appears on every space, so it can't be moved") }
        guard locate(sources[0])?.space.kind == .desktop else {
            return reject("window \(windowID) is in a fullscreen space, so it can't be moved")
        }
        if sources == [spaceID] {
            return context.createResolvedPromise(with: JSValue(undefinedIn: context))
        }

        guard skyLight.moveWindows([window], toSpace: spaceID) else {
            return reject("moving windows between spaces is unavailable on this version of macOS")
        }

        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            self.track { _ in
                do {
                    try await HSMissionControl.waitUntil("macOS did not move window \(windowID) to space \(spaceID)") {
                        skyLight.spaces(forWindow: window) == [spaceID]
                    }
                    holder.resolveWith(JSValue(undefinedIn: context))
                } catch is CancellationError {
                    // The module is shutting down - the Promise's context is going away with it
                } catch {
                    AKWarning("\(name): \(error.localizedDescription)")
                    holder.rejectWithMessage("\(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Runs `body` in a Task that shutdown() can cancel
    @discardableResult
    private func track(after previous: Task<Void, Never>? = nil,
                       _ body: @escaping @MainActor (_ id: UUID) async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await body(id)
            self?.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }

    // MARK: - Mission Control actions

    func gotoSpace(_ spaceID: HSSkyLight.SpaceID) -> JSPromise? {
        runInMissionControl("HSSpace.goto()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            let display = try self.display(holding: spaceID)
            guard display.currentSpace != spaceID else { return nil }

            guard let index = display.spaceIDs.firstIndex(of: spaceID) else { throw HSMissionControl.Failure("space \(spaceID) no longer exists") }
            let bar = try await self.openSpacesBar(for: display)
            try HSMissionControl.press(bar.spaceButtons[index])

            // Clicking a space closes Mission Control. Wait for it to finish animating away too, so
            // nothing toggles Mission Control again mid-animation.
            try await HSMissionControl.waitUntil("macOS did not switch to space \(spaceID)") {
                self.managedDisplay(withIdentifier: display.identifier)?.currentSpace == spaceID
                    && HSMissionControl.isClosed
            }
            return nil
        }
    }

    func addSpace(toDisplay identifier: String) -> JSPromise? {
        runInMissionControl("HSSpacesDisplay.addSpace()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            guard let display = self.managedDisplay(withIdentifier: identifier) else {
                throw HSMissionControl.Failure("display \(identifier) is no longer connected")
            }

            let bar = try await self.openSpacesBar(for: display)
            guard let addButton = bar.addButton else { throw HSMissionControl.Failure("Mission Control has no add desktop button") }
            try HSMissionControl.press(addButton)

            let existing = Set(display.spaceIDs)
            var added: HSSkyLight.SpaceID?
            try await HSMissionControl.waitUntil("macOS did not add a desktop") {
                added = self.managedDisplay(withIdentifier: identifier)?.spaceIDs.first { !existing.contains($0) }
                return added != nil
            }
            return added.map(self.makeSpace)
        }
    }

    func removeSpace(_ spaceID: HSSkyLight.SpaceID) -> JSPromise? {
        runInMissionControl("HSSpace.remove()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            let display = try self.display(holding: spaceID)
            let desktops = display.spaces.filter { $0.kind == .desktop }.map(\.id)
            guard desktops.contains(spaceID) else { throw HSMissionControl.Failure("space \(spaceID) is not a desktop") }
            guard desktops.count > 1 else { throw HSMissionControl.Failure("space \(spaceID) is the only desktop on its display") }
            guard display.currentSpace != spaceID else {
                throw HSMissionControl.Failure("space \(spaceID) is the one its display is showing")
            }

            guard let index = display.spaceIDs.firstIndex(of: spaceID),
                  let desktopIndex = desktops.firstIndex(of: spaceID) else { throw HSMissionControl.Failure("space \(spaceID) no longer exists") }
            let bar = try await self.openSpacesBar(for: display)
            let button = bar.spaceButtons[index]
            // Removing is destructive, so double check this really is the right button: Mission
            // Control titles desktops "Desktop N". Accept either numbering across all displays
            // (desktopNumber's rule) or within this display, in case Mission Control's differs.
            let expectedNumbers = Set([desktopIndex + 1, self.desktopNumber(of: spaceID) ?? 0])
            if let number = HSMissionControl.desktopNumber(of: button), !expectedNumbers.contains(number) {
                throw HSMissionControl.Failure("Mission Control's desktop \(number) doesn't look like space \(spaceID); not removing it")
            }
            guard HSMissionControl.actions(of: button).contains(HSMissionControl.removeDesktopAction) else {
                throw HSMissionControl.Failure("Mission Control won't remove space \(spaceID)")
            }
            try HSMissionControl.perform(HSMissionControl.removeDesktopAction, on: button)

            try await HSMissionControl.waitUntil("macOS did not remove space \(spaceID)") {
                self.locate(spaceID) == nil
            }
            return nil
        }
    }

    @objc func missionControlNames() -> JSPromise? {
        runInMissionControl("hs.spaces.missionControlNames()") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure("hs.spaces is unavailable") }
            try await HSMissionControl.open()

            var names: [String: String] = [:]
            for display in skyLight.managedDisplays() {
                let bar = try await self.spacesBar(for: display)
                for (space, button) in zip(display.spaceIDs, bar.spaceButtons) {
                    names[String(space)] = HSMissionControl.name(of: button)
                }
            }
            return names
        }
    }

    @objc func openMissionControl() -> JSPromise? {
        runInMissionControl("hs.spaces.openMissionControl()", leaveOpen: true) {
            try await HSMissionControl.open()
            return nil
        }
    }

    @objc func closeMissionControl() -> JSPromise? {
        runInMissionControl("hs.spaces.closeMissionControl()") {
            try await HSMissionControl.close()
            return nil
        }
    }

    /// A rejected Promise for an HSSpace or HSSpacesDisplay method called after hs.spaces has
    /// been shut down (by a reload)
    static func rejectGone(_ function: String) -> JSPromise? {
        JSContext.current()?.createRejectedPromise(with: "\(function): hs.spaces has been reloaded; look the space up again")
    }

    /// Runs `operation` once any earlier Mission Control operation has finished, settling the
    /// returned Promise with its result. Failures reject with "<name>: <reason>". Whether it
    /// succeeds or not, Mission Control is closed afterwards unless it was already open or
    /// `leaveOpen` is set (switching spaces closes it regardless, as clicking a space always does).
    private func runInMissionControl(_ name: String,
                                     leaveOpen: Bool = false,
                                     _ operation: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard HSSkyLight.shared != nil else {
            return context.createRejectedPromise(with: "\(name): hs.spaces is unavailable on this version of macOS")
        }
        guard AXIsProcessTrusted() else {
            return context.createRejectedPromise(with: "\(name): Accessibility permission is required")
        }

        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            self.lastMissionControlTask = self.track(after: self.lastMissionControlTask) { _ in
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
                        AKWarning("\(name): \(error.localizedDescription)")
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
                    AKWarning("\(name): \(error.localizedDescription)")
                    holder.rejectWithMessage("\(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// The managed display holding `spaceID`
    private func display(holding spaceID: HSSkyLight.SpaceID) throws -> HSSkyLight.ManagedDisplay {
        guard let display = locate(spaceID)?.display else {
            throw HSMissionControl.Failure("space \(spaceID) no longer exists")
        }
        return display
    }

    /// Opens Mission Control and finds the Spaces bar for `display`
    private func openSpacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        try await HSMissionControl.open()
        return try await spacesBar(for: display)
    }

    /// The Spaces bar for `display`, once Mission Control is open
    private func spacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        let uuid = Self.screenUUID(forDisplayIdentifier: display.identifier)
        guard let screen = NSScreen.screens.lazy.map({ HSScreen(screen: $0) }).first(where: { $0.uuid == uuid }) else {
            throw HSMissionControl.Failure("no screen for display \(display.identifier)")
        }
        return try await HSMissionControl.spacesBar(for: screen.displayID, expectedCount: display.spaces.count)
    }

    // MARK: - Dock notifications

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
        guard HSSkyLight.shared != nil else {
            AKError("hs.spaces._addWatcher: hs.spaces is unavailable on this version of macOS")
            return false
        }
        watcherCallback = JSCallback(value: callback, owner: self)
        lastCurrentSpaces = currentSpaces()

        watcherObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activeSpaceDidChange() }
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
        lastCurrentSpaces = [:]

        AKDebug("hs.spaces._removeWatcher: stopped")
    }

    /// Each managed display's current space, by identifier
    private func currentSpaces() -> [String: HSSkyLight.SpaceID] {
        var result: [String: HSSkyLight.SpaceID] = [:]
        for display in HSSkyLight.shared?.managedDisplays() ?? [] {
            result[display.identifier] = display.currentSpace
        }
        return result
    }

    /// macOS only says that something changed, so compare each display's current space with the
    /// last we saw, and report each display that switched
    private func activeSpaceDidChange() {
        let current = currentSpaces()
        let previous = lastCurrentSpaces
        lastCurrentSpaces = current

        for (identifier, to) in current.sorted(by: { $0.key < $1.key }) where previous[identifier] != to {
            let details: [String: Any] = [
                "display": HSSpacesDisplay(identifier: identifier, module: self),
                "from": previous[identifier].map(makeSpace) ?? NSNull(),
                "to": makeSpace(to),
            ]
            _ = watcherCallback?.call(withArguments: [HSSpacesEvent.change.rawValue, details])
        }
    }
}
