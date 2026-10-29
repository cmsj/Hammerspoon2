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
    @State var querySelection: TextSelection? = nil
    let onSelect: (Int?) -> Void

    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPhase: ScrollPhase = .idle

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
        .chooserBackground(viewModel)
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
                .font(.system(size: viewModel.iconSize, weight: .medium))
                .foregroundStyle(viewModel.placeholderColor ?? Color.secondary)
            TextField(
                viewModel.placeholder,
                text: queryBinding,
                selection: $querySelection,
                prompt: Text(viewModel.placeholder).foregroundStyle(viewModel.placeholderColor ?? Color.secondary)
            )
                .textFieldStyle(.plain)
                .font(.system(size: viewModel.querySize))
                .foregroundStyle(viewModel.queryColor ?? Color.primary)
                .focused($searchFocused)
                .onChange(of: viewModel.isVisible) { _, visible in
                    guard visible == true else { return }

                    let range = queryBinding.wrappedValue.startIndex..<queryBinding.wrappedValue.endIndex
                    querySelection = .init(range: range)
                }
        }
        .padding(.horizontal, 16)
        .frame(height: viewModel.searchBarHeight)
    }

    private var resultsList: some View {
        let count = viewModel.filteredChoices.count
        let visibleCount = min(count, viewModel.visibleRows)
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredChoices.enumerated()), id: \.element.id) { index, item in
                        ChooserRowView(
                            viewModel: viewModel,
                            item: item,
                            isSelected: index == viewModel.highlightedIndex,
                            shortcutDigit: index < 10 ? (index + 1) % 10 : nil
                        )
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
            .frame(height: CGFloat(visibleCount) * viewModel.rowHeight)
            .onScrollPhaseChange { _, newPhase in
                scrollPhase = newPhase
                // Scrolling has stopped, so finish any pending Page Up/Down or Home/End
                // highlight move. Don't require the previous phase to be .animating: the
                // user can interrupt the scroll with the trackpad, taking it through
                // .interacting/.decelerating instead. Outside a page move the two indices
                // are already equal, so this is a no-op.
                if newPhase == .idle {
                    viewModel.highlightedIndex = viewModel.selectedIndex
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                let animated = viewModel.animateNextScroll && !reduceMotion
                viewModel.animateNextScroll = false
                guard newIndex < viewModel.filteredChoices.count else {
                    viewModel.highlightedIndex = newIndex
                    return
                }
                let id = viewModel.filteredChoices[newIndex].id
                if animated {
                    // Scroll first, then move the highlight, so it lands on the new row
                    // rather than jumping there and riding along with the scroll. The
                    // highlight is moved by onScrollPhaseChange when the scroll ends;
                    // withAnimation's completion can't be used, because it fires
                    // immediately — the scroll is driven by AppKit, not by SwiftUI.
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    // If the list is already where it needs to be (e.g. paging down to the
                    // last row while it's already in view), nothing scrolls and the phase
                    // never changes, so highlight the row directly.
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        if scrollPhase != .animating && viewModel.selectedIndex == newIndex {
                            viewModel.highlightedIndex = newIndex
                        }
                    }
                } else {
                    proxy.scrollTo(id, anchor: .center)
                    viewModel.highlightedIndex = newIndex
                }
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
    func chooserBackground(_ viewModel: ChooserViewModel) -> some View {
        modifier(ChooserBackgroundModifier(viewModel: viewModel))
    }
}

private struct ChooserBackgroundModifier: ViewModifier {
    var viewModel: ChooserViewModel

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: viewModel.cornerRadius, style: .continuous)

        // clipShape is required here: .background(_, in:) only clips the background fill
        // itself, not `content` on top of it, so a selected row's square highlight in the
        // last row would otherwise poke past the panel's rounded corners.
        Group {
            if let backgroundColor = viewModel.backgroundColor {
                content.background(backgroundColor, in: shape)
            } else {
                content.glassEffect(in: shape)
            }
        }
        .clipShape(shape)
        .overlay {
            if let borderColor = viewModel.borderColor {
                shape.strokeBorder(borderColor, lineWidth: viewModel.borderWidth)
            }
        }
    }
}
