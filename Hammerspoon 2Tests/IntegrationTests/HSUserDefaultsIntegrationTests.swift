//
//  HSUserDefaultsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import Foundation
@testable import Hammerspoon_2

@Suite("hs.userdefaults tests")
struct HSUserDefaultsTests {

    // MARK: - Suite 1: API Structure

    @Suite("hs.userdefaults API structure tests")
    struct HSUserDefaultsStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUserDefaultsModule.self, as: "userdefaults")
            return harness
        }

        @Test("set is a function")
        func testSetIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.set") == "function")
        }

        @Test("get is a function")
        func testGetIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.get") == "function")
        }

        @Test("clear is a function")
        func testClearIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.clear") == "function")
        }

        @Test("getKeys is a function")
        func testGetKeysIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.getKeys") == "function")
        }

        @Test("on is a function")
        func testOnIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.userdefaults.once") == "function")
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSUserDefaultsModule.self, as: "userdefaults")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.userdefaults.on") == "function")
            #expect(harness.evalTypeOf("hs.userdefaults.off") == "function")
            #expect(harness.evalTypeOf("hs.userdefaults.once") == "function")

            harness.eval("""
                var fn = function(v) {};
                hs.userdefaults.on('__gcTestKey', fn);
                hs.userdefaults.off('__gcTestKey', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("_watcherEmitter is initialized by hs.userdefaults.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.userdefaults._watcherEmitter !== null && hs.userdefaults._watcherEmitter !== undefined"
            )
        }

        @Test("get() for an unknown key returns null without throwing")
        func testGetUnknownKeyReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.userdefaults.get('hs_userdefaults_test_definitely_unset_key')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("clear() for an unknown key returns false without throwing")
        func testClearUnknownKeyReturnsFalse() {
            let harness = makeHarness()
            harness.eval("var r = hs.userdefaults.clear('hs_userdefaults_test_definitely_unset_key')")
            #expect(harness.evalBool("r") == false)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2: Read / Write Behaviour

    @Suite("hs.userdefaults read/write tests", .serialized)
    struct HSUserDefaultsReadWriteTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUserDefaultsModule.self, as: "userdefaults")
            return harness
        }

        private func testKey() -> String {
            "hs_userdefaults_test_\(UUID().uuidString)"
        }

        @Test("string value round-trips through set/get")
        func testStringRoundTrip() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', 'hello')")
            #expect(harness.evalString("hs.userdefaults.get('\(key)')") == "hello")
            #expect(!harness.hasException)
        }

        @Test("number value round-trips through set/get")
        func testNumberRoundTrip() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', 3.14)")
            harness.expectTrue("Math.abs(hs.userdefaults.get('\(key)') - 3.14) < 0.001")
            #expect(!harness.hasException)
        }

        @Test("boolean value round-trips through set/get")
        func testBooleanRoundTrip() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', true)")
            #expect(harness.evalBool("hs.userdefaults.get('\(key)')") == true)
            #expect(!harness.hasException)
        }

        @Test("array value round-trips through set/get")
        func testArrayRoundTrip() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', ['a', 'b', 'c'])")
            harness.eval("var r = hs.userdefaults.get('\(key)')")
            harness.expectTrue("Array.isArray(r) && r.length === 3 && r[0] === 'a' && r[2] === 'c'")
            #expect(!harness.hasException)
        }

        @Test("object value round-trips through set/get")
        func testObjectRoundTrip() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', { x: 1, y: 'two' })")
            harness.eval("var r = hs.userdefaults.get('\(key)')")
            harness.expectTrue("r.x === 1 && r.y === 'two'")
            #expect(!harness.hasException)
        }

        @Test("Date value round-trips through set/get")
        func testDateRoundTrip() throws {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var original = new Date('2024-06-01T12:00:00.000Z')
                hs.userdefaults.set('\(key)', original)
                var r = hs.userdefaults.get('\(key)')
            """)
            harness.expectTrue("r instanceof Date")
            let roundTripped = try #require(harness.evalDouble("r.getTime()"))
            let original = try #require(harness.evalDouble("original.getTime()"))
            #expect(roundTripped == original)
            #expect(!harness.hasException)
        }

        @Test("set() with a native hs.* object does not crash, does not throw, and does not store anything")
        func testSetNativeObjectRejected() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            // A native Hammerspoon object (unlike a plain JS object or function) keeps its
            // native identity across the JS<->Swift bridge, so it reaches `set()` as a
            // non-property-list NSObject. Without validation, forwarding it straight to
            // UserDefaults raises an uncatchable Objective-C exception and crashes the process.
            harness.eval("hs.userdefaults.set('\(key)', hs.userdefaults)")
            harness.expectTrue("hs.userdefaults.get('\(key)') === null || hs.userdefaults.get('\(key)') === undefined")
            #expect(!harness.hasException)
        }

        @Test("set() with a function value stores an empty object rather than throwing")
        func testSetFunctionValueStoresEmptyObject() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            // JavaScriptCore's bridge has no property-list representation for a JS function,
            // so it coerces it to an empty object before Swift ever sees it. This is a
            // harmless JSC bridging quirk, not a storable-type validation gap.
            harness.eval("hs.userdefaults.set('\(key)', function() {})")
            harness.eval("var r = hs.userdefaults.get('\(key)')")
            harness.expectTrue("typeof r === 'object' && r !== null && Object.keys(r).length === 0")
            #expect(!harness.hasException)
        }

        @Test("set() with undefined does not store anything and does not throw")
        func testSetUndefinedValueRejected() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', undefined)")
            harness.expectTrue("hs.userdefaults.get('\(key)') === null || hs.userdefaults.get('\(key)') === undefined")
            #expect(!harness.hasException)
        }

        @Test("clear removes a stored value")
        func testClearRemovesValue() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', 'temp')")
            #expect(harness.evalBool("hs.userdefaults.clear('\(key)')") == true)
            harness.expectTrue("hs.userdefaults.get('\(key)') === null || hs.userdefaults.get('\(key)') === undefined")
            #expect(!harness.hasException)
        }

        @Test("overwriting a key replaces the previous value")
        func testOverwriteValue() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', 'first')")
            harness.eval("hs.userdefaults.set('\(key)', 'second')")
            #expect(harness.evalString("hs.userdefaults.get('\(key)')") == "second")
            #expect(!harness.hasException)
        }

        @Test("getKeys includes a newly stored key")
        func testGetKeysIncludesNewKey() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("hs.userdefaults.set('\(key)', 'present')")
            harness.expectTrue("hs.userdefaults.getKeys().includes('\(key)')")
            #expect(!harness.hasException)
        }

        @Test("getKeys no longer includes a cleared key")
        func testGetKeysExcludesClearedKey() {
            let key = testKey()
            let harness = makeHarness()

            harness.eval("hs.userdefaults.set('\(key)', 'present')")
            harness.eval("hs.userdefaults.clear('\(key)')")
            harness.expectTrue("!hs.userdefaults.getKeys().includes('\(key)')")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: Watchers

    @Suite("hs.userdefaults watcher tests", .serialized)
    struct HSUserDefaultsWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSUserDefaultsModule.self, as: "userdefaults")
            return harness
        }

        @Test("_addWatcher reports success, then refuses a second subscription by returning false")
        func testAddWatcherReportsRefusal() {
            let harness = makeHarness()
            harness.eval("""
            var first = hs.userdefaults._addWatcher('hs2RefusalTestKey', function() {});
            var second = hs.userdefaults._addWatcher('hs2RefusalTestKey', function() {});
            hs.userdefaults._removeWatcher('hs2RefusalTestKey');
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("first") == true)
            #expect(harness.evalBool("second") == false)
        }

        @Test("on() throws and records nothing when the native watcher fails to start")
        func testOnThrowsWhenNativeStartFails() {
            let harness = makeHarness()
            harness.eval("""
            hs.userdefaults._addWatcher = function(key, fn) { return false; };
            var threw = false;
            try {
                hs.userdefaults.on('hs2ThrowTestKey', function() {});
            } catch (err) {
                threw = true;
            }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            harness.expectFalse("hs.userdefaults._watcherEmitter.events['hs2ThrowTestKey'] && hs.userdefaults._watcherEmitter.events['hs2ThrowTestKey'].length > 0")
        }

        private func testKey() -> String {
            "hs_userdefaults_test_\(UUID().uuidString)"
        }

        @Test("watcher fires with the new value when the key changes")
        func testWatcherFiresOnChange() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var seenValue = null
                function handler(v) { seenValue = v }
                hs.userdefaults.on('\(key)', handler)
                hs.userdefaults.set('\(key)', 'watched-value')
            """)
            #expect(harness.evalString("seenValue") == "watched-value")
            #expect(!harness.hasException)
        }

        @Test("off stops further callbacks for that listener")
        func testOffStopsCallbacks() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var callCount = 0
                function handler() { callCount++ }
                hs.userdefaults.on('\(key)', handler)
                hs.userdefaults.set('\(key)', 'first')
                hs.userdefaults.off('\(key)', handler)
                hs.userdefaults.set('\(key)', 'second')
            """)
            #expect(harness.evalInt("callCount") == 1)
            #expect(!harness.hasException)
        }

        @Test("multiple listeners on the same key both fire")
        func testMultipleListenersFire() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var aCount = 0
                var bCount = 0
                function handlerA() { aCount++ }
                function handlerB() { bCount++ }
                hs.userdefaults.on('\(key)', handlerA)
                hs.userdefaults.on('\(key)', handlerB)
                hs.userdefaults.set('\(key)', 'value')
            """)
            #expect(harness.evalInt("aCount") == 1)
            #expect(harness.evalInt("bCount") == 1)
            #expect(!harness.hasException)
        }

        @Test("registering the same listener twice logs an error and does not double-fire")
        func testDuplicateListenerRejected() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var callCount = 0
                function handler() { callCount++ }
                hs.userdefaults.on('\(key)', handler)
                hs.userdefaults.on('\(key)', handler)
                hs.userdefaults.set('\(key)', 'value')
            """)
            #expect(harness.evalInt("callCount") == 1)
            #expect(!harness.hasException)
        }

        @Test("watching two different keys fires independently")
        func testIndependentKeysFireIndependently() {
            let keyA = testKey()
            let keyB = testKey()
            let harness = makeHarness()
            defer {
                harness.eval("hs.userdefaults.clear('\(keyA)')")
                harness.eval("hs.userdefaults.clear('\(keyB)')")
            }

            harness.eval("""
                var aCount = 0, bCount = 0
                hs.userdefaults.on('\(keyA)', function() { aCount++; });
                hs.userdefaults.on('\(keyB)', function() { bCount++; });
                hs.userdefaults.set('\(keyA)', 'value');
            """)
            #expect(harness.evalInt("aCount") == 1)
            #expect(harness.evalInt("bCount") == 0)
            #expect(!harness.hasException)
        }

        @Test("once-registered listener fires only one time")
        func testOnceFiresOnlyOnce() {
            let key = testKey()
            let harness = makeHarness()
            defer { harness.eval("hs.userdefaults.clear('\(key)')") }

            harness.eval("""
                var count = 0
                hs.userdefaults.once('\(key)', function() { count++; })
                hs.userdefaults.set('\(key)', 'first')
                hs.userdefaults.set('\(key)', 'second')
            """)
            #expect(harness.evalInt("count") == 1)
            #expect(!harness.hasException)
        }
    }
}
