//
//  WindowFilterRules.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

/// Why a set of rules from JavaScript couldn't be used; the message becomes the thrown Error's
struct WindowFilterRuleError: Error, Equatable {
    let message: String
}

/// Matches window titles: exactly, or with a regular expression
enum TitleMatcher {
    case exact(String)
    case regex(NSRegularExpression, source: String, flags: String)

    func matches(_ title: String) -> Bool {
        switch self {
        case .exact(let expected):
            return title == expected
        case .regex(let regex, _, _):
            return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
        }
    }

    /// Builds a matcher from a JS RegExp's source and flags. Only flags that mean the same thing
    /// for NSRegularExpression are accepted, so a pattern never quietly matches differently.
    /// - Parameter name: Where the pattern came from, for error messages
    static func regex(source: String, flags: String, name: String) throws(WindowFilterRuleError) -> TitleMatcher {
        var options: NSRegularExpression.Options = []
        for flag in flags {
            switch flag {
            case "i": options.insert(.caseInsensitive)
            case "m": options.insert(.anchorsMatchLines)
            case "s": options.insert(.dotMatchesLineSeparators)
            case "g", "d": break // No effect on whether a title matches
            default:
                throw WindowFilterRuleError(message: "\(name): the '\(flag)' flag of /\(source)/\(flags) isn't supported (only i, m and s are)")
            }
        }
        do {
            return .regex(try NSRegularExpression(pattern: source, options: options), source: source, flags: flags)
        } catch {
            throw WindowFilterRuleError(message: "\(name): /\(source)/\(flags) isn't a supported regular expression")
        }
    }
}

/// Matches the screen a window is mostly on, by UUID or name
enum ScreenMatcher: Equatable {
    case uuid(String)
    case nameOrUUID(String)

    func matches(uuid: String?, name: String?) -> Bool {
        switch self {
        case .uuid(let expected): return uuid == expected
        case .nameOrUUID(let expected): return uuid == expected || name == expected
        }
    }

    var jsValue: String {
        switch self {
        case .uuid(let value), .nameOrUUID(let value): return value
        }
    }
}

/// Which window subroles a rule allows
enum RoleSet: Equatable {
    /// Those in `hs.windowfilter.allowedWindowRoles`
    case standard
    /// Every window, including ones with no subrole
    case any
    case only(Set<String>)
}

/// The conditions a window must meet to be allowed. A nil condition isn't checked.
struct WindowRule {
    var visible: Bool?
    var currentSpace: Bool?
    var fullscreen: Bool?
    var hasTitlebar: Bool?
    var focused: Bool?
    var activeApplication: Bool?
    var minTitleLength: Int?
    var allowTitles: [TitleMatcher]?
    var rejectTitles: [TitleMatcher]?
    var allowRegions: [CGRect]?
    var rejectRegions: [CGRect]?
    var allowScreens: [ScreenMatcher]?
    var rejectScreens: [ScreenMatcher]?
    var allowRoles: RoleSet = .standard

    static let visibleOnly = WindowRule(visible: true)

    func allows(_ window: WindowState, allowedRoles: Set<String>) -> Bool {
        if let visible, visible != window.isVisible { return false }
        if let currentSpace, currentSpace != window.isInCurrentSpace { return false }
        if let fullscreen, fullscreen != window.isFullscreen { return false }
        if let hasTitlebar, hasTitlebar != window.hasTitlebar { return false }
        if let focused, focused != window.hasFocus { return false }
        if let activeApplication, activeApplication != window.isAppActive { return false }
        if let minTitleLength, window.title.count < minTitleLength { return false }
        if let allowTitles, !allowTitles.contains(where: { $0.matches(window.title) }) { return false }
        if let rejectTitles, rejectTitles.contains(where: { $0.matches(window.title) }) { return false }

        // Minimized and hidden windows aren't anywhere on screen, so regions and screens don't
        // apply to them (as in Hammerspoon 1)
        if window.isVisible {
            if let allowRegions, !allowRegions.contains(where: { Self.overlapsMostly(window.frame, $0) }) { return false }
            if let rejectRegions, rejectRegions.contains(where: { Self.overlapsMostly(window.frame, $0) }) { return false }
            if let allowScreens, !allowScreens.contains(where: { $0.matches(uuid: window.screenUUID, name: window.screenName) }) { return false }
            if let rejectScreens, rejectScreens.contains(where: { $0.matches(uuid: window.screenUUID, name: window.screenName) }) { return false }
        }

        switch allowRoles {
        case .any: return true
        case .standard: return allowedRoles.contains(window.subrole ?? "")
        case .only(let roles): return roles.contains(window.subrole ?? "")
        }
    }

    /// Whether at least half of the window is in the region, or the window covers at least half of it
    static func overlapsMostly(_ frame: CGRect, _ region: CGRect) -> Bool {
        let overlap = frame.intersection(region)
        guard !overlap.isNull else { return false }
        let area = overlap.width * overlap.height
        return area > 0 && (area >= frame.width * frame.height * 0.5 || area >= region.width * region.height * 0.5)
    }
}

/// What a filter does with an application's windows (or every application's, for the default
/// and override rules)
enum AppRule {
    case reject
    case allow(WindowRule)

    func allows(_ window: WindowState, allowedRoles: Set<String>) -> Bool {
        switch self {
        case .reject: return false
        case .allow(let rule): return rule.allows(window, allowedRoles: allowedRoles)
        }
    }
}

/// The orders `windows()` can return windows in
enum WindowSortOrder: String, CaseIterable {
    /// Most recently focused first
    case focusedLast
    /// Least recently focused first
    case focused
    /// Newest first
    case createdLast
    /// Oldest first
    case created
}

/// A filter's complete set of rules.
///
/// A window must pass the override rule, if there is one. Then the rule for its application (by
/// bundle ID, then by name) decides, or the default rule if the application has none. App rules
/// replace the default rather than adding to it, as in Hammerspoon 1.
struct WindowFilterRules {
    var override: AppRule?
    var defaultRule: AppRule = .allow(WindowRule())
    var apps: [String: AppRule] = [:]
    var sortOrder: WindowSortOrder = .focusedLast

    func allows(_ window: WindowState, allowedRoles: Set<String>) -> Bool {
        if let override, !override.allows(window, allowedRoles: allowedRoles) { return false }
        return rule(forBundleID: window.bundleID, appName: window.appName).allows(window, allowedRoles: allowedRoles)
    }

    /// The rule for an application's windows: its own, or the default
    func rule(forBundleID bundleID: String?, appName: String) -> AppRule {
        if let bundleID, let rule = apps[bundleID] { return rule }
        return apps[appName] ?? defaultRule
    }

    /// Whether an application's windows could be allowed at all
    func allowsApp(_ name: String) -> Bool {
        if case .reject? = override { return false }
        if case .reject = apps[name] ?? defaultRule { return false }
        return true
    }
}

// MARK: - From JavaScript

extension WindowFilterRules {
    private static let ruleSetKeys: Set<String> = ["override", "default", "apps", "sortOrder"]

    /// Reads a set of rules: `{ override, default, apps, sortOrder }`, all optional. An omitted
    /// default allows every window with a standard role.
    static func parse(_ value: JSValue) throws(WindowFilterRuleError) -> WindowFilterRules {
        guard value.isObject, !value.isArray else {
            throw WindowFilterRuleError(message: "rules must be an object")
        }
        let keys = ownKeys(of: value)
        if let unknown = keys.first(where: { !ruleSetKeys.contains($0) }) {
            throw WindowFilterRuleError(message: "unknown key '\(unknown)' (expected override, default, apps or sortOrder)")
        }

        var rules = WindowFilterRules()
        if keys.contains("override") {
            rules.override = try parseAppRule(value.forProperty("override"), name: "override", defaultRoles: .any)
        }
        if keys.contains("default") {
            rules.defaultRule = try parseAppRule(value.forProperty("default"), name: "default") ?? .allow(WindowRule())
        }
        if keys.contains("apps"), let apps = value.forProperty("apps"), !apps.isUndefined, !apps.isNull {
            guard apps.isObject, !apps.isArray else {
                throw WindowFilterRuleError(message: "apps must be an object, mapping application names or bundle IDs to rules")
            }
            for app in ownKeys(of: apps) {
                if let rule = try parseAppRule(apps.forProperty(app), name: "apps['\(app)']") {
                    rules.apps[app] = rule
                }
            }
        }
        if keys.contains("sortOrder"), let order = value.forProperty("sortOrder"), !order.isUndefined, !order.isNull {
            rules.sortOrder = try parseSortOrder(order)
        }
        return rules
    }

    static func parseSortOrder(_ value: JSValue) throws(WindowFilterRuleError) -> WindowSortOrder {
        guard value.isString, let name = value.toString(), let order = WindowSortOrder(rawValue: name) else {
            throw WindowFilterRuleError(message: "sortOrder must be one of " + WindowSortOrder.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", "))
        }
        return order
    }

    private static let ruleKeys: Set<String> = [
        "visible", "currentSpace", "fullscreen", "hasTitlebar", "focused", "activeApplication",
        "allowTitles", "rejectTitles", "allowRegions", "rejectRegions", "allowScreens", "rejectScreens",
        "allowRoles",
    ]

    /// Reads one rule: `true` (visible windows), `false` (no windows), or an object of conditions.
    /// - Parameter defaultRoles: The subroles the rule allows if it doesn't say. The override rule
    ///   allows any, so it only restricts subroles when it's asked to.
    /// - Returns: nil for null or undefined, meaning no rule
    static func parseAppRule(_ value: JSValue?, name: String, defaultRoles: RoleSet = .standard) throws(WindowFilterRuleError) -> AppRule? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isBoolean {
            return value.toBool() ? .allow(WindowRule(visible: true, allowRoles: defaultRoles)) : .reject
        }
        guard value.isObject, !value.isArray else {
            throw WindowFilterRuleError(message: "\(name) must be true, false, or an object of conditions")
        }

        let keys = ownKeys(of: value)
        if let unknown = keys.first(where: { !ruleKeys.contains($0) }) {
            throw WindowFilterRuleError(message: "\(name) has an unknown condition '\(unknown)'")
        }

        var rule = WindowRule(allowRoles: defaultRoles)
        func bool(_ key: String) throws(WindowFilterRuleError) -> Bool? {
            guard keys.contains(key), let field = value.forProperty(key), !field.isUndefined, !field.isNull else { return nil }
            guard field.isBoolean else {
                throw WindowFilterRuleError(message: "\(name).\(key) must be true or false")
            }
            return field.toBool()
        }
        func field(_ key: String) -> JSValue? {
            guard keys.contains(key), let field = value.forProperty(key), !field.isUndefined, !field.isNull else { return nil }
            return field
        }

        rule.visible = try bool("visible")
        rule.currentSpace = try bool("currentSpace")
        rule.fullscreen = try bool("fullscreen")
        rule.hasTitlebar = try bool("hasTitlebar")
        rule.focused = try bool("focused")
        rule.activeApplication = try bool("activeApplication")

        if let titles = field("allowTitles") {
            if titles.isNumber {
                // Int(exactly:) rejects fractions, infinities and numbers too big for an Int,
                // any of which Int() would trap on or round
                let length = titles.toDouble()
                guard length >= 0, let minimum = Int(exactly: length) else {
                    throw WindowFilterRuleError(message: "\(name).allowTitles must be a whole number of characters, a string, a RegExp, or an array of them")
                }
                rule.minTitleLength = minimum
            } else {
                rule.allowTitles = try parseTitles(titles, name: "\(name).allowTitles")
            }
        }
        if let titles = field("rejectTitles") {
            rule.rejectTitles = try parseTitles(titles, name: "\(name).rejectTitles")
        }
        if let regions = field("allowRegions") {
            rule.allowRegions = try parseRegions(regions, name: "\(name).allowRegions")
        }
        if let regions = field("rejectRegions") {
            rule.rejectRegions = try parseRegions(regions, name: "\(name).rejectRegions")
        }
        if let screens = field("allowScreens") {
            rule.allowScreens = try parseScreens(screens, name: "\(name).allowScreens")
        }
        if let screens = field("rejectScreens") {
            rule.rejectScreens = try parseScreens(screens, name: "\(name).rejectScreens")
        }
        if let roles = field("allowRoles") {
            if roles.isString, roles.toString() == "*" {
                rule.allowRoles = .any
            } else {
                let names = try list(roles).map { (role: JSValue) throws(WindowFilterRuleError) -> String in
                    guard role.isString, let name = role.toString() else {
                        throw WindowFilterRuleError(message: "\(name).allowRoles must be \"*\", a subrole name, or an array of them")
                    }
                    return name
                }
                rule.allowRoles = .only(Set(names))
            }
        }
        return .allow(rule)
    }

    /// One value, or the elements of an array
    private static func list(_ value: JSValue) throws(WindowFilterRuleError) -> [JSValue] {
        guard value.isArray else { return [value] }
        let count = value.forProperty("length")?.toInt32() ?? 0
        return (0..<Int(count)).compactMap { value.atIndex($0) }
    }

    private static func parseTitles(_ value: JSValue, name: String) throws(WindowFilterRuleError) -> [TitleMatcher] {
        try list(value).map { (title: JSValue) throws(WindowFilterRuleError) -> TitleMatcher in
            if title.isString, let string = title.toString() {
                return .exact(string)
            }
            // A RegExp: anything with string `source` and `flags`
            if title.isObject,
               let source = title.forProperty("source"), source.isString,
               let flags = title.forProperty("flags"), flags.isString {
                return try TitleMatcher.regex(source: source.toString(), flags: flags.toString(), name: name)
            }
            throw WindowFilterRuleError(message: "\(name) must be a string, a RegExp, or an array of them")
        }
    }

    private static func parseRegions(_ value: JSValue, name: String) throws(WindowFilterRuleError) -> [CGRect] {
        try list(value).map { (region: JSValue) throws(WindowFilterRuleError) -> CGRect in
            if let rect = region.toObjectOf(HSRect.self) as? HSRect {
                return rect.rect
            }
            if region.isObject,
               let x = region.forProperty("x"), x.isNumber, let y = region.forProperty("y"), y.isNumber,
               let w = region.forProperty("w"), w.isNumber, let h = region.forProperty("h"), h.isNumber {
                return CGRect(x: x.toDouble(), y: y.toDouble(), width: w.toDouble(), height: h.toDouble())
            }
            throw WindowFilterRuleError(message: "\(name) must be an HSRect, an object with x, y, w and h, or an array of them")
        }
    }

    private static func parseScreens(_ value: JSValue, name: String) throws(WindowFilterRuleError) -> [ScreenMatcher] {
        try list(value).map { (screen: JSValue) throws(WindowFilterRuleError) -> ScreenMatcher in
            if let screen = screen.toObjectOf(HSScreen.self) as? HSScreen {
                return .uuid(screen.uuid)
            }
            if screen.isString, let string = screen.toString() {
                return .nameOrUUID(string)
            }
            throw WindowFilterRuleError(message: "\(name) must be an HSScreen, a screen's name or UUID, or an array of them")
        }
    }

    /// The names of an object's own enumerable properties. Read with the C API rather than by
    /// calling `Object.keys`, which a user script could have replaced.
    private static func ownKeys(of value: JSValue) -> [String] {
        guard let ctx = unsafe value.context?.jsGlobalContextRef,
              let object = unsafe JSValueToObject(ctx, value.jsValueRef, nil) else { return [] }
        let names = unsafe JSObjectCopyPropertyNames(ctx, object)
        defer { unsafe JSPropertyNameArrayRelease(names) }
        let count = unsafe JSPropertyNameArrayGetCount(names)
        return (0..<count).compactMap { index in
            guard let name = unsafe JSPropertyNameArrayGetNameAtIndex(names, index) else { return nil }
            return unsafe JSStringCopyCFString(kCFAllocatorDefault, name) as String
        }
    }
}

// MARK: - To JavaScript

extension WindowFilterRules {
    /// These rules as a plain JS object, in the form `parse` reads
    func jsValue(in context: JSContext) -> JSValue {
        let object: JSValue = JSValue(newObjectIn: context)
        if let override {
            object.setValue(override.jsValue(in: context, defaultRoles: .any), forProperty: "override")
        }
        object.setValue(defaultRule.jsValue(in: context), forProperty: "default")
        let appRules: JSValue = JSValue(newObjectIn: context)
        for (name, rule) in apps.sorted(by: { $0.key < $1.key }) {
            appRules.setValue(rule.jsValue(in: context), forProperty: name)
        }
        object.setValue(appRules, forProperty: "apps")
        object.setValue(sortOrder.rawValue, forProperty: "sortOrder")
        return object
    }
}

extension AppRule {
    /// - Parameter defaultRoles: The subroles the rule allows when it doesn't say, which needn't be written out
    func jsValue(in context: JSContext, defaultRoles: RoleSet = .standard) -> JSValue {
        switch self {
        case .reject:
            return JSValue(bool: false, in: context)
        case .allow(let rule):
            return rule.jsValue(in: context, defaultRoles: defaultRoles)
        }
    }
}

extension WindowRule {
    func jsValue(in context: JSContext, defaultRoles: RoleSet = .standard) -> JSValue {
        let object: JSValue = JSValue(newObjectIn: context)
        let flags: [(String, Bool?)] = [
            ("visible", visible), ("currentSpace", currentSpace), ("fullscreen", fullscreen),
            ("hasTitlebar", hasTitlebar), ("focused", focused), ("activeApplication", activeApplication),
        ]
        for (key, value) in flags {
            if let value { object.setValue(value, forProperty: key) }
        }
        if let minTitleLength {
            object.setValue(minTitleLength, forProperty: "allowTitles")
        } else if let allowTitles {
            object.setValue(Self.titles(allowTitles, in: context), forProperty: "allowTitles")
        }
        if let rejectTitles {
            object.setValue(Self.titles(rejectTitles, in: context), forProperty: "rejectTitles")
        }
        if let allowRegions {
            object.setValue(allowRegions.map { $0.toBridge() }, forProperty: "allowRegions")
        }
        if let rejectRegions {
            object.setValue(rejectRegions.map { $0.toBridge() }, forProperty: "rejectRegions")
        }
        if let allowScreens {
            object.setValue(allowScreens.map(\.jsValue), forProperty: "allowScreens")
        }
        if let rejectScreens {
            object.setValue(rejectScreens.map(\.jsValue), forProperty: "rejectScreens")
        }
        if allowRoles != defaultRoles {
            switch allowRoles {
            case .standard: break // Only an override rule defaults to other roles, and it can never ask for these
            case .any: object.setValue("*", forProperty: "allowRoles")
            case .only(let roles): object.setValue(roles.sorted(), forProperty: "allowRoles")
            }
        }
        return object
    }

    private static func titles(_ matchers: [TitleMatcher], in context: JSContext) -> JSValue {
        let array: JSValue = JSValue(newArrayIn: context)
        for (index, matcher) in matchers.enumerated() {
            switch matcher {
            case .exact(let title):
                array.setValue(title, at: index)
            case .regex(_, let source, let flags):
                array.setValue(JSValue(newRegularExpressionFromPattern: source, flags: flags, in: context), at: index)
            }
        }
        return array
    }
}
