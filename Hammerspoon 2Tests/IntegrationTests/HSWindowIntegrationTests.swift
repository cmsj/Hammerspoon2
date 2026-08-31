//
//  HSWindowIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.window module
///
/// These only cover the JS-enhancement surface added by hs.window.js. Anything that touches
/// real windows requires Accessibility permission and isn't exercised here.
@Suite("hs.window tests")
struct HSWindowIntegrationTests {

    // MARK: - Issue #185: JS enhancements must survive garbage collection

    private static let enhancementTypeChecks = """
    [
        typeof win.focused,
        typeof win.findByTitle,
        typeof win.currentWindows,
        typeof win.moveToLeftHalf,
        typeof win.moveToRightHalf,
        typeof win.maximize,
        typeof win.cycleWindows,
        typeof win.grid,
        typeof win.tiling
    ].join(',')
    """
    private static let allFunctionsOrObjects =
        "function,function,function,function,function,function,function,object,object"

    @Test("hs.window.js enhancements are all present after loading")
    func testEnhancementsPresentAfterLoad() {
        let harness = JSTestHarness()
        harness.loadModule(HSWindowModule.self, as: "window")

        let types = harness.eval("var win = hs.window; \(Self.enhancementTypeChecks)") as? String
        #expect(types == Self.allFunctionsOrObjects)
    }

    /// JavaScriptCore wraps an Objective-C object returned from native code (a property getter, a
    /// block call) in a JSValue. That wrapper is cached per-context by object identity, but the
    /// cache entry is weak: if nothing on the JS side keeps that specific wrapper reachable, a
    /// garbage collection can evict it. The next access then gets a *new* wrapper for the same
    /// underlying object. Dynamically-added JS properties (`someObject.foo = ...`) live on the
    /// wrapper and are lost when this happens; properties declared on the Swift class (real
    /// `@objc var` storage, as added to `HSWindowModuleAPI` here) are not, because they're read
    /// through the Objective-C accessor regardless of which wrapper asked - see issue #185.
    ///
    /// `JSTestHarness.loadModule()` doesn't exercise the eviction case: it stores the module
    /// directly as a JS property on `hs`, which permanently roots that one wrapper - unlike
    /// `ModuleRoot.window`, a *computed* property that hands back a wrapper only as the transient
    /// result of a native call, never stored anywhere on the JS side. This test reproduces that
    /// "value returned by native code, never stored in a JS variable" pattern directly against a
    /// block registered on the harness's own context, bypassing `ModuleRoot`/`JSEngine.shared`
    /// (whose lazy module loading runs `hs.window.js` against a different JSContext than the one
    /// the test harness uses, so it can't be exercised end-to-end from a test).
    @Test("hs.window.js enhancements survive garbage collection when never stored in a JS variable")
    func testEnhancementsSurviveGarbageCollectionThroughFreshWrapper() {
        let harness = JSTestHarness()
        let module = HSWindowModule(engineID: UUID())

        // Mirrors what `hs.window.focused = hs.window.focusedWindow` etc. actually do in
        // production: read a freshly-wrapped reference to the module, assign a property onto it,
        // and never keep that particular wrapper alive from JS.
        let getter: @convention(block) () -> HSWindowModule = { module }
        harness.context.setObject(getter, forKeyedSubscript: "__getWindow" as NSString)

        harness.eval("__getWindow().focused = function() { return 1 }")

        let before = harness.eval("typeof __getWindow().focused") as? String
        #expect(before == "function")

        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

        let after = harness.eval("typeof __getWindow().focused") as? String
        #expect(after == "function")
    }
}
