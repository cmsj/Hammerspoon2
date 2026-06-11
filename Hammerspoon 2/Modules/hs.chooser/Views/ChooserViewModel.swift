//
//  ChooserViewModel.swift
//  Hammerspoon 2
//

import AppKit
import Observation

/// A single selectable item in the chooser list.
struct ChooserItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let subText: String?
    let image: NSImage?
    let isValid: Bool
    /// Original JS-side fields (excluding text/subText/image/valid) for passback to onSelect.
    let extra: [String: Any]

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
