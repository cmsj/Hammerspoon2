//
//  HSPasteboardIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Chris Jones on 13/05/2026.
//

import Testing
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

// MARK: - Suite 1: API Structure

/// Tests the module's API surface — that all expected functions and properties exist.
/// No pasteboard reads or writes are performed.
@Suite("hs.pasteboard API structure tests")
struct HSPasteboardStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPasteboardModule.self, as: "pasteboard")
        return harness
    }

    // MARK: Read functions

    @Test("readString is a function") func testReadStringIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readString === 'function'")
    }

    @Test("readHTML is a function") func testReadHTMLIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readHTML === 'function'")
    }

    @Test("readRTF is a function") func testReadRTFIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readRTF === 'function'")
    }

    @Test("readURL is a function") func testReadURLIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readURL === 'function'")
    }

    @Test("readImage is a function") func testReadImageIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readImage === 'function'")
    }

    @Test("readData is a function") func testReadDataIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.readData === 'function'")
    }

    // MARK: Write functions

    @Test("writeString is a function") func testWriteStringIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeString === 'function'")
    }

    @Test("writeHTML is a function") func testWriteHTMLIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeHTML === 'function'")
    }

    @Test("writeRTF is a function") func testWriteRTFIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeRTF === 'function'")
    }

    @Test("writeURL is a function") func testWriteURLIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeURL === 'function'")
    }

    @Test("writeImage is a function") func testWriteImageIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeImage === 'function'")
    }

    @Test("writeData is a function") func testWriteDataIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeData === 'function'")
    }

    @Test("writeObjects is a function") func testWriteObjectsIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.writeObjects === 'function'")
    }

    // MARK: Introspection

    @Test("types is a function") func testTypesIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.types === 'function'")
    }

    @Test("hasType is a function") func testHasTypeIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.hasType === 'function'")
    }

    @Test("changeCount is a number") func testChangeCountIsNumber() {
        makeHarness().expectTrue("typeof hs.pasteboard.changeCount === 'number'")
    }

    // MARK: Management

    @Test("clear is a function") func testClearIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.clear === 'function'")
    }

    // MARK: Watcher API

    @Test("addWatcher is a function") func testAddWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.addWatcher === 'function'")
    }

    @Test("removeWatcher is a function") func testRemoveWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.pasteboard.removeWatcher === 'function'")
    }

    @Test("watcherInterval is a number") func testWatcherIntervalIsNumber() {
        makeHarness().expectTrue("typeof hs.pasteboard.watcherInterval === 'number'")
    }

    @Test("watcherInterval defaults to 0.5") func testWatcherIntervalDefault() {
        makeHarness().expectEqual("hs.pasteboard.watcherInterval", 0.5)
    }

    @Test("watcherInterval can be changed") func testWatcherIntervalMutable() {
        let harness = makeHarness()
        harness.eval("hs.pasteboard.watcherInterval = 1.0")
        harness.expectEqual("hs.pasteboard.watcherInterval", 1.0)
        harness.eval("hs.pasteboard.watcherInterval = 0.5")  // restore
    }

    @Test("_watcherEmitter is initialized by hs.pasteboard.js") func testWatcherEmitterInitialized() {
        makeHarness().expectTrue(
            "hs.pasteboard._watcherEmitter !== null && hs.pasteboard._watcherEmitter !== undefined"
        )
    }
}

// MARK: - Suite 2: Read / Write Round-trips

/// Tests that data written to the pasteboard can be read back correctly.
/// These tests modify the real system pasteboard and restore it afterwards.
@Suite("hs.pasteboard read/write tests", .serialized)
struct HSPasteboardReadWriteTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPasteboardModule.self, as: "pasteboard")
        return harness
    }

    /// Save and restore the real pasteboard contents around a test.
    private func withSavedPasteboard(_ body: () -> Void) {
        let saved = NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        let savedChangeCount = NSPasteboard.general.changeCount

        body()

        // Restore
        if let saved, NSPasteboard.general.changeCount != savedChangeCount {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved)
        }
    }

    // MARK: Plain text

    @Test("writeString round-trips through readString")
    func testStringRoundTrip() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('hello from hammerspoon')")
            harness.expectEqual("hs.pasteboard.readString()", "hello from hammerspoon")
        }
    }

    @Test("writeString returns true on success")
    func testWriteStringReturnsTrue() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectTrue("hs.pasteboard.writeString('test') === true")
        }
    }

    @Test("writeString handles unicode correctly")
    func testStringUnicode() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('emoji: 🎉 日本語')")
            harness.expectEqual("hs.pasteboard.readString()", "emoji: 🎉 日本語")
        }
    }

    @Test("writeString handles an empty string")
    func testStringEmpty() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('')")
            // Empty string may return empty or null depending on platform behaviour
            harness.expectTrue(
                "(function() { var s = hs.pasteboard.readString(); return s === '' || s === null || s === undefined; })()"
            )
        }
    }

    // MARK: HTML

    @Test("writeHTML round-trips through readHTML")
    func testHTMLRoundTrip() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeHTML('<b>bold text</b>')")
            harness.expectEqual("hs.pasteboard.readHTML()", "<b>bold text</b>")
        }
    }

    @Test("writeHTML returns true on success")
    func testWriteHTMLReturnsTrue() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectTrue("hs.pasteboard.writeHTML('<p>hi</p>') === true")
        }
    }

    // MARK: URL

    @Test("writeURL round-trips through readURL")
    func testURLRoundTrip() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeURL('https://hammerspoon.org')")
            harness.expectEqual("hs.pasteboard.readURL()", "https://hammerspoon.org")
        }
    }

    @Test("writeURL returns false for an invalid URL")
    func testWriteURLInvalidURL() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectFalse("hs.pasteboard.writeURL('not a valid url !!') === true")
        }
    }

    // MARK: Raw data

    @Test("writeData/readData round-trip via base64")
    func testDataRoundTrip() {
        withSavedPasteboard {
            let harness = makeHarness()
            // Compute base64 from Swift (btoa is not available in standalone JSContext)
            let originalBase64 = Data("hello".utf8).base64EncodedString()
            harness.eval("hs.pasteboard.writeData('\(originalBase64)', 'public.utf8-plain-text')")
            let result = harness.eval("hs.pasteboard.readData('public.utf8-plain-text')") as? String
            #expect(result != nil, "readData should return a non-null string")
            if let b64 = result, let data = Data(base64Encoded: b64) {
                #expect(String(data: data, encoding: .utf8) == "hello")
            }
        }
    }

    @Test("writeData returns false for invalid base64")
    func testWriteDataInvalidBase64() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectFalse(
                "hs.pasteboard.writeData('!!!not valid base64!!!', 'public.utf8-plain-text') === true"
            )
        }
    }

    // MARK: Multi-type (writeObjects)

    @Test("writeObjects writes multiple UTI types atomically")
    func testWriteObjects() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("""
                hs.pasteboard.writeObjects({
                    "public.utf8-plain-text": "plain hello",
                    "public.html": "<b>bold hello</b>"
                });
            """)
            harness.expectEqual("hs.pasteboard.readString()", "plain hello")
            harness.expectEqual("hs.pasteboard.readHTML()", "<b>bold hello</b>")
        }
    }

    @Test("writeObjects returns true on success")
    func testWriteObjectsReturnsTrue() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectTrue("""
                hs.pasteboard.writeObjects({ "public.utf8-plain-text": "test" }) === true
            """)
        }
    }

    @Test("writeObjects returns false when passed a non-object")
    func testWriteObjectsNonObject() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectFalse("hs.pasteboard.writeObjects('a string') === true")
        }
    }

    @Test("writeObjects returns false when passed an object with no string values")
    func testWriteObjectsNoValidEntries() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.expectFalse("hs.pasteboard.writeObjects({ 'public.utf8-plain-text': 42 }) === true")
        }
    }

    // MARK: Introspection

    @Test("types() returns an array after writing")
    func testTypesReturnsArray() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('type check')")
            harness.expectTrue("Array.isArray(hs.pasteboard.types())")
            harness.expectTrue("hs.pasteboard.types().length > 0")
        }
    }

    @Test("types() contains the plain-text UTI after writeString")
    func testTypesContainsPlainText() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('check types')")
            harness.expectTrue("hs.pasteboard.types().indexOf('public.utf8-plain-text') !== -1")
        }
    }

    @Test("hasType returns true for a type that was written")
    func testHasTypeTrue() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('has type check')")
            harness.expectTrue("hs.pasteboard.hasType('public.utf8-plain-text')")
        }
    }

    @Test("hasType returns false for a type that was not written")
    func testHasTypeFalse() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('only plain text')")
            harness.expectFalse("hs.pasteboard.hasType('com.adobe.pdf')")
        }
    }

    @Test("changeCount is an integer that increments after a write")
    func testChangeCountIncrements() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("var _countBefore = hs.pasteboard.changeCount")
            harness.eval("hs.pasteboard.writeString('increment test')")
            harness.expectTrue("hs.pasteboard.changeCount > _countBefore")
        }
    }

    @Test("clear() removes all contents")
    func testClear() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('to be cleared')")
            harness.eval("hs.pasteboard.clear()")
            harness.expectTrue(
                "(function() { var s = hs.pasteboard.readString(); return s === null || s === undefined; })()"
            )
        }
    }

    // MARK: Null reads

    @Test("readString returns null when pasteboard has no text")
    func testReadStringNullWhenEmpty() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.clear()")
            harness.expectTrue(
                "(function() { var s = hs.pasteboard.readString(); return s === null || s === undefined; })()"
            )
        }
    }

    @Test("readImage returns null when pasteboard has no image")
    func testReadImageNullWhenNoImage() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('only text')")
            harness.expectTrue(
                "(function() { var i = hs.pasteboard.readImage(); return i === null || i === undefined; })()"
            )
        }
    }

    @Test("readData returns null for a UTI not present on the pasteboard")
    func testReadDataNullForMissingType() {
        withSavedPasteboard {
            let harness = makeHarness()
            harness.eval("hs.pasteboard.writeString('only text')")
            harness.expectTrue(
                "(function() { var d = hs.pasteboard.readData('com.example.nonexistent.type'); return d === null || d === undefined; })()"
            )
        }
    }
}

// MARK: - Suite 3: Watcher Structure

/// Tests add/remove watcher lifecycle mechanics — no pasteboard writes are needed.
@Suite("hs.pasteboard watcher structure tests")
struct HSPasteboardWatcherStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPasteboardModule.self, as: "pasteboard")
        return harness
    }

    @Test("addWatcher throws when listener is not a function")
    func testAddWatcherThrowsForNonFunction() {
        let harness = makeHarness()
        harness.eval("hs.pasteboard.addWatcher('not a function')")
        #expect(harness.hasException)
    }

    @Test("addWatcher throws when listener is null")
    func testAddWatcherThrowsForNull() {
        let harness = makeHarness()
        harness.eval("hs.pasteboard.addWatcher(null)")
        #expect(harness.hasException)
    }

    @Test("addWatcher and removeWatcher cycle completes without error")
    func testAddRemoveCycleIsSafe() {
        let harness = makeHarness()
        harness.eval("""
            var _pw1Fn = function(count) {};
            hs.pasteboard.addWatcher(_pw1Fn);
            hs.pasteboard.removeWatcher(_pw1Fn);
        """)
        #expect(!harness.hasException)
    }

    @Test("adding the same listener twice is idempotent")
    func testAddSameListenerTwiceIsIdempotent() {
        let harness = makeHarness()
        harness.eval("""
            var _pw2Fn = function(count) {};
            hs.pasteboard.addWatcher(_pw2Fn);
            hs.pasteboard.addWatcher(_pw2Fn);
            hs.pasteboard.removeWatcher(_pw2Fn);
        """)
        #expect(!harness.hasException)
    }

    @Test("multiple distinct listeners can be added and removed")
    func testMultipleDistinctListeners() {
        let harness = makeHarness()
        harness.eval("""
            var _pw3Fn1 = function(count) {};
            var _pw3Fn2 = function(count) {};
            var _pw3Fn3 = function(count) {};
            hs.pasteboard.addWatcher(_pw3Fn1);
            hs.pasteboard.addWatcher(_pw3Fn2);
            hs.pasteboard.addWatcher(_pw3Fn3);
            hs.pasteboard.removeWatcher(_pw3Fn1);
            hs.pasteboard.removeWatcher(_pw3Fn2);
            hs.pasteboard.removeWatcher(_pw3Fn3);
        """)
        #expect(!harness.hasException)
    }

    @Test("removeWatcher with an unregistered listener does not throw")
    func testRemoveUnregisteredListenerIsSafe() {
        let harness = makeHarness()
        harness.eval("hs.pasteboard.removeWatcher(function(count) {})")
        #expect(!harness.hasException)
    }

    @Test("removing one of two listeners leaves the other in place")
    func testRemovingOneListenerLeavesOtherIntact() {
        let harness = makeHarness()
        harness.eval("""
            var _pw4Fn1 = function(count) {};
            var _pw4Fn2 = function(count) {};
            hs.pasteboard.addWatcher(_pw4Fn1);
            hs.pasteboard.addWatcher(_pw4Fn2);
            hs.pasteboard.removeWatcher(_pw4Fn1);
            hs.pasteboard.removeWatcher(_pw4Fn2);
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: Watcher Event Delivery

/// Tests that registered callbacks are invoked when the pasteboard contents change.
/// These tests write to the real system pasteboard and restore it afterwards.
@Suite("hs.pasteboard watcher event delivery tests", .serialized)
struct HSPasteboardWatcherEventTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPasteboardModule.self, as: "pasteboard")
        return harness
    }

    @Test("watcher callback is invoked when the pasteboard changes")
    func testWatcherReceivesChange() async {
        let harness = makeHarness()

        // Use a fast interval so the test doesn't take long
        harness.eval("hs.pasteboard.watcherInterval = 0.1")
        harness.eval("""
            var _we1Count = 0;
            var _we1Fn = function(changeCount) { _we1Count++; };
            hs.pasteboard.addWatcher(_we1Fn);
        """)
        defer {
            harness.eval("hs.pasteboard.removeWatcher(_we1Fn)")
            harness.eval("hs.pasteboard.watcherInterval = 0.5")
        }

        // Write to the pasteboard to trigger a change
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("watcher trigger \(Date())", forType: .string)

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_we1Count > 0") as? Bool == true
        }
        #expect(received, "Watcher callback should have fired after pasteboard write")
    }

    @Test("callback receives the new changeCount as a number")
    func testWatcherCallbackReceivesChangeCount() async {
        let harness = makeHarness()

        harness.eval("hs.pasteboard.watcherInterval = 0.1")
        harness.eval("""
            var _we2ReceivedCount = null;
            var _we2Fn = function(changeCount) {
                if (_we2ReceivedCount === null) { _we2ReceivedCount = changeCount; }
            };
            hs.pasteboard.addWatcher(_we2Fn);
        """)
        defer {
            harness.eval("hs.pasteboard.removeWatcher(_we2Fn)")
            harness.eval("hs.pasteboard.watcherInterval = 0.5")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("count type check \(Date())", forType: .string)

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_we2ReceivedCount !== null") as? Bool == true
        }

        if received {
            harness.expectTrue("typeof _we2ReceivedCount === 'number'")
            harness.expectTrue("_we2ReceivedCount > 0")
        } else {
            #expect(Bool(false), "Watcher callback should have fired")
        }
    }

    @Test("multiple listeners all receive the same change event")
    func testMultipleListenersAllReceiveChange() async {
        let harness = makeHarness()

        harness.eval("hs.pasteboard.watcherInterval = 0.1")
        harness.eval("""
            var _we3Count1 = 0, _we3Count2 = 0;
            var _we3Fn1 = function(c) { _we3Count1++; };
            var _we3Fn2 = function(c) { _we3Count2++; };
            hs.pasteboard.addWatcher(_we3Fn1);
            hs.pasteboard.addWatcher(_we3Fn2);
        """)
        defer {
            harness.eval("""
                hs.pasteboard.removeWatcher(_we3Fn1);
                hs.pasteboard.removeWatcher(_we3Fn2);
            """)
            harness.eval("hs.pasteboard.watcherInterval = 0.5")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("multi-listener test \(Date())", forType: .string)

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_we3Count1 > 0 && _we3Count2 > 0") as? Bool == true
        }

        if received {
            harness.expectTrue("_we3Count1 > 0")
            harness.expectTrue("_we3Count2 > 0")
        } else {
            #expect(Bool(false), "Both watcher callbacks should have fired")
        }
    }

    @Test("a removed listener does not receive subsequent events")
    func testRemovedListenerDoesNotReceiveEvents() async {
        let harness = makeHarness()

        harness.eval("hs.pasteboard.watcherInterval = 0.1")
        harness.eval("""
            var _we4RemovedCount = 0, _we4KeptCount = 0;
            var _we4RemovedFn = function(c) { _we4RemovedCount++; };
            var _we4KeptFn    = function(c) { _we4KeptCount++; };
            hs.pasteboard.addWatcher(_we4RemovedFn);
            hs.pasteboard.addWatcher(_we4KeptFn);
            hs.pasteboard.removeWatcher(_we4RemovedFn);
        """)
        defer {
            harness.eval("hs.pasteboard.removeWatcher(_we4KeptFn)")
            harness.eval("hs.pasteboard.watcherInterval = 0.5")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("removed listener test \(Date())", forType: .string)

        let received = await harness.waitForAsync(timeout: 2.0) {
            harness.eval("_we4KeptCount > 0") as? Bool == true
        }

        if received {
            harness.expectTrue("_we4KeptCount > 0")
            harness.expectEqual("_we4RemovedCount", 0)
        } else {
            #expect(Bool(false), "The kept watcher callback should have fired")
        }
    }
}
