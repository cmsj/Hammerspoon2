//
//  JSCallbackOwnerReachabilityProbeTests.swift
//  Hammerspoon 2Tests
//
//  SCRATCH / investigation only - not meant to be committed. Directly tests whether
//  JSCallback(value:owner:self) actually goes nil after GC when `self` is reached via an
//  unpinned computed accessor (mirroring ModuleRoot.usb), isolated from HSUSBModule's own
//  complexity (IOKit, MainActor, etc.) so the result is unambiguous.
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

    @Test("JSCallback(owner: self) where self is reached via an unpinned computed accessor")
    func testUnpinnedAccessor() {
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

        print("PROBE[unpinned] callback=\(String(describing: probe.callback)) value=\(String(describing: probe.callback?.value))")
        #expect(probe.callback != nil, "the JSCallback Swift wrapper itself should never go nil on its own")
        #expect(probe.callback?.value != nil, "EXPECTED TO FAIL IF THEORY IS RIGHT: .value should have gone nil")
    }

    @Test("JSCallback(owner: self) with an unpinned accessor, separated calls + stack churn + autoreleasepool draining")
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
        // rather than forcing GC in the same frame that just did the registration.
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

        print("PROBE[cold] callback=\(String(describing: probe.callback)) value=\(String(describing: probe.callback?.value))")
        #expect(probe.callback != nil)
        #expect(probe.callback?.value != nil, "EXPECTED TO FAIL IF THEORY IS RIGHT: .value should have gone nil after cold-stack GC")
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

        print("PLAINPROBE[cold] callback=\(String(describing: probe.callback))")
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

        print("PROBE[pinned] callback=\(String(describing: probe.callback)) value=\(String(describing: probe.callback?.value))")
        #expect(probe.callback?.value != nil, "pinned-wrapper case should definitely survive")
    }
}
