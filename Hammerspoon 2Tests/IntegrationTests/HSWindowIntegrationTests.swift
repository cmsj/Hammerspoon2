//
//  HSWindowIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AppKit
import AXSwift
@testable import Hammerspoon_2

private nonisolated func canDriveTextEditAndPreview() -> Bool {
    AXIsProcessTrusted()
        && NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") != nil
        && NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") != nil
}

/// Integration tests for hs.window module
///
/// Most of these cover the JS-enhancement surface added by hs.window.js. Tests that touch real
/// windows need Accessibility permission and are skipped without it. Serialized, because several
/// suites open and close TextEdit windows.
@Suite("hs.window tests", .serialized)
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

    // MARK: - Issue #269: layout helpers must set the window's frame

    /// The helpers only read `win.screen.frame` and assign `win.frame`, so a plain object standing in
    /// for an HSWindow shows where they would put a real window, without needing Accessibility.
    @Suite("hs.window layout helper tests")
    struct HSWindowLayoutHelperTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSWindowModule.self, as: "window")
            return harness
        }

        /// Runs `call` against a stand-in window on a 1000x800 screen at (0, 25), and returns the
        /// frame it was given as [x, y, w, h].
        private func frameAfter(_ call: String) -> [Double]? {
            let harness = makeHarness()
            harness.eval("var fakeWin = { screen: { frame: { x: 0, y: 25, w: 1000, h: 800 } }, frame: null }")
            let result = harness.evalBool(call)
            #expect(!harness.hasException, "\(call) threw")
            #expect(result == true, "\(call) did not return true")
            return harness.eval("var f = fakeWin.frame; f ? [f.x, f.y, f.w, f.h] : null") as? [Double]
        }

        @Test("layout helpers assign the expected frame", arguments: [
            ("hs.window.maximize(fakeWin)", [0.0, 25, 1000, 800]),
            ("hs.window.moveToLeftHalf(fakeWin)", [0.0, 25, 500, 800]),
            ("hs.window.moveToRightHalf(fakeWin)", [500.0, 25, 500, 800]),
            ("hs.window.tiling.top(fakeWin)", [0.0, 25, 1000, 400]),
            ("hs.window.tiling.bottom(fakeWin)", [0.0, 425, 1000, 400]),
            ("hs.window.tiling.topLeft(fakeWin)", [0.0, 25, 500, 400]),
            ("hs.window.tiling.topRight(fakeWin)", [500.0, 25, 500, 400]),
            ("hs.window.tiling.bottomLeft(fakeWin)", [0.0, 425, 500, 400]),
            ("hs.window.tiling.bottomRight(fakeWin)", [500.0, 425, 500, 400]),
            ("hs.window.grid.setGrid(fakeWin, {rows: 2, cols: 4}, {row: 1, col: 1, rowSpan: 1, colSpan: 2})",
             [250.0, 425, 500, 400]),
        ])
        func testLayoutHelperFrames(call: String, expected: [Double]) {
            #expect(frameAfter(call) == expected)
        }
    }

    /// Moves a real TextEdit window with the layout helpers, which need Accessibility.
    @Suite("hs.window frame-setting tests",
           .serialized,
           .disabled(if: !canDriveTextEditAndPreview(), "Needs Accessibility permission and TextEdit"))
    struct HSWindowFrameTests {
        private static let textEditID = "com.apple.TextEdit"

        @Test("layout helpers move a real window, and restore AXEnhancedUserInterface afterwards")
        func testLayoutHelpersMoveRealWindow() async throws {
            let textEditWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.textEditID).isEmpty
            let prefix = "hs-frame-test-\(UUID().uuidString)"
            let documentURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix).txt")
            try "frame".write(to: documentURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: documentURL) }

            let appURL = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.textEditID))
            let app = try await NSWorkspace.shared.open([documentURL], withApplicationAt: appURL,
                                                        configuration: NSWorkspace.OpenConfiguration())

            // Clean up outside a defer, so there's time to wait for TextEdit to quit.
            var failure: (any Error)?
            do {
                try await checkLayoutHelpers(in: app, windowTitlePrefix: prefix)
            } catch {
                failure = error
            }

            if textEditWasRunning {
                for window in HSApplication(runningApplication: app).allWindows where window.title?.hasPrefix(prefix) == true {
                    let closeButton: UIElement? = try? window.element.attribute(.closeButton)
                    try? closeButton?.performAction(.press)
                }
            } else {
                app.terminate()
                // Let TextEdit finish quitting, or the next test to open it can fail to launch it.
                let deadline = Date().addingTimeInterval(5)
                while !app.isTerminated && Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }

            if let failure { throw failure }
        }

        private func checkLayoutHelpers(in app: NSRunningApplication, windowTitlePrefix prefix: String) async throws {
            var window: HSWindow?
            let deadline = Date().addingTimeInterval(5)
            while window == nil && Date() < deadline {
                window = HSApplication(runningApplication: app).allWindows.first { $0.title?.hasPrefix(prefix) == true }
                if window == nil { try? await Task.sleep(for: .milliseconds(100)) }
            }
            let win = try #require(window, "TextEdit did not open \(prefix)")
            let screenFrame = try #require(win.screen?.frame)

            // Pretend an assistive client has turned the application's enhanced UI on. Not every
            // application lets this be set (TextEdit refuses on some macOS versions), in which case
            // only the frame change itself is checked.
            let appElement = UIElement(AXUIElementCreateApplication(app.processIdentifier))
            let enhancedUIWasSet = (try? appElement.setAttribute(.enhancedUserInterface, value: true)) != nil
            defer {
                if enhancedUIWasSet {
                    try? appElement.setAttribute(.enhancedUserInterface, value: false)
                }
            }

            let harness = JSTestHarness()
            harness.loadModule(HSWindowModule.self, as: "window")
            harness.context.setObject(win, forKeyedSubscript: "testWin" as NSString)

            #expect(harness.evalBool("hs.window.moveToLeftHalf(testWin)") == true)
            #expect(!harness.hasException)

            let frame = try #require(win.frame)
            #expect(frame.x == screenFrame.x)
            #expect(frame.y == screenFrame.y)
            #expect(frame.w == (screenFrame.w / 2).rounded(.down))

            if enhancedUIWasSet {
                let enhanced: Bool? = try? appElement.attribute(.enhancedUserInterface)
                #expect(enhanced == true, "AXEnhancedUserInterface should be restored after the frame change")
            }

            // Setting the property directly, as its documentation shows.
            harness.eval("testWin.frame = new HSRect(\(screenFrame.x + 10), \(screenFrame.y + 10), 400, 300)")
            #expect(!harness.hasException)
            let directFrame = try #require(win.frame)
            #expect(directFrame.x == screenFrame.x + 10)
            #expect(directFrame.w == 400)
        }
    }

    // MARK: - Issue #228: focus() must raise only the requested window

    /// Interleaves two TextEdit windows with a Preview window, then focuses one TextEdit window from JS.
    /// Like Hammerspoon 1, only that window should come forward; the other must stay behind Preview.
    ///
    /// Preview rather than Chess, because the hs.application watcher tests terminate Chess while
    /// running in parallel with this suite.
    @Suite("hs.window focus tests",
           .serialized,
           .disabled(if: !canDriveTextEditAndPreview(), "Needs Accessibility permission, TextEdit and Preview"))
    struct HSWindowFocusTests {
        private static let textEditID = "com.apple.TextEdit"
        private static let previewID = "com.apple.Preview"

        /// Polls `condition` until it holds or `timeout` elapses.
        private func waitUntil(timeout: TimeInterval = 5.0, _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return condition()
        }

        /// On-screen window IDs, front to back.
        private func windowStackingOrder() -> [Int] {
            let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            return info.compactMap { $0[kCGWindowNumber as String] as? Int }
        }

        /// Whether the windows with these IDs are on screen in this front-to-back order.
        private func isStacked(_ windowIDs: [Int]) -> Bool {
            let order = windowStackingOrder()
            let indices = windowIDs.compactMap { order.firstIndex(of: $0) }
            return indices.count == windowIDs.count && indices == indices.sorted()
        }

        private func window(titled prefix: String, in app: NSRunningApplication) -> HSWindow? {
            HSApplication(runningApplication: app).allWindows.first { $0.title?.hasPrefix(prefix) == true }
        }

        /// Opens `documents` in the app with `bundleID`, then waits for a window per document.
        /// - Returns: The app, and the window IDs in the same order as `documents`.
        private func open(_ documents: [URL], in bundleID: String) async throws -> (NSRunningApplication, [Int]) {
            let appURL = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID))
            let app = try await NSWorkspace.shared.open(documents, withApplicationAt: appURL,
                                                        configuration: NSWorkspace.OpenConfiguration())
            // Match on the file name without its extension, which Finder settings can hide.
            let prefixes = documents.map { $0.deletingPathExtension().lastPathComponent }
            let opened = await waitUntil { prefixes.allSatisfy { window(titled: $0, in: app) != nil } }
            try #require(opened, "\(bundleID) did not open \(prefixes)")
            return (app, try prefixes.map { try #require(window(titled: $0, in: app)).id })
        }

        /// Closes the windows of documents whose names start with `prefix`, or quits the app if
        /// it wasn't running before the test. The documents are unmodified, so nothing prompts to save.
        private func cleanUp(_ bundleID: String, documentsPrefixed prefix: String, wasRunning: Bool) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
            guard wasRunning else {
                app.terminate()
                return
            }
            for window in HSApplication(runningApplication: app).allWindows where window.title?.hasPrefix(prefix) == true {
                let closeButton: UIElement? = try? window.element.attribute(.closeButton)
                try? closeButton?.performAction(.press)
            }
        }

        private func isRunning(_ bundleID: String) -> Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }

        @Test("focus() brings forward only the requested window, not all of its application's windows")
        func testFocusRaisesOnlyRequestedWindow() async throws {
            let textEditWasRunning = isRunning(Self.textEditID)
            let previewWasRunning = isRunning(Self.previewID)

            let prefix = "hs-focus-test-\(UUID().uuidString)"
            let directory = FileManager.default.temporaryDirectory
            let behindURL = directory.appendingPathComponent("\(prefix)-behind.txt")
            let requestedURL = directory.appendingPathComponent("\(prefix)-requested.txt")
            let coverURL = directory.appendingPathComponent("\(prefix)-cover.png")
            try "behind".write(to: behindURL, atomically: true, encoding: .utf8)
            try "requested".write(to: requestedURL, atomically: true, encoding: .utf8)
            let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                                      bytesPerRow: 0, bitsPerPixel: 0))
            try #require(image.representation(using: .png, properties: [:])).write(to: coverURL)

            defer {
                cleanUp(Self.textEditID, documentsPrefixed: prefix, wasRunning: textEditWasRunning)
                cleanUp(Self.previewID, documentsPrefixed: prefix, wasRunning: previewWasRunning)
                for url in [behindURL, requestedURL, coverURL] {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            // Two TextEdit windows, both behind a Preview window.
            let (textEdit, textEditIDs) = try await open([behindURL, requestedURL], in: Self.textEditID)
            let (behindID, requestedID) = (textEditIDs[0], textEditIDs[1])
            let (preview, previewIDs) = try await open([coverURL], in: Self.previewID)
            let coverID = previewIDs[0]

            #expect(preview.setFrontmost(allWindows: true))
            let coverInFront = await waitUntil {
                isStacked([coverID, behindID]) && isStacked([coverID, requestedID])
            }
            try #require(coverInFront, "Preview did not come in front of the TextEdit windows")

            // Focus one TextEdit window through the JS API.
            let harness = JSTestHarness()
            harness.loadModule(HSApplicationModule.self, as: "application")
            harness.loadModule(HSWindowModule.self, as: "window")
            let focused = harness.evalBool("""
                hs.application.matchingBundleID('\(Self.textEditID)').allWindows
                    .find(w => w.title && w.title.indexOf('\(prefix)-requested') === 0)
                    .focus()
                """)
            #expect(!harness.hasException)
            #expect(focused == true)

            let requestedInFront = await waitUntil { textEdit.isActive && isStacked([requestedID, coverID]) }
            try #require(requestedInFront, "focus() did not bring the requested window in front of Preview")
            #expect(isStacked([requestedID, coverID, behindID]),
                    "the other TextEdit window should have stayed behind Preview")
        }
    }
}
