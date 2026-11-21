//
//  HSSpace.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// One space (a desktop, or a fullscreen app's space) on a display.
///
/// Get these from `hs.spaces` (e.g. `hs.spaces.focusedSpace()`) or from an `HSSpacesDisplay`;
/// don't create them yourself. An `HSSpace` always reports the space's current state, so there's
/// no need to fetch it again after something changes. If the space is removed, `exists` becomes
/// `false`, its other properties become `null`, and its methods reject.
///
/// Compare spaces by `id`, not with `===`: two lookups of the same space give two different objects.
@objc protocol HSSpaceAPI: HSTypeAPI, JSExport {
    /// The space's ID. macOS assigns these, and they last until the space is removed, so a
    /// removed and re-added space gets a new ID. They may change when you log out or restart:
    /// use `uuid` (with `hs.spaces.spaceForUUID()`) to find a space again in a later session.
    /// - Example:
    /// ```js
    /// console.log("Focused space ID: " + hs.spaces.focusedSpace().id)
    /// ```
    @objc var id: Int { get }

    /// The space's UUID, which macOS keeps across logins (it's how it remembers which space
    /// is which). `null` if the space no longer exists, or if macOS hasn't given it one, which
    /// it doesn't for the first desktop of a new user account.
    /// - Example:
    /// ```js
    /// const uuid = hs.spaces.focusedSpace().uuid
    /// // ...in a later session:
    /// const space = hs.spaces.spaceForUUID(uuid)
    /// ```
    @objc var uuid: String? { get }

    /// Whether the space still exists
    /// - Example:
    /// ```js
    /// if (!space.exists) console.log("That space has been removed")
    /// ```
    @objc var exists: Bool { get }

    /// What kind of space this is: `"desktop"` for an ordinary desktop, `"fullscreen"` for a
    /// fullscreen app (or two apps in Split View), or `"unknown"` for a kind of space this
    /// version of Hammerspoon doesn't recognise. `null` if the space no longer exists.
    /// - Example:
    /// ```js
    /// const desktops = hs.spaces.allSpaces().filter(s => s.type === "desktop")
    /// ```
    @objc var type: String? { get }

    /// The display the space belongs to. Every space belongs to exactly one display. `null` if
    /// the space no longer exists.
    /// - Example:
    /// ```js
    /// const display = hs.spaces.focusedSpace().display
    /// console.log("Focused space is on " + display.screen.name)
    /// ```
    @objc var display: HSSpacesDisplay? { get }

    /// The "Desktop N" number Mission Control shows for this desktop. Mission Control only
    /// numbers desktops, and numbers them across all displays in turn, so a second display's
    /// first desktop can be "Desktop 3". (When there's only one desktop, Mission Control calls
    /// it just "Desktop", but this is still 1.) `null` for a fullscreen space, or if the space
    /// no longer exists.
    /// - Example:
    /// ```js
    /// console.log("You're on Desktop " + hs.spaces.focusedSpace().desktopNumber)
    /// ```
    @objc var desktopNumber: NSNumber? { get }

    /// Whether this is the space its display is currently showing. Each display shows one
    /// space at a time, so with several displays, several spaces are current.
    /// - Example:
    /// ```js
    /// const showing = hs.spaces.allSpaces().filter(s => s.isCurrent)
    /// ```
    @objc var isCurrent: Bool { get }

    /// Whether this is the focused space: the current space of the display with keyboard focus
    /// - Example:
    /// ```js
    /// const space = hs.spaces.focusedSpace()
    /// console.log(space.isFocused)  // true
    /// ```
    @objc var isFocused: Bool { get }

    /// The IDs of the windows on this space, front to back. Only ordinary windows are
    /// included (not menus, panels, the menu bar, etc). Windows set to appear on every space are
    /// included for every space. Hammerspoon can't make `HSWindow` objects for windows on other
    /// spaces, which is why these are IDs.
    /// - Returns: An array of window IDs, empty if the space no longer exists
    /// - Example:
    /// ```js
    /// const space = hs.spaces.focusedSpace()
    /// console.log(space.windowIDs().length + " windows on this space")
    /// ```
    @objc func windowIDs() -> [Int]

    /// Switches this space's display to this space, by opening Mission Control and clicking it.
    /// Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once the display is showing this space
    ///   and Mission Control has closed, or rejects with the reason it couldn't switch
    /// - Example:
    /// ```js
    /// const display = hs.spaces.focusedSpace().display
    /// display.spaces[0].goto()
    ///     .then(() => console.log("Switched"))
    ///     .catch(err => console.error(err))
    /// ```
    @objc func goto() -> JSPromise?

    /// Removes this desktop, by opening Mission Control and clicking its close button. Any
    /// windows on it move to another desktop on the same display. Needs Accessibility permission.
    ///
    /// Only desktops can be removed - not fullscreen spaces - and macOS won't remove a display's
    /// only desktop, or the desktop the display is currently showing.
    /// - Returns: {Promise<void>} A Promise that resolves once the desktop has gone, or rejects
    ///   with the reason it couldn't be removed
    /// - Example:
    /// ```js
    /// hs.spaces.focusedSpace().display.addSpace()
    ///     .then(space => space.remove())
    /// ```
    @objc func remove() -> JSPromise?

    /// Moves a window to this space, without switching to it. This works for any app's
    /// windows, and doesn't use Mission Control.
    ///
    /// Only windows on a desktop can be moved, and only to a desktop - not to or from a
    /// fullscreen space. Windows set to appear on every space can't be moved either.
    /// - Parameter window: The window to move
    /// - Returns: {Promise<void>} A Promise that resolves once the window is on this space, or
    ///   rejects with the reason it couldn't be moved
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// const spaces = hs.spaces.focusedSpace().display.spaces.filter(s => s.type === "desktop")
    /// spaces[spaces.length - 1].moveWindow(win)
    /// ```
    @objc func moveWindow(_ window: HSWindow) -> JSPromise?

    /// Moves a window to this space by its ID, without switching to it. This is the same as
    /// `moveWindow()`, for windows you only have the ID of (such as those from `windowIDs()`).
    /// - Parameter windowID: The ID of the window to move
    /// - Returns: {Promise<void>} A Promise that resolves once the window is on this space, or
    ///   rejects with the reason it couldn't be moved
    /// - Example:
    /// ```js
    /// // Gather every window from the focused display's other desktops onto the focused space
    /// const here = hs.spaces.focusedSpace()
    /// for (const space of here.display.spaces) {
    ///     if (space.id === here.id || space.type !== "desktop") continue
    ///     for (const id of space.windowIDs()) here.moveWindowID(id)
    /// }
    /// ```
    @objc func moveWindowID(_ windowID: Int) -> JSPromise?

    /// A summary of the space, for `JSON.stringify()` and the Console
    /// - Returns: An object with the space's `id`, `uuid`, `type`, `display` (its UUID),
    ///   `desktopNumber`, `isCurrent` and `isFocused`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.spaces.focusedSpace()))
    /// ```
    @objc func toJSON() -> [String: Any]
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpace: NSObject, HSSpaceAPI {
    @objc var typeName = "HSSpace"

    let spaceID: HSSkyLight.SpaceID
    private weak var module: HSSpacesModule?

    init(id: HSSkyLight.SpaceID, module: HSSpacesModule) {
        spaceID = id
        self.module = module
        super.init()
    }

    isolated deinit {
        AKGarbage("deinit of HSSpace: \(spaceID)")
    }

    @objc func toString() -> String {
        guard let type else { return "<\(typeName): \(id), removed>" }
        return "<\(typeName): \(id), \(desktopNumber.map { "Desktop \($0)" } ?? type)\(isCurrent ? ", current" : "")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func toJSON() -> [String: Any] {
        [
            "id": id,
            "uuid": uuid.orNSNull,
            "type": type.orNSNull,
            "display": (display?.uuid).orNSNull,
            "desktopNumber": desktopNumber.orNSNull,
            "isCurrent": isCurrent,
            "isFocused": isFocused,
        ]
    }

    /// The space and its display, as SkyLight describes them right now
    private var located: (space: HSSkyLight.Space, display: HSSkyLight.ManagedDisplay)? {
        module?.locate(spaceID)
    }

    @objc var id: Int { Int(clamping: spaceID) }

    @objc var uuid: String? {
        guard let uuid = located?.space.uuid, !uuid.isEmpty else { return nil }
        return uuid
    }

    @objc var exists: Bool { located != nil }

    @objc var type: String? {
        guard let space = located?.space else { return nil }
        switch space.kind {
        case .desktop: return "desktop"
        case .fullscreen: return "fullscreen"
        case nil: return "unknown"
        }
    }

    @objc var display: HSSpacesDisplay? {
        guard let module, let display = located?.display else { return nil }
        return HSSpacesDisplay(identifier: display.identifier, module: module)
    }

    @objc var desktopNumber: NSNumber? {
        module?.desktopNumber(of: spaceID).map { NSNumber(value: $0) }
    }

    @objc var isCurrent: Bool {
        located?.display.currentSpace == spaceID
    }

    @objc var isFocused: Bool {
        HSSkyLight.shared?.activeSpace == spaceID && exists
    }

    @objc func windowIDs() -> [Int] {
        module?.windowIDs(onSpace: spaceID) ?? []
    }

    @objc func goto() -> JSPromise? {
        module?.gotoSpace(spaceID) ?? HSSpacesModule.rejectGone("goto")
    }

    @objc func remove() -> JSPromise? {
        module?.removeSpace(spaceID) ?? HSSpacesModule.rejectGone("remove")
    }

    @objc func moveWindow(_ window: HSWindow) -> JSPromise? {
        module?.moveWindow(window.id, toSpace: spaceID, function: "moveWindow") ?? HSSpacesModule.rejectGone("moveWindow")
    }

    @objc func moveWindowID(_ windowID: Int) -> JSPromise? {
        module?.moveWindow(windowID, toSpace: spaceID, function: "moveWindowID") ?? HSSpacesModule.rejectGone("moveWindowID")
    }
}
