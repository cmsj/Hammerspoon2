//
//  HSSpace.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// One space (a desktop, or a fullscreen app's space) on a screen.
///
/// Get these from a screen (`screen.spaces`, `screen.currentSpace`), a window (`window.spaces`)
/// or `hs.screen` (e.g. `hs.screen.focusedSpace()`); don't create them yourself. An `HSSpace`
/// always reports the space's current state, so there's no need to fetch it again after
/// something changes. If the space is removed, `exists` becomes `false`, its other properties
/// become `null`, and its methods reject.
///
/// To move a window to a space, use the window's `moveToSpace()`.
///
/// Compare spaces by `id`, not with `===`: two lookups of the same space give two different objects.
@objc protocol HSSpaceAPI: HSTypeAPI, JSExport {
    /// The space's ID. macOS assigns these, and they last until the space is removed, so a
    /// removed and re-added space gets a new ID. They may change when you log out or restart:
    /// use `uuid` (with `hs.screen.spaceForUUID()`) to find a space again in a later session.
    /// - Example:
    /// ```js
    /// console.log("Focused space ID: " + hs.screen.focusedSpace().id)
    /// ```
    @objc var id: Int { get }

    /// The space's UUID, which macOS keeps across logins (it's how it remembers which space
    /// is which). `null` if the space no longer exists, or if macOS hasn't given it one, which
    /// it doesn't for the first desktop of a new user account.
    /// - Example:
    /// ```js
    /// const uuid = hs.screen.focusedSpace().uuid
    /// // ...in a later session:
    /// const space = hs.screen.spaceForUUID(uuid)
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
    /// const desktops = hs.screen.allSpaces().filter(s => s.type === "desktop")
    /// ```
    @objc var type: String? { get }

    /// The screen the space belongs to. Every space belongs to exactly one screen. `null` if
    /// the space no longer exists, or its screen has been disconnected.
    ///
    /// If "Displays have separate Spaces" is turned off, all screens share one set of spaces,
    /// which macOS attributes to the primary screen.
    /// - Example:
    /// ```js
    /// console.log("Focused space is on " + hs.screen.focusedSpace().screen.name)
    /// ```
    @objc var screen: HSScreen? { get }

    /// The "Desktop N" number Mission Control shows for this desktop. Mission Control only
    /// numbers desktops, and numbers them across all displays in turn, so a second display's
    /// first desktop can be "Desktop 3". (When there's only one desktop, Mission Control calls
    /// it just "Desktop", but this is still 1.) `null` for a fullscreen space, or if the space
    /// no longer exists.
    /// - Example:
    /// ```js
    /// console.log("You're on Desktop " + hs.screen.focusedSpace().desktopNumber)
    /// ```
    @objc var desktopNumber: NSNumber? { get }

    /// Whether this is the space its screen is currently showing. Each screen shows one
    /// space at a time, so with several screens, several spaces are current.
    /// - Example:
    /// ```js
    /// const showing = hs.screen.allSpaces().filter(s => s.isCurrent)
    /// ```
    @objc var isCurrent: Bool { get }

    /// Whether this is the focused space: the current space of the screen with keyboard focus
    /// - Example:
    /// ```js
    /// const space = hs.screen.focusedSpace()
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
    /// const space = hs.screen.focusedSpace()
    /// console.log(space.windowIDs().length + " windows on this space")
    /// ```
    @objc func windowIDs() -> [Int]

    /// Switches this space's screen to this space, by opening Mission Control and clicking it.
    /// Needs Accessibility permission.
    /// - Returns: {Promise<void>} A Promise that resolves once the screen is showing this space
    ///   and Mission Control has closed, or rejects with the reason it couldn't switch
    /// - Example:
    /// ```js
    /// hs.screen.main().spaces[0].goto()
    ///     .then(() => console.log("Switched"))
    ///     .catch(err => console.error(err))
    /// ```
    @objc func goto() -> JSPromise?

    /// Removes this desktop, by opening Mission Control and clicking its close button. Any
    /// windows on it move to another desktop on the same screen. Needs Accessibility permission.
    ///
    /// Only desktops can be removed - not fullscreen spaces - and macOS won't remove a screen's
    /// only desktop, or the desktop the screen is currently showing.
    /// - Returns: {Promise<void>} A Promise that resolves once the desktop has gone, or rejects
    ///   with the reason it couldn't be removed
    /// - Example:
    /// ```js
    /// hs.screen.main().addSpace()
    ///     .then(space => space.remove())
    /// ```
    @objc func remove() -> JSPromise?

    /// A summary of the space, for `JSON.stringify()` and the Console
    /// - Returns: An object with the space's `id`, `uuid`, `type`, `screen` (its UUID),
    ///   `desktopNumber`, `isCurrent` and `isFocused`
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.screen.focusedSpace()))
    /// ```
    @objc func toJSON() -> [String: Any]
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpace: NSObject, HSSpaceAPI {
    @objc var typeName = "HSSpace"

    let spaceID: HSSkyLight.SpaceID

    init(id: HSSkyLight.SpaceID) {
        spaceID = id
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
            "screen": located.map { HSSpaces.screenUUID(forDisplayIdentifier: $0.display.identifier) }.orNSNull,
            "desktopNumber": desktopNumber.orNSNull,
            "isCurrent": isCurrent,
            "isFocused": isFocused,
        ]
    }

    /// The space and its display, as SkyLight describes them right now
    private var located: (space: HSSkyLight.Space, display: HSSkyLight.ManagedDisplay)? {
        HSSpaces.shared.locate(spaceID)
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

    @objc var screen: HSScreen? {
        located.flatMap { HSSpaces.screen(forDisplayIdentifier: $0.display.identifier) }
    }

    @objc var desktopNumber: NSNumber? {
        HSSpaces.shared.desktopNumber(of: spaceID).map { NSNumber(value: $0) }
    }

    @objc var isCurrent: Bool {
        located?.display.currentSpace == spaceID
    }

    @objc var isFocused: Bool {
        HSSkyLight.shared?.activeSpace == spaceID && exists
    }

    @objc func windowIDs() -> [Int] {
        HSSpaces.shared.windowIDs(onSpace: spaceID)
    }

    @objc func goto() -> JSPromise? {
        HSSpaces.shared.gotoSpace(spaceID)
    }

    @objc func remove() -> JSPromise? {
        HSSpaces.shared.removeSpace(spaceID)
    }
}
