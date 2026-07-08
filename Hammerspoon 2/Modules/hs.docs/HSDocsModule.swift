//
//  HSDocsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - JavaScript API Protocol

/// # hs.docs
///
/// **Offline API documentation browser**
///
/// Browse and query the Hammerspoon 2 API documentation from within the app.
///
/// `hs.docs.show()` opens an `hs.ui.webview` window with the JS or TypeScript docs.
/// `hs.docs.get()` returns formatted plain-text documentation from the bundled `api.json`.
@objc protocol HSDocsModuleAPI: JSExport {
    /// Open the Hammerspoon 2 API documentation in a new window
    /// - Parameter moduleName?: Optional module to navigate to directly (e.g. `"hs.application"`). Omit to open the index page.
    /// - Parameter showTS?: Pass `true` to show TypeScript docs instead of JS docs
    /// - Example:
    /// ```js
    /// hs.docs.show()
    /// hs.docs.show("hs.application")
    /// hs.docs.show("hs.application", true)
    /// ```
    @objc func show(_ moduleName: String?, _ showTS: Bool)

    /// Return documentation for a module, method, or property
    /// - Parameter identifier: Dot-separated path such as `"hs.camera"` or `"hs.camera.all"`
    /// - Returns: A plain-text summary of the item, or `null` if not found
    /// - Example:
    /// ```js
    /// console.log(hs.docs.get("hs.application"))
    /// console.log(hs.docs.get("hs.camera.all"))
    /// ```
    @objc func get(_ identifier: String) -> String?

    /// Return the filesystem path to the bundled JS documentation directory
    /// - Returns: Absolute path to the JS docs folder inside the app bundle, or `null`
    /// - Example:
    /// ```js
    /// console.log(hs.docs.jsDocsPath())
    /// ```
    @objc func jsDocsPath() -> String?

    /// Return the filesystem path to the bundled TypeScript documentation directory
    /// - Returns: Absolute path to the TS docs folder inside the app bundle, or `null`
    /// - Example:
    /// ```js
    /// console.log(hs.docs.tsDocsPath())
    /// ```
    @objc func tsDocsPath() -> String?

    /// Return the contents of the bundled `api.json` file
    /// - Returns: JSON string containing the full API specification, or `null`
    /// - Example:
    /// ```js
    /// const data = JSON.parse(hs.docs.apiJSON())
    /// console.log(data.modules.length)
    /// ```
    @objc func apiJSON() -> String?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSDocsModule: NSObject, HSModuleAPI, HSDocsModuleAPI {
    var name = "hs.docs"
    let engineID: UUID

    private var cachedModules: [[String: Any]]? = nil

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    func shutdown() {
        cachedModules = nil
    }

    // MARK: - Public API

    @objc func show(_ moduleName: String?, _ showTS: Bool) {
        guard let context = JSContext.current() else { return }
        let basePath = showTS ? tsDocsPath() : jsDocsPath()
        guard let basePath = basePath else {
            AKWarning("hs.docs.show: documentation not bundled")
            return
        }
        let htmlFile = moduleName.flatMap { ["undefined", "null", ""].contains($0) ? nil : "\($0).html" } ?? "index.html"
        // Percent-encode the filename to handle any special characters in moduleName,
        // then pass via a JS variable to avoid string-literal injection entirely.
        let encodedFile = htmlFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "index.html"
        let fileURL = "file://\(basePath)/\(encodedFile)"
        context.setObject(fileURL, forKeyedSubscript: "__hsDsUrl" as NSString)
        context.evaluateScript("""
            (function(url) {
                const wv = hs.ui.webview()
                    .toolbar(["back", "forward", "reload", "url"])
                    .loadURL(url);
                hs.ui.window({x: 100, y: 100, w: 1200, h: 800})
                    .titled(true).closable(true).allowResize(true)
                    .level("normal").webview(wv).show();
            })(__hsDsUrl);
        """)
        context.setObject(NSNull(), forKeyedSubscript: "__hsDsUrl" as NSString)
    }

    @objc func get(_ identifier: String) -> String? {
        guard !identifier.isEmpty, let modules = parsedModules() else { return nil }

        // api.json names modules without "hs." prefix (e.g. "camera", not "hs.camera")
        let normalized = identifier.hasPrefix("hs.") ? String(identifier.dropFirst(3)) : identifier

        if let dotIdx = normalized.firstIndex(of: ".") {
            let moduleName = String(normalized[normalized.startIndex..<dotIdx])
            let memberName = String(normalized[normalized.index(after: dotIdx)...])
            guard let mod = modules.first(where: { $0["name"] as? String == moduleName }) else { return nil }
            return formatMember(memberName, in: mod, moduleName: moduleName)
        } else {
            guard let mod = modules.first(where: { $0["name"] as? String == normalized }) else { return nil }
            return formatModule(mod)
        }
    }

    @objc func jsDocsPath() -> String? {
        Bundle.main.resourcePath.map { "\($0)/js/html" }
    }

    @objc func tsDocsPath() -> String? {
        Bundle.main.resourcePath.map { "\($0)/ts/html" }
    }

    @objc func apiJSON() -> String? {
        guard let url = Bundle.main.url(forResource: "api", withExtension: "json") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Private helpers

    private func parsedModules() -> [[String: Any]]? {
        if let cached = cachedModules { return cached }
        guard let jsonString = apiJSON(),
              let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modules = root["modules"] as? [[String: Any]] else { return nil }
        cachedModules = modules
        return cachedModules
    }

    private func formatModule(_ mod: [String: Any]) -> String {
        let modName = mod["name"] as? String ?? ""
        var lines = ["# hs.\(modName)\n"]
        let methods = mod["methods"] as? [[String: Any]] ?? []
        let props = mod["properties"] as? [[String: Any]] ?? []
        for item in methods + props {
            if let n = item["name"] as? String { lines.append("## \(n)") }
            if let d = item["description"] as? String { lines.append(d) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func formatMember(_ memberName: String, in mod: [String: Any], moduleName: String) -> String? {
        let methods = mod["methods"] as? [[String: Any]] ?? []
        let props = mod["properties"] as? [[String: Any]] ?? []
        guard let item = (methods + props).first(where: { $0["name"] as? String == memberName }) else { return nil }

        var lines = ["## hs.\(moduleName).\(memberName)\n"]
        if let d = item["description"] as? String { lines.append(d); lines.append("") }
        for p in item["params"] as? [[String: Any]] ?? [] {
            let pName = p["name"] as? String ?? ""
            let pDesc = p["description"] as? String ?? ""
            lines.append("- Parameter \(pName): \(pDesc)")
        }
        if let ret = item["returns"] as? [String: Any], let rDesc = ret["description"] as? String {
            lines.append("- Returns: \(rDesc)")
        }
        for ex in item["examples"] as? [String] ?? [] {
            lines.append("\n```js\n\(ex)\n```")
        }
        return lines.joined(separator: "\n")
    }
}
