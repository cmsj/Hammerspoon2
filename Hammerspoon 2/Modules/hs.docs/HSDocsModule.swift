//
//  HSDocsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import HammerspoonSDK

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
    /// Open the Hammerspoon 2 API documentation in a window
    ///
    /// If the documentation window is already open, it is brought to the front (and restored if
    /// minimized) instead of opening another one. It navigates to the requested page if
    /// `moduleName` is given, or if it isn't currently showing the requested docs (JS or TS);
    /// otherwise it stays on whatever page it is showing.
    ///
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
    var moduleName = "hs.docs"
    let engineID: UUID

    private var cachedModules: [[String: Any]]?

    // The window opened by show(), so another show() while it's open raises it instead of
    // opening a second one. Weak: a shown window is kept alive by hs.ui, and a closed one is
    // garbage.
    private(set) weak var docsWindow: HSUIWindow?
    private(set) weak var docsWebView: UIWebView?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): API documentation viewer>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    func shutdown() {
        cachedModules = nil
        docsWindow = nil
        docsWebView = nil
    }

    // MARK: - Public API

    @objc func show(_ moduleName: String?, _ showTS: Bool) {
        guard let context = JSContext.current() else { return }
        let basePath = showTS ? tsDocsPath() : jsDocsPath()
        guard let basePath = basePath else {
            AKWarning("hs.docs.show: documentation not bundled")
            return
        }
        let requestedModule = moduleName.flatMap { ["undefined", "null", ""].contains($0) ? nil : $0 }
        let htmlFile = requestedModule.map { "\($0).html" } ?? "index.html"
        // Percent-encode the filename to handle any special characters in moduleName,
        // then pass via a JS variable to avoid string-literal injection entirely.
        let encodedFile = htmlFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "index.html"
        let fileURL = "file://\(basePath)/\(encodedFile)"

        if let window = docsWindow, window.isShown, let webView = docsWebView {
            // Ask the web view what it's showing rather than remembering what we loaded: the
            // user may have navigated since, with its toolbar or links.
            let currentPath = webView.url.flatMap { URL(string: $0) }?.path
            let showingRequestedDocs = currentPath?.hasPrefix(basePath + "/") ?? false
            if requestedModule != nil || !showingRequestedDocs {
                _ = webView.loadURL(fileURL)
            }
            _ = window.show()
            return
        }

        context.setObject(fileURL, forKeyedSubscript: "__hsDsUrl" as NSString)
        let created = context.evaluateScript("""
            (function(url) {
                const wv = hs.ui.webview()
                    .toolbar(["back", "forward", "reload", "url"])
                    .loadURL(url);
                const win = hs.ui.window({x: 100, y: 100, w: 1200, h: 800})
                    .titled(true).closable(true).allowResize(true)
                    .level("normal").webview(wv).show();
                return [win, wv];
            })(__hsDsUrl);
        """)
        context.setObject(NSNull(), forKeyedSubscript: "__hsDsUrl" as NSString)
        if let exception = context.exception {
            AKError("hs.docs.show: JS exception: \(exception)")
            return
        }
        docsWindow = created?.atIndex(0).toObject() as? HSUIWindow
        docsWebView = created?.atIndex(1).toObject() as? UIWebView
    }

    @objc func get(_ identifier: String) -> String? {
        guard !identifier.isEmpty, let modules = parsedModules() else { return nil }

        // api.json names modules without "hs." prefix (e.g. "camera", not "hs.camera")
        let normalized = identifier.hasPrefix("hs.") ? String(identifier.dropFirst(3)) : identifier
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        // Walk longest-prefix-first so "ui.webview.toolbar" matches module "ui.webview"
        // before falling back to module "ui" with member "webview.toolbar".
        for splitAt in stride(from: parts.count, through: 1, by: -1) {
            let modName = parts[0..<splitAt].joined(separator: ".")
            guard let mod = modules.first(where: { $0["name"] as? String == modName }) else { continue }
            if splitAt == parts.count { return formatModule(mod) }
            return formatMember(parts[splitAt...].joined(separator: "."), in: mod, moduleName: modName)
        }
        return nil
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
