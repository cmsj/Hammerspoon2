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
        for name in ["calendars", "events", "search", "eventsToday", "eventsTomorrow"] {
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

    @Test("Calendar permission is checked and requested through hs.permissions")
    func testPermissionsAPI() {
        let harness = makeHarness()
        harness.loadModule(HSPermissionsModule.self, as: "permissions")
        #expect(harness.evalTypeOf("hs.permissions.requestCalendars") == "function")
        #expect(harness.evalTypeOf("hs.eventkit.requestAccess") == "undefined")
        let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        harness.expectEqual("hs.permissions.checkCalendars()", granted)
    }

    @Test("Day ranges cover a whole local day, including across a DST change")
    func testDayRanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        // 11:00 on Saturday 28 March 2026; the clocks go forward at 01:00 the next day
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 11)))
        let today = HSEventKitModule.day(offsetFromToday: 0, now: now, calendar: calendar)
        let tomorrow = HSEventKitModule.day(offsetFromToday: 1, now: now, calendar: calendar)
        #expect(today.start == calendar.startOfDay(for: now))
        #expect(today.duration == 24 * 3600)
        #expect(tomorrow.start == today.end)
        #expect(tomorrow.duration == 23 * 3600)
    }

    @Test("Convenience methods throw without calendar access", .enabled(if: EKEventStore.authorizationStatus(for: .event) != .fullAccess))
    func testConvenienceThrowsWithoutAccess() {
        let harness = makeHarness()
        for name in ["eventsToday()", "eventsTomorrow()", "search('x', new Date(), new Date())"] {
            harness.expectEqual("""
                (() => { try { hs.eventkit.\(name); return false } catch (e) { return true } })()
                """, true)
        }
    }

    @Test("Calendar IDs that match nothing find no events", .enabled(if: EKEventStore.authorizationStatus(for: .event) == .fullAccess))
    func testUnknownCalendarIDs() {
        let harness = makeHarness()
        harness.expectEqual("""
            hs.eventkit.events(new Date(0), new Date(Date.now() + 86400000 * 365), ["no-such-calendar"]).length
            """, 0)
        harness.expectEqual("hs.eventkit.search('', new Date(0), new Date(), ['no-such-calendar']).length", 0)
        harness.expectEqual("hs.eventkit.eventsToday(['no-such-calendar']).length", 0)
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
