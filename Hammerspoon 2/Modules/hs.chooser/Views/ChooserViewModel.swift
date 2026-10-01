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
    var selectedIndex: Int = 0
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

    func expectedHeight() -> CGFloat {
        let count = filteredChoices.count
        guard count > 0 else { return searchBarHeight }
        let visibleCount = min(count, visibleRows)
        return searchBarHeight + Self.separatorHeight + rowHeight * CGFloat(visibleCount)
    }
}
