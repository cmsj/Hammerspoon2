//
//  HSUIWebView.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit
import SwiftUI
import WebKit

// MARK: - Navigation Decider (avoids retain cycle WebPage → HSUIWebView)

/// Forwards navigation policy decisions to HSUIWebView without creating a retain cycle.
/// WebPage holds this object strongly; this object holds HSUIWebView weakly.
@available(macOS 26.0, *)
@MainActor
private final class HSUIWebViewNavigationDecider: WebPage.NavigationDeciding {
    weak var owner: HSUIWebView?

    init(owner: HSUIWebView) {
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
/// Not exported to JavaScript — internal rendering model for `UIWebViewContainer`.
@available(macOS 26.0, *)
@MainActor
final class HSUIWebViewToolbarEntry: Identifiable {
    let id = UUID()

    enum Kind {
        case back
        case forward
        case reload
        case url
        case flexibleSpacer
        case custom
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

/// # hs.ui.webview2
///
/// **Create native web browser windows powered by WebPage and WebView**
///
/// Available on macOS 26.0 or later, `hs.ui.webview2` creates standard macOS windows hosting a
/// native SwiftUI `WebView` backed by a `WebPage` instance. It supports navigation, an optional
/// toolbar, JavaScript evaluation, and callbacks for loading, navigation, and title changes.
///
/// ## Requirements
///
/// macOS 26.0 or later. The `hs.ui.webview2()` factory returns `null` on older systems.
///
/// ## Basic Example
///
/// ```javascript
/// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
///     .toolbar(["back", "forward", "reload", "url"])
///     .loadURL("https://apple.com")
///     .show();
/// ```
///
/// ## Custom Toolbar Example
///
/// ```javascript
/// const browser = hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
///     .toolbar([
///         "back", "forward", "reload", "url",
///         {title: "Home", systemImage: "house", callback: () => browser.loadURL("https://apple.com")},
///         {title: "Reload HS",  callback: () => hs.reload()}
///     ])
///     .loadURL("https://apple.com")
///     .show();
/// ```
///
/// ## Full Example
///
/// ```javascript
/// const browser = hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
///     .toolbar(["back", "forward", "reload", "url"])
///     .inspectable(true)
///     .onNavigate((url) => console.log("Navigated to: " + url))
///     .onTitleChange((title) => console.log("Title: " + title))
///     .onLoadChange((loading, url, title, progress) => {
///         if (!loading) console.log("Page ready: " + url)
///     })
///     .loadURL("https://apple.com")
///     .show();
///
/// // Navigate programmatically
/// browser.loadURL("https://google.com");
/// browser.goBack();
/// browser.reload();
/// ```
///
/// ## Navigation Policy Example
///
/// ```javascript
/// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
///     .toolbar(["back", "forward", "reload", "url"])
///     .onNavigationDecision((url) => {
///         return !url.includes("evil.com")
///     })
///     .loadURL("https://apple.com")
///     .show();
/// ```
///
/// ## JavaScript Evaluation Example
///
/// ```javascript
/// const browser = hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
///     .loadURL("https://apple.com")
///     .show();
///
/// // Fire and forget
/// browser.execJS("document.body.style.backgroundColor = 'lightyellow'");
///
/// // With result (note the JS method name is evalJSResult)
/// browser.evalJSResult("document.title", (result, error) => {
///     if (error) { console.log("Error: " + error) }
///     else { console.log("Title: " + result) }
/// });
/// ```
@available(macOS 26.0, *)
@objc protocol HSUIWebViewAPI: HSTypeAPI, JSExport {

    // MARK: Window Management

    /// Show the web browser window
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650}).loadURL("https://apple.com").show()
    /// ```
    @objc func show() -> HSUIWebView

    /// Hide the window without destroying it; page state is preserved
    /// - Example:
    /// ```js
    /// const b = hs.ui.webview2({x: 100, y: 100, w: 900, h: 650}).loadURL("https://apple.com").show()
    /// b.hide()
    /// ```
    @objc func hide()

    /// Close and destroy the window, releasing all resources
    /// - Example:
    /// ```js
    /// const b = hs.ui.webview2({x: 100, y: 100, w: 900, h: 650}).loadURL("https://apple.com").show()
    /// b.close()
    /// ```
    @objc func close()

    // MARK: Navigation

    /// Load a URL in the web view
    /// - Parameter urlString: The URL to load (e.g. "https://apple.com")
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650}).loadURL("https://apple.com").show()
    /// ```
    @objc func loadURL(_ urlString: String) -> HSUIWebView

    /// Load an HTML string directly into the web view
    /// - Parameter html: The HTML content to display
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 500, h: 300})
    ///     .loadHTML("<html><body><h1>Hello from Hammerspoon!</h1></body></html>")
    ///     .show()
    /// ```
    @objc func loadHTML(_ html: String) -> HSUIWebView

    /// Navigate back in the browser history
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// if (browser.canGoBack) browser.goBack()
    /// ```
    @objc func goBack() -> HSUIWebView

    /// Navigate forward in the browser history
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// if (browser.canGoForward) browser.goForward()
    /// ```
    @objc func goForward() -> HSUIWebView

    /// Reload the current page
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.reload()
    /// ```
    @objc func reload() -> HSUIWebView

    /// Stop loading the current page
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.stopLoading()
    /// ```
    @objc func stopLoading() -> HSUIWebView

    // MARK: Configuration

    /// Set a custom User-Agent string for HTTP requests
    ///
    /// Can be called before or after `show()`.
    ///
    /// - Parameter ua: The User-Agent string
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
    ///     .userAgent("MyApp/1.0 AppleWebKit")
    ///     .loadURL("https://example.com")
    ///     .show()
    /// ```
    @objc func userAgent(_ ua: String) -> HSUIWebView

    /// Enable or disable the Safari Web Inspector for this web view
    ///
    /// When enabled, the web view appears in Safari → Develop menu.
    ///
    /// - Parameter value: Pass `true` to enable the Web Inspector
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
    ///     .inspectable(true)
    ///     .loadURL("https://apple.com")
    ///     .show()
    /// ```
    @objc func inspectable(_ value: Bool) -> HSUIWebView

    /// Configure the window toolbar with a list of standard and custom items
    ///
    /// Each element of the array is either a string naming a standard control or a dictionary
    /// describing a custom button. An empty array (or omitting this call) hides the toolbar.
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
    /// - Example:
    /// ```js
    /// hs.ui.webview2({x: 100, y: 100, w: 900, h: 650})
    ///     .toolbar(["back", "forward", "reload", "url",
    ///               {title: "Home", systemImage: "house", callback: () => browser.loadURL("https://apple.com")}])
    ///     .loadURL("https://apple.com")
    ///     .show()
    /// ```
    @objc func toolbar(_ items: [Any]) -> HSUIWebView

    /// Enable or disable the macOS back/forward trackpad swipe gestures
    ///
    /// Gestures are enabled by default. Pass `false` to disable them.
    ///
    /// - Parameter enabled: Pass `false` to disable back/forward swipe gestures
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.backForwardGestures(false)
    /// ```
    @objc func backForwardGestures(_ enabled: Bool) -> HSUIWebView

    /// Enable or disable the trackpad pinch-to-zoom magnification gesture
    ///
    /// The gesture is enabled by default. Pass `false` to disable it.
    ///
    /// - Parameter enabled: Pass `false` to disable pinch-to-zoom
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.magnificationGestures(false)
    /// ```
    @objc func magnificationGestures(_ enabled: Bool) -> HSUIWebView

    /// Enable or disable link preview popovers shown on force-click
    ///
    /// Link previews are enabled by default. Pass `false` to disable them.
    ///
    /// - Parameter enabled: Pass `false` to disable link previews
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.linkPreviews(false)
    /// ```
    @objc func linkPreviews(_ enabled: Bool) -> HSUIWebView

    /// Control whether the web page background is visible
    ///
    /// Pass `false` to make the web view background transparent, allowing the window
    /// background to show through. Enabled (visible) by default.
    ///
    /// - Parameter visible: Pass `false` to hide the web content background
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.contentBackground(false)
    /// ```
    @objc func contentBackground(_ visible: Bool) -> HSUIWebView

    // MARK: Observable State

    /// The URL of the current page, or `null` if no page is loaded
    /// - Example:
    /// ```js
    /// console.log("URL: " + browser.url)
    /// ```
    @objc var url: String? { get }

    /// The title of the current page
    /// - Example:
    /// ```js
    /// console.log("Title: " + browser.title)
    /// ```
    @objc var title: String { get }

    /// Whether the web view is currently loading a page
    /// - Example:
    /// ```js
    /// console.log("Loading: " + browser.isLoading)
    /// ```
    @objc var isLoading: Bool { get }

    /// The estimated loading progress from 0.0 to 1.0
    /// - Example:
    /// ```js
    /// console.log(Math.round(browser.estimatedProgress * 100) + "%")
    /// ```
    @objc var estimatedProgress: Double { get }

    /// Whether the web view can navigate back in history
    /// - Example:
    /// ```js
    /// if (browser.canGoBack) browser.goBack()
    /// ```
    @objc var canGoBack: Bool { get }

    /// Whether the web view can navigate forward in history
    /// - Example:
    /// ```js
    /// if (browser.canGoForward) browser.goForward()
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
    /// browser.onLoadChange((loading, url, title, progress) => {
    ///     if (!loading) console.log("Finished loading: " + url)
    /// })
    /// ```
    @objc func onLoadChange(_ callback: JSFunction) -> HSUIWebView

    /// Register a callback that fires when navigation to a new page completes
    ///
    /// - Parameter callback: {(url: string) => void} Called with the final URL
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.onNavigate((url) => console.log("Navigated to: " + url))
    /// ```
    @objc func onNavigate(_ callback: JSFunction) -> HSUIWebView

    /// Register a callback that fires when the page title changes
    ///
    /// - Parameter callback: {(title: string) => void} Called with the new title
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.onTitleChange((title) => console.log("New title: " + title))
    /// ```
    @objc func onTitleChange(_ callback: JSFunction) -> HSUIWebView

    /// Register a callback that controls whether navigation is allowed
    ///
    /// Called before each navigation. Return `true` to allow or `false` to block.
    ///
    /// - Parameter callback: {(url: string) => boolean} Return `true` to allow, `false` to block
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.onNavigationDecision((url) => {
    ///     return !url.startsWith("file://")
    /// })
    /// ```
    @objc func onNavigationDecision(_ callback: JSFunction) -> HSUIWebView

    // MARK: JavaScript Execution

    /// Execute JavaScript in the web page without capturing the result
    /// - Parameter script: The JavaScript code to execute
    /// - Returns: Self for chaining
    /// - Example:
    /// ```js
    /// browser.execJS("document.body.style.backgroundColor = 'lightyellow'")
    /// ```
    @objc func execJS(_ script: String) -> HSUIWebView

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
    /// browser.evalJSResult("document.title", (result, error) => {
    ///     if (error) { console.log("Error: " + error) }
    ///     else { console.log("Title: " + result) }
    /// })
    /// ```
    @objc(evalJS:result:)
    func evalJSResult(_ script: String, _ callback: JSFunction) -> HSUIWebView
}

// MARK: - Implementation

@available(macOS 26.0, *)
@_documentation(visibility: private)
@MainActor
@objc class HSUIWebView: NSObject, HSUIWebViewAPI, NSWindowDelegate {
    @objc var typeName = "HSUIWebView"

    // MARK: Private State

    private var page: WebPage!
    private var navigationDecider: HSUIWebViewNavigationDecider!
    private var nsWindow: NSWindow?
    private let windowFrame: CGRect
    private let windowID: UUID = UUID()
    private weak var module: HSUIModule?

    // Configuration
    private var customUserAgentString: String?
    private var isInspectableValue: Bool = false
    private var toolbarEntries: [HSUIWebViewToolbarEntry] = []
    private var allowsBackForwardGesturesValue: Bool = true
    private var allowsMagnificationGesturesValue: Bool = true
    private var allowsLinkPreviewsValue: Bool = true
    private var showsContentBackground: Bool = true

    // Callbacks
    var navigationDecisionCallback: JSCallback?
    private var onLoadChangeCallback: JSCallback?
    private var onNavigateCallback: JSCallback?
    private var onTitleChangeCallback: JSCallback?

    // Observation tasks
    private var navigationEventTask: Task<Void, Never>?
    private var stateObservationTask: Task<Void, Never>?

    // MARK: Init

    init(frame: CGRect, module: HSUIModule) {
        self.windowFrame = frame
        self.module = module
        super.init()
        self.navigationDecider = HSUIWebViewNavigationDecider(owner: self)
        self.page = WebPage(navigationDecider: self.navigationDecider)
    }

    convenience init(dict: [String: Any], module: HSUIModule) {
        let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
        let w = (dict["w"] as? NSNumber)?.doubleValue ?? 800
        let h = (dict["h"] as? NSNumber)?.doubleValue ?? 600
        self.init(frame: CGRect(x: x, y: y, width: w, height: h), module: module)
    }

    isolated deinit {
        close()
        AKDebug("deinit of HSUIWebView: \(windowID)")
    }

    // MARK: Window Management

    @objc func show() -> HSUIWebView {
        guard nsWindow == nil else {
            nsWindow?.makeKeyAndOrderFront(nil)
            return self
        }

        page.customUserAgent = customUserAgentString
        page.isInspectable = isInspectableValue

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let currentTitle = page.title
        window.title = currentTitle.isEmpty ? "Web Browser" : currentTitle
        window.isReleasedWhenClosed = false
        window.delegate = self

        let config = UIWebViewConfiguration(
            toolbarEntries: toolbarEntries,
            allowsBackForwardGestures: allowsBackForwardGesturesValue,
            allowsMagnificationGestures: allowsMagnificationGesturesValue,
            allowsLinkPreviews: allowsLinkPreviewsValue,
            showsContentBackground: showsContentBackground
        )
        let contentView = UIWebViewContainer(page: page, configuration: config)
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        self.nsWindow = window

        startObservation()
        module?.register(self, id: windowID)

        return self
    }

    @objc func hide() {
        nsWindow?.orderOut(nil)
    }

    @objc func close() {
        guard nsWindow != nil || page != nil else { return }

        // Cancel observation (no more JS callbacks after close)
        navigationEventTask?.cancel()
        navigationEventTask = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil

        // Detach callbacks — releases JSValues holding the old JSContext
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

        module?.unregister(webview: windowID)

        nsWindow?.delegate = nil
        nsWindow?.close()
        nsWindow = nil
    }

    // MARK: NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.close()
        }
    }

    // MARK: Observation

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
                            let t = self.page.title
                            if !t.isEmpty { self.nsWindow?.title = t }
                        }
                    }
                    return // sequence ended normally (page likely closed)
                } catch let navErr as WebPage.NavigationError {
                    switch navErr {
                    case .pageClosed, .webContentProcessTerminated:
                        return
                    case .failedProvisionalNavigation, .invalidURL:
                        break // transient — restart watching
                    @unknown default:
                        return
                    }
                } catch {
                    return // unknown error — stop
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
                // Wait until any tracked observable property changes
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
                    if !title.isEmpty { self.nsWindow?.title = title }
                }
            }
        }
    }

    // MARK: Navigation

    @objc func loadURL(_ urlString: String) -> HSUIWebView {
        guard let url = URL(string: urlString) else {
            AKError("hs.ui.webview2: Invalid URL: \(urlString)")
            return self
        }
        _ = page.load(url)
        return self
    }

    @objc func loadHTML(_ html: String) -> HSUIWebView {
        _ = page.load(html: html)
        return self
    }

    @objc func goBack() -> HSUIWebView {
        if let item = page.backForwardList.backList.last {
            _ = page.load(item)
        }
        return self
    }

    @objc func goForward() -> HSUIWebView {
        if let item = page.backForwardList.forwardList.first {
            _ = page.load(item)
        }
        return self
    }

    @objc func reload() -> HSUIWebView {
        _ = page.reload()
        return self
    }

    @objc func stopLoading() -> HSUIWebView {
        page.stopLoading()
        return self
    }

    // MARK: Configuration

    @objc func userAgent(_ ua: String) -> HSUIWebView {
        customUserAgentString = ua
        page?.customUserAgent = ua
        return self
    }

    @objc func inspectable(_ value: Bool) -> HSUIWebView {
        isInspectableValue = value
        page?.isInspectable = value
        return self
    }

    @objc func toolbar(_ items: [Any]) -> HSUIWebView {
        for entry in toolbarEntries { entry.detachCallback(from: self) }
        toolbarEntries = items.compactMap { item in
            if let str = item as? String {
                switch str {
                case "back":    return HSUIWebViewToolbarEntry(kind: .back)
                case "forward": return HSUIWebViewToolbarEntry(kind: .forward)
                case "reload":  return HSUIWebViewToolbarEntry(kind: .reload)
                case "url":     return HSUIWebViewToolbarEntry(kind: .url)
                case "spacer", "flexibleSpacer":
                    return HSUIWebViewToolbarEntry(kind: .flexibleSpacer)
                default:
                    AKWarning("hs.ui.webview2.toolbar: unknown standard item '\(str)'")
                    return nil
                }
            } else if let dict = item as? [String: Any] {
                guard let cbValue = dict["callback"] as? JSFunction else {
                    AKWarning("hs.ui.webview2.toolbar: custom button dict missing 'callback' key")
                    return nil
                }
                let cb = JSCallback(value: cbValue, owner: self)
                return HSUIWebViewToolbarEntry(
                    kind: .custom,
                    label: dict["title"] as? String,
                    systemImage: dict["systemImage"] as? String,
                    callback: cb
                )
            }
            AKWarning("hs.ui.webview2.toolbar: unrecognised item type \(type(of: item))")
            return nil
        }
        return self
    }

    @objc func backForwardGestures(_ enabled: Bool) -> HSUIWebView {
        allowsBackForwardGesturesValue = enabled
        return self
    }

    @objc func magnificationGestures(_ enabled: Bool) -> HSUIWebView {
        allowsMagnificationGesturesValue = enabled
        return self
    }

    @objc func linkPreviews(_ enabled: Bool) -> HSUIWebView {
        allowsLinkPreviewsValue = enabled
        return self
    }

    @objc func contentBackground(_ visible: Bool) -> HSUIWebView {
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

    @objc func onLoadChange(_ callback: JSFunction) -> HSUIWebView {
        onLoadChangeCallback?.detach(from: self)
        onLoadChangeCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onNavigate(_ callback: JSFunction) -> HSUIWebView {
        onNavigateCallback?.detach(from: self)
        onNavigateCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onTitleChange(_ callback: JSFunction) -> HSUIWebView {
        onTitleChangeCallback?.detach(from: self)
        onTitleChangeCallback = JSCallback(value: callback, owner: self)
        return self
    }

    @objc func onNavigationDecision(_ callback: JSFunction) -> HSUIWebView {
        navigationDecisionCallback?.detach(from: self)
        navigationDecisionCallback = JSCallback(value: callback, owner: self)
        return self
    }

    // MARK: JavaScript Execution

    @objc func execJS(_ script: String) -> HSUIWebView {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.page.callJavaScript(script, arguments: [:])
            } catch {
                AKError("hs.ui.webview2.execJS: \(error.localizedDescription)")
            }
        }
        return self
    }

    @objc(evalJS:result:)
    func evalJSResult(_ script: String, _ callback: JSFunction) -> HSUIWebView {
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
}
