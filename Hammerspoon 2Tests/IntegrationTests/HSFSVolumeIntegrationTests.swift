//
//  HSFSVolumeIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@MainActor
@Suite("hs.fs volume tests")
struct HSFSVolumeTests {

    // MARK: - API structure

    @Suite("hs.fs volume API structure tests")
    struct HSFSVolumeStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("volumes is a function")
        func testVolumesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.fs.volumes") == "function")
        }

        @Test("ejectVolume is a function")
        func testEjectVolumeIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.fs.ejectVolume") == "function")
        }

        @Test("addVolumeWatcher is a function")
        func testAddVolumeWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.fs.addVolumeWatcher") == "function")
        }

        @Test("removeVolumeWatcher is a function")
        func testRemoveVolumeWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.fs.removeVolumeWatcher") == "function")
        }

        @Test("addVolumeWatcher returns an object with an identifier string")
        func testWatcherHasIdentifier() {
            let harness = makeHarness()
            harness.eval("var w = hs.fs.addVolumeWatcher()")
            #expect(harness.evalTypeOf("w") == "object")
            #expect(harness.evalTypeOf("w.identifier") == "string")
            harness.expectTrue("w.identifier.length > 0")
            #expect(!harness.hasException)
        }

        @Test("watcher has start, stop, setCallback and destroy functions")
        func testWatcherMethods() {
            let harness = makeHarness()
            harness.eval("var w = hs.fs.addVolumeWatcher()")
            #expect(harness.evalTypeOf("w.start") == "function")
            #expect(harness.evalTypeOf("w.stop") == "function")
            #expect(harness.evalTypeOf("w.setCallback") == "function")
            #expect(harness.evalTypeOf("w.destroy") == "function")
            #expect(!harness.hasException)
        }

        @Test("two watchers have different identifiers")
        func testWatchersHaveUniqueIdentifiers() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.fs.addVolumeWatcher()
                    var b = hs.fs.addVolumeWatcher()
                    return a.identifier !== b.identifier
                })()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - volumes()

    @Suite("hs.fs.volumes() tests")
    struct HSFSVolumesTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("volumes() returns an object")
        func testVolumesReturnsObject() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.fs.volumes()") == "object")
            #expect(!harness.hasException)
        }

        @Test("volumes() includes the root filesystem")
        func testVolumesIncludesRoot() {
            let harness = makeHarness()
            harness.expectTrue("hs.fs.volumes()['/'] !== undefined")
            #expect(!harness.hasException)
        }

        @Test("root volume entry has expected properties")
        func testRootVolumeProperties() {
            let harness = makeHarness()
            harness.eval("var root = hs.fs.volumes()['/']")
            #expect(harness.evalTypeOf("root.name") == "string")
            #expect(harness.evalTypeOf("root.isLocal") == "boolean")
            #expect(harness.evalTypeOf("root.isReadOnly") == "boolean")
            #expect(harness.evalTypeOf("root.isRootFileSystem") == "boolean")
            #expect(harness.evalBool("root.isRootFileSystem") == true)
            #expect(harness.evalTypeOf("root.totalCapacity") == "number")
            #expect(harness.evalTypeOf("root.availableCapacity") == "number")
            harness.expectTrue("root.totalCapacity > 0")
            #expect(!harness.hasException)
        }

        @Test("volumes(false) default excludes hidden volumes — result has at least one entry")
        func testVolumesDefault() {
            let harness = makeHarness()
            harness.expectTrue("Object.keys(hs.fs.volumes()).length >= 1")
            #expect(!harness.hasException)
        }

        @Test("volumes(true) includes hidden volumes — result has at least as many as visible")
        func testVolumesShowHidden() {
            let harness = makeHarness()
            harness.expectTrue("""
                Object.keys(hs.fs.volumes(true)).length >= Object.keys(hs.fs.volumes(false)).length
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - ejectVolume()

    @Suite("hs.fs.ejectVolume() tests")
    struct HSFSEjectVolumeTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("ejectVolume('/') returns false — cannot eject root")
        func testEjectRootFails() {
            let harness = makeHarness()
            harness.expectTrue("hs.fs.ejectVolume('/') === false")
            #expect(!harness.hasException)
        }

        @Test("ejectVolume with a non-existent path returns false")
        func testEjectNonExistentPath() {
            let harness = makeHarness()
            harness.expectTrue("hs.fs.ejectVolume('/nonexistent/volume/path') === false")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Watcher lifecycle

    @Suite("hs.fs volume watcher lifecycle tests")
    struct HSFSVolumeWatcherLifecycleTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")
            return harness
        }

        @Test("start() and stop() can be chained and do not throw")
        func testStartStop() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.start().stop()
            """)
            #expect(!harness.hasException)
        }

        @Test("setCallback returns self for chaining")
        func testSetCallbackChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                var result = w.setCallback(function(event, info) {})
                var same = (result === w)
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("start returns self for chaining")
        func testStartChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                var result = w.start()
                var same = (result === w)
                w.stop()
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("stop returns self for chaining")
        func testStopChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.start()
                var result = w.stop()
                var same = (result === w)
            """)
            harness.expectTrue("same")
            #expect(!harness.hasException)
        }

        @Test("calling start twice does not crash")
        func testDoubleStart() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.start().start()
                w.stop()
            """)
            #expect(!harness.hasException)
        }

        @Test("calling stop before start does not crash")
        func testStopBeforeStart() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.stop()
            """)
            #expect(!harness.hasException)
        }

        @Test("removeVolumeWatcher stops a running watcher without throwing")
        func testRemoveWatcher() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.start()
                hs.fs.removeVolumeWatcher(w)
            """)
            #expect(!harness.hasException)
        }

        @Test("destroy() stops the watcher without throwing")
        func testDestroy() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.start()
                w.destroy()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory leak test

    @Test("active HSVolumeWatcher is released after shutdown")
    func testVolumeWatcherDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSFSModule.self, as: "fs")

            harness.eval("""
                var w = hs.fs.addVolumeWatcher()
                w.setCallback(function(event, info) {})
                w.start()
            """)

            if let swift = harness.evalValue("w")?.toObjectOf(HSVolumeWatcher.self) as? HSVolumeWatcher {
                tracker.track(swift)
            }

            harness.eval("w = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
