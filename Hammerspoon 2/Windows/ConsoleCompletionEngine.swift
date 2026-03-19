//
//  ConsoleCompletionEngine.swift
//  Hammerspoon 2
//

import Foundation

/// Tab-completion engine for the Console input field.
///
/// ## Completion strategy
///
/// | Input shape                    | Strategy                                          |
/// |-------------------------------|---------------------------------------------------|
/// | `hs.`                         | JS reflection on `hs` (dynamic namespace object)  |
/// | `hs.screen.`                  | api.json module-level items for `hs.screen`       |
/// | `hs.screen.primary().`        | api.json return-type lookup → HSScreen instances  |
/// | `hs.screen.primary().next().` | No completion (nested call, too risky)            |
///
/// ## Formatting
///
/// Completions are formatted using api.json metadata:
/// - Properties → bare name (e.g. `frame`)
/// - 0-param methods → `name()` (e.g. `all()`)
/// - N-param methods → `name(p1, p2, …)` (e.g. `setMode(width, height, scale, frequency)`)
enum ConsoleCompletionEngine {

    // MARK: - Result type

    struct Result {
        struct Candidate {
            /// Bare name, used for stem filtering and LCP computation.
            let name: String
            /// What gets inserted into the input field.
            let completion: String
        }

        /// Text that precedes the expression being completed (e.g. `"var x = "`).
        /// Must be prepended when writing back to the input field.
        let inputPrefix: String
        /// The object expression plus a trailing dot (e.g. `"hs.screen."`).
        let prefix: String
        let stem: String
        let candidates: [Candidate]

        var isUnique: Bool { candidates.count == 1 }

        /// Longest common prefix across all candidate *names* (always ≥ stem).
        var longestCommonPrefix: String {
            guard let first = candidates.first else { return stem }
            var lcp = first.name
            for c in candidates.dropFirst() {
                while !c.name.hasPrefix(lcp) { lcp = String(lcp.dropLast()) }
                if lcp.isEmpty { break }
            }
            return lcp
        }

        /// Space-separated list of completions, suitable for printing to the console.
        var displayString: String {
            candidates.map(\.completion).joined(separator: "  ")
        }
    }

    // MARK: - Entry point

    /// Returns a `Result` for `input`, or `nil` if no completion can be offered.
    static func complete(input: String) -> Result? {
        guard let dotIdx = input.lastIndex(of: ".") else { return nil }

        let stem = String(input[input.index(after: dotIdx)...])

        // Extract only the expression fragment that ends at the last dot.
        // Walk backward to find the first character that cannot be part of an
        // expression chain (letter, digit, _, ., (, )) — everything after that
        // separator is the object expression. This lets completion work when the
        // input field contains a larger statement like "var x = hs.screen.pri".
        let beforeDot = String(input[input.startIndex..<dotIdx])
        let isExprChar: (Character) -> Bool = {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "(" || $0 == ")"
        }
        let objectExpr: String
        let inputPrefix: String
        if let lastSep = beforeDot.lastIndex(where: { !isExprChar($0) }) {
            inputPrefix = String(beforeDot[...lastSep])
            objectExpr = String(beforeDot[beforeDot.index(after: lastSep)...])
        } else {
            inputPrefix = ""
            objectExpr = beforeDot
        }

        // Stem must look like a partial identifier — no brackets.
        guard !stem.contains("("), !stem.contains(")") else { return nil }
        guard !objectExpr.isEmpty else { return nil }

        if !objectExpr.contains("(") {
            // Pure property chain: `hs.screen` etc.
            return completePropertyChain(objectExpr: objectExpr, stem: stem, inputPrefix: inputPrefix)
        } else if objectExpr.hasSuffix("()") {
            // Ends with a single no-argument call: `hs.screen.primary()`
            let calleeExpr = String(objectExpr.dropLast(2))
            if !calleeExpr.contains("(") {
                // Callee is itself a pure property chain — safe to look up statically.
                return completeAfterCall(calleeExpr: calleeExpr,
                                         objectExpr: objectExpr,
                                         stem: stem,
                                         inputPrefix: inputPrefix)
            }
        }
        // Nested calls, calls with arguments, etc. — don't complete.
        return nil
    }

    // MARK: - Completion strategies

    /// Handles pure property chains (no `()` in the expression).
    ///
    /// Uses api.json for known modules (authoritative, no prototype noise).
    /// Falls back to JS reflection for dynamic objects (e.g. `hs` itself).
    private static func completePropertyChain(objectExpr: String, stem: String, inputPrefix: String) -> Result? {
        // api.json path — preferred
        if let items = apiData?.moduleItems[objectExpr] {
            let candidates = candidates(from: items, stem: stem)
            if !candidates.isEmpty {
                return Result(inputPrefix: inputPrefix, prefix: objectExpr + ".", stem: stem, candidates: candidates)
            }
        }

        // If the expression evaluates to a known HS type, use api.json for proper formatting.
        if let typeName = reflectedTypeName(of: objectExpr),
           let items = apiData?.instanceItems[typeName] {
            let candidates = candidates(from: items, stem: stem)
            if !candidates.isEmpty {
                return Result(inputPrefix: inputPrefix, prefix: objectExpr + ".", stem: stem, candidates: candidates)
            }
        }

        // Full JS reflection fallback (handles `hs.` root and any unrecognised objects)
        guard let names = reflectedNames(of: objectExpr) else { return nil }
        let candidates = names.compactMap { name -> Result.Candidate? in
            guard stem.isEmpty || name.hasPrefix(stem) else { return nil }
            return Result.Candidate(name: name, completion: name)
        }
        guard !candidates.isEmpty else { return nil }
        return Result(inputPrefix: inputPrefix, prefix: objectExpr + ".", stem: stem, candidates: candidates)
    }

    /// Handles a single no-argument call at the end, e.g. `hs.screen.primary()`.
    ///
    /// Looks up the method's return type in api.json, then returns the instance-level
    /// items for that type.  Never evaluates JavaScript.
    private static func completeAfterCall(calleeExpr: String,
                                          objectExpr: String,
                                          stem: String,
                                          inputPrefix: String) -> Result? {
        // calleeExpr: "hs.screen.primary" → split into module + method
        guard let dotIdx = calleeExpr.lastIndex(of: ".") else { return nil }
        let moduleName = String(calleeExpr[calleeExpr.startIndex..<dotIdx])
        let methodName = String(calleeExpr[calleeExpr.index(after: dotIdx)...])

        let lookupKey = "\(moduleName).\(methodName)"

        // Static api.json path (preferred — no JS evaluation).
        if let returnType = apiData?.returnTypes[lookupKey],
           let items = apiData?.instanceItems[returnType] {
            let candidates = candidates(from: items, stem: stem)
            if !candidates.isEmpty {
                return Result(inputPrefix: inputPrefix, prefix: objectExpr + ".", stem: stem, candidates: candidates)
            }
        } else {
            // Fallback: evaluate the call expression to discover the return type at runtime.
            // This handles cases where api.json is absent or the return-type map is incomplete.
            if let typeName = reflectedTypeName(of: objectExpr),
               let items = apiData?.instanceItems[typeName] {
                let candidates = candidates(from: items, stem: stem)
                if !candidates.isEmpty {
                    return Result(inputPrefix: inputPrefix, prefix: objectExpr + ".", stem: stem, candidates: candidates)
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func candidates(from items: [APICompletionItem],
                                   stem: String) -> [Result.Candidate] {
        items
            .filter { stem.isEmpty || $0.name.hasPrefix(stem) }
            .sorted { $0.name < $1.name }
            .map { Result.Candidate(name: $0.name, completion: $0.formattedCompletion) }
    }

    // MARK: - JS reflection

    /// Returns the `typeName` property of the evaluated expression, or `nil` if unavailable.
    /// Used to cross-reference the JS object against api.json instance items for proper formatting.
    private static func reflectedTypeName(of expression: String) -> String? {
        let js = """
        (function() {
            try {
                var obj = \(expression);
                if (obj === null || obj === undefined) return null;
                var t = obj.typeName;
                return (typeof t === 'string' && t.length > 0) ? t : null;
            } catch (e) {
                return null;
            }
        })()
        """
        guard let raw = JSEngine.shared.eval(js) else { return nil }
        return raw as? String
    }

    private static func reflectedNames(of expression: String) -> [String]? {
        // Walks the prototype chain collecting own property names, filtering out
        // internal/framework noise.  Runs in a JS try/catch so a bad expression
        // never prints an error to the console.
        let js = """
        (function() {
            try {
                var obj = \(expression);
                if (obj === null || obj === undefined) return [];
                var seen = Object.create(null);
                var cur = obj;
                while (cur !== null && cur !== undefined) {
                    Object.getOwnPropertyNames(cur).forEach(function(n) { seen[n] = true; });
                    var proto = Object.getPrototypeOf(cur);
                    if (!proto || proto === cur) break;
                    cur = proto;
                }
                return Object.keys(seen).filter(function(n) {
                    return typeof n === 'string'
                        && n.indexOf('__') !== 0
                        && n !== 'constructor'
                        && n !== 'typeName';
                }).sort();
            } catch (e) {
                return [];
            }
        })()
        """
        guard let raw = JSEngine.shared.eval(js),
              let array = raw as? [Any] else { return nil }
        let names = array.compactMap { $0 as? String }
        return names.isEmpty ? nil : names
    }

    // MARK: - API data

    private static let apiData: APICompletionData? = {
        // App bundle (release builds)
        if let url = Bundle.main.url(forResource: "api", withExtension: "json") {
            return APICompletionData(url: url)
        }
        // Dev fallback: walk up from the bundle to find docs/api.json in the source tree
        var dir = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<10 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("docs/api.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return APICompletionData(url: candidate)
            }
        }
        return nil
    }()
}

// MARK: - Internal API data model

private struct APICompletionItem {
    let name: String
    let paramNames: [String]
    let isProperty: Bool

    var formattedCompletion: String {
        if isProperty          { return name }
        if paramNames.isEmpty  { return "\(name)()" }
        return "\(name)(\(paramNames.joined(separator: ", ")))"
    }
}

private struct APICompletionData {
    /// Module-level items keyed by module name (e.g. `"hs.screen"`).
    let moduleItems: [String: [APICompletionItem]]
    /// Instance-level items keyed by Swift type name (e.g. `"HSScreen"`).
    let instanceItems: [String: [APICompletionItem]]
    /// Return-type map: `"hs.screen.primary"` → `"HSScreen"`.
    let returnTypes: [String: String]

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modules = json["modules"] as? [[String: Any]] else { return nil }

        var modItems:  [String: [APICompletionItem]] = [:]
        var instItems: [String: [APICompletionItem]] = [:]
        var retTypes:  [String: String] = [:]

        for module in modules {
            guard let moduleName = module["name"] as? String else { continue }

            let methods    = module["methods"]    as? [[String: Any]] ?? []
            let properties = module["properties"] as? [[String: Any]] ?? []

            for method in methods {
                guard let name     = method["name"]     as? String,
                      let filePath = method["filePath"] as? String else { continue }

                let params = (method["params"] as? [[String: Any]] ?? [])
                    .compactMap { $0["name"] as? String }
                let item = APICompletionItem(name: name, paramNames: params, isProperty: false)

                if Self.isModuleLevel(filePath) {
                    modItems[moduleName, default: []].append(item)
                } else {
                    instItems[Self.typeName(from: filePath), default: []].append(item)
                }

                // Record return type for instance-completion lookup
                if let returns    = method["returns"]  as? [String: Any],
                   let returnType = returns["type"]    as? String {
                    let normalized = Self.normalizeType(returnType)
                    if !normalized.isEmpty {
                        retTypes["\(moduleName).\(name)"] = normalized
                    }
                }
            }

            for prop in properties {
                guard let name     = prop["name"]     as? String,
                      let filePath = prop["filePath"] as? String else { continue }

                let item = APICompletionItem(name: name, paramNames: [], isProperty: true)
                if Self.isModuleLevel(filePath) {
                    modItems[moduleName, default: []].append(item)
                } else {
                    instItems[Self.typeName(from: filePath), default: []].append(item)
                }
            }
        }

        self.moduleItems  = modItems
        self.instanceItems = instItems
        self.returnTypes  = retTypes
    }

    /// Files from `*Module.swift` or `.js` stubs are module-level; everything else is instance-level.
    private static func isModuleLevel(_ filePath: String) -> Bool {
        let filename = URL(fileURLWithPath: filePath).lastPathComponent
        return filename.hasSuffix("Module.swift") || filename.hasSuffix(".js")
    }

    /// `"…/HSScreen.swift"` → `"HSScreen"`.
    private static func typeName(from filePath: String) -> String {
        URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    }

    /// Strips `?`, `[`, `]` and discards primitive types that aren't our HS types.
    private static func normalizeType(_ type: String) -> String {
        var t = type
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespaces)
        let primitives: Set<String> = [
            "Bool", "Int", "Double", "Float", "String", "Void",
            "JSPromise", "NSDictionary", "NSArray",
        ]
        return primitives.contains(t) ? "" : t
    }
}
