//
//  HSUIWebViewTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// Note: hs.ui.webview requires macOS 26.0. Tests are written using the JS harness
// exclusively (no direct UIWebView Swift references) so they compile against the
// 15.6 test target. On macOS < 26 the 'webview' method will be absent and the
// tests that check its existence will fail — but this project only runs on macOS 26+.

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
            makeHarness().expectTrue("typeof hs.ui.webview === 'function'")
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
            makeHarness().expectTrue("typeof hs.ui.webview().loadURL === 'function'")
        }

        @Test("loadHTML is a function")
        func testLoadHTMLIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().loadHTML === 'function'")
        }

        @Test("goBack is a function")
        func testGoBackIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().goBack === 'function'")
        }

        @Test("goForward is a function")
        func testGoForwardIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().goForward === 'function'")
        }

        @Test("reload is a function")
        func testReloadIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().reload === 'function'")
        }

        @Test("stopLoading is a function")
        func testStopLoadingIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().stopLoading === 'function'")
        }

        @Test("userAgent is a function")
        func testUserAgentIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().userAgent === 'function'")
        }

        @Test("inspectable is a function")
        func testInspectableIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().inspectable === 'function'")
        }

        @Test("toolbar is a function")
        func testToolbarIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().toolbar === 'function'")
        }

        @Test("backForwardGestures is a function")
        func testBackForwardGesturesIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().backForwardGestures === 'function'")
        }

        @Test("magnificationGestures is a function")
        func testMagnificationGesturesIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().magnificationGestures === 'function'")
        }

        @Test("linkPreviews is a function")
        func testLinkPreviewsIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().linkPreviews === 'function'")
        }

        @Test("contentBackground is a function")
        func testContentBackgroundIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().contentBackground === 'function'")
        }

        @Test("onLoadChange is a function")
        func testOnLoadChangeIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().onLoadChange === 'function'")
        }

        @Test("onNavigate is a function")
        func testOnNavigateIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().onNavigate === 'function'")
        }

        @Test("onTitleChange is a function")
        func testOnTitleChangeIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().onTitleChange === 'function'")
        }

        @Test("onNavigationDecision is a function")
        func testOnNavigationDecisionIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().onNavigationDecision === 'function'")
        }

        @Test("execJS is a function")
        func testExecJSIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().execJS === 'function'")
        }

        @Test("evalJSResult is a function")
        func testEvalJSResultIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview().evalJSResult === 'function'")
        }

        @Test("window has a webview method for embedding")
        func testWindowHasWebviewMethod() {
            makeHarness().expectTrue("typeof hs.ui.window({x:0,y:0,w:100,h:100}).webview === 'function'")
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
            harness.expectTrue("wv.isLoading === false")
        }

        @Test("estimatedProgress defaults to 0")
        func testEstimatedProgressDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.estimatedProgress === 0")
        }

        @Test("canGoBack defaults to false")
        func testCanGoBackDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.canGoBack === false")
        }

        @Test("canGoForward defaults to false")
        func testCanGoForwardDefault() {
            let harness = makeHarness()
            harness.eval("var wv = hs.ui.webview()")
            harness.expectTrue("wv.canGoForward === false")
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
                win.close()
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
    }
}
