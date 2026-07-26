//
//  HSFSPathWatcherIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
@testable import Hammerspoon_2

// MARK: - Helpers

/// Creates a unique temporary directory and removes it on dealloc.
private final class TempWatchDir {
    let url: URL
    let path: String

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hs.fs-pathwatcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.path
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Write a file inside the directory to trigger a filesystem event.
    func touch(_ name: String) throws {
        let file = url.appendingPathComponent(name)
        try "x".write(to: file, atomically: true, encoding: .utf8)
    }
}

// MARK: - Test suite

@MainActor
@Suite("hs.fs path watcher tests")
struct HSFSPathWatcherTests {

    // MARK: - API structure

    @Suite("hs.fs path watcher API structure tests")
    struct HSFSPathWatcherStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("createPathWatcher is a function")
        func testCreatePathWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.fs.createPathWatcher === 'function'")
        }

        @Test("createPathWatcher returns an object")
        func testCreatePathWatcherReturnsObject() {
            let harness = makeHarness()
            harness.eval("var w = hs.fs.createPathWatcher('/tmp')")
            harness.expectTrue("typeof w === 'object'")
            #expect(!harness.hasException)
        }

        @Test("returned watcher has a string identifier")
        func testWatcherHasIdentifier() {
            let harness = makeHarness()
            harness.eval("var w = hs.fs.createPathWatcher('/tmp')")
            harness.expectTrue("typeof w.identifier === 'string'")
            harness.expectTrue("w.identifier.length > 0")
            #expect(!harness.hasException)
        }

        @Test("watcher has start, stop, setCallback and destroy functions")
        func testWatcherHasMethods() {
            let harness = makeHarness()
            harness.eval("var w = hs.fs.createPathWatcher('/tmp')")
            harness.expectTrue("typeof w.start === 'function'")
            harness.expectTrue("typeof w.stop === 'function'")
            harness.expectTrue("typeof w.setCallback === 'function'")
            harness.expectTrue("typeof w.destroy === 'function'")
            #expect(!harness.hasException)
        }

        @Test("two watchers have different identifiers")
        func testWatchersHaveUniqueIdentifiers() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.fs.createPathWatcher('/tmp')
                    var b = hs.fs.createPathWatcher('/tmp')
                    return a.identifier !== b.identifier
                })()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Lifecycle

    @Suite("hs.fs path watcher lifecycle tests", .serialized)
    struct HSFSPathWatcherLifecycleTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("start() returns self for chaining")
        func testStartChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/tmp')
                var same = (w.start() === w)
                w.stop()
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("stop() returns self for chaining")
        func testStopChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/tmp')
                w.start()
                var same = (w.stop() === w)
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("setCallback returns self for chaining")
        func testSetCallbackChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/tmp')
                var same = (w.setCallback(function() {}) === w)
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("start().stop() chain does not crash")
        func testStartStopChain() {
            let harness = makeHarness()
            harness.eval("hs.fs.createPathWatcher('/tmp').setCallback(function() {}).start().stop()")
            #expect(!harness.hasException)
        }

        @Test("calling start() twice does not crash")
        func testDoubleStart() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/tmp')
                w.start().start()
                w.stop()
            """)
            #expect(!harness.hasException)
        }

        @Test("calling stop() before start() does not crash")
        func testStopBeforeStart() {
            let harness = makeHarness()
            harness.eval("hs.fs.createPathWatcher('/tmp').stop()")
            #expect(!harness.hasException)
        }

        @Test("destroy() on a running watcher does not crash")
        func testDestroyRunning() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/tmp')
                w.setCallback(function() {}).start()
                w.destroy()
            """)
            #expect(!harness.hasException)
        }

        @Test("watcher on a non-existent path starts without crashing")
        func testNonExistentPath() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.createPathWatcher('/nonexistent/\(UUID().uuidString)')
                w.setCallback(function() {}).start().stop()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Callback firing

    @Suite("hs.fs path watcher callback tests", .serialized)
    struct HSFSPathWatcherCallbackTests {

        @Test("callback fires with paths and flags when a file is created")
        func testCallbackFiresOnFileCreation() async throws {
            let tmp = try TempWatchDir()
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")

            var callbackFired = false
            harness.registerCallback("onChanged") { callbackFired = true }

            // Store paths/flags in JS variables so we can read them back via evalValue.
            harness.eval("""
                var _cbPaths = null
                var _cbFlags = null
                var w = hs.fs.createPathWatcher('\(tmp.path)')
                w.setCallback(function(paths, flags) {
                    _cbPaths = paths
                    _cbFlags = flags
                    __test_callback('onChanged')
                }).start()
            """)
            #expect(!harness.hasException)

            try tmp.touch("test.txt")

            let fired = await harness.waitForAsync(timeout: 5.0) { callbackFired }
            #expect(fired, "callback should have fired after file creation")

            let pathsVal = harness.evalValue("_cbPaths")
            #expect(pathsVal?.isArray == true)
            let paths = (pathsVal?.toArray() ?? []).compactMap { $0 as? String }
            #expect(!paths.isEmpty)

            let flagsVal = harness.evalValue("_cbFlags")
            #expect(flagsVal?.isArray == true)

            harness.eval("w.stop()")
        }

        @Test("callback receives non-empty flags arrays")
        func testCallbackFlagsNonEmpty() async throws {
            let tmp = try TempWatchDir()
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")

            var callbackFired = false
            harness.registerCallback("onChanged") { callbackFired = true }

            harness.eval("""
                var _cbFlags = null
                var w = hs.fs.createPathWatcher('\(tmp.path)')
                w.setCallback(function(paths, flags) {
                    _cbFlags = flags
                    __test_callback('onChanged')
                }).start()
            """)
            #expect(!harness.hasException)

            try tmp.touch("flagtest.txt")

            let fired = await harness.waitForAsync(timeout: 5.0) { callbackFired }
            #expect(fired, "callback should have fired")

            // Each entry in _cbFlags should be a non-empty array of strings.
            let flagsVal = harness.evalValue("_cbFlags")
            #expect(flagsVal?.isArray == true)
            harness.expectTrue("_cbFlags.length > 0")
            harness.expectFalse("_cbFlags.some(function(f) { return f.length === 0 })")

            harness.eval("w.stop()")
        }

        @Test("callback is not invoked after stop()")
        func testNoCallbackAfterStop() async throws {
            let tmp = try TempWatchDir()
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")

            var callCount = 0
            harness.registerCallback("onChanged") { callCount += 1 }

            harness.eval("""
                var w = hs.fs.createPathWatcher('\(tmp.path)')
                w.setCallback(function() {
                    __test_callback('onChanged')
                }).start().stop()
            """)
            #expect(!harness.hasException)

            try tmp.touch("after-stop.txt")
            _ = await harness.waitForAsync(timeout: 2.0) { callCount > 0 }
            #expect(callCount == 0, "callback should not fire after stop()")
        }
    }

    // MARK: - Memory leak test

    @Test("active HSPathWatcher is released after shutdown")
    func testPathWatcherDoesNotLeakAfterReload() throws {
        let tmp = try TempWatchDir()
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")

            harness.eval("""
                var w = hs.fs.createPathWatcher('\(tmp.path)')
                w.setCallback(function(paths, flags) {})
                w.start()
            """)

            if let swift = harness.evalValue("w")?.toObjectOf(HSPathWatcher.self) as? HSPathWatcher {
                tracker.track(swift)
            }

            harness.eval("w = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
