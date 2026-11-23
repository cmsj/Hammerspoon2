//
//  HSEventKitIntegrationTests.swift
//  Hammerspoon 2Tests
//

import EventKit
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.eventkit tests")
@MainActor
struct HSEventKitIntegrationTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSEventKitModule.self, as: "eventkit")
        return harness
    }

    private func makeEvent() -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Standup"
        event.location = "https://example.zoom.us/j/123"
        event.notes = "Join on Teams"
        event.startDate = Date(timeIntervalSince1970: 1_000)
        event.endDate = Date(timeIntervalSince1970: 2_000)
        return event
    }

    @Test("API is exposed")
    func testAPI() {
        let harness = makeHarness()
        for name in ["hasAccess", "requestAccess", "calendars", "events", "search"] {
            #expect(harness.evalTypeOf("hs.eventkit.\(name)") == "function")
        }
    }

    @Test("Methods throw without calendar access", .enabled(if: EKEventStore.authorizationStatus(for: .event) != .fullAccess))
    func testThrowsWithoutAccess() {
        let harness = makeHarness()
        harness.expectEqual("""
            (() => { try { hs.eventkit.events(new Date(), new Date()); return false } catch (e) { return true } })()
            """, true)
    }

    @Test("Event objects reach JS with Date fields and nulls")
    func testEventBridgesToJS() {
        let harness = makeHarness()
        harness.context.setObject(HSEventKitModule.eventToDict(makeEvent()), forKeyedSubscript: "ev" as NSString)
        harness.expectTrue("ev.startDate instanceof Date && ev.startDate.getTime() === 1000000")
        harness.expectTrue("ev.endDate instanceof Date && ev.endDate.getTime() === 2000000")
        harness.expectTrue("ev.url === null")
        harness.expectEqual("ev.location", "https://example.zoom.us/j/123")
    }

    @Test("Events are listed", .enabled(if: EKEventStore.authorizationStatus(for: .event) == .fullAccess))
    func testEventsWithAccess() {
        let harness = makeHarness()
        harness.expectEqual("Array.isArray(hs.eventkit.events(new Date(), new Date(Date.now() + 86400000)))", true)
        harness.expectEqual("Array.isArray(hs.eventkit.calendars())", true)
    }

    @Test("eventToDict carries location, notes and dates")
    func testEventToDict() {
        let dict = HSEventKitModule.eventToDict(makeEvent())
        #expect(dict["title"] as? String == "Standup")
        #expect(dict["location"] as? String == "https://example.zoom.us/j/123")
        #expect(dict["notes"] as? String == "Join on Teams")
        #expect(dict["url"] is NSNull)
        #expect(dict["startDate"] as? Date == Date(timeIntervalSince1970: 1_000))
    }

    @Test("search matches title, location and notes ignoring case")
    func testMatches() {
        let event = makeEvent()
        #expect(HSEventKitModule.event(event, matches: "ZOOM.us"))
        #expect(HSEventKitModule.event(event, matches: "teams"))
        #expect(HSEventKitModule.event(event, matches: "standup"))
        #expect(!HSEventKitModule.event(event, matches: "webex"))
    }
}
