//
//  HSWindowFilter.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

/// The settings an `hs.windowfilter` module shares with all its filters
@MainActor
final class WindowFilterSettings {
    /// The subroles allowed by rules that don't say which subroles they allow
    var allowedRoles: Set<String> = ["AXStandardWindow", "AXDialog", "AXSystemDialog"]
}

/// A window filter: a set of rules choosing some of the windows on the system.
///
/// Get the windows it allows with `windows()`, or listen for windows being created, moved,
/// focused etc. with `on()`. Create one with `hs.windowfilter.create()`.
///
/// ## Events
///
/// Listeners are called with the window, its application's name, and the event's name. They're
/// only told about windows the filter allows, or has just stopped allowing (so they hear why it
/// stopped).
///
/// - `windowCreated`, `windowDestroyed`. A destroyed window has gone, so only its `id` can still be
///   read (and its application's name is passed to the listener).
/// - `windowMoved`: moved or resized, including going fullscreen
/// - `windowFullscreened`, `windowUnfullscreened`
/// - `windowMinimized`, `windowUnminimized`
/// - `windowHidden`, `windowUnhidden`: its application was hidden or unhidden
/// - `windowVisible`, `windowNotVisible`: it's visible when it's neither minimized nor hidden
/// - `windowInCurrentSpace`, `windowNotInCurrentSpace`: whether it's on a Space currently shown.
///   Minimized and hidden windows count as being in every Space.
/// - `windowOnScreen`, `windowNotOnScreen`: whether it's actually on screen: visible, and in a
///   Space currently shown
/// - `windowFocused`, `windowUnfocused`
/// - `windowTitleChanged`
///
/// Five more events are about the filter's set of allowed windows:
///
/// - `windowAllowed`: a window is now allowed. Emitted before any other event about it, e.g.
///   before `windowCreated` for a new window.
/// - `windowRejected`: a window is no longer allowed, or was destroyed. Emitted after the events
///   that caused it.
/// - `hasWindow`: the filter allows a window, having allowed none
/// - `hasNoWindows`: the filter allows no windows any more. The listener gets the last one.
/// - `windowsChanged`: the set of allowed windows changed. The listener gets one of the allowed
///   windows, or `null` if there are none.
///
/// Moves, resizes and title changes are reported once the window has stopped changing for a
/// moment, so dragging a window emits one `windowMoved`, not hundreds.
@objc protocol HSWindowFilterAPI: HSTypeAPI, JSExport {
    /// The windows this filter allows, sorted
    /// - Parameter sortOrder?: {"focusedLast" | "focused" | "createdLast" | "created"} How to sort them: most or least recently focused first, or newest or oldest first. Defaults to the filter's `sortOrder`
    /// - Returns: {HSWindow[]} The windows
    /// - Example:
    /// ```js
    /// const wf = hs.windowfilter.create({ default: { visible: true, currentSpace: true } })
    /// for (const win of wf.windows()) console.log(win.title)
    /// ```
    @objc func windows(_ sortOrder: String?) -> [HSWindow]

    /// Whether this filter allows a window
    /// - Parameter window: The window
    /// - Returns: `true` if the window is allowed
    /// - Example:
    /// ```js
    /// const win = hs.window.focusedWindow()
    /// if (win && hs.windowfilter.defaultFilter.isWindowAllowed(win)) console.log("The focused window counts")
    /// ```
    @objc func isWindowAllowed(_ window: HSWindow?) -> Bool

    /// Whether this filter could allow any of an application's windows: `false` if the
    /// application is rejected outright
    /// - Parameter app: The application's name or bundle ID
    /// - Returns: `false` if none of the application's windows can be allowed
    /// - Example:
    /// ```js
    /// console.log(hs.windowfilter.defaultFilter.isAppAllowed("Spotlight"))  // false
    /// ```
    @objc func isAppAllowed(_ app: String) -> Bool

    /// This filter's rules, as an object `hs.windowfilter.create()` and `setRules()` accept, or
    /// `null` for a filter made from a function
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.windowfilter.defaultFilter.rules))
    /// ```
    @objc var rules: JSValue? { get }

    /// Replaces all of this filter's rules
    /// - Parameter rules: {object} The rules, as for `hs.windowfilter.create()`
    /// - Returns: This filter
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     wf.setRules({ default: false, apps: { Safari: true } })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func setRules(_ rules: JSValue) -> HSWindowFilter?

    /// Sets the rule for one application's windows, which replaces the default rule for them
    /// - Parameter app: The application's name or bundle ID
    /// - Parameter rule: {boolean | object | null} `true` for its visible windows, `false` for none, an object of conditions (as for the `default` rule of `hs.windowfilter.create()`), or `null` to remove the application's rule so the default applies again
    /// - Returns: This filter
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     wf.setAppRule("com.apple.Safari", { visible: true, allowTitles: 1 })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func setAppRule(_ app: String, _ rule: JSValue) -> HSWindowFilter?

    /// Sets the rule for applications that have no rule of their own
    /// - Parameter rule: {boolean | object | null} `true` for visible windows, `false` for none, an object of conditions, or `null` for every window with a standard role
    /// - Returns: This filter
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     wf.setDefaultRule({ visible: true, fullscreen: false })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func setDefaultRule(_ rule: JSValue) -> HSWindowFilter?

    /// Sets the rule every window must pass, whatever its application's rule says
    /// - Parameter rule: {boolean | object | null} `true` for visible windows only, `false` for none, an object of conditions, or `null` for no override rule
    /// - Returns: This filter
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     wf.setOverrideRule({ currentSpace: true })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func setOverrideRule(_ rule: JSValue) -> HSWindowFilter?

    /// Allows an application's visible windows. The same as `setAppRule(app, true)`.
    /// - Parameter app: The application's name or bundle ID
    /// - Returns: This filter
    /// - Example:
    /// ```js
    /// hs.windowfilter.defaultFilter.allowApp("Spotlight")
    /// ```
    @objc func allowApp(_ app: String) -> HSWindowFilter

    /// Rejects all of an application's windows. The same as `setAppRule(app, false)`.
    /// - Parameter app: The application's name or bundle ID
    /// - Returns: This filter
    /// - Example:
    /// ```js
    /// hs.windowfilter.defaultFilter.rejectApp("Cool New Launcher")
    /// ```
    @objc func rejectApp(_ app: String) -> HSWindowFilter

    /// Sets the override rule's `currentSpace` condition, leaving its other conditions alone
    /// - Parameter value: {boolean | null} `true` to allow only windows in the current Space (along with minimized and hidden windows, which belong to every Space), `false` to reject them, or `null` to ignore Spaces
    /// - Returns: This filter
    /// - Example:
    /// ```js
    /// const here = hs.windowfilter.create().setCurrentSpace(true)
    /// ```
    @objc func setCurrentSpace(_ value: JSValue) -> HSWindowFilter

    /// How `windows()` sorts windows when not told otherwise: `"focusedLast"` (most recently
    /// focused first, the default), `"focused"`, `"createdLast"` (newest first) or `"created"`.
    /// Windows that existed before Hammerspoon started watching count as older than any created
    /// since, in order of their IDs, and as focused in their order on screen, front to back.
    /// - Example:
    /// ```js
    /// wf.sortOrder = "createdLast"
    /// ```
    @objc var sortOrder: String { get set }

    /// A new filter with the same rules, which can then be changed without affecting this one
    /// - Returns: The new filter
    /// - Example:
    /// ```js
    /// const noFullscreen = hs.windowfilter.defaultFilter.duplicate().setOverrideRule({ fullscreen: false })
    /// ```
    @objc func duplicate() -> HSWindowFilter

    /// Registers a listener for an event about this filter's windows. A filter with listeners
    /// keeps working after you drop your reference to it, until its listeners are removed or it's
    /// paused.
    /// - Parameter event: {"windowCreated" | "windowDestroyed" | "windowMoved" | "windowFullscreened" | "windowUnfullscreened" | "windowMinimized" | "windowUnminimized" | "windowHidden" | "windowUnhidden" | "windowVisible" | "windowNotVisible" | "windowOnScreen" | "windowNotOnScreen" | "windowInCurrentSpace" | "windowNotInCurrentSpace" | "windowFocused" | "windowUnfocused" | "windowTitleChanged" | "windowAllowed" | "windowRejected" | "hasWindow" | "hasNoWindows" | "windowsChanged"} The event to listen for
    /// - Parameter listener: {(window: HSWindow | null, appName: string | null, event: string) => void} Called with the window, its application's name, and the event's name. Only `windowsChanged` passes `null`s, when there are no windows left
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.windowfilter.defaultFilter.on("windowFocused", (win, appName) => {
    ///         console.log("Focused " + appName + ": " + win.title)
    ///     })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func on(_ event: String, _ listener: JSFunction)

    /// Removes a listener registered with `on()` or `once()`
    /// - Parameter event: {"windowCreated" | "windowDestroyed" | "windowMoved" | "windowFullscreened" | "windowUnfullscreened" | "windowMinimized" | "windowUnminimized" | "windowHidden" | "windowUnhidden" | "windowVisible" | "windowNotVisible" | "windowOnScreen" | "windowNotOnScreen" | "windowInCurrentSpace" | "windowNotInCurrentSpace" | "windowFocused" | "windowUnfocused" | "windowTitleChanged" | "windowAllowed" | "windowRejected" | "hasWindow" | "hasNoWindows" | "windowsChanged"} The event it was registered for
    /// - Parameter listener: {(window: HSWindow | null, appName: string | null, event: string) => void} The function originally registered
    /// - Example:
    /// ```js
    /// const onFocus = (win) => console.log(win.title)
    /// wf.on("windowFocused", onFocus)
    /// // later…
    /// wf.off("windowFocused", onFocus)
    /// ```
    @objc func off(_ event: String, _ listener: JSFunction)

    /// Registers a listener that's called once, the next time the event happens, then removed
    /// - Parameter event: {"windowCreated" | "windowDestroyed" | "windowMoved" | "windowFullscreened" | "windowUnfullscreened" | "windowMinimized" | "windowUnminimized" | "windowHidden" | "windowUnhidden" | "windowVisible" | "windowNotVisible" | "windowOnScreen" | "windowNotOnScreen" | "windowInCurrentSpace" | "windowNotInCurrentSpace" | "windowFocused" | "windowUnfocused" | "windowTitleChanged" | "windowAllowed" | "windowRejected" | "hasWindow" | "hasNoWindows" | "windowsChanged"} The event to listen for
    /// - Parameter listener: {(window: HSWindow | null, appName: string | null, event: string) => void} Called once
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.windowfilter.create(["Safari"]).once("windowCreated", (win) => console.log("New Safari window: " + win.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func once(_ event: String, _ listener: JSFunction)

    /// Stops calling this filter's listeners, until `resume()`. Its listeners stay registered.
    /// A paused filter doesn't keep itself alive, so keep a reference to one you mean to resume.
    /// - Returns: This filter
    /// - Example:
    /// ```js
    /// wf.pause()
    /// ```
    @objc func pause() -> HSWindowFilter

    /// Starts calling this filter's listeners again after `pause()`
    /// - Returns: This filter
    /// - Example:
    /// ```js
    /// wf.resume()
    /// ```
    @objc func resume() -> HSWindowFilter

    /// Whether this filter is paused
    /// - Example:
    /// ```js
    /// console.log(wf.isPaused)
    /// ```
    @objc var isPaused: Bool { get }

    // MARK: - Neighbouring windows

    /// The windows this filter allows that are to the right of a window, nearest first. Only windows on
    /// screen count, so combine this with a `currentSpace` rule (or use
    /// `hs.windowfilter.currentSpaceFilter`) to ignore windows on other Spaces cheaply.
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: {HSWindow[]} The windows, nearest first
    /// - Example:
    /// ```js
    /// const next = hs.windowfilter.currentSpaceFilter.windowsToEast()[0]
    /// if (next) console.log("Next window east: " + next.title)
    /// ```
    @objc func windowsToEast(_ options: [String: Any]?) -> [HSWindow]

    /// Focuses the nearest window this filter allows that is to the right of a window
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: `true` if a window was focused, `false` if there was none to focus
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "right", () => {
    ///     hs.windowfilter.currentSpaceFilter.focusWindowEast({ frontmost: true })
    /// })
    /// ```
    @objc func focusWindowEast(_ options: [String: Any]?) -> Bool

    /// The windows this filter allows that are to the left of a window, nearest first. Only windows on
    /// screen count, so combine this with a `currentSpace` rule (or use
    /// `hs.windowfilter.currentSpaceFilter`) to ignore windows on other Spaces cheaply.
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: {HSWindow[]} The windows, nearest first
    /// - Example:
    /// ```js
    /// const next = hs.windowfilter.currentSpaceFilter.windowsToWest()[0]
    /// if (next) console.log("Next window west: " + next.title)
    /// ```
    @objc func windowsToWest(_ options: [String: Any]?) -> [HSWindow]

    /// Focuses the nearest window this filter allows that is to the left of a window
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: `true` if a window was focused, `false` if there was none to focus
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "left", () => {
    ///     hs.windowfilter.currentSpaceFilter.focusWindowWest({ frontmost: true })
    /// })
    /// ```
    @objc func focusWindowWest(_ options: [String: Any]?) -> Bool

    /// The windows this filter allows that are above a window, nearest first. Only windows on
    /// screen count, so combine this with a `currentSpace` rule (or use
    /// `hs.windowfilter.currentSpaceFilter`) to ignore windows on other Spaces cheaply.
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: {HSWindow[]} The windows, nearest first
    /// - Example:
    /// ```js
    /// const next = hs.windowfilter.currentSpaceFilter.windowsToNorth()[0]
    /// if (next) console.log("Next window north: " + next.title)
    /// ```
    @objc func windowsToNorth(_ options: [String: Any]?) -> [HSWindow]

    /// Focuses the nearest window this filter allows that is above a window
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: `true` if a window was focused, `false` if there was none to focus
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "up", () => {
    ///     hs.windowfilter.currentSpaceFilter.focusWindowNorth({ frontmost: true })
    /// })
    /// ```
    @objc func focusWindowNorth(_ options: [String: Any]?) -> Bool

    /// The windows this filter allows that are below a window, nearest first. Only windows on
    /// screen count, so combine this with a `currentSpace` rule (or use
    /// `hs.windowfilter.currentSpaceFilter`) to ignore windows on other Spaces cheaply.
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: {HSWindow[]} The windows, nearest first
    /// - Example:
    /// ```js
    /// const next = hs.windowfilter.currentSpaceFilter.windowsToSouth()[0]
    /// if (next) console.log("Next window south: " + next.title)
    /// ```
    @objc func windowsToSouth(_ options: [String: Any]?) -> [HSWindow]

    /// Focuses the nearest window this filter allows that is below a window
    /// - Parameter options?: How to choose the windows
    ///   - window?: {HSWindow} The window to start from. Defaults to the focused window
    ///   - frontmost?: {boolean} `true` to put windows that can be seen before windows hidden behind others
    ///   - strict?: {boolean} `true` to only consider windows within 45° of the direction, rather than anywhere on that side of the window
    /// - Returns: `true` if a window was focused, `false` if there was none to focus
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "down", () => {
    ///     hs.windowfilter.currentSpaceFilter.focusWindowSouth({ frontmost: true })
    /// })
    /// ```
    @objc func focusWindowSouth(_ options: [String: Any]?) -> Bool

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
    /// The event names `on()`/`once()` accept - see HSWindowFilterEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }
}

@_documentation(visibility: private)
@MainActor
@objc class HSWindowFilter: NSObject, HSWindowFilterAPI, HSTrackedObject {
    @objc var typeName = "HSWindowFilter"

    private var filterRules: WindowFilterRules
    private var predicate: JSCallback?
    private let settings: WindowFilterSettings
    private weak var tracker: HSObjectTracker<HSWindowFilter>?
    private weak var module: HSWindowFilterModule?

    private var membership = WindowFilterMembership()
    private var watcherCallback: JSCallback? {
        didSet { updateSubscription() }
    }
    private var paused = false {
        didSet { updateSubscription() }
    }
    /// Live while the filter has listeners and isn't paused, and so active: it keeps itself (and
    /// its listeners) alive after the user drops it
    private var subscription: WindowTracker.Subscription? {
        didSet { tracker?.setActive(self, subscription != nil) }
    }

    @objc var _watcherEmitter: JSFunction?
    @objc var _eventNames: [String] { HSWindowFilterEvent.allNames }

    init(rules: WindowFilterRules, settings: WindowFilterSettings, tracker: HSObjectTracker<HSWindowFilter>?, module: HSWindowFilterModule?) {
        self.filterRules = rules
        self.settings = settings
        self.tracker = tracker
        self.module = module
        super.init()
    }

    /// A filter that allows the windows `predicate` returns `true` for. Called from JS, so the
    /// callback can capture the calling context.
    convenience init?(predicate: JSValue, settings: WindowFilterSettings, tracker: HSObjectTracker<HSWindowFilter>?, module: HSWindowFilterModule?) {
        self.init(rules: WindowFilterRules(), settings: settings, tracker: tracker, module: module)
        guard let callback = JSCallback(value: predicate, owner: self) else { return nil }
        self.predicate = callback
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSWindowFilter")
    }

    func destroy() {
        subscription = nil
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        predicate?.detach(from: self)
        predicate = nil
        _watcherEmitter = nil
    }

    @objc func toString() -> String {
        if predicate != nil {
            return "<HSWindowFilter: function>"
        }
        let state = paused ? "paused" : (subscription != nil ? "watching" : "idle")
        return "<HSWindowFilter: \(filterRules.apps.count) app rule\(filterRules.apps.count == 1 ? "" : "s"), \(state)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Evaluating windows

    /// Whether the filter allows a window, given its state
    func allows(_ state: WindowState, window: HSWindow) -> Bool {
        if let predicate {
            return predicate.call(withArguments: [window])?.toBool() ?? false
        }
        return filterRules.allows(state, allowedRoles: settings.allowedRoles)
    }

    @objc func windows(_ sortOrder: String?) -> [HSWindow] {
        var order = filterRules.sortOrder
        // An omitted optional String arrives as the literal "undefined"
        if let sortOrder, sortOrder != "undefined" {
            guard let requested = WindowSortOrder(rawValue: sortOrder) else {
                throwError("HSWindowFilter.windows(): sortOrder must be one of " + WindowSortOrder.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", "))
                return []
            }
            order = requested
        }
        guard AXIsProcessTrusted() else {
            AKError("HSWindowFilter.windows(): Accessibility permission not granted")
            return []
        }

        let entries = WindowTracker.shared.entries().filter { allows($0.state, window: $0.window) }
        let sorted: [WindowTracker.Entry]
        switch order {
        case .focusedLast: sorted = entries.sorted { ($0.focusedAt, $0.state.id) > ($1.focusedAt, $1.state.id) }
        case .focused: sorted = entries.sorted { ($0.focusedAt, $0.state.id) < ($1.focusedAt, $1.state.id) }
        case .createdLast: sorted = entries.sorted { ($0.createdAt, $0.state.id) > ($1.createdAt, $1.state.id) }
        case .created: sorted = entries.sorted { ($0.createdAt, $0.state.id) < ($1.createdAt, $1.state.id) }
        }
        return sorted.map(\.window)
    }

    @objc func isWindowAllowed(_ window: HSWindow?) -> Bool {
        guard let window, let state = WindowTracker.shared.state(of: window) else { return false }
        return allows(state, window: window)
    }

    @objc func isAppAllowed(_ app: String) -> Bool {
        predicate != nil || filterRules.allowsApp(app)
    }

    // MARK: - Rules

    @objc var rules: JSValue? {
        guard predicate == nil, let context = JSContext.current() else { return nil }
        return filterRules.jsValue(in: context)
    }

    /// The rules, for duplicating this filter. A predicate filter's are meaningless.
    var currentRules: WindowFilterRules { filterRules }

    /// Applies a change to the rules, re-evaluating the allowed windows without emitting anything,
    /// or throws `message` into the calling JS
    private func changeRules(_ name: String, _ change: (inout WindowFilterRules) throws(WindowFilterRuleError) -> Void) -> HSWindowFilter? {
        guard predicate == nil else {
            throwError("HSWindowFilter.\(name)(): a filter made from a function has no rules")
            return nil
        }
        var rules = filterRules
        do {
            try change(&rules)
        } catch {
            throwError("HSWindowFilter.\(name)(): \(error.message)")
            return nil
        }
        filterRules = rules
        if subscription != nil {
            resetMembership()
        }
        return self
    }

    @objc func setRules(_ rules: JSValue) -> HSWindowFilter? {
        changeRules("setRules") { (updated: inout WindowFilterRules) throws(WindowFilterRuleError) in updated = try WindowFilterRules.parse(rules) }
    }

    @objc func setAppRule(_ app: String, _ rule: JSValue) -> HSWindowFilter? {
        changeRules("setAppRule") { (updated: inout WindowFilterRules) throws(WindowFilterRuleError) in updated.apps[app] = try WindowFilterRules.parseAppRule(rule, name: "rule") }
    }

    @objc func setDefaultRule(_ rule: JSValue) -> HSWindowFilter? {
        changeRules("setDefaultRule") { (updated: inout WindowFilterRules) throws(WindowFilterRuleError) in updated.defaultRule = try WindowFilterRules.parseAppRule(rule, name: "rule") ?? .allow(WindowRule()) }
    }

    @objc func setOverrideRule(_ rule: JSValue) -> HSWindowFilter? {
        changeRules("setOverrideRule") { (updated: inout WindowFilterRules) throws(WindowFilterRuleError) in updated.override = try WindowFilterRules.parseAppRule(rule, name: "rule", defaultRoles: .any) }
    }

    @objc func allowApp(_ app: String) -> HSWindowFilter {
        changeRules("allowApp") { $0.apps[app] = .allow(.visibleOnly) } ?? self
    }

    @objc func rejectApp(_ app: String) -> HSWindowFilter {
        changeRules("rejectApp") { $0.apps[app] = .reject } ?? self
    }

    @objc func setCurrentSpace(_ value: JSValue) -> HSWindowFilter {
        // A JSValue rather than a Bool, which can't be null
        let currentSpace: Bool? = value.isBoolean ? value.toBool() : nil
        return changeRules("setCurrentSpace") { rules in
            var rule: WindowRule
            switch rules.override {
            case .allow(let existing)?: rule = existing
            // Rejecting everything stays rejecting everything
            case .reject?: return
            case nil: rule = WindowRule(allowRoles: .any)
            }
            rule.currentSpace = currentSpace
            rules.override = .allow(rule)
        } ?? self
    }

    @objc var sortOrder: String {
        get { filterRules.sortOrder.rawValue }
        set {
            guard let order = WindowSortOrder(rawValue: newValue) else {
                throwError("HSWindowFilter.sortOrder must be one of " + WindowSortOrder.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", "))
                return
            }
            filterRules.sortOrder = order
        }
    }

    @objc func duplicate() -> HSWindowFilter {
        if let predicate = predicate?.value, let copy = HSWindowFilter(predicate: predicate, settings: settings, tracker: tracker, module: module) {
            tracker?.add(copy)
            return copy
        }
        let copy = HSWindowFilter(rules: filterRules, settings: settings, tracker: tracker, module: module)
        tracker?.add(copy)
        return copy
    }

    private func throwError(_ message: String) {
        AKError(message)
        guard let context = JSContext.current() else { return }
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }

    // MARK: - Events

    private func ensureWatcherEmitter(_ ctx: JSContext) -> JSValue? {
        if _watcherEmitter == nil {
            guard let module else {
                ctx.exception = JSValue(newErrorFromMessage: "hs.windowfilter: the module is unavailable", in: ctx)
                return nil
            }
            guard let emitter = module.makeFilterEmitter(for: self, in: ctx) else { return nil }
            _watcherEmitter = emitter
        }
        return _watcherEmitter
    }

    @objc func on(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        _ = ctx.callCapturingException { emitter.invokeMethod("on", withArguments: [event, listener]) }
    }

    @objc func off(_ event: String, _ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("off", withArguments: [event, listener])
    }

    @objc func once(_ event: String, _ listener: JSFunction) {
        guard let ctx = JSContext.current(), let emitter = ensureWatcherEmitter(ctx) else { return }
        _ = ctx.callCapturingException { emitter.invokeMethod("once", withArguments: [event, listener]) }
    }

    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("HSWindowFilter._addWatcher(): already watching, refusing a second subscription")
            return false
        }
        guard AXIsProcessTrusted() else {
            AKError("HSWindowFilter.on(): Accessibility permission not granted")
            return false
        }
        watcherCallback = JSCallback(value: listener, owner: self)
        AKDebug("HSWindowFilter._addWatcher(): started watching")
        return watcherCallback != nil
    }

    @objc func _removeWatcher() {
        // Cleared first so the next on() creates a fresh emitter, in the caller's VM
        _watcherEmitter = nil
        guard watcherCallback != nil else { return }
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("HSWindowFilter._removeWatcher(): stopped watching")
    }

    @objc func pause() -> HSWindowFilter {
        paused = true
        return self
    }

    @objc func resume() -> HSWindowFilter {
        paused = false
        return self
    }

    @objc var isPaused: Bool { paused }

    private func updateSubscription() {
        let wanted = watcherCallback != nil && !paused
        if wanted && subscription == nil {
            subscription = WindowTracker.shared.subscribe { [weak self] change in
                self?.handle(change)
            }
            resetMembership()
        } else if !wanted && subscription != nil {
            subscription?.cancel()
            subscription = nil
        }
    }

    /// Works out which windows are allowed now, without emitting anything
    private func resetMembership() {
        let allowed = WindowTracker.shared.entries().filter { allows($0.state, window: $0.window) }.map(\.state.id)
        membership.reset(allowed: Set(allowed))
    }

    private func handle(_ change: WindowTracker.Change) {
        guard subscription != nil else { return }
        let isAllowed = change.new.map { allows($0, window: change.window) } ?? false
        let emissions = membership.process(windowID: change.windowID, events: change.events, isAllowed: isAllowed)
        for emission in emissions {
            // A listener may have removed the last listener, or paused the filter
            guard subscription != nil, let callback = watcherCallback else { return }
            var window: HSWindow?
            var appName: String?
            if emission.windowID == change.windowID {
                window = change.window
                appName = (change.new ?? change.old)?.appName
            } else if let id = emission.windowID {
                window = WindowTracker.shared.window(withID: id)
                appName = window?.app.localizedName
            }
            _ = callback.call(withArguments: [emission.event.rawValue, window ?? NSNull(), appName ?? NSNull(), emission.event.rawValue])
        }
    }

    // MARK: - Neighbouring windows

    // MARK: - Neighbouring windows API

    @objc func windowsToEast(_ options: [String: Any]?) -> [HSWindow] {
        neighbours(.east, options)
    }

    @objc func focusWindowEast(_ options: [String: Any]?) -> Bool {
        neighbours(.east, options).contains { $0.focus() }
    }

    @objc func windowsToWest(_ options: [String: Any]?) -> [HSWindow] {
        neighbours(.west, options)
    }

    @objc func focusWindowWest(_ options: [String: Any]?) -> Bool {
        neighbours(.west, options).contains { $0.focus() }
    }

    @objc func windowsToNorth(_ options: [String: Any]?) -> [HSWindow] {
        neighbours(.north, options)
    }

    @objc func focusWindowNorth(_ options: [String: Any]?) -> Bool {
        neighbours(.north, options).contains { $0.focus() }
    }

    @objc func windowsToSouth(_ options: [String: Any]?) -> [HSWindow] {
        neighbours(.south, options)
    }

    @objc func focusWindowSouth(_ options: [String: Any]?) -> Bool {
        neighbours(.south, options).contains { $0.focus() }
    }

    /// The windows in `direction` from `options.window` (or the focused window), among the
    /// windows this filter allows
    func neighbours(_ direction: WindowNeighbours.Direction, _ options: [String: Any]?) -> [HSWindow] {
        guard let origin = (options?["window"] as? HSWindow) ?? WindowTracker.focusedWindow() else { return [] }
        let frontmost = options?["frontmost"] as? Bool ?? false
        let strict = options?["strict"] as? Bool ?? false
        return WindowNeighbours.windows(from: origin, in: direction, candidates: windows(nil), frontmost: frontmost, strict: strict)
    }
}

extension WindowTracker {
    /// The focused window of the frontmost application
    static func focusedWindow() -> HSWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, let element = focusedWindowElement(of: app) else { return nil }
        return HSWindow(element: element, app: app)
    }
}
