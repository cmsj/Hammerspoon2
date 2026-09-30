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

    /// Notified when the user types in the search field (not when set programmatically).
    @ObservationIgnored var onUserQueryChange: ((String) -> Void)?
    /// Notified when content size changes so the window frame can be updated.
    @ObservationIgnored var onContentSizeChange: ((CGFloat) -> Void)?

    static let searchBarHeight: CGFloat = 56
    static let separatorHeight: CGFloat = 1
    static let rowHeight: CGFloat = 52

    func expectedHeight() -> CGFloat {
        let count = filteredChoices.count
        guard count > 0 else { return Self.searchBarHeight }
        let visibleCount = min(count, visibleRows)
        return Self.searchBarHeight + Self.separatorHeight + Self.rowHeight * CGFloat(visibleCount)
    }
}
