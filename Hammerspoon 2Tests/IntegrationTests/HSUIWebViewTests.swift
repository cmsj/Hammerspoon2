//
//  HSUIWebViewTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// Note: hs.ui.webview2 requires macOS 26.0. Tests are written using the JS harness
// exclusively (no direct HSUIWebView Swift references) so they compile against the
// 15.6 test target. On macOS < 26 the 'webview2' method will be absent and the
// tests that check its existence will fail — but this project only runs on macOS 26+.

@Suite("hs.ui.webview2 tests")
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

        @Test("webview2 is a function on hs.ui")
        func testWebview2IsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2 === 'function'")
        }

        @Test("webview2 returns a non-null object")
        func testWebview2ReturnsObject() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("typeof b === 'object' && b !== null")
            #expect(!harness.hasException)
        }

        @Test("typeName is HSUIWebView")
        func testTypeName() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectEqual("b.typeName", "HSUIWebView")
        }

        @Test("show is a function")
        func testShowIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).show === 'function'")
        }

        @Test("hide is a function")
        func testHideIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).hide === 'function'")
        }

        @Test("close is a function")
        func testCloseIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).close === 'function'")
        }

        @Test("loadURL is a function")
        func testLoadURLIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).loadURL === 'function'")
        }

        @Test("loadHTML is a function")
        func testLoadHTMLIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).loadHTML === 'function'")
        }

        @Test("goBack is a function")
        func testGoBackIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).goBack === 'function'")
        }

        @Test("goForward is a function")
        func testGoForwardIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).goForward === 'function'")
        }

        @Test("reload is a function")
        func testReloadIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).reload === 'function'")
        }

        @Test("stopLoading is a function")
        func testStopLoadingIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).stopLoading === 'function'")
        }

        @Test("userAgent is a function")
        func testUserAgentIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).userAgent === 'function'")
        }

        @Test("inspectable is a function")
        func testInspectableIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).inspectable === 'function'")
        }

        @Test("toolbar is a function")
        func testToolbarIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).toolbar === 'function'")
        }

        @Test("backForwardGestures is a function")
        func testBackForwardGesturesIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).backForwardGestures === 'function'")
        }

        @Test("magnificationGestures is a function")
        func testMagnificationGesturesIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).magnificationGestures === 'function'")
        }

        @Test("linkPreviews is a function")
        func testLinkPreviewsIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).linkPreviews === 'function'")
        }

        @Test("contentBackground is a function")
        func testContentBackgroundIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).contentBackground === 'function'")
        }

        @Test("onLoadChange is a function")
        func testOnLoadChangeIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).onLoadChange === 'function'")
        }

        @Test("onNavigate is a function")
        func testOnNavigateIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).onNavigate === 'function'")
        }

        @Test("onTitleChange is a function")
        func testOnTitleChangeIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).onTitleChange === 'function'")
        }

        @Test("onNavigationDecision is a function")
        func testOnNavigationDecisionIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).onNavigationDecision === 'function'")
        }

        @Test("execJS is a function")
        func testExecJSIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).execJS === 'function'")
        }

        @Test("evalJSResult is a function")
        func testEvalJSResultIsFunction() {
            makeHarness().expectTrue("typeof hs.ui.webview2({}).evalJSResult === 'function'")
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
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.url === null || b.url === undefined")
        }

        @Test("title defaults to empty string")
        func testTitleDefault() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectEqual("b.title", "")
        }

        @Test("isLoading defaults to false")
        func testIsLoadingDefault() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.isLoading === false")
        }

        @Test("estimatedProgress defaults to 0")
        func testEstimatedProgressDefault() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.estimatedProgress === 0")
        }

        @Test("canGoBack defaults to false")
        func testCanGoBackDefault() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.canGoBack === false")
        }

        @Test("canGoForward defaults to false")
        func testCanGoForwardDefault() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.canGoForward === false")
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
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.userAgent('test') === b")
        }

        @Test("inspectable returns self")
        func testInspectableReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.inspectable(true) === b")
        }

        @Test("toolbar returns self — empty array")
        func testToolbarReturnsSelfEmpty() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.toolbar([]) === b")
        }

        @Test("toolbar returns self — standard items")
        func testToolbarReturnsSelfStandard() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.toolbar(['back', 'forward', 'reload', 'url']) === b")
        }

        @Test("toolbar returns self — with custom button")
        func testToolbarReturnsSelfCustomButton() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.toolbar(['back', 'url', {title: 'Home', callback: () => {}}]) === b")
        }

        @Test("backForwardGestures returns self")
        func testBackForwardGesturesReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.backForwardGestures(false) === b")
        }

        @Test("magnificationGestures returns self")
        func testMagnificationGesturesReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.magnificationGestures(false) === b")
        }

        @Test("linkPreviews returns self")
        func testLinkPreviewsReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.linkPreviews(false) === b")
        }

        @Test("contentBackground returns self")
        func testContentBackgroundReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.contentBackground(false) === b")
        }

        @Test("loadHTML returns self")
        func testLoadHTMLReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.loadHTML('<html></html>') === b")
        }

        @Test("goBack returns self")
        func testGoBackReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.goBack() === b")
        }

        @Test("goForward returns self")
        func testGoForwardReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.goForward() === b")
        }

        @Test("reload returns self")
        func testReloadReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.reload() === b")
        }

        @Test("stopLoading returns self")
        func testStopLoadingReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.stopLoading() === b")
        }

        @Test("execJS returns self")
        func testExecJSReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.execJS('1+1') === b")
        }

        @Test("onLoadChange returns self")
        func testOnLoadChangeReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.onLoadChange(() => {}) === b")
        }

        @Test("onNavigate returns self")
        func testOnNavigateReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.onNavigate(() => {}) === b")
        }

        @Test("onTitleChange returns self")
        func testOnTitleChangeReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.onTitleChange(() => {}) === b")
        }

        @Test("onNavigationDecision returns self")
        func testOnNavigationDecisionReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.onNavigationDecision(() => true) === b")
        }

        @Test("evalJSResult returns self")
        func testEvalJSResultReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.evalJSResult('1', () => {}) === b")
        }

        @Test("toolbar with systemImage-only custom button")
        func testToolbarSystemImageOnlyCustomButton() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({})")
            harness.expectTrue("b.toolbar(['url', {systemImage: 'house', callback: () => {}}]) === b")
            #expect(!harness.hasException)
        }

        @Test("toolbar with mixed standard and custom items")
        func testToolbarMixedItems() {
            let harness = makeHarness()
            harness.eval("""
                var b = hs.ui.webview2({})
                b.toolbar([
                    'back', 'forward', 'reload', 'url', 'spacer',
                    {title: 'A', callback: () => {}},
                    {title: 'B', systemImage: 'star', callback: () => {}}
                ])
            """)
            #expect(!harness.hasException)
        }

        @Test("full builder chain produces no exception")
        func testFullChainNoException() {
            let harness = makeHarness()
            harness.eval("""
                var b = hs.ui.webview2({x: 100, y: 100, w: 800, h: 600})
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
            harness.expectTrue("typeof b === 'object' && b !== null")
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

        @Test("close on unshown webview produces no exception")
        func testCloseUnshownNoException() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({}); b.close()")
            #expect(!harness.hasException)
        }

        @Test("close is idempotent")
        func testCloseIdempotent() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({}); b.close(); b.close(); b.close()")
            #expect(!harness.hasException)
        }

        @Test("hide on unshown webview produces no exception")
        func testHideUnshownNoException() {
            let harness = makeHarness()
            harness.eval("var b = hs.ui.webview2({}); b.hide()")
            #expect(!harness.hasException)
        }

        @Test("multiple webviews can be created independently")
        func testMultipleWebViewsNoException() {
            let harness = makeHarness()
            harness.eval("""
                var b1 = hs.ui.webview2({x: 0, y: 0, w: 400, h: 300})
                var b2 = hs.ui.webview2({x: 500, y: 0, w: 400, h: 300})
            """)
            #expect(!harness.hasException)
            harness.expectTrue("b1 !== b2")
        }

        @Test("callbacks are released on close without exception")
        func testCallbacksReleasedOnClose() {
            let harness = makeHarness()
            harness.eval("""
                var called = false
                var b = hs.ui.webview2({})
                    .onNavigate(() => { called = true })
                    .onTitleChange(() => { called = true })
                    .onLoadChange(() => { called = true })
                b.close()
            """)
            #expect(!harness.hasException)
        }

        @Test("setting callbacks after close produces no exception")
        func testCallbacksAfterCloseNoException() {
            let harness = makeHarness()
            harness.eval("""
                var b = hs.ui.webview2({})
                b.close()
                b.onNavigate(() => {})
            """)
            #expect(!harness.hasException)
        }
    }
}
