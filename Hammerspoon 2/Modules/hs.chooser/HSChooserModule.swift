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
/// chooser.setStaticChoices([
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
/// chooser.setChoicesCallback((query) => {
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
/// chooser.setChoicesCallback(() => cachedResults)
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
    /// c.setStaticChoices([{text: "Hello"}]).onSelect = item => console.log(item.text)
    /// c.show()
    /// ```
    @objc func create() -> HSChooser
}

@_documentation(visibility: private)
@MainActor
@objc class HSChooserModule: NSObject, HSModuleAPI, HSChooserModuleAPI {
    var name: String = "hs.chooser"
    let engineID: UUID
    private var choosers = HSWeakObjectSet<HSChooser>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    func shutdown() {
        for chooser in choosers.allObjects {
            chooser.destroy()
        }
        choosers.removeAllObjects()
        AKTrace("\(name) shutdown: \(engineID)")
    }

    @objc func create() -> HSChooser {
        let chooser = HSChooser()
        choosers.add(chooser)
        AKTrace("hs.chooser.create(): \(chooser.identifier)")
        return chooser
    }
}
