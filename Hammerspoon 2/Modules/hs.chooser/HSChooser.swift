//
//  HSChooser.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI

/// A keyboard-driven floating chooser panel.
///
/// Create via `hs.chooser.create()`. Configure choices, set callbacks, then call `.show()`.
///
/// ## Choice format
///
/// Each choice is a plain object with required `text` and optional `subText`, `image`, `valid`,
/// and `contextMenu` fields. All other fields are passed through to the `onSelect` callback unchanged.
///
/// The `contextMenu` array defines per-row right-click menu entries. Each entry is either
/// `{ title: "...", action: (item) => {} }` for a button or `{ type: "divider" }` for a separator:
///
/// ```javascript
/// {
///   text: "Open Safari", subText: "com.apple.Safari",
///   image: HSImage.fromAppBundle("com.apple.Safari"), valid: true, myData: 42,
///   contextMenu: [
///     { title: "Open", action: () => hs.urlevent.openURL("https://apple.com") },
///     { type: "divider" },
///     { title: "Copy bundle ID", action: () => hs.pasteboard.writeString("com.apple.Safari") }
///   ]
/// }
/// ```
///
/// ## Keyboard shortcuts
///
/// - **Return** — confirm selection
/// - **Escape** — dismiss (calls `onSelect` with `null`)
/// - **↑ / ↓** — move through results
@objc protocol HSChooserAPI: HSTypeAPI, JSExport {

    /// Read-only type identifier.
    @objc var typeName: String { get }

    /// Stable UUID string for this chooser instance.
    @objc var identifier: String { get }

    // MARK: Search field

    /// The current text in the search field. Setting this from JS updates the display but
    /// does not invoke the `onQueryChange` callback.
    /// - Example:
    /// ```js
    /// chooser.query = "he"
    /// ```
    @objc var query: String { get set }

    /// Placeholder text shown in the empty search field (default: `"Search..."`).
    /// - Example:
    /// ```js
    /// chooser.placeholder = "Type to search..."
    /// ```
    @objc var placeholder: String { get set }

    /// Whether searches match against `subText` in addition to `text` (default: `false`).
    /// Only applies when a static choices array is provided.
    /// - Example:
    /// ```js
    /// chooser.searchSubText = true
    /// ```
    @objc var searchSubText: Bool { get set }

    /// When `true` and the query is non-empty but there are no matching choices, `onSelect`
    /// is called with `{ text: <query> }` instead of `null` (default: `false`).
    /// - Example:
    /// ```js
    /// chooser.enableDefaultForQuery = true
    /// ```
    @objc var enableDefaultForQuery: Bool { get set }

    // MARK: Choices

    /// Set choices from a static array of choice objects.
    ///
    /// The chooser automatically filters the array as the user types.
    ///
    /// - Parameter choices: An array of choice objects, each with `text`, optional `subText`, `image`, `valid`, and custom fields
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.setStaticChoices([{text: "Foo"}, {text: "Bar"}])
    /// ```
    @objc @discardableResult func setStaticChoices(_ choices: [Any]) -> HSChooser

    /// Set choices from a function called with the current query on each `refreshChoices()` and on show.
    ///
    /// The function is responsible for filtering; the chooser displays all items it returns.
    ///
    /// - Parameter fn: {(query: string) => object[]} A function called with the current query string that returns choice objects
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.setChoicesCallback(q => items.filter(i => i.text.toLowerCase().includes(q.toLowerCase())))
    /// ```
    @objc @discardableResult func setChoicesCallback(_ fn: JSFunction) -> HSChooser

    /// Re-apply filtering (static choices) or re-invoke the choices function (dynamic).
    /// Call after updating an external data source in an async `onQueryChange` handler.
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.refreshChoices()
    /// ```
    @objc @discardableResult func refreshChoices() -> HSChooser

    // MARK: Selection

    /// The zero-based index of the currently highlighted row (-1 when empty).
    /// - Example:
    /// ```js
    /// chooser.selectedRow = 0
    /// ```
    @objc var selectedRow: Int { get set }

    // MARK: Appearance

    /// Width of the chooser as a fraction of the screen width (default: `0.5` = 50 %).
    /// - Example:
    /// ```js
    /// chooser.width = 0.4
    /// ```
    @objc var width: Double { get set }

    /// Maximum number of rows visible at once without scrolling (default: `10`).
    /// - Example:
    /// ```js
    /// chooser.visibleRows = 8
    /// ```
    @objc var visibleRows: Int { get set }

    // MARK: Lifecycle

    /// Show the chooser.
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.show()
    /// ```
    @objc @discardableResult func show() -> HSChooser

    /// Hide the chooser without making a selection. Restores focus to the previously active window.
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.hide()
    /// ```
    @objc @discardableResult func hide() -> HSChooser

    /// `true` if the chooser panel is currently on screen.
    /// - Example:
    /// ```js
    /// if (!chooser.isVisible) chooser.show()
    /// ```
    @objc var isVisible: Bool { get }

    // MARK: Callbacks

    /// Called when the user confirms a selection.
    ///
    /// The argument is the chosen row object (the original dict you passed to `setChoices`,
    /// with `text`, `subText`, `image`, `valid`, and any custom fields intact).
    /// The argument is `null` when dismissed (Escape).
    ///
    /// - Example:
    /// ```js
    /// chooser.onSelect = (item) => {
    ///     if (item) console.log("Selected: " + item.text)
    ///     else console.log("Dismissed")
    /// }
    /// ```
    @objc var onSelect: JSFunction? { get set }

    /// Called on every keystroke with the new query string.
    ///
    /// Use this to debounce expensive searches or trigger async data fetching.
    ///
    /// - Example:
    /// ```js
    /// chooser.onQueryChange = (q) => {
    ///     hs.timer.doAfter(0.05, () => { fetchResults(q).then(r => { cache = r; chooser.refreshChoices() }) })
    /// }
    /// ```
    @objc var onQueryChange: JSFunction? { get set }

    /// Called after the panel becomes visible.
    /// - Example:
    /// ```js
    /// chooser.onShow = () => console.log("Chooser appeared")
    /// ```
    @objc var onShow: JSFunction? { get set }

    /// Called after the panel is hidden (for any reason: selection, Escape, or `hide()`).
    /// - Example:
    /// ```js
    /// chooser.onHide = () => console.log("Chooser hidden")
    /// ```
    @objc var onHide: JSFunction? { get set }

    /// Called when the user activates a row whose `valid` field is `false`.
    /// The chooser stays open; the argument is the row dict (same shape as `onSelect`).
    /// If unset, activating an invalid row is silently ignored.
    /// - Example:
    /// ```js
    /// chooser.onInvalid = (item) => console.log("Tapped invalid row: " + item.text)
    /// ```
    @objc var onInvalid: JSFunction? { get set }

    /// Programmatically confirm the selection at a specific row index.
    ///
    /// Fires `onSelect` (or `onInvalid` for rows with `valid: false`) and hides the chooser.
    ///
    /// - Parameter index: Zero-based row index to select
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.selectRow(2)
    /// ```
    @objc @discardableResult func selectRow(_ index: Int) -> HSChooser

    /// Programmatically confirm the currently highlighted row.
    ///
    /// Fires `onSelect` (or `onInvalid` for rows with `valid: false`) and hides the chooser.
    ///
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.selectCurrentRow()
    /// ```
    @objc @discardableResult func selectCurrentRow() -> HSChooser

    /// Returns the dict for a specific row by index.
    /// Returns `null` if the index is out of range or no choices are set.
    ///
    /// - Parameter index: Zero-based row index
    /// - Returns: The row dict (`{ text, subText?, image?, valid, ...extras }`) or `null`.
    /// - Example:
    /// ```js
    /// const item = chooser.rowContents(2)
    /// ```
    @objc func rowContents(_ index: Int) -> NSDictionary?

    /// Returns the dict for the currently highlighted row.
    /// Returns `null` if no choices are set or the chooser is empty.
    ///
    /// - Returns: The row dict (`{ text, subText?, image?, valid, ...extras }`) or `null`.
    /// - Example:
    /// ```js
    /// const item = chooser.currentRowContents()
    /// ```
    @objc func currentRowContents() -> NSDictionary?
}

// MARK: -

@_documentation(visibility: private)
@MainActor
@objc class HSChooser: NSObject, HSChooserAPI {
    @objc var typeName = "HSChooser"
    @objc let identifier = UUID().uuidString

    private let viewModel = ChooserViewModel()
    private var window: ChooserPanel?

    private var allChoices: [ChooserItem] = []
    private var isStaticChoices = true
    private var _choicesFunction: JSCallback?

    @objc var searchSubText = false
    @objc var enableDefaultForQuery = false
    @objc var width: Double = 0.5
    @objc var visibleRows: Int {
        get { viewModel.visibleRows }
        set { viewModel.visibleRows = newValue }
    }

    private var _onSelect: JSCallback?
    private var _onQueryChange: JSCallback?
    private var _onShow: JSCallback?
    private var _onHide: JSCallback?
    private var _onInvalid: JSCallback?
    private var contextMenuCallbacks: [JSCallback] = []

    private var previouslyActiveWindow: NSWindow?
    private var keyEventMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    // MARK: - query

    @objc var query: String {
        get { _storedQuery }
        set {
            _storedQuery = newValue
            viewModel.filteredChoices = filteredChoices(for: newValue)
            viewModel.selectedIndex = 0

            // Programmatic set — update height but do NOT fire onQueryChange.
            viewModel.onContentSizeChange?(viewModel.expectedHeight())
        }
    }

    private var _storedQuery: String = ""

    @objc var placeholder: String {
        get { viewModel.placeholder }
        set { viewModel.placeholder = newValue }
    }

    @objc var isVisible: Bool { window?.isVisible ?? false }

    @objc var selectedRow: Int {
        get { viewModel.selectedIndex }
        set {
            let maxIndex = viewModel.filteredChoices.isEmpty ? 0 : viewModel.filteredChoices.count - 1
            viewModel.selectedIndex = min(max(0, newValue), maxIndex)
        }
    }

    // MARK: - Callbacks (JSCallback-backed properties)

    @objc var onSelect: JSFunction? {
        get { _onSelect?.value }
        set {
            _onSelect?.detach(from: self)
            _onSelect = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var onQueryChange: JSFunction? {
        get { _onQueryChange?.value }
        set {
            _onQueryChange?.detach(from: self)
            _onQueryChange = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var onShow: JSFunction? {
        get { _onShow?.value }
        set {
            _onShow?.detach(from: self)
            _onShow = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var onHide: JSFunction? {
        get { _onHide?.value }
        set {
            _onHide?.detach(from: self)
            _onHide = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var onInvalid: JSFunction? {
        get { _onInvalid?.value }
        set {
            _onInvalid?.detach(from: self)
            _onInvalid = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    // MARK: - Choices

    @objc @discardableResult func setStaticChoices(_ choices: [Any]) -> HSChooser {
        isStaticChoices = true
        _choicesFunction?.detach(from: self)
        _choicesFunction = nil
        clearContextMenuCallbacks()
        allChoices = parseChoiceArray(from: choices)
        viewModel.filteredChoices = filteredChoices(for: _storedQuery)
        viewModel.selectedIndex = 0
        viewModel.onContentSizeChange?(viewModel.expectedHeight())
        return self
    }

    @objc @discardableResult func setChoicesCallback(_ fn: JSFunction) -> HSChooser {
        isStaticChoices = false
        _choicesFunction?.detach(from: self)
        _choicesFunction = JSCallback(value: fn, owner: self)
        callChoicesFunction()
        viewModel.onContentSizeChange?(viewModel.expectedHeight())
        return self
    }

    @objc @discardableResult func refreshChoices() -> HSChooser {
        if isStaticChoices {
            viewModel.filteredChoices = filteredChoices(for: _storedQuery)
        } else {
            callChoicesFunction()
        }
        viewModel.onContentSizeChange?(viewModel.expectedHeight())
        return self
    }

    // MARK: - Lifecycle

    @objc @discardableResult func show() -> HSChooser {
        previouslyActiveWindow = NSApp.keyWindow

        if window == nil {
            createWindow()
        }

        if !isStaticChoices { callChoicesFunction() }

        // Size the window to the correct height before making it visible so there
        // is no flash at the wrong size. callChoicesFunction / setChoices already
        // called onContentSizeChange, but that only resizes when the panel is live;
        // here we set it imperatively one more time to be sure.
        window?.setHeight(viewModel.expectedHeight())

        viewModel.isVisible = true
        startKeyMonitor()
        startResignKeyObserver()
        window?.makeKeyAndOrderFront(nil)
        _ = _onShow?.call(withArguments: [])
        AKTrace("hs.chooser.show(): \(identifier)")
        return self
    }

    @objc @discardableResult func hide() -> HSChooser {
        guard let w = window, w.isVisible else { return self }
        viewModel.isVisible = false
        stopKeyMonitor()
        stopResignKeyObserver()  // must be before orderOut — orderOut resigns key, which would re-fire the observer
        w.orderOut(nil)

        if let prev = previouslyActiveWindow, prev.isVisible {
            prev.makeKeyAndOrderFront(nil)
        }
        previouslyActiveWindow = nil

        _ = _onHide?.call(withArguments: [])
        AKTrace("hs.chooser.hide(): \(identifier)")
        return self
    }

    @objc @discardableResult func selectRow(_ index: Int) -> HSChooser {
        let safeIndex = (index >= 0 && index < viewModel.filteredChoices.count) ? index : nil
        handleSelection(safeIndex)
        return self
    }

    @objc @discardableResult func selectCurrentRow() -> HSChooser {
        handleSelection(viewModel.selectedIndex)
        return self
    }

    @objc func rowContents(_ index: Int) -> NSDictionary? {
        guard index >= 0, index < viewModel.filteredChoices.count else { return nil }
        return buildReturnDict(for: viewModel.filteredChoices[index])
    }

    @objc func currentRowContents() -> NSDictionary? {
        let index = viewModel.selectedIndex
        guard index >= 0, index < viewModel.filteredChoices.count else { return nil }
        return buildReturnDict(for: viewModel.filteredChoices[index])
    }

    func destroy() {
        stopKeyMonitor()
        stopResignKeyObserver()
        _ = hide()
        window?.close()
        window = nil

        _choicesFunction?.detach(from: self)
        _choicesFunction = nil
        _onSelect?.detach(from: self)
        _onSelect = nil
        _onQueryChange?.detach(from: self)
        _onQueryChange = nil
        _onShow?.detach(from: self)
        _onShow = nil
        _onHide?.detach(from: self)
        _onHide = nil
        _onInvalid?.detach(from: self)
        _onInvalid = nil
        clearContextMenuCallbacks()

        allChoices = []
        viewModel.filteredChoices = []
        viewModel.onUserQueryChange = nil
        viewModel.onContentSizeChange = nil
        AKTrace("hs.chooser.destroy(): \(identifier)")
    }

    isolated deinit {
        destroy()
        AKTrace("deinit of HSChooser(\(identifier))")
    }

    // MARK: - Key event monitor

    private func startKeyMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent monitors fire on the main thread. Extract the key code (a Sendable
            // UInt16) before entering MainActor.assumeIsolated so we never try to pass
            // the non-Sendable NSEvent across the isolation boundary.
            let keyCode = event.keyCode
            let consumed = MainActor.assumeIsolated {
                self?.interceptKeyCode(keyCode) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func stopKeyMonitor() {
        guard let monitor = keyEventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        keyEventMonitor = nil
    }

    private func startResignKeyObserver() {
        // Remove any stale observer before adding a fresh one (guards against double-show).
        stopResignKeyObserver()
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSelection(nil) }
        }
    }

    private func stopResignKeyObserver() {
        guard let obs = resignKeyObserver else { return }
        NotificationCenter.default.removeObserver(obs)
        resignKeyObserver = nil
    }

    private func interceptKeyCode(_ keyCode: UInt16) -> Bool {
        // Only intercept while our panel is the key window.
        guard let panel = window, panel.isKeyWindow else { return false }

        switch keyCode {
        case 125: // kVK_DownArrow
            if viewModel.selectedIndex < viewModel.filteredChoices.count - 1 {
                viewModel.selectedIndex += 1
            }
            return true
        case 126: // kVK_UpArrow
            if viewModel.selectedIndex > 0 {
                viewModel.selectedIndex -= 1
            }
            return true
        case 53: // kVK_Escape
            handleSelection(nil)
            return true
        case 36, 76: // kVK_Return, kVK_ANSI_KeypadEnter
            handleSelection(viewModel.filteredChoices.isEmpty ? nil : viewModel.selectedIndex)
            return true
        default:
            return false
        }
    }

    // MARK: - Private

    private func createWindow() {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let windowWidth = CGFloat(width) * screenWidth
        let screen = NSScreen.main

        viewModel.onContentSizeChange = { [weak self] height in
            self?.window?.setHeight(height)
        }

        viewModel.onUserQueryChange = { [weak self] newQuery in
            guard let self else { return }
            self._storedQuery = newQuery
            self.viewModel.selectedIndex = 0
            if self.isStaticChoices {
                self.viewModel.filteredChoices = self.filteredChoices(for: newQuery)
                self.viewModel.onContentSizeChange?(self.viewModel.expectedHeight())
            } else {
                // callChoicesFunction updates filteredChoices and calls onContentSizeChange.
                self.callChoicesFunction()
            }
            _ = self._onQueryChange?.call(withArguments: [newQuery])
        }

        let queryBinding = Binding<String>(
            get: { [weak self] in self?._storedQuery ?? "" },
            set: { [weak self] newValue in
                guard let self else { return }
                self._storedQuery = newValue
                self.viewModel.onUserQueryChange?(newValue)
            }
        )

        window = ChooserPanel(
            screen: screen,
            width: windowWidth,
            viewModel: viewModel,
            queryBinding: queryBinding,
            onSelect: { [weak self] index in
                self?.handleSelection(index)
            }
        )
    }

    private func callChoicesFunction() {
        guard let fn = _choicesFunction?.value else { return }
        let result = fn.call(withArguments: [_storedQuery])
        clearContextMenuCallbacks()
        allChoices = parseChoiceArray(fromJSValue: result)
        viewModel.filteredChoices = allChoices
        viewModel.selectedIndex = 0
        viewModel.onContentSizeChange?(viewModel.expectedHeight())
    }

    private func filteredChoices(for query: String) -> [ChooserItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allChoices }
        return allChoices.filter { item in
            item.text.lowercased().contains(q) ||
            (searchSubText && item.subText?.lowercased().contains(q) == true)
        }
    }

    private func handleSelection(_ index: Int?) {
        if let idx = index, idx >= 0, idx < viewModel.filteredChoices.count {
            let item = viewModel.filteredChoices[idx]
            if !item.isValid {
                // Invalid row — fire onInvalid, keep chooser open
                if let cbValue = _onInvalid?.value {
                    let dict = buildReturnDict(for: item)
                    _ = cbValue.call(withArguments: [dict])
                }
                return
            }
            _ = hide()
            if let cbValue = _onSelect?.value {
                let dict = buildReturnDict(for: item)
                _ = cbValue.call(withArguments: [dict])
            }
        } else if enableDefaultForQuery && !_storedQuery.isEmpty && viewModel.filteredChoices.isEmpty {
            _ = hide()
            if let cbValue = _onSelect?.value {
                let dict: NSDictionary = ["text": _storedQuery]
                _ = cbValue.call(withArguments: [dict])
            }
        } else {
            // Dismissed (Escape, focus loss, or no-match without enableDefaultForQuery)
            _ = hide()
            if let cbValue = _onSelect?.value, let context = cbValue.context {
                _ = cbValue.call(withArguments: [JSValue(nullIn: context) as Any])
            }
        }
    }

    private func buildReturnDict(for item: ChooserItem) -> NSMutableDictionary {
        let dict = NSMutableDictionary(dictionary: item.extra)
        dict["text"] = item.text
        if let subText = item.subText { dict["subText"] = subText }
        if let image = item.image { dict["image"] = HSImage(image: image) }
        dict["valid"] = item.isValid
        return dict
    }

    private func parseChoiceArray(from items: [Any]) -> [ChooserItem] {
        return items.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return parseChoice(dict, contextMenu: dict["contextMenu"] as? JSValue)
        }
    }

    private func parseChoiceArray(fromJSValue raw: JSValue?) -> [ChooserItem] {
        guard let raw, raw.isArray else { return [] }
        let basicItems = raw.toArray() ?? []
        return basicItems.indices.compactMap { i in
            guard let dict = basicItems[i] as? [String: Any] else { return nil }
            return parseChoice(dict, contextMenu: raw.objectAtIndexedSubscript(i)?.objectForKeyedSubscript("contextMenu"))
        }
    }

    private func parseChoice(_ dict: [String: Any], contextMenu: JSValue?) -> ChooserItem? {
        guard let text = dict["text"] as? String else { return nil }

        let subText = dict["subText"] as? String
        let isValid = dict["valid"] as? Bool ?? true

        var image: NSImage? = nil
        if let hsImg = dict["image"] as? HSImage {
            image = hsImg.image
        } else if let nsImg = dict["image"] as? NSImage {
            image = nsImg
        }

        let contextMenuItems = parseContextMenu(contextMenu)

        var extra = dict
        extra.removeValue(forKey: "text")
        extra.removeValue(forKey: "subText")
        extra.removeValue(forKey: "image")
        extra.removeValue(forKey: "valid")
        extra.removeValue(forKey: "contextMenu")

        return ChooserItem(id: UUID(), text: text, subText: subText, image: image, isValid: isValid, extra: extra, contextMenuItems: contextMenuItems)
    }

    private func parseContextMenu(_ value: JSValue?) -> [ChooserContextMenuEntry] {
        guard let value, value.isArray else { return [] }
        let length = Int(value.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        return (0..<length).compactMap { i -> ChooserContextMenuEntry? in
            guard let jsItem = value.objectAtIndexedSubscript(i),
                  jsItem.isObject, !jsItem.isNull, !jsItem.isUndefined else { return nil }

            if jsItem.objectForKeyedSubscript("type")?.toString() == "divider" {
                return ChooserContextMenuEntry(kind: .divider)
            }

            guard let title = jsItem.objectForKeyedSubscript("title")?.toString(), !title.isEmpty else { return nil }
            let actionVal = jsItem.objectForKeyedSubscript("action")
            guard let actionVal, actionVal.isObject, !actionVal.isNull, !actionVal.isUndefined else { return nil }

            guard let cb = JSCallback(value: actionVal, owner: self) else { return nil }
            contextMenuCallbacks.append(cb)
            return ChooserContextMenuEntry(kind: .button(title: title, action: { [weak cb] in
                _ = cb?.value?.call(withArguments: [])
            }))
        }
    }

    private func clearContextMenuCallbacks() {
        for cb in contextMenuCallbacks { cb.detach(from: self) }
        contextMenuCallbacks.removeAll()
    }
}
