//
//  NodeModuleUtil.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

/// A partial re-implementation of Node.js's `util` module.
///
/// Hammerspoon 2 is expected to grow more of Node's standard library surface over time
/// (eg. `fs`, `path`, `events`); this "node" directory groups those re-implementations
/// together, separately from the `hs.*` module namespace.
enum NodeUtil {
    /// How many levels of nested objects/arrays ``inspect(_:options:)`` expands before
    /// collapsing them to a placeholder like `[Object]`. Matches Node's own default.
    static let defaultInspectDepth = 2

    /// Options controlling how ``inspect(_:options:)`` formats a value.
    ///
    /// This is a small subset of Node's real `util.inspect` options object - just `depth` and
    /// `getters`. Node's much larger surface (`showHidden`, `customInspect`, `colors`,
    /// `compact`, `maxArrayLength`, `breakLength`, `sorted`, `numericSeparator`, `showProxy`)
    /// is not implemented. Notably, without `showHidden`, `getters: true` only reaches *own*,
    /// enumerable accessor properties (eg. `{ get x() {...} }`) - accessors defined in a
    /// `class` body live on the prototype, are non-enumerable, and are not reached even with
    /// `getters: true`, the same as real Node without `showHidden`.
    struct InspectOptions {
        /// How many levels of nested objects/arrays to expand before collapsing them to a
        /// placeholder like `[Object]`. `nil` means unlimited (Node's `depth: null`).
        var depth: Int?
        /// When `true`, invokes getters and formats their returned value instead of showing a
        /// `[Getter]`/`[Getter/Setter]` placeholder.
        var getters: Bool

        static let `default` = InspectOptions(depth: defaultInspectDepth, getters: false)

        /// Parses the second, optional argument to `util.inspect(value, options)`. Any value
        /// that isn't an object (including `undefined`) yields the defaults.
        static func parse(_ value: JSValue?) -> InspectOptions {
            guard let value, value.isObject else { return .default }
            var result = InspectOptions.default
            if let depthValue = value.objectForKeyedSubscript("depth"), !depthValue.isUndefined {
                result.depth = depthValue.isNull ? nil : Int(depthValue.toInt32())
            }
            if let gettersValue = value.objectForKeyedSubscript("getters"), !gettersValue.isUndefined {
                result.getters = gettersValue.toBool()
            }
            return result
        }

        /// The same options, one level deeper into the value tree.
        fileprivate func descending() -> InspectOptions {
            InspectOptions(depth: depth.map { $0 - 1 }, getters: getters)
        }

        fileprivate var isExhausted: Bool {
            guard let depth else { return false }
            return depth < 0
        }
    }

    /// Formats a value for human-readable display, similar to Node's `util.inspect`.
    ///
    /// A top-level string is returned as-is; every other value is recursively formatted
    /// the way Node/browser consoles render it: nested strings are quoted, objects render
    /// as `{ key: value }`, arrays as `[ item, item ]`, functions as `[Function: name]`,
    /// and so on.
    ///
    /// - Parameters:
    ///   - value: The value to format.
    ///   - options: Formatting options. See ``InspectOptions``.
    /// - Returns: A formatted string.
    static func inspect(_ value: JSValue, options: InspectOptions = .default) -> String {
        value.isString ? (value.toString() ?? "") : format(value, options: options)
    }

    private static func format(_ value: JSValue, options: InspectOptions) -> String {
        if value.isUndefined { return "undefined" }
        if value.isNull { return "null" }
        if value.isBoolean { return value.toBool() ? "true" : "false" }
        if value.isNumber { return formatNumber(value) }
        if value.isString { return quoted(value.toString() ?? "") }
        if value.isDate { return formatDate(value) }
        if value.isInstanceOf(className: "Error") { return formatError(value) }
        if value.isSet { return formatSet(value, options: options) }
        if value.isInstanceOf(className: "Map") { return formatMap(value, options: options) }
        if value.isArray { return formatArray(value, options: options) }
        if value.isFunction { return formatFunction(value) }
        if value.isObject { return formatObject(value, options: options) }
        return value.toString() ?? "undefined"
    }

    private static func formatNumber(_ value: JSValue) -> String {
        let double = value.toDouble()
        if double == 0, double.sign == .minus { return "-0" }
        return value.toString() ?? "\(double)"
    }

    private static func formatDate(_ value: JSValue) -> String {
        // `toISOString()` throws a RangeError for an invalid date instead of returning
        // anything, so check validity with `getTime()` (which just returns NaN) first.
        let time = value.invokeMethod("getTime", withArguments: [])?.toDouble() ?? .nan
        guard time.isFinite else { return "Invalid Date" }
        return value.invokeMethod("toISOString", withArguments: [])?.toString() ?? "Invalid Date"
    }

    private static func formatError(_ value: JSValue) -> String {
        if let stack = value.objectForKeyedSubscript("stack")?.toString(), !stack.isEmpty {
            return stack
        }
        let name = value.objectForKeyedSubscript("name")?.toString() ?? "Error"
        let message = value.objectForKeyedSubscript("message")?.toString() ?? ""
        return message.isEmpty ? name : "\(name): \(message)"
    }

    private static func formatFunction(_ value: JSValue) -> String {
        let name = value.objectForKeyedSubscript("name")?.toString() ?? ""
        let label = isClassConstructor(value) ? "class" : "Function"
        return name.isEmpty ? "[\(label) (anonymous)]" : "[\(label): \(name)]"
    }

    private static func isClassConstructor(_ value: JSValue) -> Bool {
        (value.toString() ?? "").hasPrefix("class")
    }

    private static func formatArray(_ value: JSValue, options: InspectOptions) -> String {
        guard !options.isExhausted else { return "[Array]" }
        let length = Int(value.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        guard length > 0 else { return "[]" }
        let objectConstructor = value.context.objectForKeyedSubscript("Object")
        let items = (0..<length).map {
            formatProperty(value, key: String($0), options: options.descending(), objectConstructor: objectConstructor)
        }
        return "[ \(items.joined(separator: ", ")) ]"
    }

    private static func formatSet(_ value: JSValue, options: InspectOptions) -> String {
        let items = forEachValues(value)
        guard !options.isExhausted else { return "[Set]" }
        guard !items.isEmpty else { return "Set(0) {}" }
        let formatted = items.map { format($0, options: options.descending()) }.joined(separator: ", ")
        return "Set(\(items.count)) { \(formatted) }"
    }

    private static func formatMap(_ value: JSValue, options: InspectOptions) -> String {
        guard !options.isExhausted else { return "[Map]" }
        var entries: [(key: JSValue, value: JSValue)] = []
        let collect: @convention(block) (JSValue, JSValue) -> Void = { entryValue, entryKey in
            entries.append((entryKey, entryValue))
        }
        unsafe value.invokeMethod("forEach", withArguments: [unsafeBitCast(collect, to: JSValue.self)])
        guard !entries.isEmpty else { return "Map(0) {}" }
        let formatted = entries
            .map { "\(format($0.key, options: options.descending())) => \(format($0.value, options: options.descending()))" }
            .joined(separator: ", ")
        return "Map(\(entries.count)) { \(formatted) }"
    }

    private static func forEachValues(_ value: JSValue) -> [JSValue] {
        var values: [JSValue] = []
        let collect: @convention(block) (JSValue) -> Void = { values.append($0) }
        unsafe value.invokeMethod("forEach", withArguments: [unsafeBitCast(collect, to: JSValue.self)])
        return values
    }

    private static func formatObject(_ value: JSValue, options: InspectOptions) -> String {
        guard !options.isExhausted else { return "[Object]" }
        let prefix = constructorPrefix(value)
        let objectConstructor = value.context.objectForKeyedSubscript("Object")
        let keysValue = objectConstructor?.invokeMethod("keys", withArguments: [value])
        let keys = (keysValue?.toArray() as? [String]) ?? []
        guard !keys.isEmpty else { return "\(prefix){}" }
        let entries = keys.map { key -> String in
            "\(formatKey(key)): \(formatProperty(value, key: key, options: options.descending(), objectConstructor: objectConstructor))"
        }
        return "\(prefix){ \(entries.joined(separator: ", ")) }"
    }

    /// Formats a single property. Without `options.getters`, a getter (or getter/setter pair)
    /// is shown as a placeholder instead of being invoked - Node's `util.inspect` doesn't
    /// execute getters by default either, since merely logging an object shouldn't be able to
    /// run arbitrary code, mutate state, or throw. With `options.getters`, the getter is called
    /// and its result folded into the placeholder (`[Getter: 123]` for a primitive result,
    /// `[Getter] { ... }` for an object one, matching Node).
    private static func formatProperty(
        _ value: JSValue,
        key: String,
        options: InspectOptions,
        objectConstructor: JSValue?
    ) -> String {
        let descriptor = objectConstructor?.invokeMethod("getOwnPropertyDescriptor", withArguments: [value, key])
        if let getter = descriptor?.objectForKeyedSubscript("get"), getter.isFunction {
            let hasSetter = descriptor?.objectForKeyedSubscript("set")?.isFunction ?? false
            let label = hasSetter ? "Getter/Setter" : "Getter"
            guard options.getters else { return "[\(label)]" }
            let gotten = getter.call(withArguments: []) ?? JSValue(undefinedIn: value.context)
            guard let gotten else { return "[\(label)]" }
            if gotten.isObject, !gotten.isNull {
                return "[\(label)] \(format(gotten, options: options))"
            }
            return "[\(label): \(format(gotten, options: options))]"
        }
        return format(value.objectForKeyedSubscript(key), options: options)
    }

    private static func constructorPrefix(_ value: JSValue) -> String {
        guard
            let name = value.objectForKeyedSubscript("constructor")?
                .objectForKeyedSubscript("name")?.toString(),
            !name.isEmpty, name != "Object"
        else { return "" }
        return "\(name) "
    }

    private static func formatKey(_ key: String) -> String {
        let isValidIdentifier = key.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
        return isValidIdentifier ? key : quoted(key)
    }

    private static func quoted(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }
}

// MARK: - JSExport

/// The JS-facing surface of Node's `util` module, reachable as `require('util')`.
@objc protocol NodeUtilModuleAPI: JSExport {
    /// Returns a string representation of a value, intended for debugging.
    ///
    /// Objects, arrays, `Map`/`Set`, functions, dates, and errors are formatted the way
    /// Node/browser consoles render them; a top-level string is returned as-is.
    /// - Parameters:
    ///   - value: The value to format.
    ///   - options?: Formatting options. Supports `depth` (levels of nested objects/arrays to expand before collapsing to a placeholder; `null` for unlimited; defaults to `2`) and `getters` (when `true`, invokes own enumerable getter properties and shows their result instead of a `[Getter]` placeholder; defaults to `false`). Node's much larger options surface (`showHidden`, `colors`, `compact`, etc.) is not implemented - in particular, `getters` alone does not reach getters defined in a `class` body, since those are non-enumerable and live on the prototype.
    /// - Returns: A formatted string.
    /// - Example: `util.inspect({ a: 1, b: [1, 2, 3] }) // "{ a: 1, b: [ 1, 2, 3 ] }"`
    /// - Example: `util.inspect({ get x() { return 42 } }, { getters: true }) // "{ x: [Getter: 42] }"`
    @objc func inspect(_ value: JSValue, _ options: JSValue?) -> String
}

/// Backs the `util` object returned by `require('util')`. See ``NodeUtil`` for the
/// underlying formatting logic.
@objc class NodeUtilModule: NSObject, NodeUtilModuleAPI {
    @objc func inspect(_ value: JSValue, _ options: JSValue?) -> String {
        NodeUtil.inspect(value, options: NodeUtil.InspectOptions.parse(options))
    }
}
