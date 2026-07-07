//
//  UIWebView.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import SwiftUI
import WebKit
import _WebKit_SwiftUI

// MARK: - Navigation Decider

/// Forwards navigation policy decisions to UIWebView without creating a retain cycle.
/// WebPage holds this object strongly; this object holds UIWebView weakly.
@available(macOS 26.0, *)
@MainActor
private final class UIWebViewNavigationDecider: WebPage.NavigationDeciding {
    weak var owner: UIWebView?

    init(owner: UIWebView) {
        self.owner = owner
    }

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let cb = owner?.navigationDecisionCallback else { return .allow }
        let url = action.request.url?.absoluteString ?? ""
        let result = cb.call(withArguments: [url])
        return (result?.toBool() == true) ? .allow : .cancel
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        .allow
    }

    func decideAuthenticationChallengeDisposition(
        for challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }
}

// MARK: - Toolbar Entry Model

/// A single configured toolbar item produced by parsing the JS `toolbar([...])` call.
/// Not exported to JavaScript — internal rendering model for `UIWebViewElementView`.
@available(macOS 26.0, *)
@MainActor
final class UIWebViewToolbarEntry: Identifiable {
    let id = UUID()

    enum Kind {
        case back, forward, reload, url, flexibleSpacer, custom
    }

    let kind: Kind
    let label: String?
    let systemImage: String?
    private(set) var callback: JSCallback?

    init(kind: Kind, label: String? = nil, systemImage: String? = nil, callback: JSCallback? = nil) {
        self.kind = kind
        self.label = label
        self.systemImage = systemImage
        self.callback = callback
    }

    func detachCallback(from owner: AnyObject) {
        callback?.detach(from: owner)
        callback = nil
    }
}

// MARK: - JavaScript API Protocol

/// # hs.ui.webview
///
/// **A web browser element for embedding in `hs.ui.window` layouts**
///
/// Available on macOS 26.0 or later, `hs.ui.webview()` creates a web browser element backed
/// by a SwiftUI `WebView` and `WebPage`. Embed it in any `hs.ui.window` using
/// `.webview(element)` — it fills the available space and can sit alongside other elements in
/// stacks.
///
/// Create the element first, configure it, then embed it into a window:
///
/// ```javascript
/// const wv = hs.ui.webview()
///     .toolbar(["back", "forward", "reload", "url"])
///     .loadURL("https://apple.com")
///
/// hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
///     .titled(true)
///     .closable(true)
///     .allowResize(true)
///     .level("normal")
///     .webview(wv)
///     .show()
/// ```
///
/// Because `wv` is a regular JavaScript object you can keep a reference and call navigation
/// methods on it at any time after the window is shown:
///
/// ```javascript
/// wv.loadURL("https://google.com")
/// wv.goBack()
/// ```
///
/// ## Custom Toolbar Example
///
/// ```javascript
/// const wv = hs.ui.webview()
///     .toolbar([
///         "back", "forward", "reload", "url",
///         {title: "Home", systemImage: "house", callback: () => wv.loadURL("https://apple.com")},
///         {title: "Reload HS", callback: () => hs.reload()}
///     ])
///     .loadURL("https://apple.com")
///
/// hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
///     .webview(wv)
///     .show()
/// ```
///
/// ## Full Example with Callbacks
///
/// ```javascript
/// const wv = hs.ui.webview()
///     .toolbar(["back", "forward", "reload", "url"])
///     .inspectable(true)
///     .onNavigate((url) => console.log("Navigated to: " + url))
///     .onTitleChange((title) => console.log("Title: " + title))
///     .onLoadChange((loading, url, title, progress) => {
///         if (!loading) console.log("Page ready: " + url)
///     })
///     .loadURL("https://apple.com")
///
/// hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
///     .webview(wv)
///     .show()
/// ```
///
/// ## Navigation Policy Example
///
/// ```javascript
/// const wv = hs.ui.webview()
///     .toolbar(["back", "forward", "reload", "url"])
///     .onNavigationDecision((url) => {
///         return !url.includes("evil.com")
///     })
///     .loadURL("https://apple.com")
///
/// hs.ui.window({x: 100, y: 100, w: 1024, h: 768})
///     .webview(wv)
///     .show()
/// ```
///
/// ## JavaScript Evaluation Example
///
/// ```javascript
/// const wv = hs.ui.webview().loadURL("https://apple.com")
/// hs.ui.window({x: 100, y: 100, w: 1024, h: 768}).webview(wv).show()
///
/// // Fire and forget
/// wv.execJS("document.body.style.backgroundColor = 'lightyellow'")
///
/// // With result (note the JS method name is evalJSResult)
/// wv.evalJSResult("document.title", (result, error) => {
///     if (error) { console.log("Error: " + error) }
///     else { console.log("Title: " + result) }
/// })
/// ```
@available(macOS 26.0, *)
@objc protocol UIWebViewAPI: HSTypeAPI, JSExport {

    // MARK: Navigation

    /// Load a URL in the web view
    /// - Parameter urlString: The URL to load (e.g. "https://apple.com")
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview().loadURL("https://apple.com")
    /// ```
    @objc func loadURL(_ urlString: String) -> UIWebView

    /// Load an HTML string directly into the web view
    /// - Parameter html: The HTML content to display
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview().loadHTML("<html><body><h1>Hello from Hammerspoon!</h1></body></html>")
    /// ```
    @objc func loadHTML(_ html: String) -> UIWebView

    /// Navigate back in the browser history
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// if (wv.canGoBack) wv.goBack()
    /// ```
    @objc func goBack() -> UIWebView

    /// Navigate forward in the browser history
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// if (wv.canGoForward) wv.goForward()
    /// ```
    @objc func goForward() -> UIWebView

    /// Reload the current page
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.reload()
    /// ```
    @objc func reload() -> UIWebView

    /// Stop loading the current page
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.stopLoading()
    /// ```
    @objc func stopLoading() -> UIWebView

    // MARK: Configuration

    /// Set a custom User-Agent string for HTTP requests
    /// - Parameter ua: The User-Agent string
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview().userAgent("MyApp/1.0 AppleWebKit")
    /// ```
    @objc func userAgent(_ ua: String) -> UIWebView

    /// Enable or disable the Safari Web Inspector for this web view
    ///
    /// When enabled, the web view appears in Safari → Develop menu.
    ///
    /// - Parameter value: Pass `true` to enable the Web Inspector
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview().inspectable(true)
    /// ```
    @objc func inspectable(_ value: Bool) -> UIWebView

    /// Configure the toolbar with a list of standard and custom items
    ///
    /// The toolbar renders above the web view. Each element of the array is either a string
    /// naming a standard control or a dictionary describing a custom button.
    /// An empty array (or omitting this call) hides the toolbar.
    ///
    /// Standard string items: `"back"`, `"forward"`, `"reload"`, `"url"`, `"spacer"`.
    ///
    /// Custom button dictionaries accept:
    /// - `title` (string, optional) — button label
    /// - `systemImage` (string, optional) — SF Symbol name (e.g. `"house"`)
    /// - `callback` (function, required) — called when the button is clicked
    ///
    /// - Parameter items: {Array<string | {title?: string, systemImage?: string, callback: () => void}>} Toolbar items in display order
    /// - Returns: Self for chaining
    /// - Note: The toolbar will not be shown if the web view is in a borderless window
    /// - Example:
    /// ```js
    /// hs.ui.webview()
    ///     .toolbar(["back", "forward", "reload", "url",
    ///               {title: "Home", systemImage: "house", callback: () => wv.loadURL("https://apple.com")}])
    /// ```
    @objc func toolbar(_ items: JSValue) -> UIWebView

    /// Enable or disable the macOS back/forward trackpad swipe gestures
    ///
    /// Gestures are enabled by default. Pass `false` to disable them.
    ///
    /// - Parameter enabled: Pass `false` to disable back/forward swipe gestures
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.backForwardGestures(false)
    /// ```
    @objc func backForwardGestures(_ enabled: Bool) -> UIWebView

    /// Enable or disable the trackpad pinch-to-zoom magnification gesture
    ///
    /// The gesture is enabled by default. Pass `false` to disable it.
    ///
    /// - Parameter enabled: Pass `false` to disable pinch-to-zoom
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.magnificationGestures(false)
    /// ```
    @objc func magnificationGestures(_ enabled: Bool) -> UIWebView

    /// Enable or disable link preview popovers shown on force-click
    ///
    /// Link previews are enabled by default. Pass `false` to disable them.
    ///
    /// - Parameter enabled: Pass `false` to disable link previews
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.linkPreviews(false)
    /// ```
    @objc func linkPreviews(_ enabled: Bool) -> UIWebView

    /// Control whether the web page background is visible
    ///
    /// Pass `false` to make the web view background transparent. Enabled (visible) by default.
    ///
    /// - Parameter visible: Pass `false` to hide the web content background
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.contentBackground(false)
    /// ```
    @objc func contentBackground(_ visible: Bool) -> UIWebView

    // MARK: Observable State

    /// The URL of the current page, or `null` if no page is loaded
    /// - Example:
    /// ```js
    /// console.log("URL: " + wv.url)
    /// ```
    @objc var url: String? { get }

    /// The title of the current page
    /// - Example:
    /// ```js
    /// console.log("Title: " + wv.title)
    /// ```
    @objc var title: String { get }

    /// Whether the web view is currently loading a page
    /// - Example:
    /// ```js
    /// console.log("Loading: " + wv.isLoading)
    /// ```
    @objc var isLoading: Bool { get }

    /// The estimated loading progress from 0.0 to 1.0
    /// - Example:
    /// ```js
    /// console.log(Math.round(wv.estimatedProgress * 100) + "%")
    /// ```
    @objc var estimatedProgress: Double { get }

    /// Whether the web view can navigate back in history
    /// - Example:
    /// ```js
    /// if (wv.canGoBack) wv.goBack()
    /// ```
    @objc var canGoBack: Bool { get }

    /// Whether the web view can navigate forward in history
    /// - Example:
    /// ```js
    /// if (wv.canGoForward) wv.goForward()
    /// ```
    @objc var canGoForward: Bool { get }

    // MARK: Callbacks

    /// Register a callback that fires when loading state or progress changes
    ///
    /// Called whenever `isLoading`, `url`, `title`, or `estimatedProgress` changes.
    ///
    /// - Parameter callback: {(isLoading: boolean, url: string | null, title: string, progress: number) => void} Called with current loading state
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.onLoadChange((loading, url, title, progress) => {
    ///     if (!loading) console.log("Finished loading: " + url)
    /// })
    /// ```
    @objc func onLoadChange(_ callback: JSFunction) -> UIWebView

    /// Register a callback that fires when navigation to a new page completes
    ///
    /// - Parameter callback: {(url: string) => void} Called with the final URL
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.onNavigate((url) => console.log("Navigated to: " + url))
    /// ```
    @objc func onNavigate(_ callback: JSFunction) -> UIWebView

    /// Register a callback that fires when the page title changes
    ///
    /// - Parameter callback: {(title: string) => void} Called with the new title
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.onTitleChange((title) => console.log("New title: " + title))
    /// ```
    @objc func onTitleChange(_ callback: JSFunction) -> UIWebView

    /// Register a callback that controls whether navigation is allowed
    ///
    /// Called before each navigation. Return `true` to allow or `false` to block.
    ///
    /// - Parameter callback: {(url: string) => boolean} Return `true` to allow, `false` to block
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.onNavigationDecision((url) => {
    ///     return !url.startsWith("file://")
    /// })
    /// ```
    @objc func onNavigationDecision(_ callback: JSFunction) -> UIWebView

    // MARK: JavaScript Execution

    /// Execute JavaScript in the web page without capturing the result
    /// - Parameter script: The JavaScript code to execute
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.execJS("document.body.style.backgroundColor = 'lightyellow'")
    /// ```
    @objc func execJS(_ script: String) -> UIWebView

    /// Execute JavaScript in the web page and deliver the result to a callback
    ///
    /// The JavaScript method name is `evalJSResult` — it derives from the internal
    /// Objective-C selector `evalJS:result:`.
    ///
    /// - Parameter script: The JavaScript expression to evaluate
    /// - Parameter callback: {(result: any, error: string | null) => void} Called with the result or an error message
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// wv.evalJSResult("document.title", (result, error) => {
    ///     if (error) { console.log("Error: " + error) }
    ///     else { console.log("Title: " + result) }
    /// })
    /// ```
    @objc(evalJS:result:)
    func evalJSResult(_ script: String, _ callback: JSFunction) -> UIWebView
}

// MARK: - Implementation

@available(macOS 26.0, *)
@_documentation(visibility: private)
@MainActor
@objc class UIWebView: NSObject, UIWebViewAPI, HSUIElement {
    @objc var typeName = "UIWebView"

    // MARK: Internal State
    // (internal access level so the private SwiftUI views below can read them)

    var page: WebPage!
    private var navigationDecider: UIWebViewNavigationDecider!

    private var customUserAgentString: String?
    private var isInspectableValue: Bool = false
    var toolbarEntries: [UIWebViewToolbarEntry] = []
    var allowsBackForwardGesturesValue: Bool = true
    var allowsMagnificationGesturesValue: Bool = true
    var allowsLinkPreviewsValue: Bool = true
    var showsContentBackground: Bool = true

    // Callbacks
    var navigationDecisionCallback: JSCallback?
    private var onLoadChangeCallback: JSCallback?
    private var onNavigateCallback: JSCallback?
    private var onTitleChangeCallback: JSCallback?

    // Observation tasks start at init and cancel when destroy() is called
    private var navigationEventTask: Task<Void, Never>?
    private var stateObservationTask: Task<Void, Never>?

    // MARK: Init

    override init() {
        super.init()
        self.navigationDecider = UIWebViewNavigationDecider(owner: self)
        self.page = WebPage(navigationDecider: self.navigationDecider)
        startObservation()
        AKDebug("Init of UIWebView")
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of UIWebView")
    }

    // MARK: HSUIElement

    func toSwiftUI(containerSize: CGSize) -> AnyView {
        AnyView(UIWebViewElementView(element: self))
    }

    // MARK: Destroy
    // Called by HSUIWindow.close() to eagerly release JS resources before the element
    // tree is released. Also called from isolated deinit as a safety net.

    func destroy() {
        navigationEventTask?.cancel()
        navigationEventTask = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil

        onLoadChangeCallback?.detach(from: self)
        onLoadChangeCallback = nil
        onNavigateCallback?.detach(from: self)
        onNavigateCallback = nil
        onTitleChangeCallback?.detach(from: self)
        onTitleChangeCallback = nil
        navigationDecisionCallback?.detach(from: self)
        navigationDecisionCallback = nil
        for entry in toolbarEntries { entry.detachCallback(from: self) }
        toolbarEntries.removeAll()
    }

    // MARK: Navigation

    @objc func loadURL(_ urlString: String) -> UIWebView {
        guard let url = URL(string: urlString) else {
            AKError("hs.ui.webview: Invalid URL: \(urlString)")
            return self
        }
        _ = page.load(url)
        return self
    }

    @objc func loadHTML(_ html: String) -> UIWebView {
        _ = page.load(html: html)
        return self
    }

    @objc func goBack() -> UIWebView {
        if let item = page.backForwardList.backList.last { _ = page.load(item) }
        return self
    }

    @objc func goForward() -> UIWebView {
        if let item = page.backForwardList.forwardList.first { _ = page.load(item) }
        return self
    }

    @objc func reload() -> UIWebView {
        _ = page.reload()
        return self
    }

    @objc func stopLoading() -> UIWebView {
        page.stopLoading()
        return self
    }

    // MARK: Configuration

    @objc func userAgent(_ ua: String) -> UIWebView {
        customUserAgentString = ua
        page?.customUserAgent = ua
        return self
    }

    @objc func inspectable(_ value: Bool) -> UIWebView {
        isInspectableValue = value
        page?.isInspectable = value
        return self
    }

    @objc func toolbar(_ items: JSValue) -> UIWebView {
        for entry in toolbarEntries { entry.detachCallback(from: self) }
        toolbarEntries.removeAll()

        guard items.isArray else {
            AKError("hs.ui.webview.toolbar: expected an array")
            return self
        }

        let count = items.objectForKeyedSubscript("length").toInt32()
        for i in 0..<count {
            guard let item = items.atIndex(Int(i)) else { continue }
            if item.isString, let str = item.toString() {
                switch str {
                case "back":    toolbarEntries.append(UIWebViewToolbarEntry(kind: .back))
                case "forward": toolbarEntries.append(UIWebViewToolbarEntry(kind: .forward))
                case "reload":  toolbarEntries.append(UIWebViewToolbarEntry(kind: .reload))
                case "url":     toolbarEntries.append(UIWebViewToolbarEntry(kind: .url))
                case "spacer", "flexibleSpacer":
                    toolbarEntries.append(UIWebViewToolbarEntry(kind: .flexibleSpacer))
                default:
                    AKWarning("hs.ui.webview.toolbar: unknown standard item '\(str)'")
                }
            } else if item.isObject {
                let cbValue = item.objectForKeyedSubscript("callback")
                guard let cbValue, !cbValue.isUndefined, !cbValue.isNull, cbValue.isObject else {
                    AKWarning("hs.ui.webview.toolbar: custom button missing 'callback' function")
                    continue
                }
                let cb = JSCallback(value: cbValue, owner: self)
                let titleVal = item.objectForKeyedSubscript("title")
                let sysImgVal = item.objectForKeyedSubscript("systemImage")
                toolbarEntries.append(UIWebViewToolbarEntry(
                    kind: .custom,
                    label: (titleVal?.isString == true) ? titleVal?.toString() : nil,
                    systemImage: (sysImgVal?.isString == true) ? sysImgVal?.toString() : nil,
                    callback: cb
                ))
            } else {
                AKWarning("hs.ui.webview.toolbar: unrecognised item type, skipping")
            }
        }
        return self
    }

    @objc func backForwardGestures(_ enabled: Bool) -> UIWebView {
        allowsBackForwardGesturesValue = enabled
        return self
    }

    @objc func magnificationGestures(_ enabled: Bool) -> UIWebView {
        allowsMagnificationGesturesValue = enabled
        return self
    }

    @objc func linkPreviews(_ enabled: Bool) -> UIWebView {
        allowsLinkPreviewsValue = enabled
        return self
    }

    @objc func contentBackground(_ visible: Bool) -> UIWebView {
        showsContentBackground = visible
        return self
    }

    // MARK: Observable State

    @objc var url: String? { page?.url?.absoluteString }
    @objc var title: String { page?.title ?? "" }
    @objc var isLoading: Bool { page?.isLoading ?? false }
    @objc var estimatedProgress: Double { page?.estimatedProgress ?? 0 }
    @objc var canGoBack: Bool { !(page?.backForwardList.backList.isEmpty ?? true) }
    @objc var canGoForward: Bool { !(page?.backForwardList.forwardList.isEmpty ?? true) }

    // MARK: Callbacks

    @objc func onLoadChange(_ callback: JSFunction) -> UIWebView {
        onLoadChangeCallback?.detach(from: self)
        onLoadChangeCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onNavigate(_ callback: JSFunction) -> UIWebView {
        onNavigateCallback?.detach(from: self)
        onNavigateCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onTitleChange(_ callback: JSFunction) -> UIWebView {
        onTitleChangeCallback?.detach(from: self)
        onTitleChangeCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onNavigationDecision(_ callback: JSFunction) -> UIWebView {
        navigationDecisionCallback?.detach(from: self)
        navigationDecisionCallback = JSCallback(value: callback, owner: self)
        return self
    }

    // MARK: JavaScript Execution

    @objc func execJS(_ script: String) -> UIWebView {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.page.callJavaScript(script, arguments: [:])
            } catch {
                AKError("hs.ui.webview.execJS: \(error.localizedDescription)")
            }
        }
        return self
    }

    @objc(evalJS:result:)
    func evalJSResult(_ script: String, _ callback: JSFunction) -> UIWebView {
        guard let capturedCallback = JSCallback(value: callback, owner: self) else {
            return self
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { capturedCallback.detach(from: self) }
            do {
                let result = try await self.page.callJavaScript(script, arguments: [:])
                _ = capturedCallback.call(withArguments: [result as Any, NSNull()])
            } catch {
                _ = capturedCallback.call(withArguments: [NSNull(), error.localizedDescription])
            }
        }
        return self
    }

    // MARK: Private Observation

    private func startObservation() {
        startNavigationEventObservation()
        startStateObservation()
    }

    private func startNavigationEventObservation() {
        navigationEventTask?.cancel()
        navigationEventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    for try await event in self.page.navigations {
                        if Task.isCancelled { return }
                        if event == .finished {
                            let url = self.page.url?.absoluteString ?? ""
                            _ = self.onNavigateCallback?.call(withArguments: [url])
                        }
                    }
                    return
                } catch let navErr as WebPage.NavigationError {
                    switch navErr {
                    case .pageClosed, .webContentProcessTerminated: return
                    case .failedProvisionalNavigation, .invalidURL: break
                    @unknown default: return
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func startStateObservation() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastTitle = ""
            while !Task.isCancelled {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.page.isLoading
                        _ = self.page.url
                        _ = self.page.title
                        _ = self.page.estimatedProgress
                    } onChange: {
                        cont.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                let isLoading = self.page.isLoading
                let url = self.page.url?.absoluteString as Any
                let title = self.page.title
                let progress = self.page.estimatedProgress
                _ = self.onLoadChangeCallback?.call(withArguments: [isLoading, url, title, progress])
                if title != lastTitle {
                    lastTitle = title
                    _ = self.onTitleChangeCallback?.call(withArguments: [title])
                }
            }
        }
    }
}

// MARK: - SwiftUI Views

/// Root view for a UIWebView element. Toolbar entries are surfaced via the native
/// macOS toolbar (`.toolbar {}` modifier), which requires a titled window.
@available(macOS 26.0, *)
private struct UIWebViewElementView: View {
    let element: UIWebView

    var body: some View {
        WebView(element.page)
            .webViewBackForwardNavigationGestures(
                element.allowsBackForwardGesturesValue ? .enabled : .disabled
            )
            .webViewMagnificationGestures(
                element.allowsMagnificationGesturesValue ? .enabled : .disabled
            )
            .webViewLinkPreviews(
                element.allowsLinkPreviewsValue ? .enabled : .disabled
            )
            .webViewContentBackground(
                element.showsContentBackground ? .visible : .hidden
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup {
                    ForEach(element.toolbarEntries) { entry in
                        UIWebViewToolbarEntryView(entry: entry, page: element.page)
                    }
                }
            }
    }
}

/// Renders a single toolbar entry as a SwiftUI view within a native macOS toolbar.
@available(macOS 26.0, *)
private struct UIWebViewToolbarEntryView: View {
    let entry: UIWebViewToolbarEntry
    let page: WebPage

    var body: some View {
        switch entry.kind {
        case .back:
            Button {
                if let item = page.backForwardList.backList.last { _ = page.load(item) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page.backForwardList.backList.isEmpty)
            .help("Go Back")
            .accessibilityLabel("Go Back")

        case .forward:
            Button {
                if let item = page.backForwardList.forwardList.first { _ = page.load(item) }
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
                if let img = entry.systemImage, let label = entry.label {
                    Label(label, systemImage: img)
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
                if !isFocused { urlText = newURL?.absoluteString ?? "" }
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
        guard let url = URL(string: urlString) else {
            AKWarning("UIWebView: could not form a valid URL from: \(urlString)")
            return
        }
        _ = page.load(url)
    }
}
