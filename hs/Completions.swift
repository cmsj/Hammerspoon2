//
//  Completions.swift
//  hs — Hammerspoon 2 interactive REPL
//
//  Parses api.json (module-level items only) to drive LineReader tab-completion and hints.
//

import Foundation

// MARK: - Data model

nonisolated struct CompletionItem: Sendable {
    let name: String
    let paramNames: [String]
    let isProperty: Bool

    var formatted: String {
        if isProperty         { return name }
        if paramNames.isEmpty { return "\(name)()" }
        return "\(name)(\(paramNames.joined(separator: ", ")))"
    }
}

nonisolated struct CompletionTable: Sendable {
    // "hs.ipc" → [item, …]
    let items: [String: [CompletionItem]]

    init?(url: URL) {
        guard let data    = try? Data(contentsOf: url),
              let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modules = json["modules"] as? [[String: Any]] else { return nil }

        var table: [String: [CompletionItem]] = [:]
        for module in modules {
            guard let moduleName = module["name"] as? String else { continue }

            var entries: [CompletionItem] = []
            for m in (module["methods"] as? [[String: Any]] ?? []) {
                guard let mname   = m["name"]     as? String,
                      let filePath = m["filePath"] as? String,
                      Self.isModuleLevel(filePath) else { continue }
                let params = (m["params"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                entries.append(CompletionItem(name: mname, paramNames: params, isProperty: false))
            }
            for p in (module["properties"] as? [[String: Any]] ?? []) {
                guard let pname    = p["name"]     as? String,
                      let filePath  = p["filePath"] as? String,
                      Self.isModuleLevel(filePath) else { continue }
                entries.append(CompletionItem(name: pname, paramNames: [], isProperty: true))
            }
            if !entries.isEmpty { table[moduleName] = entries }
        }
        self.items = table
    }

    // MARK: - Completion

    /// Returns completions for `input` as full strings prefixed by `input`.
    ///
    /// LineReader expects: each returned string must start with the current buffer.
    /// It then shows the common prefix and allows cycling.
    func complete(input: String) -> [String] {
        guard let lastDot = input.lastIndex(of: ".") else {
            // No dot — match top-level roots (e.g. "hs")
            let roots = Set(items.keys.compactMap { $0.split(separator: ".").first.map(String.init) })
            return roots.filter { $0.hasPrefix(input) }.sorted()
        }

        let prefix     = String(input[input.startIndex...lastDot])   // "hs.ipc."
        let objectExpr = String(prefix.dropLast())                   // "hs.ipc"
        let stem       = String(input[input.index(after: lastDot)...]) // "s"

        // Try completing sub-module names: "hs." → ["hs.ipc.", "hs.screen.", …]
        let subModulePrefix = objectExpr + "."
        let subModules = items.keys
            .filter { $0.hasPrefix(subModulePrefix) }
            .compactMap { name -> String? in
                let remainder = String(name.dropFirst(subModulePrefix.count))
                return remainder.contains(".") ? nil : remainder  // direct children only
            }
            .filter { stem.isEmpty || $0.hasPrefix(stem) }

        if !subModules.isEmpty {
            return subModules.sorted().map { prefix + $0 + "." }
        }

        // Try completing method / property names: "hs.ipc.s" → ["hs.ipc.start(port)", …]
        if let entries = items[objectExpr] {
            return entries
                .filter { stem.isEmpty || $0.name.hasPrefix(stem) }
                .sorted { $0.name < $1.name }
                .map { prefix + $0.formatted }
        }

        return []
    }

    // MARK: - Private

    private static func isModuleLevel(_ filePath: String) -> Bool {
        let filename = URL(fileURLWithPath: filePath).lastPathComponent
        return filename.hasSuffix("Module.swift") || filename.hasSuffix(".js")
    }
}

// MARK: - Loading

/// Locates api.json from the running executable path.
/// Resolves symlinks so the production symlink in `/usr/local/bin` points back into the app bundle.
nonisolated func findAPIJSON() -> URL? {
    let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let execDir = execURL.deletingLastPathComponent()

    // App bundle: …/Contents/MacOS/hs → …/Contents/Resources/api.json
    let resources = execDir.deletingLastPathComponent().appendingPathComponent("Resources")
    let bundleCandidate = resources.appendingPathComponent("api.json")
    if FileManager.default.fileExists(atPath: bundleCandidate.path) { return bundleCandidate }

    // Development: walk up from the executable to find docs/api.json in the source tree
    var dir = execDir
    for _ in 0..<15 {
        dir = dir.deletingLastPathComponent()
        let candidate = dir.appendingPathComponent("docs/api.json")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return nil
}

/// Loads and parses api.json off the main actor.
/// Intended for use with `async let` so it runs concurrently with the IPC connection.
@concurrent
nonisolated func loadCompletions() async -> CompletionTable? {
    guard let url = findAPIJSON() else { return nil }
    return CompletionTable(url: url)
}
