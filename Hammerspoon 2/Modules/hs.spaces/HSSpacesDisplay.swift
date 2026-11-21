//
//  HSSpacesDisplay.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

/// A display and the spaces on it.
///
/// Each display has its own ordered set of spaces, and shows exactly one of them at a time (its
/// current space). Get these from `hs.spaces.displays()`, `hs.spaces.displayForScreen()` or an
/// `HSSpace`'s `display`; don't create them yourself. An `HSSpacesDisplay` always reports the
/// display's current state.
///
/// If "Displays have separate Spaces" is turned off in System Settings, macOS treats all
/// displays as one, so there's a single `HSSpacesDisplay` whose `screen` is the primary screen.
@objc protocol HSSpacesDisplayAPI: HSTypeAPI, JSExport {
    /// The display's UUID, the same as its `HSScreen`'s `uuid`
    /// - Example:
    /// ```js
    /// const display = hs.spaces.displayForScreen(hs.screen.main())
    /// console.log(display.uuid === hs.screen.main().uuid)  // true
    /// ```
    @objc var uuid: String { get }

    /// The screen this display is, or `null` if it has been disconnected
    /// - Example:
    /// ```js
    /// for (const display of hs.spaces.displays()) {
    ///     console.log(display.screen.name + " has " + display.spaces.length + " spaces")
    /// }
    /// ```
    @objc var screen: HSScreen? { get }

    /// The display's spaces, in the order Mission Control shows them. Empty if the display has
    /// been disconnected.
    /// - Example:
    /// ```js
    /// const display = hs.spaces.focusedSpace().display
    /// const desktops = display.spaces.filter(s => s.type === "desktop")
    /// ```
    @objc var spaces: [HSSpace] { get }

    /// The space the display is showing, or `null` if it has been disconnected
    /// - Example:
    /// ```js
    /// const display = hs.spaces.displayForScreen(hs.screen.main())
    /// console.log("Showing space " + display.currentSpace.id)
    /// ```
    @objc var currentSpace: HSSpace? { get }

    /// Adds a desktop to the end of this display's spaces, by opening Mission Control and
    /// clicking its add button. Needs Accessibility permission.
    /// - Returns: {Promise<HSSpace>} A Promise that resolves to the new desktop, or rejects with
    ///   the reason it couldn't be added
    /// - Example:
    /// ```js
    /// hs.spaces.focusedSpace().display.addSpace()
    ///     .then(space => space.goto())
    ///     .catch(err => console.error(err))
    /// ```
    @objc func addSpace() -> JSPromise?

    /// A summary of the display, for `JSON.stringify()` and the Console
    /// - Returns: An object with the display's `uuid`, `screen` name, `spaces` (their IDs) and
    ///   `currentSpace` (its ID)
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.spaces.displays()))
    /// ```
    @objc func toJSON() -> [String: Any]
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpacesDisplay: NSObject, HSSpacesDisplayAPI {
    @objc var typeName = "HSSpacesDisplay"

    /// SkyLight's managed display identifier: the display's UUID, or "Main" for shared spaces
    let identifier: String
    private weak var module: HSSpacesModule?

    init(identifier: String, module: HSSpacesModule) {
        self.identifier = identifier
        self.module = module
        super.init()
    }

    isolated deinit {
        AKGarbage("deinit of HSSpacesDisplay: \(identifier)")
    }

    @objc func toString() -> String {
        "<\(typeName): \(screen?.name ?? uuid)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func toJSON() -> [String: Any] {
        [
            "uuid": uuid,
            "screen": (screen?.name).orNSNull,
            "spaces": spaces.map(\.id),
            "currentSpace": (currentSpace?.id).orNSNull,
        ]
    }

    private var managedDisplay: HSSkyLight.ManagedDisplay? {
        module?.managedDisplay(withIdentifier: identifier)
    }

    @objc var uuid: String { HSSpacesModule.screenUUID(forDisplayIdentifier: identifier) }

    @objc var screen: HSScreen? {
        let uuid = uuid
        return NSScreen.screens.lazy.map { HSScreen(screen: $0) }.first { $0.uuid == uuid }
    }

    @objc var spaces: [HSSpace] {
        guard let module, let display = managedDisplay else { return [] }
        return display.spaces.map { HSSpace(id: $0.id, module: module) }
    }

    @objc var currentSpace: HSSpace? {
        guard let module, let current = managedDisplay?.currentSpace else { return nil }
        return HSSpace(id: current, module: module)
    }

    @objc func addSpace() -> JSPromise? {
        module?.addSpace(toDisplay: identifier) ?? HSSpacesModule.rejectGone("addSpace")
    }
}
