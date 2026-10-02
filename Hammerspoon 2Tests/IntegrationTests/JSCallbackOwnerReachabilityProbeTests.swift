//
//  JSCallbackOwnerReachabilityProbeTests.swift
//  Hammerspoon 2Tests
//
//  Standalone proof of the mechanism behind the hs.usb/hs.serial watcher-callback-goes-silently-
//  dead bug (see project memory: feedback_jscallback_owner_self_wrong_for_module_singletons).
//  Isolated from any real module's complexity (IOKit, MainActor, etc.) so the result is
//  unambiguous: JSCallback(value:owner:self) is unsafe for a module-level singleton reached via
//  an unpinned computed accessor (ModuleRoot's module properties), because nothing keeps a
//  specific wrapper for `self` reachable from JS once the registering call's stack frame goes
//  cold - at which point JSManagedValue's "owner reachable" condition goes false and the
//  callback's .value silently becomes nil, even though the JSCallback object itself persists.
//
//  Plain JSFunction storage (no JSCallback/JSManagedValue) does not have this problem, because
//  it is unconditionally retained by ARC regardless of the owning object's own JS reachability.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@objc protocol ProbeAPI: JSExport {
    @objc func register(_ fn: JSValue)
}

final class Probe: NSObject, ProbeAPI {
    var callback: JSCallback?
    @objc func register(_ fn: JSValue) {
        callback = JSCallback(value: fn, owner: self)
    }
}

@objc protocol PlainProbeAPI: JSExport {
    @objc func register(_ fn: JSValue)
}

final class PlainProbe: NSObject, PlainProbeAPI {
    // Plain strong JSValue, exactly like HSAudioDeviceModule.moduleCallback / HSUSBModule's
    // fixed `listener` - no JSCallback/JSManagedValue involved at all.
    var callback: JSFunction?
    @objc func register(_ fn: JSValue) {
        callback = fn
    }
}

@Suite("JSCallback owner-reachability probe")
struct JSCallbackOwnerReachabilityProbeTests {

    @Test("JSCallback(owner: self) with GC forced in the same stack frame as registration survives - a false sense of safety")
    func testUnpinnedAccessorWarmStackIsMisleading() {
        let harness = JSTestHarness()
        let probe = Probe()

        let getter: @convention(block) () -> ProbeAPI = { probe }
        harness.context.setObject(getter, forKeyedSubscript: "__get_probe" as NSString)
        harness.eval("Object.defineProperty(globalThis, 'probe', { get: __get_probe, configurable: true });")

        harness.eval("probe.register(function() { return 42; });")
        #expect(!harness.hasException)
        #expect(probe.callback != nil)
        #expect(probe.callback?.value != nil, "sanity: callback should be alive immediately after registration")

        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

        // Forcing GC right here, in the same Swift stack frame that just registered the
        // callback, does NOT reproduce the bug - almost certainly because conservative stack
        // scanning sees leftover temporaries from the registration call and treats them as GC
        // roots. This is the trap: testing it this way gives a false "it's fine" result.
        #expect(probe.callback != nil)
        #expect(probe.callback?.value != nil)
    }

    @Test("JSCallback(owner: self) with an unpinned accessor really does go stale once the stack is cold")
    func testUnpinnedAccessorColdStack() {
        let harness = JSTestHarness()
        let probe = Probe()

        let getter: @convention(block) () -> ProbeAPI = { probe }
        harness.context.setObject(getter, forKeyedSubscript: "__get_probe" as NSString)
        harness.eval("Object.defineProperty(globalThis, 'probe', { get: __get_probe, configurable: true });")

        autoreleasepool {
            harness.eval("probe.register(function() { return 42; });")
        }
        #expect(!harness.hasException)

        // Churn the stack/autorelease pool with unrelated work between registration and GC,
        // rather than forcing GC in the same frame that just did the registration - this is
        // what actually distinguishes this test from the misleading "warm stack" one above.
        for i in 0..<2000 {
            autoreleasepool {
                _ = harness.eval("({ i: \(i), s: 'churn' + \(i) });")
            }
        }

        autoreleasepool {
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        }
        autoreleasepool {
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        }

        #expect(probe.callback != nil, "the JSCallback Swift wrapper itself should never go nil on its own")

        // This is the actual bug, reproduced deterministically: .value goes nil once the stack
        // has gone cold, confirming JSManagedValue's owner-reachability condition failed - not a
        // regression to fix, this IS what hs.usb's _addWatcher hit before being switched to
        // plain JSFunction storage. Recorded as a known issue so the suite stays green while
        // still asserting (and alerting us if the behavior ever changes) that it reproduces.
        withKnownIssue("JSManagedValue correctly drops .value once `owner`'s unpinned wrapper is no longer JS-reachable - this is the documented failure mode, not a bug in this test") {
            #expect(probe.callback?.value != nil)
        }
    }

    @Test("plain JSFunction storage (no JSCallback) survives the same cold-stack GC that kills JSCallback - matches hs.audiodevice.moduleCallback")
    func testPlainJSFunctionUnpinnedAccessorColdStack() {
        let harness = JSTestHarness()
        let probe = PlainProbe()

        let getter: @convention(block) () -> PlainProbeAPI = { probe }
        harness.context.setObject(getter, forKeyedSubscript: "__get_plainprobe" as NSString)
        harness.eval("Object.defineProperty(globalThis, 'plainprobe', { get: __get_plainprobe, configurable: true });")

        autoreleasepool {
            harness.eval("plainprobe.register(function() { return 42; });")
        }
        #expect(!harness.hasException)

        for i in 0..<2000 {
            autoreleasepool {
                _ = harness.eval("({ i: \(i), s: 'churn' + \(i) });")
            }
        }

        autoreleasepool {
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        }
        autoreleasepool {
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        }

        #expect(probe.callback != nil, "plain JSFunction should survive - it is unconditionally retained by ARC, not by JSManagedValue's owner-reachability check")
    }

    @Test("JSCallback(owner: self) where self is reached via a PINNED (stored) property")
    func testPinnedProperty() {
        let harness = JSTestHarness()
        let probe = Probe()

        // Store as a plain value property (like JSTestHarness.loadModule does), not a computed
        // accessor - this is the "something holds a live JS reference" control case.
        harness.context.setObject(probe, forKeyedSubscript: "probe" as NSString)

        harness.eval("probe.register(function() { return 42; });")
        #expect(!harness.hasException)

        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
        unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

        #expect(probe.callback?.value != nil, "pinned-wrapper case should definitely survive")
    }
}
