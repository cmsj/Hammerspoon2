//
//  HSUIWebViewTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
import AppKit
import WebKit
@testable import Hammerspoon_2

// Note: hs.ui.webview requires macOS 26.0. Tests are written using the JS harness
// exclusively (no direct UIWebView Swift references) so they compile against the
// 15.6 test target. On macOS < 26 the 'webview' method will be absent and the
// tests that check its existence will fail — but this project only runs on macOS 26+.

/// Used to skip tests that only crash inside GitHub's virtualized macOS runner (see
/// MemoryLeakTests below) while still running them locally. Must be `nonisolated` —
/// `.disabled(if:)` trait expressions are evaluated outside any actor.
///
/// Note: `xcodebuild test` does NOT forward the invoking shell's environment into the
/// test host process — confirmed directly (a plain `CI=true xcodebuild test` leaves
/// `ProcessInfo.processInfo.environment` empty of `CI` inside the test). Only vars
/// prefixed `TEST_RUNNER_` are passed through, with the prefix stripped. The CI
/// workflow (`.github/workflows/test.yml`) sets `TEST_RUNNER_CI=true` for exactly
/// this reason — GitHub Actions' own `CI=true` alone would never reach this check.
private nonisolated func isRunningInCI() -> Bool {
    ProcessInfo.processInfo.environment["CI"] != nil
}

@Suite("hs.ui.webview tests")
struct HSUIWebViewTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSUIModule.self, as: "ui")
        return harness
    }

    // MARK: - API Structure

    @Suite("API structure")
    struct APIStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("webview is a function on hs.ui")
        func testWebviewIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview") == "function")
        }

        @Test("webview() returns a non-null object")
        func testWebviewReturnsObject() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("typeof wv === 'object' && wv !== null")
            #expect(!harness.hasException)
        }

        @Test("typeName is UIWebView")
        func testTypeName() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectEqual("wv.typeName", "UIWebView")
        }

        @Test("loadURL is a function")
        func testLoadURLIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().loadURL") == "function")
        }

        @Test("loadHTML is a function")
        func testLoadHTMLIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().loadHTML") == "function")
        }

        @Test("goBack is a function")
        func testGoBackIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().goBack") == "function")
        }

        @Test("goForward is a function")
        func testGoForwardIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().goForward") == "function")
        }

        @Test("reload is a function")
        func testReloadIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().reload") == "function")
        }

        @Test("stopLoading is a function")
        func testStopLoadingIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().stopLoading") == "function")
        }

        @Test("userAgent is a function")
        func testUserAgentIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().userAgent") == "function")
        }

        @Test("inspectable is a function")
        func testInspectableIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().inspectable") == "function")
        }

        @Test("toolbar is a function")
        func testToolbarIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().toolbar") == "function")
        }

        @Test("backForwardGestures is a function")
        func testBackForwardGesturesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().backForwardGestures") == "function")
        }

        @Test("magnificationGestures is a function")
        func testMagnificationGesturesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().magnificationGestures") == "function")
        }

        @Test("linkPreviews is a function")
        func testLinkPreviewsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().linkPreviews") == "function")
        }

        @Test("contentBackground is a function")
        func testContentBackgroundIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().contentBackground") == "function")
        }

        @Test("onLoadChange is a function")
        func testOnLoadChangeIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().onLoadChange") == "function")
        }

        @Test("onNavigate is a function")
        func testOnNavigateIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().onNavigate") == "function")
        }

        @Test("onTitleChange is a function")
        func testOnTitleChangeIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().onTitleChange") == "function")
        }

        @Test("onNavigationDecision is a function")
        func testOnNavigationDecisionIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().onNavigationDecision") == "function")
        }

        @Test("onMessage is a function")
        func testOnMessageIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().onMessage") == "function")
        }

        @Test("removeMessageHandler is a function")
        func testRemoveMessageHandlerIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().removeMessageHandler") == "function")
        }

        @Test("execJS is a function")
        func testExecJSIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().execJS") == "function")
        }

        @Test("evalJSResult is a function")
        func testEvalJSResultIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.ui.webview().evalJSResult") == "function")
        }

        @Test("window has a webview method for embedding")
        func testWindowHasWebviewMethod() {
            #expect(makeHarness().evalTypeOf("hs.ui.window({x:0,y:0,w:100,h:100}).webview") == "function")
        }
    }

    // MARK: - Default State

    @Suite("Default state")
    struct DefaultStateTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("url defaults to null")
        func testURLDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.url === null || wv.url === undefined")
        }

        @Test("title defaults to empty string")
        func testTitleDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectEqual("wv.title", "")
        }

        @Test("isLoading defaults to false")
        func testIsLoadingDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            #expect(harness.evalBool("wv.isLoading") == false)
        }

        @Test("estimatedProgress defaults to 0")
        func testEstimatedProgressDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            #expect(harness.evalDouble("wv.estimatedProgress") == 0)
        }

        @Test("canGoBack defaults to false")
        func testCanGoBackDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            #expect(harness.evalBool("wv.canGoBack") == false)
        }

        @Test("canGoForward defaults to false")
        func testCanGoForwardDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            #expect(harness.evalBool("wv.canGoForward") == false)
        }
    }

    // MARK: - Builder Chaining

    @Suite("Builder method chaining")
    struct ChainingTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("userAgent returns self")
        func testUserAgentReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.userAgent('test') === wv")
        }

        @Test("inspectable returns self")
        func testInspectableReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.inspectable(true) === wv")
        }

        @Test("toolbar returns self — empty array")
        func testToolbarReturnsSelfEmpty() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.toolbar([]) === wv")
        }

        @Test("toolbar returns self — standard items")
        func testToolbarReturnsSelfStandard() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.toolbar(['back', 'forward', 'reload', 'url']) === wv")
        }

        @Test("toolbar returns self — with custom button")
        func testToolbarReturnsSelfCustomButton() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.toolbar(['back', 'url', {title: 'Home', callback: () => {}}]) === wv")
        }

        @Test("backForwardGestures returns self")
        func testBackForwardGesturesReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.backForwardGestures(false) === wv")
        }

        @Test("magnificationGestures returns self")
        func testMagnificationGesturesReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.magnificationGestures(false) === wv")
        }

        @Test("linkPreviews returns self")
        func testLinkPreviewsReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.linkPreviews(false) === wv")
        }

        @Test("contentBackground returns self")
        func testContentBackgroundReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.contentBackground(false) === wv")
        }

        @Test("loadHTML returns self")
        func testLoadHTMLReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.loadHTML('<html></html>') === wv")
        }

        @Test("goBack returns self")
        func testGoBackReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.goBack() === wv")
        }

        @Test("goForward returns self")
        func testGoForwardReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.goForward() === wv")
        }

        @Test("reload returns self")
        func testReloadReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.reload() === wv")
        }

        @Test("stopLoading returns self")
        func testStopLoadingReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.stopLoading() === wv")
        }

        @Test("execJS returns self")
        func testExecJSReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.execJS('1+1') === wv")
        }

        @Test("onLoadChange returns self")
        func testOnLoadChangeReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.onLoadChange(() => {}) === wv")
        }

        @Test("onNavigate returns self")
        func testOnNavigateReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.onNavigate(() => {}) === wv")
        }

        @Test("onTitleChange returns self")
        func testOnTitleChangeReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.onTitleChange(() => {}) === wv")
        }

        @Test("onNavigationDecision returns self")
        func testOnNavigationDecisionReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.onNavigationDecision(() => true) === wv")
        }

        @Test("onMessage returns self")
        func testOnMessageReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.onMessage('hs', () => {}) === wv")
        }

        @Test("removeMessageHandler returns self, even for a name never registered")
        func testRemoveMessageHandlerReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.removeMessageHandler('never') === wv")
        }

        @Test("evalJSResult returns self")
        func testEvalJSResultReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.evalJSResult('1', () => {}) === wv")
        }

        @Test("toolbar with systemImage-only custom button")
        func testToolbarSystemImageOnlyCustomButton() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.toolbar(['url', {systemImage: 'house', callback: () => {}}]) === wv")
            #expect(!harness.hasException)
        }

        @Test("toolbar with mixed standard and custom items")
        func testToolbarMixedItems() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview()
                wv.toolbar([
                    'back', 'forward', 'reload', 'url', 'spacer',
                    {title: 'A', callback: () => {}},
                    {title: 'B', systemImage: 'star', callback: () => {}}
                ])
            """)
            #expect(!harness.hasException)
        }

        @Test("full element builder chain produces no exception")
        func testFullChainNoException() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview()
                    .toolbar(['back', 'forward', 'reload', 'url'])
                    .inspectable(false)
                    .backForwardGestures(true)
                    .magnificationGestures(true)
                    .linkPreviews(true)
                    .contentBackground(true)
                    .userAgent("TestAgent/1.0")
                    .onNavigate(() => {})
                    .onTitleChange(() => {})
                    .onLoadChange(() => {})
                    .onNavigationDecision(() => true)
                    .loadHTML("<html><body>Hello</body></html>")
            """)
            #expect(!harness.hasException)
            harness.expectTrue("typeof wv === 'object' && wv !== null")
        }

        @Test("embedding in window returns the window for chaining")
        func testWindowWebviewReturnsSelf() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview()
                var win = hs.ui.window({x: 0, y: 0, w: 800, h: 600})
                var result = win.webview(wv)
            """)
            harness.expectTrue("result === win")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Lifecycle

    @Suite("Lifecycle")
    struct LifecycleTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            return harness
        }

        @Test("multiple webview elements can be created independently")
        func testMultipleWebViewsNoException() {
            let harness = makeHarness()
            harness.eval("""
                var wv1 = hs.ui.webview()
                var wv2 = hs.ui.webview()
            """)
            #expect(!harness.hasException)
            harness.expectTrue("wv1 !== wv2")
        }

        @Test("element can be embedded in a window")
        func testEmbedInWindow() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview().loadHTML("<html><body>Hi</body></html>")
                hs.ui.window({x: 0, y: 0, w: 800, h: 600}).webview(wv)
            """)
            #expect(!harness.hasException)
        }

        @Test("element with toolbar can be embedded in a window")
        func testEmbedWithToolbar() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview()
                    .toolbar(['back', 'forward', 'reload', 'url'])
                    .loadHTML("<html></html>")
                hs.ui.window({x: 0, y: 0, w: 800, h: 600}).webview(wv)
            """)
            #expect(!harness.hasException)
        }

        @Test("callbacks on element do not throw after window close")
        func testCallbacksReleasedOnWindowClose() {
            let harness = makeHarness()
            harness.eval("""
                var called = false
                var wv = hs.ui.webview()
                    .onNavigate(() => { called = true })
                    .onTitleChange(() => { called = true })
                    .onLoadChange(() => { called = true })
                var win = hs.ui.window({x: 0, y: 0, w: 800, h: 600})
                win.webview(wv)
                win.destroy()
            """)
            #expect(!harness.hasException)
        }

        @Test("same element can be configured after embedding")
        func testConfigureAfterEmbedding() {
            let harness = makeHarness()
            harness.eval("""
                var wv = hs.ui.webview()
                hs.ui.window({x: 0, y: 0, w: 800, h: 600}).webview(wv)
                wv.loadHTML("<html><body>Updated</body></html>")
                wv.userAgent("TestAgent/2.0")
            """)
            #expect(!harness.hasException)
        }

        @Test(
            "A window holding a web view can be shown again after it's hidden, and is the same window",
            .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI comment below")
        )
        func testWebViewWindowReshownAfterHide() throws {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.ui.window({x: 100, y: 100, w: 400, h: 300})
                    .webview(hs.ui.webview().loadHTML("hi"))
                w.show()
                void 0
            """)
            let window = try #require(harness.evalValue("w")?.toObjectOf(HSUIWindow.self) as? HSUIWindow)
            let firstWindow = try #require(NSApp.windows.first { ($0.delegate as AnyObject?) === window })

            // Each step needs a pass of the run loop: the crash (#286) came as SwiftUI laid out
            // the reshown window's web view
            for step in ["w.hide()", "w.show()", "w.hide()", "w.show()"] {
                harness.eval("\(step); void 0")
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            }

            #expect(!harness.hasException)
            #expect(firstWindow.isVisible)
            #expect(NSApp.windows.filter { ($0.delegate as AnyObject?) === window }.count == 1,
                    "Showing a hidden window again must reuse its NSWindow, not make another")
            harness.eval("w.destroy()")
        }

        // #399: JavaScriptCore holds its lock for the whole of a call from JS into Swift (and the
        // autorelease pool it wraps that call in drains before the lock is released). While it's
        // held, the thread's atom string table is the JS VM's own, so if WebKit is torn down then,
        // freeing a back/forward list with saved form state aborts in AtomStringImpl::remove.
        // Which pages' state reaches the list depends on WebKit internals, so rather than try to
        // provoke the abort, these check that the WebKit objects outlive the call from JS.
        @Test(
            "Destroying a window from JavaScript frees its web view once the call has returned",
            .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI comment below")
        )
        func testDestroyFreesWebKitOutsideJavaScript() async throws {
            let harness = makeHarness()
            autoreleasepool {
                _ = harness.eval("""
                    var loaded = false
                    var wv = hs.ui.webview()
                        .onMessage("loaded", () => { loaded = true })
                        .loadHTML("<script>onload = () => webkit.messageHandlers.loaded.postMessage(1)</script>")
                    var win = hs.ui.window({x: 100, y: 100, w: 400, h: 300}).webview(wv)
                    win.show()
                    void 0
                    """)
            }
            #expect(!harness.hasException)
            #expect(await harness.waitForAsync(timeout: 5.0) { harness.evalBool("loaded") == true })
            // Let the page settle and read its back/forward list, as a toolbar does. Without
            // these the WKWebView can happen to outlive the call anyway, hiding a regression.
            try await Task.sleep(for: .seconds(1))
            #expect(harness.evalBool("wv.canGoBack") == false)

            weak var webKitView: WKWebView?
            autoreleasepool {
                webKitView = NSApp.windows.lazy.compactMap { $0.contentView.flatMap(Self.findWebKitView(in:)) }.first
                // Leave the window's views holding the last references to the web view's WebKit objects
                harness.eval("wv = null; void 0")
                harness.collectGarbage()
            }
            try #require(webKitView != nil)

            autoreleasepool { _ = harness.eval("win.destroy(); void 0") }
            #expect(webKitView != nil, "The WKWebView must not be freed during the call from JS")
            #expect(await harness.waitForAsync(timeout: 2.0) { webKitView == nil })
        }

        @Test("Collecting a web view's JS wrapper frees its WebKit objects once the collector has finished")
        func testCollectionFreesWebKitOutsideJavaScript() async throws {
            let harness = makeHarness()
            weak var webView: UIWebView?
            weak var page: WebPage?
            autoreleasepool {
                harness.eval("var wv = hs.ui.webview().loadHTML('hi'); void 0")
                let object = harness.evalValue("wv")?.toObjectOf(UIWebView.self) as? UIWebView
                webView = object
                page = object?.page
            }
            try #require(page != nil)

            // The collector holds JavaScriptCore's lock while it finalizes the wrapper
            autoreleasepool {
                harness.eval("wv = null; void 0")
                harness.collectGarbage()
            }
            try #require(webView == nil, "The collector should have freed the UIWebView")
            #expect(page != nil, "The WebPage must not be freed while the collector holds the lock")
            #expect(await harness.waitForAsync(timeout: 2.0) { page == nil })
        }

        private static func findWebKitView(in view: NSView) -> WKWebView? {
            if let webKitView = view as? WKWebView { return webKitView }
            return view.subviews.lazy.compactMap(findWebKitView(in:)).first
        }
    }

    // MARK: - Page Messages

    /// These load real pages, but into a WebPage with no window, so they don't hit the WebKit
    /// CVDisplayLink crash that window teardown causes in CI (see QUARANTINED IN CI below).
    @Suite("Page messages")
    struct PageMessageTests {

        /// A harness with `wv`, a web view, and `postingPage(name, body)`, which makes a page
        /// that posts `body` to `webkit.messageHandlers[name]` as it loads, then sets its title to
        /// `ok:<reply as JSON>` or `error:<rejection message>`.
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            harness.eval(#"""
                var wv = hs.ui.webview()
                function postingPage(name, body) {
                    return "<script>webkit.messageHandlers[" + JSON.stringify(name) + "]" +
                        ".postMessage(" + JSON.stringify(body) + ")" +
                        ".then(r => document.title = 'ok:' + JSON.stringify(r)," +
                        " e => document.title = 'error:' + e.message)</script>"
                }
                """#)
            return harness
        }

        private func waitForTitle(_ harness: JSTestHarness, prefix: String) async -> String? {
            _ = await harness.waitForAsync(timeout: 5.0) {
                harness.evalString("wv.title")?.hasPrefix(prefix) == true
            }
            return harness.evalString("wv.title")
        }

        @Test("The page's message reaches the callback, and the callback's result is the page's reply")
        func testMessageRoundTrip() async {
            let harness = makeHarness()
            harness.eval("""
                var received = null
                wv.onMessage("hs", (body) => { received = body; return [body.text, body.n + 1] })
                    .loadHTML(postingPage("hs", {text: "hello", n: 41}))
                """)
            #expect(!harness.hasException)

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == #"ok:["hello",42]"#)
            #expect(harness.evalString("received.text") == "hello")
            #expect(harness.evalInt("received.n") == 41)
        }

        @Test("A Promise returned by the callback settles the page's reply")
        func testPromiseReply() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", (body) => Promise.resolve(body).then(b => b + "!"))
                    .loadHTML(postingPage("hs", "later"))
                """)

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == #"ok:"later!""#)
        }

        @Test("A rejected Promise rejects the page's reply")
        func testRejectedPromiseReply() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", () => Promise.reject(new Error("nope")))
                    .loadHTML(postingPage("hs", null))
                """)

            let title = await waitForTitle(harness, prefix: "error:")
            #expect(title == "error:nope")
        }

        @Test("A reply still pending after the callback returns reaches the page when it settles")
        func testDelayedReply() async {
            let harness = makeHarness()
            harness.eval("""
                var settle = null
                wv.onMessage("hs", () => new Promise(resolve => { settle = resolve }))
                    .loadHTML(postingPage("hs", null))
                """)
            let received = await harness.waitForAsync(timeout: 5.0) {
                harness.evalTypeOf("settle") == "function"
            }
            #expect(received)

            // The reply's callbacks are only held by the pending Promise
            harness.collectGarbage()
            harness.eval("settle('later')")

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == #"ok:"later""#)
        }

        @Test("A thenable whose then() throws rejects the page's reply")
        func testThrowingThenable() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", () => ({ then() { throw new Error("bad then") } }))
                    .loadHTML(postingPage("hs", null))
                """)

            let title = await waitForTitle(harness, prefix: "error:")
            #expect(title == "error:bad then")
        }

        @Test("Only the first settlement of a thenable reaches the page")
        func testThenableSettlingTwice() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", () => ({
                    then(resolve, reject) {
                        resolve("first")
                        resolve("second")
                        reject(new Error("third"))
                        throw new Error("fourth")
                    }
                }))
                    .loadHTML(postingPage("hs", null))
                """)

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == #"ok:"first""#)
        }

        @Test("An error thrown by the callback rejects the page's reply")
        func testThrowRejects() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", () => { throw new Error("boom") })
                    .loadHTML(postingPage("hs", 1))
                """)

            let title = await waitForTitle(harness, prefix: "error:")
            #expect(title == "error:boom")
        }

        @Test("Registering a name again replaces its callback")
        func testReplaceCallback() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("hs", () => "first")
                    .onMessage("hs", () => "second")
                    .loadHTML(postingPage("hs", 1))
                """)
            #expect(!harness.hasException)

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == #"ok:"second""#)
        }

        @Test("removeMessageHandler removes only that name from the page")
        func testRemoveMessageHandler() async {
            let harness = makeHarness()
            harness.eval("""
                wv.onMessage("kept", () => 1)
                    .onMessage("gone", () => 2)
                    .removeMessageHandler("gone")
                    .loadHTML("<script>var h = webkit.messageHandlers;" +
                        "document.title = 'done:' + (h.kept !== undefined) + '-' + (h.gone !== undefined)</script>")
                """)

            let title = await waitForTitle(harness, prefix: "done:")
            #expect(title == "done:true-false")
        }

        @Test("A handler added after the page loaded is available to it")
        func testHandlerAddedAfterLoad() async {
            let harness = makeHarness()
            harness.eval("wv.loadHTML('<title>loaded</title>')")
            _ = await waitForTitle(harness, prefix: "loaded")

            harness.eval("""
                wv.onMessage("late", (body) => body * 2)
                    .execJS("webkit.messageHandlers.late.postMessage(21).then(r => document.title = 'ok:' + r)")
                """)

            let title = await waitForTitle(harness, prefix: "ok:")
            #expect(title == "ok:42")
        }

        @Test("A web view with a message handler is released once the page has messaged it")
        func testMessageHandlerDoesNotLeak() async {
            let tracker = WeakLeakTracker()
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            var webView: UIWebView?
            autoreleasepool {
                harness.eval("""
                    var wv = hs.ui.webview()
                    wv.onMessage("hs", (body) => body)
                        .loadHTML("<script>webkit.messageHandlers.hs.postMessage('hi')" +
                            ".then(r => document.title = 'reply:' + r)</script>")
                    void 0
                    """)
                webView = harness.evalValue("wv")?.toObjectOf(UIWebView.self) as? UIWebView
                if let webView { tracker.track(webView) }
            }
            guard webView != nil else {
                Issue.record("Could not resolve UIWebView from JS value")
                return
            }

            // Poll the Swift object, so no JSValues are left outside the pool
            let replied = await harness.waitForAsync(timeout: 5.0) { webView?.title == "reply:hi" }
            #expect(replied)

            autoreleasepool {
                harness.eval("wv = null")
                harness.shutdownForLeakTest()
            }
            webView = nil
            tracker.assertNoLeaks(timeout: 2.0)
        }
    }

    // MARK: - Script Results

    /// Like the page message tests, these use a WebPage with no window.
    @Suite("Script results")
    struct ScriptResultTests {

        /// A harness with `wv`, a web view that has loaded a page titled "T1", and
        /// `evalInPage(script)`, which runs `script` with `evalJSResult()` and stores what its
        /// callback receives in `got`, as `{result, error}`.
        private func makeHarness() async -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")
            harness.eval("""
                var wv = hs.ui.webview().loadHTML("<title>T1</title><body><p>hi</p></body>")
                var got = null
                function evalInPage(script) {
                    got = null
                    wv.evalJSResult(script, (result, error) => { got = {result: result, error: error} })
                }
                """)
            let loaded = await harness.waitForAsync(timeout: 5.0) { harness.evalString("wv.title") == "T1" }
            #expect(loaded)
            return harness
        }

        /// Runs `script` in the page and returns what the callback got, as JSON
        private func evalInPage(_ harness: JSTestHarness, _ script: String) async -> String? {
            harness.eval("evalInPage(\(jsStringLiteral(script)))")
            #expect(!harness.hasException)
            let calledBack = await harness.waitForAsync(timeout: 5.0) { harness.evalBool("got !== null") == true }
            #expect(calledBack, "evalJSResult never called back for: \(script)")
            return harness.evalString("JSON.stringify(got)")
        }

        private func jsStringLiteral(_ string: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed)
            return String(decoding: data, as: UTF8.self)
        }

        @Test("A script that returns a value delivers it, with a null error")
        func testReturnedValue() async {
            let harness = await makeHarness()
            #expect(await evalInPage(harness, "return document.title") == #"{"result":"T1","error":null}"#)
            #expect(await evalInPage(harness, "return 1 + 1") == #"{"result":2,"error":null}"#)
        }

        @Test("A bare expression is not returned, so the result is null")
        func testBareExpressionIsNull() async {
            let harness = await makeHarness()
            #expect(await evalInPage(harness, "document.title") == #"{"result":null,"error":null}"#)
            #expect(await evalInPage(harness, "1 + 1") == #"{"result":null,"error":null}"#)
        }

        @Test("Returning undefined gives a null result")
        func testUndefinedIsNull() async {
            let harness = await makeHarness()
            #expect(await evalInPage(harness, "return undefined") == #"{"result":null,"error":null}"#)
        }

        @Test("Several statements run, and the returned value is delivered")
        func testStatements() async {
            let harness = await makeHarness()
            let script = """
                const p = document.querySelector("p")
                p.textContent = "changed"
                return p.textContent.length
                """
            #expect(await evalInPage(harness, script) == #"{"result":7,"error":null}"#)
        }

        @Test("Arrays and plain objects are copied out of the page")
        func testStructuredResult() async {
            let harness = await makeHarness()
            #expect(await evalInPage(harness, "return {name: document.title, list: [1, 'two', true, null]}")
                    == #"{"result":{"name":"T1","list":[1,"two",true,null]},"error":null}"#)
        }

        @Test("The script can await, and a returned Promise delivers what it resolves to")
        func testAwait() async {
            let harness = await makeHarness()
            let awaited = "const v = await new Promise(r => setTimeout(() => r(20), 10)); return v + 1"
            #expect(await evalInPage(harness, awaited) == #"{"result":21,"error":null}"#)
            #expect(await evalInPage(harness, "return Promise.resolve('later')") == #"{"result":"later","error":null}"#)
        }

        @Test("A thrown error or rejected Promise is delivered as the page's own error message, with a null result",
              arguments: [
                ("throw new Error('boom')", "Error: boom"),
                ("return Promise.reject(new TypeError('nope'))", "TypeError: nope"),
                ("throw 'a plain string'", "a plain string"),
              ])
        func testErrors(script: String, message: String) async {
            let harness = await makeHarness()
            let got = await evalInPage(harness, script)
            #expect(got == #"{"result":null,"error":\#(jsStringLiteral(message))}"#)
        }

        @Test("A syntax error is delivered as the page's SyntaxError message")
        func testSyntaxError() async {
            let harness = await makeHarness()
            _ = await evalInPage(harness, "return (")
            #expect(harness.evalBool("got.result === null") == true)
            let error = harness.evalString("got.error") ?? ""
            // The rest of the message depends on how WebKit wraps the script in a function
            #expect(error.hasPrefix("SyntaxError: "), "got \(error)")
        }

        @Test("A result that can't be copied out of the page, such as a DOM element, is delivered as an error")
        func testUncopyableResult() async {
            let harness = await makeHarness()
            let got = await evalInPage(harness, "return document.body")
            #expect(got == #"{"result":null,"error":"JavaScript execution returned a result of an unsupported type"}"#)
        }
    }

    // MARK: - Memory Leak Tests
    //
    // UIWebView is embedded into a window's element tree (not registered in a strong
    // module-level dictionary like HSUIWindow/HSUIAlert/HSUIDialog), so its release
    // depends entirely on HSUIWindow.destroy() eagerly calling UIWebView.destroy() to
    // detach callbacks and cancel its two long-lived MainActor observation Tasks (see
    // HSUIWindow.destroy() and UIWebView.destroy()). This loads real page content
    // (rather than an inert, never-navigated element) so those observation Tasks are
    // actually driven by a live WebPage before verifying they don't keep the element
    // alive. Network-backed loadURL() is deliberately avoided here — see HSTests skill
    // guidance on flaky network-dependent tests — so loadHTML() is used instead, which
    // still exercises the full WebPage/WebKit navigation and rendering pipeline.
    //
    // KNOWN ISSUE (wrapped in withKnownIssue below, not fixed): once a page has loaded
    // AND a caller has registered onLoadChange/onTitleChange/onNavigate,
    // UIWebView.startNavigationEventObservation()'s `for try await event in
    // self.page.navigations` and startStateObservation()'s withObservationTracking/
    // withCheckedContinuation loop both suspend permanently waiting for their next
    // value. Task.cancel() (called from destroy()) does not wake either of them —
    // confirmed by direct tracing, not merely a slow teardown. WebKit's WebPage class
    // (macOS 26, `WebKit`/`_WebKit_SwiftUI`) has no public close()/invalidate() API
    // (confirmed via `swift-api-digester -dump-sdk -module WebKit`'s full member list),
    // so there is no way from Hammerspoon's code to force these to terminate. This
    // leaks the UIWebView Swift object *and* the underlying WebPage/WKWebView content
    // process for any hs.ui.webview() that has loaded a page, had one of those
    // callbacks registered, and is then destroyed. Revisit if a future WebKit release
    // changes this behavior, or if UIWebView moves off AsyncSequence/Observations-based
    // bridging for this state.
    //
    // MITIGATION: UIWebView.ensureNavigationEventObservationStarted()/
    // ensureStateObservationStarted() only start these Tasks lazily, the first time a
    // relevant callback is actually registered, rather than unconditionally in init().
    // A webview that never registers onLoadChange/onTitleChange/onNavigate never starts
    // the un-cancellable Tasks in the first place, so it doesn't leak — see
    // testWebViewWithoutObservationCallbacksDoesNotLeak below.
    //
    // QUARANTINED IN CI: both tests below reliably crash the whole xctest process with
    // SIGSEGV in GitHub Actions (`runs-on: macos-26`, currently macOS 26.5.2/25F84).
    // The crash is a use-after-free deep in WebKit itself — `EXC_BAD_ACCESS` inside
    // `WebKit::DisplayLink::notifyObserversDisplayDidRefresh()`, on a background
    // `CVDisplayLink` thread, firing after a loaded WebPage's window has been torn
    // down. It reproduces on *both* tests (including the one that registers no
    // observation callbacks at all), so it is unrelated to the Task-cancellation leak
    // documented above — it's WebKit's own rendering pipeline, not anything under our
    // control. `withKnownIssue` cannot mask it: that only intercepts recorded Swift
    // Testing issues, not a process-level signal that kills the whole test runner.
    // Confirmed not to reproduce locally on bare-metal Apple Silicon (only inside
    // GitHub's virtualized "Apple Virtual Machine" runner), and CI is currently pinned
    // one point release behind (26.5.2/25F84 vs. locally-current 26.6.2/25G83), so this
    // is presumed to be a WebKit/CVDisplayLink race that's specific to the virtualized
    // display pipeline and/or already fixed upstream. `isRunningInCI()` skips both
    // tests only when `CI=true` (set automatically by GitHub Actions) so they keep
    // running — and keep exercising real leak coverage — everywhere else. Revisit by
    // removing the `.disabled(if:)` trait once the CI runner image moves past 25F84.

    @Suite("Memory leak tests")
    struct MemoryLeakTests {

        @available(macOS 26.0, *)
        @Test(
            "Embedded UIWebView with onLoadChange registered leaks after window destroy, having loaded a page",
            .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI comment above")
        )
        func testWebViewWithLoadObservationLeaksAfterWindowDestroy() async {
            let tracker = WeakLeakTracker()
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")

            var webView: UIWebView?
            // See HSUITests.testWindowDoesNotLeakAfterReload (HSUIIntegrationTests.swift)
            // for why autoreleasepool {} (not do {}) is required around eval()-produced
            // JSValues: each holds a strong reference to its JSContext, so leaving any
            // unreleased would keep the whole bridge (and this element) alive.
            autoreleasepool {
                harness.eval("""
                    var wv = hs.ui.webview()
                        .onLoadChange(() => {})
                        .loadHTML(
                            "<html><head><title>HS2 Leak Test</title></head>" +
                            "<body><h1>Hello from Hammerspoon!</h1></body></html>"
                        )
                    var win = hs.ui.window({x: 0, y: 0, w: 800, h: 600}).webview(wv)
                    win.show()
                """)
                #expect(!harness.hasException)
                if let obj = harness.evalValue("wv")?.toObjectOf(UIWebView.self) as? UIWebView {
                    tracker.track(obj)
                    webView = obj
                }
            }

            guard webView != nil else {
                Issue.record("Could not resolve UIWebView from JS value")
                return
            }

            // Wait for the page to actually finish loading by polling the Swift object's
            // properties directly rather than through further eval() calls, so no
            // additional JSValues are autoreleased outside the pool above while awaiting
            // (JSValue's autorelease semantics require calls with eval() to be in a
            // pool that closes before assertNoLeaks() runs, which an async condition
            // closure inside autoreleasepool {} cannot express — autoreleasepool only
            // accepts a synchronous closure).
            let loaded = await harness.waitForAsync(timeout: 5.0) {
                webView?.title == "HS2 Leak Test" && webView?.isLoading == false
            }
            #expect(loaded, "Page should finish loading before checking for leaks")

            autoreleasepool {
                harness.eval("wv = null; win = null")
                harness.shutdownForLeakTest()
            }
            // Drop the test's own strong reference used for polling above — otherwise
            // this local would itself be the "leak" assertNoLeaks() reports.
            webView = nil
            // As in the next test, let the window's views be released on the main queue
            await JSTestHarness.drainMainActorQueue()
            // Known, currently-unfixable leak — see the comment above this suite.
            // withKnownIssue keeps this from failing CI while still surfacing loudly
            // (as an unexpected pass) if WebKit or UIWebView's implementation changes
            // to actually fix it.
            withKnownIssue("""
                hs.ui.webview leaks WebPage/WKWebView after a loaded page's window is \
                destroyed, once onLoadChange/onTitleChange/onNavigate has started the \
                observation Task: WebPage.navigations and its Observable properties \
                don't respond to Task cancellation once suspended, and WebPage exposes \
                no public close()/invalidate() API to force them to terminate.
                """) {
                tracker.assertNoLeaks(timeout: 2.0)
            }
        }

        @available(macOS 26.0, *)
        @Test(
            "Embedded UIWebView without observation callbacks does not leak after window destroy, having loaded a page",
            .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI comment above")
        )
        func testWebViewWithoutObservationCallbacksDoesNotLeak() async {
            let tracker = WeakLeakTracker()
            let harness = JSTestHarness()
            harness.loadModule(HSUIModule.self, as: "ui")

            var webView: UIWebView?
            autoreleasepool {
                harness.eval("""
                    var wv = hs.ui.webview().loadHTML(
                        "<html><head><title>HS2 Leak Test</title></head>" +
                        "<body><h1>Hello from Hammerspoon!</h1></body></html>"
                    )
                    var win = hs.ui.window({x: 0, y: 0, w: 800, h: 600}).webview(wv)
                    win.show()
                """)
                #expect(!harness.hasException)
                if let obj = harness.evalValue("wv")?.toObjectOf(UIWebView.self) as? UIWebView {
                    tracker.track(obj)
                    webView = obj
                }
            }

            guard webView != nil else {
                Issue.record("Could not resolve UIWebView from JS value")
                return
            }

            // No onLoadChange/onTitleChange/onNavigate is registered here, so neither
            // observation Task should ever start (see ensureStateObservationStarted /
            // ensureNavigationEventObservationStarted in UIWebView.swift). Poll the
            // Swift object's properties directly rather than via eval() — url/title/
            // isLoading read the underlying WebPage regardless of whether anything is
            // observing it, and this avoids autoreleasing JSValues outside the pool
            // above while awaiting (see the comment on the previous test).
            let loaded = await harness.waitForAsync(timeout: 5.0) {
                webView?.title == "HS2 Leak Test" && webView?.isLoading == false
            }
            #expect(loaded, "Page should finish loading before checking for leaks")

            autoreleasepool {
                harness.eval("wv = null; win = null")
                harness.shutdownForLeakTest()
            }
            webView = nil
            // Destroying the window releases its views on the main queue, which assertNoLeaks()
            // can't drain, as this test is itself running there
            await JSTestHarness.drainMainActorQueue()
            tracker.assertNoLeaks(timeout: 2.0)
        }
    }
}
