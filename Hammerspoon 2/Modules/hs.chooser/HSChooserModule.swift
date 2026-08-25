//
//  HSChooserModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// # hs.chooser
///
/// **A Spotlight-style chooser for presenting options to the user**
///
/// `hs.chooser` lets you show a floating search panel that users can type into to filter and
/// select from a list of items. It's ideal for launchers, emoji pickers, command palettes, and
/// any interface where you want fast, keyboard-driven selection.
///
/// ## Quick Start
///
/// ```javascript
/// const chooser = hs.chooser.create()
///
/// chooser.setChoices([
///     { text: "Open Safari", subText: "Web browser", action: "safari" },
///     { text: "Open Terminal", subText: "Command line", action: "terminal" }
/// ])
///
/// chooser.onSelect = (item) => {
///     if (item) console.log("Selected: " + item.text + " (" + item.action + ")")
/// }
///
/// chooser.show()
/// ```
///
/// ## Dynamic Choices
///
/// For search-as-you-type filtering powered by your own data:
///
/// ```javascript
/// const allApps = hs.application.runningApplications()
///
/// chooser.setChoices((query) => {
///     const q = query.toLowerCase()
///     return allApps
///         .filter(a => a.title.toLowerCase().includes(q))
///         .map(a => ({ text: a.title, subText: a.bundleID }))
/// })
/// ```
///
/// ## Async Choices (with debounce)
///
/// For results fetched from an external source:
///
/// ```javascript
/// let debounceTimer = null
/// let cachedResults = []
///
/// chooser.setChoices(() => cachedResults)
///
/// chooser.onQueryChange = (query) => {
///     if (debounceTimer) debounceTimer.invalidate()
///     debounceTimer = hs.timer.doAfter(0.05, () => {
///         fetchFromAPI(query).then(results => {
///             cachedResults = results
///             chooser.refreshChoices()
///         })
///     })
/// }
/// ```
@objc protocol HSChooserModuleAPI: JSExport {

    /// Create a new chooser.
    /// - Returns: A new `HSChooser` object ready for configuration
    /// - Example:
    /// ```js
    /// const c = hs.chooser.create()
    /// c.setChoices([{text: "Hello"}]).onSelect = item => console.log(item.text)
    /// c.show()
    /// ```
    @objc func create() -> HSChooser
}

@_documentation(visibility: private)
@MainActor
@objc class HSChooserModule: NSObject, HSModuleAPI, HSChooserModuleAPI {
    var moduleName: String = "hs.chooser"
    let engineID: UUID
    private var choosers = HSWeakObjectSet<HSChooser>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(moduleName): \(engineID)")
    }

    isolated deinit {
        AKDebug("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = choosers.allObjects.count
        return "<\(moduleName): \(n) active chooser\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    func shutdown() {
        for chooser in choosers.allObjects {
            chooser.destroy()
        }
        choosers.removeAllObjects()
        AKDebug("\(moduleName) shutdown: \(engineID)")
    }

    @objc func create() -> HSChooser {
        let chooser = HSChooser()
        choosers.add(chooser)
        AKDebug("hs.chooser.create(): \(chooser.identifier)")
        return chooser
    }
}
