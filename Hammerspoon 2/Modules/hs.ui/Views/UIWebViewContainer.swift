//
//  UIWebViewContainer.swift
//  Hammerspoon 2
//

import SwiftUI
import WebKit
import _WebKit_SwiftUI

// MARK: - View Configuration

/// Configuration passed from HSUIWebView to UIWebViewContainer at show() time.
@available(macOS 26.0, *)
struct UIWebViewConfiguration {
    var toolbarEntries: [HSUIWebViewToolbarEntry]
    var allowsBackForwardGestures: Bool
    var allowsMagnificationGestures: Bool
    var allowsLinkPreviews: Bool
    var showsContentBackground: Bool
}

// MARK: - Root Container

/// SwiftUI root view hosting a WebView with a native macOS window toolbar.
@available(macOS 26.0, *)
struct UIWebViewContainer: View {
    let page: WebPage
    let configuration: UIWebViewConfiguration

    var body: some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(
                configuration.allowsBackForwardGestures ? .enabled : .disabled
            )
            .webViewMagnificationGestures(
                configuration.allowsMagnificationGestures ? .enabled : .disabled
            )
            .webViewLinkPreviews(
                configuration.allowsLinkPreviews ? .enabled : .disabled
            )
            .webViewContentBackground(
                configuration.showsContentBackground ? .visible : .hidden
            )
            .toolbar {
                if !configuration.toolbarEntries.isEmpty {
                    ToolbarItemGroup(placement: .automatic) {
                        ForEach(configuration.toolbarEntries) { entry in
                            toolbarItemView(for: entry)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func toolbarItemView(for entry: HSUIWebViewToolbarEntry) -> some View {
        switch entry.kind {
        case .back:
            Button {
                if let item = page.backForwardList.backList.last {
                    _ = page.load(item)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page.backForwardList.backList.isEmpty)
            .help("Go Back")
            .accessibilityLabel("Go Back")

        case .forward:
            Button {
                if let item = page.backForwardList.forwardList.first {
                    _ = page.load(item)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(page.backForwardList.forwardList.isEmpty)
            .help("Go Forward")
            .accessibilityLabel("Go Forward")

        case .reload:
            Button {
                if page.isLoading { page.stopLoading() }
                else { _ = page.reload() }
            } label: {
                Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(page.isLoading ? "Stop" : "Reload")
            .accessibilityLabel(page.isLoading ? "Stop" : "Reload")

        case .url:
            URLToolbarField(page: page)
                .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity)

        case .flexibleSpacer:
            Spacer()

        case .custom:
            Button {
                _ = entry.callback?.call(withArguments: [])
            } label: {
                if let img = entry.systemImage, let title = entry.label {
                    Label(title, systemImage: img)
                } else if let img = entry.systemImage {
                    Image(systemName: img)
                } else {
                    Text(entry.label ?? "Button")
                }
            }
            .help(entry.label ?? "")
            .accessibilityLabel(entry.label ?? "Custom Button")
        }
    }
}

// MARK: - URL Toolbar Field

/// URL bar with focus-tracking so page URL updates don't interrupt typing.
/// Shows a thin progress bar overlay while loading.
@available(macOS 26.0, *)
private struct URLToolbarField: View {
    let page: WebPage

    @State private var urlText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("URL", text: $urlText)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { navigate() }
            .onChange(of: page.url) { _, newURL in
                if !isFocused {
                    urlText = newURL?.absoluteString ?? ""
                }
            }
            .onAppear {
                urlText = page.url?.absoluteString ?? ""
            }
            .overlay(alignment: .bottom) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                        .animation(.linear(duration: 0.1), value: page.estimatedProgress)
                }
            }
    }

    private func navigate() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: urlString) {
            _ = page.load(url)
        }
    }
}
