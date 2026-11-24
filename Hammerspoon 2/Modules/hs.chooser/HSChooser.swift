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
/// Set `contextMenu: false` on a choice to show no context menu on its row.
///
/// ```javascript
/// {
///   text: "Open Safari", subText: "com.apple.Safari",
///   image: HSImage.fromAppBundle("com.apple.Safari"), valid: true, myData: 42
/// }
/// ```
///
/// ## Context menu
///
/// A single right-click menu, set with `contextMenu`, is shared by every row (except choices with
/// `contextMenu: false`). When the user picks one of its entries, `onContextMenuSelect` is called
/// with the row's choice and the menu entry.
///
/// ```javascript
/// chooser.contextMenu = [
///   { title: "Open", id: "open" },
///   { type: "divider" },
///   { title: "Copy bundle ID", id: "copy" }
/// ]
/// chooser.onContextMenuSelect = (choice, menuItem) => {
///   if (menuItem.id === "copy") hs.pasteboard.writeString(choice.subText)
/// }
/// ```
///
/// ## Keyboard shortcuts
///
/// - **Return** — confirm selection
/// - **Escape** — dismiss (calls `onSelect` with `null`)
/// - **↑ / ↓** — move through results
/// - **Ctrl-N / Ctrl-P** — move through results (alternative to ↑ / ↓)
/// - **Page Up / Page Down** (or **Fn-↑ / Fn-↓**) — move through results a page (`visibleRows` rows) at a time
/// - **Home / End** (or **Fn-← / Fn-→**) — jump to the first / last result
/// - **Cmd-1 ... Cmd-9, Cmd-0** — instantly select one of the first ten results
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

    /// Set the choices list. Pass a static array or a function:
    ///
    /// - **Array** — the chooser filters it automatically as the user types.
    /// - **Function** — called with the current query string on every `refreshChoices()` and
    ///   on show. The function is responsible for filtering; the chooser displays all items it returns.
    ///
    /// - Parameter choices: {Array<Record<string, any>> | ((query: string) => Array<Record<string, any>>)} An array of choice objects, or a function `(query) => [...]`
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// // Static
    /// chooser.setChoices([{text: "Foo"}, {text: "Bar"}])
    ///
    /// // Dynamic
    /// chooser.setChoices(q => items.filter(i => i.text.toLowerCase().includes(q.toLowerCase())))
    /// ```
    @objc @discardableResult func setChoices(_ choices: JSValue) -> HSChooser

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

    /// Width of the chooser as a fraction of the main screen's width (default: `0.5` = 50 %).
    ///
    /// Changing it after the chooser has been shown resizes it about its centre. Setting `frame`
    /// also updates it. Values that aren't finite, or aren't positive, are ignored.
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

    /// The chooser panel's frame on screen, in the same coordinates as `hs.window` and `hs.screen`
    /// (y = 0 at the top of the primary screen, increasing downwards).
    ///
    /// Before the chooser is first shown, this is where it will appear: centred horizontally on the
    /// main screen, a quarter of the way down it. It then stays wherever it was last placed.
    ///
    /// Setting `frame` moves the chooser so its top left corner is at `x`, `y`, and makes it `w`
    /// points wide, updating `width` to match. `h` is ignored, since the chooser's height always
    /// follows its rows (see `visibleRows`). Setting a frame whose values aren't finite, or whose
    /// width isn't positive, does nothing.
    /// - Example:
    /// ```js
    /// const f = chooser.frame
    /// console.log(`The chooser's top left corner is at ${f.x}, ${f.y}`)
    /// chooser.frame = new HSRect(100, 100, 600, 0)
    /// ```
    @objc var frame: HSRect? { get set }

    /// Background color of the chooser panel. When `nil` (the default), the panel uses
    /// the system's translucent glass/material effect.
    ///
    /// If you set this to a solid or near-opaque color, also set `textColor`, `subTextColor`,
    /// and `placeholderColor` to ensure readable contrast — they are not adjusted automatically.
    /// - Example:
    /// ```js
    /// chooser.backgroundColor = HSColor.hex("#2E3440") // Nord "polar night"
    /// ```
    @objc var backgroundColor: HSColor? { get set }

    /// Corner radius of the chooser panel, in points (default: `14`).
    /// - Example:
    /// ```js
    /// chooser.cornerRadius = 20
    /// ```
    @objc var cornerRadius: Double { get set }

    /// Border color drawn around the chooser panel. When `nil` (the default), no border is drawn.
    /// - Example:
    /// ```js
    /// chooser.borderColor = HSColor.hex("#88C0D0")
    /// ```
    @objc var borderColor: HSColor? { get set }

    /// Width of the border drawn around the chooser panel, in points (default: `1`).
    /// Has no effect unless `borderColor` is also set.
    /// - Example:
    /// ```js
    /// chooser.borderWidth = 2
    /// ```
    @objc var borderWidth: Double { get set }

    /// Color of each result row's main text. When `nil` (the default), the system's
    /// primary label color is used.
    /// - Example:
    /// ```js
    /// chooser.textColor = HSColor.hex("#ECEFF4")
    /// ```
    @objc var textColor: HSColor? { get set }

    /// Color of each result row's subtext. When `nil` (the default), the system's
    /// secondary label color is used.
    /// - Example:
    /// ```js
    /// chooser.subTextColor = HSColor.hex("#D8DEE9")
    /// ```
    @objc var subTextColor: HSColor? { get set }

    /// Color of the text the user types into the search field. When `nil` (the default),
    /// the system's primary label color is used.
    /// - Example:
    /// ```js
    /// chooser.queryColor = HSColor.hex("#ECEFF4")
    /// ```
    @objc var queryColor: HSColor? { get set }

    /// Color of the placeholder text (and search icon) shown in an empty search field.
    /// When `nil` (the default), the system's secondary label color is used.
    /// - Example:
    /// ```js
    /// chooser.placeholderColor = HSColor.hex("#4C566A")
    /// ```
    @objc var placeholderColor: HSColor? { get set }

    /// Background tint of the highlighted row. When `nil` (the default), a translucent
    /// tint of the system accent color is used.
    /// - Example:
    /// ```js
    /// chooser.selectionColor = HSColor.rgb(0.37, 0.51, 0.68, 0.35) // Nord "frost" blue, 35% opacity
    /// ```
    @objc var selectionColor: HSColor? { get set }

    /// Font size of each result row's main text, in points (default: `14`). Changing this
    /// also rescales the ⌘-digit shortcut hint shown on the first ten rows, and changes the
    /// row height (and therefore the panel height) to fit. Must be a positive, finite number;
    /// invalid values are ignored (with a warning logged).
    /// - Example:
    /// ```js
    /// chooser.textSize = 18
    /// ```
    @objc var textSize: Double { get set }

    /// Font size of each result row's subtext, in points (default: `12`). Changing this
    /// also changes the row height (and therefore the panel height) to fit. Must be a
    /// positive, finite number; invalid values are ignored (with a warning logged).
    /// - Example:
    /// ```js
    /// chooser.subTextSize = 14
    /// ```
    @objc var subTextSize: Double { get set }

    /// Font size of the search field's typed text and placeholder, in points (default: `20`).
    /// Changing this also rescales the search icon, and changes the search bar height
    /// (and therefore the panel height) to fit. Must be a positive, finite number; invalid
    /// values are ignored (with a warning logged).
    /// - Example:
    /// ```js
    /// chooser.querySize = 24
    /// ```
    @objc var querySize: Double { get set }

    // MARK: Lifecycle

    /// Show the chooser.
    /// - Note: A shown chooser, and its callbacks, stay alive until it's hidden, even if you don't keep a reference to it
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

    /// The window ID of the chooser panel while it's on screen, or `null` while it's hidden.
    ///
    /// The ID is the same one `hs.window` uses, so it can be passed to any function that takes a
    /// window ID, such as `hs.window.snapshotForID()`.
    /// - Example:
    /// ```js
    /// chooser.show()
    /// const id = chooser.windowID
    /// hs.window.snapshotForID(id).then(img => console.log("Captured " + img.size.w + "pt wide"))
    /// ```
    @objc var windowID: NSNumber? { get }

    // MARK: Callbacks

    /// {((item: Record<string, any> | null) => void) | null} Called when the user confirms a selection, or null to remove the handler.
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

    /// {((query: string) => void) | null} Called on every keystroke with the new query string, or null to remove the handler.
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

    /// {((row: number, item: Record<string, any> | null) => void) | null} Called when the selected row changes while the chooser is visible, or null to remove the handler.
    ///
    /// Use this to show something that depends on the selected row, such as a preview, and keep it
    /// up to date as the user moves through the rows.
    ///
    /// The arguments are the new `selectedRow` and the row object (same shape as `onSelect`), or
    /// `null` for the item when no rows match the query. It is called once when the chooser is
    /// shown, then whenever the selection moves to a different row, or the row it is on changes
    /// to a different choice: arrow keys, Page Up/Down, Home/End, a click, a new query, new
    /// choices, or setting `selectedRow` from JavaScript.
    ///
    /// - Example:
    /// ```js
    /// chooser.onSelectionChange = (row, item) => {
    ///     if (item) showPreviewFor(item)
    /// }
    /// ```
    @objc var onSelectionChange: JSFunction? { get set }

    /// {(() => void) | null} Called after the panel becomes visible, or null to remove the handler.
    /// - Example:
    /// ```js
    /// chooser.onShow = () => console.log("Chooser appeared")
    /// ```
    @objc var onShow: JSFunction? { get set }

    /// {(() => void) | null} Called after the panel is hidden (for any reason: selection, Escape, or `hide()`), or null to remove the handler.
    /// - Example:
    /// ```js
    /// chooser.onHide = () => console.log("Chooser hidden")
    /// ```
    @objc var onHide: JSFunction? { get set }

    /// {((item: Record<string, any>) => void) | null} Called when the user activates a row whose `valid` field is `false`, or null to remove the handler.
    /// The chooser stays open; the argument is the row dict (same shape as `onSelect`).
    /// If unset, activating an invalid row is silently ignored.
    /// - Example:
    /// ```js
    /// chooser.onInvalid = (item) => console.log("Tapped invalid row: " + item.text)
    /// ```
    @objc var onInvalid: JSFunction? { get set }

    /// {Array<Record<string, any>>} The right-click menu shown for every row (default: `[]`, no menu).
    ///
    /// Each entry is either `{ title: "..." }` for a menu item, or `{ type: "divider" }` for a
    /// separator. Any other fields on an entry (e.g. an `id`) are passed back to
    /// `onContextMenuSelect` unchanged, so one handler can tell the entries apart.
    ///
    /// A menu item can show a keyboard shortcut with a `shortcut` field: a string of modifier symbols
    /// (`⌘` `⇧` `⌥` `⌃`) followed by one key, as the menu shows it (`"⇧⌘C"`, or just `"O"` for no
    /// modifiers), or an object with the modifiers and key spelled out
    /// (`{ mods: ["cmd", "shift"], key: "c" }`). Modifier and key names are the same as for
    /// `hs.hotkey.bind()`.
    ///
    /// **A menu shortcut is not a system-wide hotkey**, nor a shortcut for the chooser: pressing it
    /// chooses the item only while the context menu is open, and does nothing while it's closed.
    ///
    /// Rows whose choice has `contextMenu: false` show no menu, e.g. for a "Clear history" row.
    /// - Example:
    /// ```js
    /// chooser.contextMenu = [
    ///     { title: "Reveal in Finder", id: "reveal" },
    ///     { type: "divider" },
    ///     { title: "Copy path", id: "copy", shortcut: "⇧⌘C" }
    /// ]
    /// ```
    @objc var contextMenu: [Any] { get set }

    /// {((choice: Record<string, any>, menuItem: Record<string, any>) => void) | null} Called when the user picks an entry from the `contextMenu`, or null to remove the handler.
    ///
    /// `choice` is the row that was right-clicked (same shape as `onSelect`'s argument) and
    /// `menuItem` is the `contextMenu` entry that was picked, with any custom fields intact.
    /// The chooser stays open.
    /// - Example:
    /// ```js
    /// chooser.onContextMenuSelect = (choice, menuItem) => {
    ///     if (menuItem.id === "copy") hs.pasteboard.writeString(choice.subText)
    /// }
    /// ```
    @objc var onContextMenuSelect: JSFunction? { get set }

    /// Programmatically confirm a selection.
    ///
    /// Omit `row` to confirm the currently highlighted row. Fires `onSelect` (or `onInvalid`
    /// for rows with `valid: false`) and hides the chooser.
    ///
    /// - Parameter row: {number | null} Zero-based row index, or omit to use the current selection.
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// chooser.select()     // confirm highlighted row
    /// chooser.select(2)    // confirm row at index 2
    /// ```
    @objc @discardableResult func select(_ row: JSValue) -> HSChooser

    /// Returns the dict for the highlighted row, or for a specific row by index.
    /// Returns `null` if the index is out of range or no choices are set.
    ///
    /// - Parameter row: {number | null} Zero-based row index, or omit to query the highlighted row.
    /// - Returns: The row dict (`{ text, subText?, image?, valid, ...extras }`) or `null`.
    /// - Example:
    /// ```js
    /// const item = chooser.selectedRowContents()
    /// const item = chooser.selectedRowContents(2)
    /// ```
    @objc func selectedRowContents(_ row: JSValue) -> [String: Any]?
}

// MARK: -

@_documentation(visibility: private)
@MainActor
@objc class HSChooser: NSObject, HSChooserAPI, HSTrackedObject {
    @objc var typeName = "HSChooser"

    @objc func toString() -> String {
        return "<\(typeName): query '\(query)'>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    @objc let identifier = UUID().uuidString

    let viewModel = ChooserViewModel()
    private var window: ChooserPanel?
    private weak var tracker: HSObjectTracker<HSChooser>?

    // A shown chooser is active: it stays on screen, with its callbacks, until it's hidden,
    // even if the user dropped their reference to it. A hidden chooser nobody references can
    // never be shown again, so it's ordinary garbage.
    private var isShown = false {
        didSet {
            tracker?.setActive(self, isShown)
            // The next show() reports its selection afresh
            if !isShown { lastNotifiedSelection = nil }
        }
    }

    init(tracker: HSObjectTracker<HSChooser>) {
        self.tracker = tracker
        super.init()
        viewModel.onContextMenuSelect = { [weak self] item, entry in
            self?.handleContextMenuSelection(item, entry: entry)
        }
        viewModel.onSelectedIndexChange = { [weak self] in
            self?.notifySelectionChange()
        }
    }

    private var allChoices: [ChooserItem] = []
    private var isStaticChoices = true
    private var _choicesFunction: JSCallback?

    @objc var searchSubText = false
    @objc var enableDefaultForQuery = false
    private var _width: Double = 0.5
    @objc var width: Double {
        get { _width }
        set {
            guard newValue.isFinite, newValue > 0 else {
                AKWarning("hs.chooser.width: ignoring invalid width \(newValue)")
                return
            }
            _width = newValue
            guard let window else { return }
            // Resize about the centre, so a chooser in its default place stays centred
            var appKitFrame = window.frame
            appKitFrame.origin.x = appKitFrame.midX - windowWidth / 2
            appKitFrame.size.width = windowWidth
            window.setFrame(appKitFrame, display: true)
            window.refreshShadow()
        }
    }
    @objc var visibleRows: Int {
        get { viewModel.visibleRows }
        set { viewModel.visibleRows = newValue }
    }

    // MARK: - Styling

    @objc var backgroundColor: HSColor? {
        get { viewModel.backgroundColor.map { HSColor(color: $0) } }
        set {
            viewModel.backgroundColor = newValue?.color
            window?.refreshShadow()
        }
    }

    @objc var cornerRadius: Double {
        get { Double(viewModel.cornerRadius) }
        set {
            viewModel.cornerRadius = CGFloat(newValue)
            window?.refreshShadow()
        }
    }

    @objc var borderColor: HSColor? {
        get { viewModel.borderColor.map { HSColor(color: $0) } }
        set { viewModel.borderColor = newValue?.color }
    }

    @objc var borderWidth: Double {
        get { Double(viewModel.borderWidth) }
        set { viewModel.borderWidth = CGFloat(newValue) }
    }

    @objc var textColor: HSColor? {
        get { viewModel.textColor.map { HSColor(color: $0) } }
        set { viewModel.textColor = newValue?.color }
    }

    @objc var subTextColor: HSColor? {
        get { viewModel.subTextColor.map { HSColor(color: $0) } }
        set { viewModel.subTextColor = newValue?.color }
    }

    @objc var queryColor: HSColor? {
        get { viewModel.queryColor.map { HSColor(color: $0) } }
        set { viewModel.queryColor = newValue?.color }
    }

    @objc var placeholderColor: HSColor? {
        get { viewModel.placeholderColor.map { HSColor(color: $0) } }
        set { viewModel.placeholderColor = newValue?.color }
    }

    @objc var selectionColor: HSColor? {
        get { viewModel.selectionColor.map { HSColor(color: $0) } }
        set { viewModel.selectionColor = newValue?.color }
    }

    @objc var textSize: Double {
        get { Double(viewModel.textSize) }
        set {
            guard newValue.isFinite && newValue > 0 else {
                AKWarning("hs.chooser.textSize: value must be a positive, finite number (got \(newValue))")
                return
            }
            viewModel.textSize = CGFloat(newValue)
            viewModel.onContentSizeChange?(viewModel.expectedHeight())
        }
    }

    @objc var subTextSize: Double {
        get { Double(viewModel.subTextSize) }
        set {
            guard newValue.isFinite && newValue > 0 else {
                AKWarning("hs.chooser.subTextSize: value must be a positive, finite number (got \(newValue))")
                return
            }
            viewModel.subTextSize = CGFloat(newValue)
            viewModel.onContentSizeChange?(viewModel.expectedHeight())
        }
    }

    @objc var querySize: Double {
        get { Double(viewModel.querySize) }
        set {
            guard newValue.isFinite && newValue > 0 else {
                AKWarning("hs.chooser.querySize: value must be a positive, finite number (got \(newValue))")
                return
            }
            viewModel.querySize = CGFloat(newValue)
            viewModel.onContentSizeChange?(viewModel.expectedHeight())
        }
    }

    private var _onSelect: JSCallback?
    private var _onQueryChange: JSCallback?
    private var _onSelectionChange: JSCallback?
    private var _onShow: JSCallback?
    private var _onHide: JSCallback?
    private var _onInvalid: JSCallback?
    private var _onContextMenuSelect: JSCallback?

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

    @objc var windowID: NSNumber? {
        guard let window, window.isVisible else { return nil }
        return NSNumber(value: window.windowNumber)
    }

    @objc var frame: HSRect? {
        get {
            guard let window else {
                let initial = ChooserPanel.initialFrame(
                    on: NSScreen.main ?? NSScreen.screens[0],
                    width: windowWidth,
                    height: viewModel.expectedHeight()
                )
                return initial.flippedScreenCoordinates().toBridge()
            }
            var topDown = window.frame.flippedScreenCoordinates()
            // A hidden panel is only resized to fit its rows by the next show(), so report that height
            if !window.isVisible {
                topDown.size.height = viewModel.expectedHeight()
            }
            return topDown.toBridge()
        }
        set {
            guard let newValue else { return }
            guard newValue.x.isFinite, newValue.y.isFinite, newValue.w.isFinite, newValue.w > 0 else {
                AKWarning("hs.chooser.frame: ignoring invalid frame \(newValue.toString())")
                return
            }
            if window == nil {
                createWindow()
            }
            guard let window else { return }
            // The height follows the rows, so ignore the requested one and pin the top-left corner
            let topDown = CGRect(x: newValue.x, y: newValue.y, width: newValue.w,
                                 height: viewModel.expectedHeight())
            window.setFrame(topDown.flippedScreenCoordinates(), display: true)
            // Keep `width` describing the panel
            _width = newValue.w / mainScreenWidth
            window.refreshShadow()
        }
    }

    @objc var selectedRow: Int {
        get { viewModel.selectedIndex }
        set {
            let maxIndex = viewModel.filteredChoices.isEmpty ? 0 : viewModel.filteredChoices.count - 1
            viewModel.selectedIndex = min(max(0, newValue), maxIndex)
        }
    }

    // MARK: - Callbacks (JSCallback-backed properties)

    @objc var onSelect: JSValue? {
        get { _onSelect?.value }
        set {
            _onSelect?.detach(from: self)
            _onSelect = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onQueryChange: JSValue? {
        get { _onQueryChange?.value }
        set {
            _onQueryChange?.detach(from: self)
            _onQueryChange = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onSelectionChange: JSValue? {
        get { _onSelectionChange?.value }
        set {
            _onSelectionChange?.detach(from: self)
            _onSelectionChange = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onShow: JSValue? {
        get { _onShow?.value }
        set {
            _onShow?.detach(from: self)
            _onShow = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onHide: JSValue? {
        get { _onHide?.value }
        set {
            _onHide?.detach(from: self)
            _onHide = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onInvalid: JSValue? {
        get { _onInvalid?.value }
        set {
            _onInvalid?.detach(from: self)
            _onInvalid = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    @objc var onContextMenuSelect: JSValue? {
        get { _onContextMenuSelect?.value }
        set {
            _onContextMenuSelect?.detach(from: self)
            _onContextMenuSelect = newValue.flatMap { JSCallback(value: $0, owner: self, silentOnUndefined: true) }
        }
    }

    // MARK: - Context menu

    /// The valid entries of the last `contextMenu` set from JS, as returned by the getter.
    private var contextMenuEntries: [[String: Any]] = []

    @objc var contextMenu: [Any] {
        get { contextMenuEntries }
        set {
            let parsed = newValue.compactMap { value -> (entry: [String: Any], menuEntry: ChooserContextMenuEntry)? in
                guard let entry = value as? [String: Any] else {
                    AKWarning("hs.chooser.contextMenu: ignoring entry that isn't an object")
                    return nil
                }
                if entry["type"] as? String == "divider" {
                    return (entry, .divider)
                }
                guard let title = entry["title"] as? String, !title.isEmpty else {
                    AKWarning("hs.chooser.contextMenu: ignoring entry without a title")
                    return nil
                }
                var shortcut: MenuShortcut?
                if let shortcutValue = entry["shortcut"], !(shortcutValue is NSNull) {
                    do {
                        shortcut = try MenuShortcut(parsing: shortcutValue)
                    } catch {
                        AKWarning("hs.chooser.contextMenu: Ignoring shortcut for \"\(title)\": \(error)")
                    }
                }
                return (entry, .item(title: title, shortcut: shortcut, entry: entry))
            }
            contextMenuEntries = parsed.map(\.entry)
            viewModel.contextMenuEntries = parsed.map(\.menuEntry)
        }
    }

    // MARK: - Choices

    @objc @discardableResult func setChoices(_ choices: JSValue) -> HSChooser {
        if choices.isArray {
            isStaticChoices = true
            _choicesFunction?.detach(from: self)
            _choicesFunction = nil
            allChoices = parseChoiceArray(choices)
            viewModel.filteredChoices = filteredChoices(for: _storedQuery)
            viewModel.selectedIndex = 0
        } else if choices.isObject && !choices.isNull && !choices.isUndefined {
            isStaticChoices = false
            _choicesFunction?.detach(from: self)
            _choicesFunction = JSCallback(value: choices, owner: self)
            callChoicesFunction()
        } else {
            isStaticChoices = true
            _choicesFunction?.detach(from: self)
            _choicesFunction = nil
            allChoices = []
            viewModel.filteredChoices = []
            viewModel.selectedIndex = 0
        }
        viewModel.onContentSizeChange?(viewModel.expectedHeight())
        return self
    }

    @objc @discardableResult func refreshChoices() -> HSChooser {
        if isStaticChoices {
            viewModel.filteredChoices = filteredChoices(for: _storedQuery)
            // Keep the selection on a row that still exists
            viewModel.selectedIndex = min(viewModel.selectedIndex, max(0, viewModel.filteredChoices.count - 1))
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
        isShown = true
        startKeyMonitor()
        startResignKeyObserver()
        window?.makeKeyAndOrderFront(nil)
        window?.refreshShadow()
        _ = _onShow?.call(withArguments: [])
        notifySelectionChange()
        AKGarbage("hs.chooser.show(): \(identifier)")
        return self
    }

    @objc @discardableResult func hide() -> HSChooser {
        guard let w = window, w.isVisible else {
            // AppKit may have ordered the panel out already; it's still no longer shown
            isShown = false
            return self
        }
        viewModel.isVisible = false
        isShown = false
        stopKeyMonitor()
        stopResignKeyObserver()  // must be before orderOut — orderOut resigns key, which would re-fire the observer
        w.orderOut(nil)

        if let prev = previouslyActiveWindow, prev.isVisible {
            prev.makeKeyAndOrderFront(nil)
        }
        previouslyActiveWindow = nil

        _ = _onHide?.call(withArguments: [])
        AKGarbage("hs.chooser.hide(): \(identifier)")
        return self
    }

    @objc @discardableResult func select(_ row: JSValue) -> HSChooser {
        let index = row.isNumber ? Int(row.toInt32()) : viewModel.selectedIndex
        let safeIndex = (index >= 0 && index < viewModel.filteredChoices.count) ? index : nil
        handleSelection(safeIndex)
        return self
    }

    @objc func selectedRowContents(_ row: JSValue) -> [String: Any]? {
        let index = row.isNumber ? Int(row.toInt32()) : viewModel.selectedIndex
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
        _onSelectionChange?.detach(from: self)
        _onSelectionChange = nil
        _onShow?.detach(from: self)
        _onShow = nil
        _onHide?.detach(from: self)
        _onHide = nil
        _onInvalid?.detach(from: self)
        _onInvalid = nil
        _onContextMenuSelect?.detach(from: self)
        _onContextMenuSelect = nil

        allChoices = []
        viewModel.filteredChoices = []
        viewModel.onUserQueryChange = nil
        viewModel.onContentSizeChange = nil
        viewModel.onContextMenuSelect = nil
        viewModel.onSelectedIndexChange = nil
        // Entries can hold native objects (even this chooser) in custom fields
        contextMenuEntries = []
        viewModel.contextMenuEntries = []
        AKGarbage("hs.chooser.destroy(): \(identifier)")
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSChooser(\(identifier))")
    }

    // MARK: - Key event monitor

    private func startKeyMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent monitors fire on the main thread. Extract the key code (a Sendable
            // UInt16) before entering MainActor.assumeIsolated so we never try to pass
            // the non-Sendable NSEvent across the isolation boundary.
            let keyCode = event.keyCode
            // Caps Lock (and function/numeric-pad flags) are irrelevant to our shortcuts and must be
            // excluded here, otherwise the exact-match comparisons below never succeed while it's on.
            let modifierFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let consumed = MainActor.assumeIsolated {
                self?.interceptKeyCode(keyCode, modifierFlags: modifierFlags) ?? false
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

    private func interceptKeyCode(_ keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        // Only intercept while our panel is the key window.
        guard let panel = window, panel.isKeyWindow else { return false }
        // Ctrl-N/Ctrl-P follow the keyboard layout, like Emacs-style bindings elsewhere in macOS.
        // Cmd-0...9 below deliberately stay on the number row keys, whatever characters they type.
        let keyCodes = KeyboardLayout.shared.keyCodes

        switch keyCode {
        case 125: // kVK_DownArrow
            viewModel.moveSelection(by: 1)
            return true
        case 126: // kVK_UpArrow
            viewModel.moveSelection(by: -1)
            return true
        case 121: // kVK_PageDown (also Fn-↓ on laptop keyboards)
            viewModel.moveSelection(by: viewModel.pageSize)
            return true
        case 116: // kVK_PageUp (also Fn-↑ on laptop keyboards)
            viewModel.moveSelection(by: -viewModel.pageSize)
            return true
        case 115: // kVK_Home (also Fn-← on laptop keyboards)
            viewModel.moveSelection(to: 0)
            return true
        case 119: // kVK_End (also Fn-→ on laptop keyboards)
            viewModel.moveSelection(to: viewModel.filteredChoices.count - 1)
            return true
        case _ where modifierFlags == .control && Int(keyCode) == keyCodes.keyCode(forName: "n"): // Ctrl-N: next row
            viewModel.moveSelection(by: 1)
            return true
        case _ where modifierFlags == .control && Int(keyCode) == keyCodes.keyCode(forName: "p"): // Ctrl-P: previous row
            viewModel.moveSelection(by: -1)
            return true
        case 53: // kVK_Escape
            handleSelection(nil)
            return true
        case 36, 76: // kVK_Return, kVK_ANSI_KeypadEnter
            handleSelection(viewModel.filteredChoices.isEmpty ? nil : viewModel.selectedIndex)
            return true
        default:
            // Cmd-1 through Cmd-9, Cmd-0: jump straight to one of the first ten rows.
            if modifierFlags == .command,
               let rowIndex = Self.numberKeyRowIndex[keyCode],
               rowIndex < viewModel.filteredChoices.count {
                handleSelection(rowIndex)
                return true
            }
            return false
        }
    }

    /// Maps the ANSI number-row key codes to the row index they select (Cmd-1 → 0, ..., Cmd-9 → 8, Cmd-0 → 9).
    private static let numberKeyRowIndex: [UInt16: Int] = [
        18: 0, // kVK_ANSI_1
        19: 1, // kVK_ANSI_2
        20: 2, // kVK_ANSI_3
        21: 3, // kVK_ANSI_4
        23: 4, // kVK_ANSI_5
        22: 5, // kVK_ANSI_6
        26: 6, // kVK_ANSI_7
        28: 7, // kVK_ANSI_8
        25: 8, // kVK_ANSI_9
        29: 9  // kVK_ANSI_0
    ]

    // MARK: - Private

    private var mainScreenWidth: CGFloat { NSScreen.main?.frame.width ?? 1440 }

    /// The panel's width in points: `width` as a fraction of the main screen's width.
    private var windowWidth: CGFloat { CGFloat(width) * mainScreenWidth }

    private func createWindow() {
        let screen = NSScreen.main

        viewModel.onContentSizeChange = { [weak self] height in
            self?.window?.setHeight(height)
        }

        viewModel.onUserQueryChange = { [weak self] newQuery in
            guard let self else { return }
            self._storedQuery = newQuery
            if self.isStaticChoices {
                // Filter before resetting the selection, so onSelectionChange sees the new rows
                self.viewModel.filteredChoices = self.filteredChoices(for: newQuery)
                self.viewModel.selectedIndex = 0
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
                // SwiftUI writes the TextField's current value back through this binding
                // when the field establishes itself (shortly after show()), even though
                // nothing changed. Without this guard that no-op write is indistinguishable
                // from a real edit and resets selectedIndex out from under selectedRow. See #227.
                guard newValue != self._storedQuery else { return }
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
        allChoices = parseChoiceArray(result)
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

    /// The row and choice last reported to `onSelectionChange`, so it's only called when
    /// either of them actually changes. `nil` until the chooser reports its first selection.
    private var lastNotifiedSelection: (row: Int, item: ChooserItem?)?

    private func notifySelectionChange() {
        guard isShown else { return }
        let row = viewModel.selectedIndex
        let item = viewModel.filteredChoices.indices.contains(row) ? viewModel.filteredChoices[row] : nil
        if let last = lastNotifiedSelection, last.row == row {
            switch (last.item, item) {
            case (nil, nil): return
            case let (lastItem?, item?) where lastItem.isSameChoice(as: item): return
            default: break
            }
        }
        // Record before calling, so a handler that sets selectedRow doesn't recurse forever
        lastNotifiedSelection = (row, item)
        guard let callback = _onSelectionChange, let context = callback.value?.context else { return }
        let itemArg: Any = item.map { buildReturnDict(for: $0) } ?? JSValue(nullIn: context) as Any
        _ = callback.call(withArguments: [row, itemArg])
    }

    private func handleContextMenuSelection(_ item: ChooserItem, entry: [String: Any]) {
        _ = _onContextMenuSelect?.call(withArguments: [buildReturnDict(for: item), entry])
    }

    private func buildReturnDict(for item: ChooserItem) -> [String: Any] {
        var dict: [String: Any] = item.extra
        dict["text"] = item.text
        if let subText = item.subText { dict["subText"] = subText }
        if let image = item.image { dict["image"] = HSImage(image: image) }
        dict["valid"] = item.isValid
        return dict
    }

    private func parseChoiceArray(_ raw: JSValue?) -> [ChooserItem] {
        guard let raw, raw.isArray else { return [] }
        let basicItems = raw.toArray() ?? []
        return basicItems.compactMap { value in
            guard let dict = value as? [String: Any] else { return nil }
            return parseChoice(dict)
        }
    }

    private func parseChoice(_ dict: [String: Any]) -> ChooserItem? {
        guard let text = dict["text"] as? String else { return nil }

        let subText = dict["subText"] as? String
        let isValid = dict["valid"] as? Bool ?? true
        // Left in `extra`, so the choice round-trips to onSelect with it intact
        let showsContextMenu = dict["contextMenu"] as? Bool ?? true

        var image: NSImage?
        if let hsImg = dict["image"] as? HSImage {
            image = hsImg.image
        } else if let nsImg = dict["image"] as? NSImage {
            image = nsImg
        }

        var extra = dict
        extra.removeValue(forKey: "text")
        extra.removeValue(forKey: "subText")
        extra.removeValue(forKey: "image")
        extra.removeValue(forKey: "valid")

        return ChooserItem(id: UUID(), text: text, subText: subText, image: image, isValid: isValid,
                           showsContextMenu: showsContextMenu, extra: extra)
    }
}
