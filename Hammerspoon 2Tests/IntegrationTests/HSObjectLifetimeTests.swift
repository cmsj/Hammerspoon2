//
//  HSObjectLifetimeTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Tests for the engine's object lifetime mechanisms: HSObjectTracker's active objects,
/// ModuleRoot's module wrapper pinning, hs.activeObjects(), and the JSTestHarness teardown check.
/// Per-module lifetime behaviour is tested in each module's own suite.
private final class DestroyProbe: NSObject, HSTrackedObject {
    var destroyed = false
    func destroy() { destroyed = true }
}

@Suite("Object lifetime tests")
struct HSObjectLifetimeTests {


    // MARK: - HSObjectTracker

    @Test("An active object is counted until it's made inactive")
    func testTrackerActiveCount() {
        let harness = JSTestHarness()
        let tracker = HSObjectTracker<NSObject>()
        let object = NSObject()
        tracker.add(object)
        #expect(tracker.activeCount == 0)

        tracker.setActive(object, true, in: harness.context)
        tracker.setActive(object, true, in: harness.context)
        #expect(tracker.activeCount == 1)
        #expect(tracker.isActive(object))

        tracker.setActive(object, false, in: harness.context)
        #expect(tracker.activeCount == 0)
        #expect(!tracker.isActive(object))
    }

    @Test("An active object is kept alive until removeAllObjects()")
    func testTrackerPinsUntilRemoveAll() {
        let harness = JSTestHarness()
        let tracker = HSObjectTracker<NSObject>()
        weak var weakObject: NSObject?
        autoreleasepool {
            let object = NSObject()
            weakObject = object
            tracker.add(object)
            tracker.setActive(object, true, in: harness.context)
        }
        harness.collectGarbage()
        #expect(weakObject != nil, "An active object must not be released")

        tracker.removeAllObjects()
        #expect(tracker.activeCount == 0)
        harness.collectGarbage()
        #expect(weakObject == nil, "removeAllObjects() must release every active object")
    }

    @Test("An object made active without a context is counted, but not once it's deallocated")
    func testTrackerWithoutContext() {
        let tracker = HSObjectTracker<NSObject>()
        autoreleasepool {
            let object = NSObject()
            tracker.setActive(object, true, in: nil)
            #expect(tracker.activeCount == 1)
        }
        #expect(tracker.activeCount == 0)
    }

    @Test("A tracker's shutdown() destroys every tracked object, active or not, and drops the pins")
    func testTrackerShutdown() {
        let harness = JSTestHarness()
        let tracker = HSObjectTracker<DestroyProbe>()
        let idle = DestroyProbe()
        let active = DestroyProbe()
        tracker.add(idle)
        tracker.add(active)
        tracker.setActive(active, true, in: harness.context)

        tracker.shutdown()
        #expect(idle.destroyed)
        #expect(active.destroyed)
        #expect(tracker.activeCount == 0)
        #expect(tracker.allObjects.isEmpty)
    }

    // MARK: - ModuleRoot

    @Test("A module's JS wrapper survives garbage collection, with properties set on it")
    func testModuleWrapperIsPinned() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()

        // A plain JS property with no @objc backing only survives if the same wrapper does
        autoreleasepool { _ = harness.eval("hs.timer.__lifetimeProbe = 42; void 0") }
        harness.collectGarbage()
        harness.expectTrue("hs.timer.__lifetimeProbe === 42")
    }

    @Test("A callback owned by a module survives garbage collection")
    func testModuleOwnedCallbackSurvivesGC() throws {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        autoreleasepool { _ = harness.eval("void hs.timer") }
        let module = try #require(root.modules["timer"])

        var callback: JSCallback?
        autoreleasepool {
            let function = harness.evalValue("(function() { return 42; })")!
            callback = JSCallback(value: function, owner: module)
        }
        harness.collectGarbage()

        #expect(callback?.value != nil, "A module-owned JSCallback must not be collected")
        #expect(callback?.call(withArguments: [])?.toInt32() == 42)
        callback?.detach(from: module)
    }

    // MARK: - hs.activeObjects()

    @Test("hs.activeObjects() lists running objects, and not stopped ones")
    func testActiveObjects() {
        let harness = JSTestHarness()
        harness.loadModuleRoot()

        harness.eval("var t = hs.timer.doEvery(60, function() {})")
        harness.expectTrue("hs.activeObjects().length === 1")
        harness.expectTrue("hs.activeObjects()[0] === t")

        harness.eval("t.stop()")
        harness.expectTrue("hs.activeObjects().length === 0")
    }

    @Test("Module shutdown releases every active object")
    func testShutdownReleasesActiveObjects() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()

        weak var timer: HSTimer?
        autoreleasepool {
            timer = harness.evalValue("hs.timer.doEvery(60, function() {})")?.toObjectOf(HSTimer.self) as? HSTimer
        }
        #expect(timer != nil)

        root.shutdown()
        #expect(HSActiveObjects.wrappers(in: harness.context).isEmpty)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        harness.collectGarbage()
        #expect(timer == nil, "Shutdown must not leave anything active")
    }

    @Test("ModuleRoot shutdown drops pins a module left behind, so they can't keep the context alive")
    func testShutdownDropsLeftoverPins() {
        let harness = JSTestHarness()
        let root = harness.loadModuleRoot()
        autoreleasepool { _ = harness.eval("void hs.timer") }

        // Stands in for a module whose shutdown() forgets to shut its tracker down
        let tracker = HSObjectTracker<NSObject>()
        weak var weakObject: NSObject?
        autoreleasepool {
            let object = NSObject()
            weakObject = object
            tracker.setActive(object, true, in: harness.context)
        }

        let leftovers = root.shutdown()
        #expect(leftovers.count == 1)
        #expect(HSActiveObjects.wrappers(in: harness.context).isEmpty)
        harness.collectGarbage()
        #expect(weakObject == nil, "ModuleRoot shutdown must drop every pin left in its context")
    }

    // MARK: - JSTestHarness

    @Test("The harness fails a test that ends with an unfinished one-shot object still active")
    func testHarnessTeardownCheck() {
        withKnownIssue {
            do {
                let harness = JSTestHarness()
                harness.loadModule(HSTimerModule.self, as: "timer")
                harness.eval("void hs.timer.doAfter(60, function() {})")
            }
        }
    }

    @Test("The harness fails a test whose modules leave an object active after shutdown")
    func testHarnessFailsOnPinsLeftAfterShutdown() {
        // Stands in for a module whose shutdown() forgets to shut its tracker down
        let tracker = HSObjectTracker<NSObject>()
        let object = NSObject()
        withKnownIssue {
            do {
                let harness = JSTestHarness()
                tracker.setActive(object, true, in: harness.context)
            }
        }
    }

    @Test("The harness leaves objects that run until stopped to module shutdown")
    func testHarnessTeardownIgnoresIndefiniteActivity() {
        let harness = JSTestHarness()
        harness.loadModule(HSTimerModule.self, as: "timer")
        harness.eval("void hs.timer.doEvery(60, function() {})")
    }
}
