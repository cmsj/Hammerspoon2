//
//  HSWindowFilterModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import AppKit

// MARK: - Declare our JavaScript API

/// # Window filters
///
/// A window filter picks out some of the windows on your Mac with a set of rules, such as "visible
/// windows in the current Space, except Finder's". You can ask a filter for the windows it allows
/// right now, or listen for events about them: windows being created, focused, moved, minimized,
/// joining or leaving the filter, and so on.
///
/// ```js
/// // Every visible window of every app, except a few utility apps
/// const wf = hs.windowfilter.defaultFilter
///
/// // Only Safari and Mail's visible windows
/// const mailAndWeb = hs.windowfilter.create(["Safari", "Mail"])
///
/// // Visible, non-fullscreen windows in the current Space; no windows at all from Finder, and
/// // only titled windows from Terminal
/// const custom = hs.windowfilter.create({
///     override: { currentSpace: true, fullscreen: false },
///     default: { visible: true },
///     apps: { Finder: false, "com.apple.Terminal": { visible: true, allowTitles: 1 } },
/// })
///
/// custom.on("windowFocused", (win, appName) => console.log(appName + ": " + win.title))
/// ```
///
/// ## Rules
///
/// A window must pass the `override` rule, if there is one. Then the rule for its application
/// decides, or the `default` rule if the application has none of its own. An application rule
/// replaces the default rule rather than adding to it.
///
/// A rule is `true` (the application's visible windows), `false` (none of them), or an object of
/// conditions, all of which must hold:
///
/// - `visible`: `true` for only visible windows (neither minimized nor hidden), `false` for only
///   invisible ones
/// - `currentSpace`: `true` for only windows in a Space currently shown, `false` for only
///   windows in other Spaces. Minimized and hidden windows count as being in every Space.
/// - `fullscreen`, `focused`, `hasTitlebar`: `true` to require the window to be fullscreen,
///   focused, or to have a titlebar; `false` to require it not to be
/// - `activeApplication`: `true` for only windows of the active application, `false` for only
///   other applications' windows
/// - `allowTitles`: a number, for windows whose titles are at least that many characters long
///   (so `1` rejects untitled windows); or a string (an exact title), a RegExp, or an array of
///   them, for windows whose titles match one
/// - `rejectTitles`: a string, RegExp, or array of them; windows whose titles match one are rejected
/// - `allowRegions`, `rejectRegions`: an `HSRect` (or `{x, y, w, h}`), or an array of them.
///   A window is in a region if at least half of it is inside, or it covers at least half of the
///   region.
/// - `allowScreens`, `rejectScreens`: an `HSScreen`, a screen's name or UUID, or an array of
///   them, for the screen holding most of the window
/// - `allowRoles`: a window subrole (see `HSWindow.subrole`), an array of them, or `"*"` for any
///   window. Defaults to `hs.windowfilter.allowedWindowRoles`, except in the override rule,
///   which allows any subrole unless it says otherwise.
///
/// Regions and screens only apply to visible windows. RegExps support the `i`, `m` and `s` flags.
///
/// Hammerspoon's own windows are never included.
///
/// ## Applications that turn Accessibility off
///
/// Window filters see windows through the Accessibility API, which an application can turn off
/// for itself (Firefox does in kiosk mode). Such an application's windows never appear in any
/// filter. `hs.windowfilter.inaccessibleApplications()` lists them, and the module's
/// `inaccessibleApplication` event reports each one as it's found, so you can still offer them
/// some other way, e.g. by activating the application.
@objc protocol HSWindowFilterModuleAPI: JSExport {
    /// Creates a window filter
    /// - Parameter rules?: {{override?: boolean | object, default?: boolean | object, apps?: Record<string, boolean | object>, sortOrder?: "focusedLast" | "focused" | "createdLast" | "created"} | string | string[] | ((window: HSWindow) => boolean)} What the filter allows: omit it for a copy of `hs.windowfilter.defaultFilter` (including any changes you've made to it); an application's name or bundle ID, or an array of them, for those applications' visible windows; a function, called with each window, that returns `true` to allow it; or an object of rules:
    ///   - override?: {boolean | object} The rule every window must pass. See the module's description for rules' conditions
    ///   - default?: {boolean | object} The rule for applications without one of their own. Defaults to every window with a standard role, visible or not
    ///   - apps?: {Record<string, boolean | object>} Rules for particular applications, by name or bundle ID
    ///   - sortOrder?: {"focusedLast" | "focused" | "createdLast" | "created"} How `windows()` sorts windows. Defaults to `"focusedLast"`
    /// - Returns: The new filter
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const safari = hs.windowfilter.create("Safari")
    ///     const titled = hs.windowfilter.create({ default: { visible: true, allowTitles: 1 } })
    ///     const wide = hs.windowfilter.create(win => win.frame.w > 1000)
    ///     const noScratch = hs.windowfilter.create({ apps: { TextEdit: { rejectTitles: /^Untitled/ } } })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func create(_ rules: JSValue?) -> HSWindowFilter?

    /// The default window filter: the visible windows of every application, except some whose
    /// windows are fleeting or not really windows (Spotlight, Notification Center, menu bar
    /// utilities, and so on). It's shared by everything in your config, so change it with care,
    /// before creating other filters from it.
    /// - Example:
    /// ```js
    /// hs.windowfilter.defaultFilter.rejectApp("Cool New Launcher")
    /// console.log(hs.windowfilter.defaultFilter.windows().length + " windows")
    /// ```
    @objc var defaultFilter: HSWindowFilter { get }

    /// A copy of `hs.windowfilter.defaultFilter` that only allows windows in the current Space. It's
    /// made the first time you use it, from the default filter as it is then.
    /// - Example:
    /// ```js
    /// const here = hs.windowfilter.currentSpaceFilter.windows()
    /// ```
    @objc var currentSpaceFilter: HSWindowFilter { get }

    /// The window subroles rules allow when they don't say which subroles they allow:
    /// `AXStandardWindow`, `AXDialog` and `AXSystemDialog` to begin with. Changing it affects
    /// every filter; to allow other subroles in one filter, give its rules `allowRoles`.
    /// - Example:
    /// ```js
    /// hs.windowfilter.allowedWindowRoles = [...hs.windowfilter.allowedWindowRoles, "AXFloatingWindow"]
    /// ```
    @objc var allowedWindowRoles: [String] { get set }

    /// Focuses the nearest window to the right of the focused one, among those in
    /// `hs.windowfilter.currentSpaceFilter`, only considering windows within 45° of that direction
    /// - Returns: `true` if a window was focused
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "right", () => hs.windowfilter.focusEast())
    /// ```
    @objc func focusEast() -> Bool

    /// Focuses the nearest window to the left of the focused one, among those in
    /// `hs.windowfilter.currentSpaceFilter`, only considering windows within 45° of that direction
    /// - Returns: `true` if a window was focused
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "left", () => hs.windowfilter.focusWest())
    /// ```
    @objc func focusWest() -> Bool

    /// Focuses the nearest window above the focused one, among those in
    /// `hs.windowfilter.currentSpaceFilter`, only considering windows within 45° of that direction
    /// - Returns: `true` if a window was focused
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "up", () => hs.windowfilter.focusNorth())
    /// ```
    @objc func focusNorth() -> Bool

    /// Focuses the nearest window below the focused one, among those in
    /// `hs.windowfilter.currentSpaceFilter`, only considering windows within 45° of that direction
    /// - Returns: `true` if a window was focused
    /// - Example:
    /// ```js
    /// hs.hotkey.bind(["cmd", "ctrl"], "down", () => hs.windowfilter.focusSouth())
    /// ```
    @objc func focusSouth() -> Bool

    /// The running applications that have turned the Accessibility API off for themselves (e.g.
    /// Firefox in kiosk mode), so no window filter can see their windows. Hammerspoon stops asking
    /// such an application until it quits.
    ///
    /// While any filter or `inaccessibleApplication` listener is active, this is what Hammerspoon
    /// has found so far, at no cost; otherwise, it asks every application. It's empty if
    /// Hammerspoon hasn't been given Accessibility permission.
    /// - Returns: {HSApplication[]} The applications
    /// - Example:
    /// ```js
    /// for (const app of hs.windowfilter.inaccessibleApplications()) {
    ///     console.log(app.name + " has turned Accessibility off")
    /// }
    /// ```
    @objc func inaccessibleApplications() -> [HSApplication]

    // NOTE: Private API consumed only by hs.windowfilter.js
    /// SKIP_DOCS
    @objc var _makeFilterEmitter: JSFunction? { get set }

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
    /// The event names the module's `on()`/`once()` accept - see HSWindowFilterModuleEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // Set by hs.windowfilter.js. Must be pre-declared properties, or JSC drops them on GC (issue #185).
    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

/// Events emitted by hs.windowfilter's module-level watcher
nonisolated enum HSWindowFilterModuleEvent: String, HSEventName {
    case inaccessibleApplication
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSWindowFilterModule: NSObject, HSModuleAPI, HSWindowFilterModuleAPI {
    var moduleName = "hs.windowfilter"
    let engineID: UUID

    /// Applications whose windows the default filter leaves out, because they come and go too
    /// quickly or aren't really windows. From Hammerspoon 1.
    static let transientApps: [String] = [
        "Spotlight", "Notification Center", "loginwindow", "ScreenSaverEngine", "PressAndHold",
        // Preferences etc
        "PopClip", "Isolator", "CheatSheet", "CornerClickBG", "Alfred 2", "Moom", "CursorSense Manager",
        // Menu bar utilities
        "Music Manager", "Google Drive", "Dropbox", "1Password mini", "Colors for Hue", "MacID",
        "CrashPlan menu bar", "Flux", "Jettison", "Bartender", "SystemPal", "BetterSnapTool", "Grandview", "Radium",
        "MenuMetersApp", "DemoPro",
    ]

    /// The default filter's rules
    static var defaultRules: WindowFilterRules {
        var rules = WindowFilterRules()
        rules.defaultRule = .allow(.visibleOnly)
        for app in transientApps {
            rules.apps[app] = .reject
        }
        return rules
    }

    private let settings = WindowFilterSettings()
    private var filters = HSObjectTracker<HSWindowFilter>()
    // Owned by the module, for the engine's lifetime: everything in a config shares them
    private var sharedDefault: HSWindowFilter?
    private var sharedCurrentSpaceFilter: HSWindowFilter?

    @objc var _makeFilterEmitter: JSFunction?
    @objc var _watcherEmitter: JSFunction?
    @objc var _eventNames: [String] { HSWindowFilterModuleEvent.allNames }
    @objc var on: JSFunction?
    @objc var off: JSFunction?
    @objc var once: JSFunction?
    private var watcherCallback: JSCallback?
    private var inaccessibleSubscription: WindowTracker.Subscription?

    // MARK: - Module lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        filters.shutdown()
        sharedDefault = nil
        sharedCurrentSpaceFilter = nil
        _makeFilterEmitter = nil
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        shutdown()
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = filters.activeCount
        return "<\(moduleName): \(n) active filter\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Creating filters

    @objc func create(_ rules: JSValue?) -> HSWindowFilter? {
        guard let rules, !rules.isUndefined, !rules.isNull else {
            return makeFilter(rules: defaultFilter.currentRules)
        }
        if rules.isFunction {
            return makeFilter(predicate: rules)
        }
        do {
            return makeFilter(rules: try Self.parseCreateArgument(rules))
        } catch {
            let message = "hs.windowfilter.create(): \(error.message)"
            AKError(message)
            if let context = JSContext.current() {
                context.exception = JSValue(newErrorFromMessage: message, in: context)
            }
            return nil
        }
    }

    /// Reads `create()`'s argument, other than a function: application names, or rules
    static func parseCreateArgument(_ value: JSValue) throws(WindowFilterRuleError) -> WindowFilterRules {
        var names: [String]?
        if value.isString {
            names = [value.toString()]
        } else if value.isArray {
            let count = Int(value.forProperty("length")?.toInt32() ?? 0)
            names = try (0..<count).map { (index: Int) throws(WindowFilterRuleError) -> String in
                guard let name = value.atIndex(index), name.isString else {
                    throw WindowFilterRuleError(message: "an array of rules must only contain application names or bundle IDs")
                }
                return name.toString()
            }
        }
        guard let names else {
            return try WindowFilterRules.parse(value)
        }
        var rules = WindowFilterRules()
        rules.defaultRule = .reject
        for name in names {
            rules.apps[name] = .allow(.visibleOnly)
        }
        return rules
    }

    func makeFilter(rules: WindowFilterRules) -> HSWindowFilter {
        let filter = HSWindowFilter(rules: rules, settings: settings, tracker: filters, module: self)
        filters.add(filter)
        return filter
    }

    func makeFilter(predicate: JSValue) -> HSWindowFilter? {
        guard let filter = HSWindowFilter(predicate: predicate, settings: settings, tracker: filters, module: self) else { return nil }
        filters.add(filter)
        return filter
    }

    @objc var defaultFilter: HSWindowFilter {
        if let sharedDefault { return sharedDefault }
        let filter = makeFilter(rules: Self.defaultRules)
        sharedDefault = filter
        return filter
    }

    @objc var currentSpaceFilter: HSWindowFilter {
        if let sharedCurrentSpaceFilter { return sharedCurrentSpaceFilter }
        var rules = defaultFilter.currentRules
        switch rules.override {
        case .allow(var override)?:
            override.currentSpace = true
            rules.override = .allow(override)
        case .reject?:
            // A default filter that rejects everything still does, in the current Space
            break
        case nil:
            rules.override = .allow(WindowRule(currentSpace: true, allowRoles: .any))
        }
        let filter = makeFilter(rules: rules)
        sharedCurrentSpaceFilter = filter
        return filter
    }

    @objc var allowedWindowRoles: [String] {
        get { settings.allowedRoles.sorted() }
        set { settings.allowedRoles = Set(newValue) }
    }

    // MARK: - Focusing

    @objc func focusEast() -> Bool { focus(.east) }
    @objc func focusWest() -> Bool { focus(.west) }
    @objc func focusNorth() -> Bool { focus(.north) }
    @objc func focusSouth() -> Bool { focus(.south) }

    private func focus(_ direction: WindowNeighbours.Direction) -> Bool {
        currentSpaceFilter.neighbours(direction, ["strict": true]).contains { $0.focus() }
    }

    // MARK: - Inaccessible applications

    @objc func inaccessibleApplications() -> [HSApplication] {
        WindowTracker.shared.inaccessibleApplications().map { AXObjectCache.shared.application(for: $0) }
    }

    // MARK: - Events

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) -> Bool {
        guard watcherCallback == nil else {
            AKWarning("hs.windowfilter._addWatcher: already watching — refusing second subscription")
            return false
        }
        watcherCallback = JSCallback(value: callback, owner: self)
        inaccessibleSubscription = WindowTracker.shared.subscribeToInaccessibleApplications { [weak self] app in
            self?.applicationFoundInaccessible(app)
        }
        AKDebug("hs.windowfilter._addWatcher: started")
        return true
    }

    @objc func _removeWatcher() {
        guard watcherCallback != nil else { return }
        inaccessibleSubscription?.cancel()
        inaccessibleSubscription = nil
        watcherCallback?.detach(from: self)
        watcherCallback = nil
        AKDebug("hs.windowfilter._removeWatcher: stopped")
    }

    private func applicationFoundInaccessible(_ app: NSRunningApplication) {
        _ = watcherCallback?.call(withArguments: [HSWindowFilterModuleEvent.inaccessibleApplication.rawValue,
                                                  AXObjectCache.shared.application(for: app)])
    }

    /// Makes the JS emitter for a filter's on()/once(), via the factory in hs.windowfilter.js.
    /// Returns nil, having set `ctx.exception`, on failure.
    func makeFilterEmitter(for filter: HSWindowFilter, in ctx: JSContext) -> JSValue? {
        guard let factory = _makeFilterEmitter, factory.isFunction else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.windowfilter: the watcher emitter factory is unavailable", in: ctx)
            return nil
        }
        let emitter = ctx.callCapturingException { factory.call(withArguments: [filter]) }
        guard ctx.exception == nil, let emitter, emitter.isObject else {
            if ctx.exception == nil {
                ctx.exception = JSValue(newErrorFromMessage: "hs.windowfilter: failed to create a watcher emitter", in: ctx)
            }
            return nil
        }
        return emitter
    }
}
