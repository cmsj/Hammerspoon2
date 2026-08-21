//
//  HSSharingIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Suite 1: hs.sharing module API structure

@Suite("hs.sharing tests", .serialized)
struct HSSharingTests {

    @Suite("hs.sharing module API structure")
    struct HSSharingModuleAPITests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSharingModule.self, as: "sharing")
            return harness
        }

        @Test("hs.sharing is an object")
        func testModuleIsObject() {
            #expect(makeHarness().evalTypeOf("hs.sharing") == "object")
        }

        @Test("createShare is a function")
        func testCreateShareIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.sharing.createShare") == "function")
        }

        @Test("servicesFor is a function")
        func testServicesForIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.sharing.servicesFor") == "function")
        }

        @Test("builtinServices is an object")
        func testBuiltinServicesIsObject() {
            #expect(makeHarness().evalTypeOf("hs.sharing.builtinServices") == "object")
        }

        @Test("builtinServices has the expected shortcut keys", arguments: [
            "mail", "message", "airdrop", "safariReadingList", "photos", "desktopPicture",
        ])
        func testBuiltinServicesKeys(key: String) {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.sharing.builtinServices.\(key)") == "string")
            harness.eval("var v = hs.sharing.builtinServices.\(key)")
            harness.expectTrue("v.length > 0")
        }
    }

    // MARK: - Suite 2: createShare / servicesFor behaviour

    @Suite("hs.sharing createShare behaviour")
    struct HSSharingCreateShareTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSharingModule.self, as: "sharing")
            return harness
        }

        @Test("createShare with an unknown name returns null")
        func testCreateShareUnknownReturnsNull() {
            let harness = makeHarness()
            harness.eval("var s = hs.sharing.createShare('not-a-real-service')")
            #expect(!harness.hasException)
            #expect(harness.evalBool("s === null || s === undefined") == true)
        }

        @Test("createShare with a known builtin returns a usable HSSharingService")
        func testCreateShareKnownReturnsObject() {
            let harness = makeHarness()
            harness.eval("var s = hs.sharing.createShare(hs.sharing.builtinServices.safariReadingList)")
            #expect(!harness.hasException)
            #expect(harness.evalString("s.typeName") == "HSSharingService")
            #expect(harness.evalTypeOf("s.identifier") == "string")
            #expect(harness.evalTypeOf("s.title") == "string")
            harness.expectTrue("s.title.length > 0")
            #expect(harness.evalTypeOf("s.image") == "object")
        }

        @Test("servicesFor returns an array")
        func testServicesForReturnsArray() {
            let harness = makeHarness()
            harness.eval("var list = hs.sharing.servicesFor(['https://www.hammerspoon.org'])")
            #expect(!harness.hasException)
            harness.expectTrue("Array.isArray(list)")
        }
    }

    // MARK: - Suite 3: HSSharingService behaviour

    @Suite("hs.sharing HSSharingService behaviour")
    struct HSSharingServiceTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSharingModule.self, as: "sharing")
            harness.eval("var s = hs.sharing.createShare(hs.sharing.builtinServices.safariReadingList)")
            return harness
        }

        @Test("canShareItems returns a boolean for a plain string")
        func testCanShareItemsString() {
            let harness = makeHarness()
            harness.eval("var r = s.canShareItems(['https://www.hammerspoon.org'])")
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("r") == "boolean")
        }

        @Test("canShareItems returns a boolean for an HSImage")
        func testCanShareItemsImage() {
            let harness = makeHarness()
            harness.eval("var img = HSImage.fromName('NSComputer')")
            harness.eval("var r = s.canShareItems([img])")
            #expect(!harness.hasException)
            #expect(harness.evalTypeOf("r") == "boolean")
        }

        @Test("setCallback returns the same object for chaining")
        func testSetCallbackChains() {
            let harness = makeHarness()
            harness.eval("var same = (s.setCallback(function(){}) === s)")
            #expect(!harness.hasException)
            #expect(harness.evalBool("same") == true)
        }

        @Test("recipients round-trips")
        func testRecipientsRoundTrip() {
            let harness = makeHarness()
            harness.eval("s.recipients = ['someone@example.com']")
            #expect(!harness.hasException)
            harness.expectTrue("s.recipients.length === 1 && s.recipients[0] === 'someone@example.com'")
        }

        @Test("subject round-trips")
        func testSubjectRoundTrip() {
            let harness = makeHarness()
            harness.eval("s.subject = 'Hello there'")
            #expect(!harness.hasException)
            #expect(harness.evalString("s.subject") == "Hello there")
        }

        @Test("shareItems with items the service cannot handle returns false and does not throw")
        func testShareItemsUnsupportedReturnsFalse() {
            let harness = makeHarness()
            // safariReadingList only handles URLs; plain non-URL, non-existent-path text
            // is not something it can act on.
            harness.eval("var canDo = s.canShareItems(['just some plain text'])")
            harness.eval("if (!canDo) { var r = s.shareItems(['just some plain text']); }")
            #expect(!harness.hasException)
            harness.expectTrue("canDo === false ? r === false : true")
        }
    }

    // MARK: - Memory leak tests

    @Test("HSSharingService is released after shutdown")
    func testSharingServiceDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSSharingModule.self, as: "sharing")

            harness.eval("var s = hs.sharing.createShare(hs.sharing.builtinServices.safariReadingList)")
            harness.eval("s.setCallback(function(){})")
            harness.eval("s.canShareItems(['https://www.hammerspoon.org'])")

            if let swift = harness.evalValue("s")?.toObjectOf(HSSharingService.self) as? HSSharingService {
                tracker.track(swift)
            }

            harness.eval("s = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
