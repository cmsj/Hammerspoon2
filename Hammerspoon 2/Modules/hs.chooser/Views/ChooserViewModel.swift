//
//  ChooserViewModel.swift
//  Hammerspoon 2
//

import AppKit
import Observation
import SwiftUI

/// A single entry in a row's context menu — either an action button or a separator.
struct ChooserContextMenuEntry {
    enum Kind {
        case button(title: String, action: () -> Void)
        case divider
    }
    let kind: Kind
}

/// A single selectable item in the chooser list.
struct ChooserItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let subText: String?
    let image: NSImage?
    let isValid: Bool
    /// Original JS-side fields (excluding text/subText/image/valid/contextMenu) for passback to onSelect.
    let extra: [String: Any]
    /// Per-row context menu entries, parsed from the JS `contextMenu` array.
    let contextMenuItems: [ChooserContextMenuEntry]

    static func == (lhs: ChooserItem, rhs: ChooserItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Observable state shared between HSChooser and the SwiftUI view hierarchy.
@Observable
@MainActor
final class ChooserViewModel {
    var filteredChoices: [ChooserItem] = []
    /// The logical selection: what Return, `selectedRow` and friends act on.
    var selectedIndex: Int = 0 {
        didSet {
            // Multi-row moves leave the highlight behind until the list has scrolled to the new
            // row (see ChooserView); everything else highlights the new row immediately.
            if !animateNextScroll { highlightedIndex = selectedIndex }
        }
    }
    /// The row drawn as selected. Usually equal to `selectedIndex`, but lags behind it while
    /// a Page Up/Down or Home/End scroll animation is running, so the highlight doesn't jump
    /// to the new row and then scroll along with it.
    var highlightedIndex: Int = 0
    var placeholder: String = "Search..."
    var visibleRows: Int = 10
    var isVisible: Bool = false

    // MARK: - Styling

    /// Panel background color. `nil` uses the default glass/material effect.
    var backgroundColor: Color? = nil
    /// Panel corner radius, in points.
    var cornerRadius: CGFloat = 14
    /// Panel border color. `nil` draws no border.
    var borderColor: Color? = nil
    /// Panel border width, in points. Has no effect unless `borderColor` is set.
    var borderWidth: CGFloat = 1
    /// Result row title color. `nil` uses the system primary label color.
    var textColor: Color? = nil
    /// Result row subtitle color. `nil` uses the system secondary label color.
    var subTextColor: Color? = nil
    /// Color of text typed into the search field. `nil` uses the system primary label color.
    var queryColor: Color? = nil
    /// Color of the placeholder text (and search icon) shown in an empty search field.
    /// `nil` uses the system secondary label color.
    var placeholderColor: Color? = nil
    /// Background tint of the highlighted row. `nil` uses a translucent accent-color tint.
    var selectionColor: Color? = nil
    /// Result row title font size, in points.
    var textSize: CGFloat = 14
    /// Result row subtitle font size, in points.
    var subTextSize: CGFloat = 12
    /// Search field font size, in points (also drives the placeholder's size).
    var querySize: CGFloat = 20

    /// Font size of the ⌘-digit shortcut hint shown on the first ten rows. Scales with
    /// `textSize` (at the same ratio as the original fixed defaults: 12pt hint / 14pt title)
    /// rather than being independently configurable, since it's a small annotation on the
    /// title, not a standalone piece of text.
    var shortcutSize: CGFloat { textSize * Self.shortcutToTextRatio }
    /// Font size of the search field's magnifying glass icon. Scales with `querySize` (at
    /// the same ratio as the original fixed defaults: 17pt icon / 20pt query) rather than
    /// being independently configurable, since it's an adornment on the search field.
    var iconSize: CGFloat { querySize * Self.iconToQueryRatio }

    /// Notified when the user types in the search field (not when set programmatically).
    @ObservationIgnored var onUserQueryChange: ((String) -> Void)?
    /// Notified when content size changes so the window frame can be updated.
    @ObservationIgnored var onContentSizeChange: ((CGFloat) -> Void)?

    static let separatorHeight: CGFloat = 1

    private static let shortcutToTextRatio: CGFloat = 12.0 / 14.0
    private static let iconToQueryRatio: CGFloat = 17.0 / 20.0

    /// Vertical space between the title and subtitle lines, matching ChooserRowView's
    /// `VStack(alignment: .leading, spacing: 2)`.
    private static let rowContentSpacing: CGFloat = 2
    /// Total top+bottom padding baked into a row, chosen to reproduce the original fixed
    /// 52pt row height at the original fixed default sizes (14pt title / 12pt subtitle).
    private static let rowVerticalPadding: CGFloat = 18
    /// Total top+bottom padding baked into the search bar, chosen to reproduce the original
    /// fixed 56pt search bar height at the original fixed default size (20pt query).
    private static let searchBarVerticalPadding: CGFloat = 32

    /// The actual rendered line height of the system font at `size`/`weight`, used to size
    /// rows and the search bar precisely instead of guessing from point size alone.
    private static func lineHeight(size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// Height of the search bar, driven by `querySize`.
    var searchBarHeight: CGFloat {
        Self.lineHeight(size: querySize) + Self.searchBarVerticalPadding
    }

    /// Height of a single result row, driven by `textSize` and `subTextSize`. Every row gets
    /// this same height regardless of whether that particular item has a subtitle, so the
    /// list stays visually uniform — matching the original fixed-height behaviour.
    var rowHeight: CGFloat {
        let titleLine = Self.lineHeight(size: textSize, weight: .medium)
        let subTextLine = Self.lineHeight(size: subTextSize)
        return titleLine + Self.rowContentSpacing + subTextLine + Self.rowVerticalPadding
    }

    /// Number of rows Page Up / Page Down move the selection by: one screenful of rows.
    var pageSize: Int { max(1, visibleRows) }

    /// Set when the next selection change should scroll the list smoothly rather than
    /// jump. Consumed (and cleared) by ChooserView when it scrolls to the new selection,
    /// which then moves `highlightedIndex` once the scroll has finished.
    @ObservationIgnored var animateNextScroll = false

    /// Moves the selection by `offset` rows, clamped to the first and last rows.
    func moveSelection(by offset: Int) {
        moveSelection(to: selectedIndex + offset)
    }

    /// Moves the selection to the row at `index`, clamped to the first and last rows.
    /// Multi-row moves (Page Up/Down, Home/End) scroll smoothly so the user can follow where
    /// the selection went; single-row moves stay instant so a held arrow key doesn't queue
    /// up laggy animations.
    func moveSelection(to index: Int) {
        let maxIndex = max(0, filteredChoices.count - 1)
        let newIndex = min(max(0, index), maxIndex)
        if newIndex != selectedIndex {
            animateNextScroll = abs(newIndex - selectedIndex) > 1
            selectedIndex = newIndex
        }
    }

    func expectedHeight() -> CGFloat {
        let count = filteredChoices.count
        guard count > 0 else { return searchBarHeight }
        let visibleCount = min(count, visibleRows)
        return searchBarHeight + Self.separatorHeight + rowHeight * CGFloat(visibleCount)
    }
}
