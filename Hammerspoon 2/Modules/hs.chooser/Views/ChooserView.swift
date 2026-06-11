//
//  ChooserView.swift
//  Hammerspoon 2
//

import SwiftUI
import AppKit

struct ChooserView: View {
    var viewModel: ChooserViewModel
    /// Binding for the text field — setter notifies HSChooser of user typing.
    var queryBinding: Binding<String>
    let onSelect: (Int?) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !viewModel.filteredChoices.isEmpty {
                Divider()
                    .opacity(0.4)
                resultsList
            }
        }
        .frame(maxWidth: .infinity)
        .chooserBackground()
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.isVisible) { _, visible in
            if visible { searchFocused = true }
        }
        .onChange(of: viewModel.filteredChoices.count) { _, _ in
            // Fallback height update for static-choices mode; dynamic mode is
            // handled imperatively by callChoicesFunction().
            viewModel.onContentSizeChange?(viewModel.expectedHeight())
        }
        .onChange(of: searchFocused) { _, focused in
            // The scroll view's underlying NSScrollView can capture first responder
            // when the user clicks or scrolls. Re-assert TextField focus immediately.
            // Guard against hidden window: re-asserting focus in a hidden panel causes
            // SwiftUI to call makeKeyAndOrderFront, stealing key status from other windows.
            guard viewModel.isVisible else { return }
            if !focused { searchFocused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(viewModel.placeholder, text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: ChooserViewModel.searchBarHeight)
    }

    private var resultsList: some View {
        let count = viewModel.filteredChoices.count
        let visibleCount = min(count, viewModel.visibleRows)
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredChoices.enumerated()), id: \.element.id) { index, item in
                        ChooserRowView(item: item, isSelected: index == viewModel.selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                onSelect(index)
                            }
                            .contextMenu {
                                ForEach(Array(item.contextMenuItems.enumerated()), id: \.offset) { _, entry in
                                    contextMenuEntryView(for: entry)
                                }
                            }
                    }
                }
            }
            .frame(height: CGFloat(visibleCount) * ChooserViewModel.rowHeight)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                guard newIndex < viewModel.filteredChoices.count else { return }
                proxy.scrollTo(viewModel.filteredChoices[newIndex].id, anchor: .center)
            }
        }
    }
}

// MARK: - Context menu

extension ChooserView {
    @ViewBuilder
    func contextMenuEntryView(for entry: ChooserContextMenuEntry) -> some View {
        switch entry.kind {
        case .divider:
            Divider()
        case .button(let title, let action):
            Button(title, action: action)
        }
    }
}

// MARK: - Glass background modifier

private extension View {
    func chooserBackground() -> some View {
        modifier(ChooserBackgroundModifier())
    }
}

private struct ChooserBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
    }
}
