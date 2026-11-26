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
        event.timeZone = TimeZone(identifier: "Europe/London")
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

    /// Puts an HSCalendarEvent for `event` into JS as the global `name`
    private func expose(_ event: EKEvent, as name: String, in harness: JSTestHarness) {
        harness.context.setObject(HSCalendarEvent(event: event), forKeyedSubscript: name as NSString)
    }

    @Test("Event properties reach JS with Date fields and nulls")
    func testEventBridgesToJS() {
        let harness = makeHarness()
        expose(makeEvent(), as: "ev", in: harness)
        #expect(harness.evalString("ev.typeName") == "HSCalendarEvent")
        #expect(harness.evalString("ev.title") == "Standup")
        #expect(harness.evalString("ev.location") == "https://example.zoom.us/j/123")
        #expect(harness.evalString("ev.notes") == "Join on Teams")
        #expect(harness.evalString("ev.timeZone") == "Europe/London")
        #expect(harness.evalBool("ev.allDay") == false)
        #expect(harness.evalBool("ev.recurring") == false)
        #expect(harness.evalBool("ev.detached") == false)
        #expect(harness.evalString("ev.status") == "none")
        // An event without a calendar can't have an availability
        #expect(harness.evalString("ev.availability") == "notSupported")
        harness.expectTrue("ev.startDate instanceof Date && ev.startDate.getTime() === 1000000")
        harness.expectTrue("ev.endDate instanceof Date && ev.endDate.getTime() === 2000000")
        harness.expectTrue("ev.url === null && ev.calendarID === null && ev.calendarTitle === null")
        #expect(!harness.hasException)
    }

    @Test("JSON.stringify serialises every property through toJSON()")
    func testToJSON() {
        let harness = makeHarness()
        expose(makeEvent(), as: "ev", in: harness)
        harness.eval("var parsed = JSON.parse(JSON.stringify(ev))")
        #expect(harness.evalString("parsed.title") == "Standup")
        #expect(harness.evalString("parsed.startDate") == "1970-01-01T00:16:40.000Z")
        harness.expectTrue("parsed.url === null")
        #expect(harness.evalString("Object.keys(parsed).sort().join(',')") ==
            "allDay,availability,calendarID,calendarTitle,detached,endDate,externalID,id,location,notes,occurrenceDate,recurring,startDate,status,timeZone,title,url")
        #expect(!harness.hasException)
    }

    @Test("toString names the event")
    func testToString() {
        let harness = makeHarness()
        expose(makeEvent(), as: "ev", in: harness)
        harness.expectTrue("String(ev).startsWith('<HSCalendarEvent: Standup (')")
    }

    @Test("An event the caller drops is garbage collected")
    func testEventIsCollected() {
        let harness = makeHarness()
        weak var event: HSCalendarEvent?
        autoreleasepool {
            let strong = HSCalendarEvent(event: makeEvent())
            event = strong
            harness.context.setObject(strong, forKeyedSubscript: "ev" as NSString)
            harness.eval("ev = null; void 0")
        }
        harness.collectGarbage()
        #expect(event == nil)
    }

    @Test("EventKit enums map to their documented names")
    func testEnumNames() {
        #expect(HSCalendarEvent.statusName(.canceled) == "canceled")
        #expect(HSCalendarEvent.statusName(.tentative) == "tentative")
        #expect(HSCalendarEvent.availabilityName(.notSupported) == "notSupported")
        #expect(HSCalendarEvent.availabilityName(.busy) == "busy")
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

    @Test("search matches title, location and notes ignoring case")
    func testMatches() {
        let event = makeEvent()
        #expect(HSCalendarEvent.event(event, matches: "ZOOM.us"))
        #expect(HSCalendarEvent.event(event, matches: "teams"))
        #expect(HSCalendarEvent.event(event, matches: "standup"))
        #expect(!HSCalendarEvent.event(event, matches: "webex"))
    }
}
