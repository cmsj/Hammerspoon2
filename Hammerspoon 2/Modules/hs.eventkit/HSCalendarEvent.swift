//
//  HSCalendarEvent.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import EventKit

/// An event from a calendar, as returned by `hs.eventkit.events()` and its relatives.
///
/// Each property is read from the underlying calendar event when you access it, so fetching many
/// events is cheap even when you only look at a few of their properties. An event is a snapshot:
/// if it changes in Calendar after you fetched it, fetch it again to see the change.
///
/// Don't create these yourself; they come from `hs.eventkit`.
///
/// - Example:
/// ```js
/// hs.eventkit.eventsToday().forEach(e => {
///     console.log(e.startDate.toLocaleTimeString() + " " + e.title + (e.location ? " @ " + e.location : ""))
/// })
/// ```
@objc protocol HSCalendarEventAPI: HSTypeAPI, JSExport {
    /// The event's identifier on this Mac.
    ///
    /// Every occurrence of a repeating event has the same `id`, so use it together with
    /// `occurrenceDate` (or `startDate`) to tell occurrences apart.
    /// - Example:
    /// ```js
    /// console.log(event.id)
    /// ```
    @objc var id: String { get }

    /// The identifier the calendar server gives the event, which is the same on every device
    /// but isn't guaranteed to be unique.
    /// - Example:
    /// ```js
    /// console.log(event.externalID)
    /// ```
    @objc var externalID: String? { get }

    /// The event's title.
    /// - Example:
    /// ```js
    /// console.log(event.title)
    /// ```
    @objc var title: String { get }

    /// The event's location, which often holds a Zoom or Teams link.
    /// - Example:
    /// ```js
    /// if (event.location) console.log(event.location)
    /// ```
    @objc var location: String? { get }

    /// The event's notes (its description), which often hold a meeting link.
    /// - Example:
    /// ```js
    /// const link = (event.notes || "").match(/https:\/\/\S*zoom\.us\/\S+/)
    /// if (link) console.log(link[0])
    /// ```
    @objc var notes: String? { get }

    /// The URL attached to the event.
    /// - Example:
    /// ```js
    /// if (event.url) hs.urlevent.openURL(event.url)
    /// ```
    @objc var url: String? { get }

    /// When the event starts.
    /// - Example:
    /// ```js
    /// console.log(event.startDate.toLocaleString())
    /// ```
    @objc var startDate: Date { get }

    /// When the event ends.
    /// - Example:
    /// ```js
    /// const minutes = (event.endDate - event.startDate) / 60000
    /// console.log(event.title + " lasts " + minutes + " minutes")
    /// ```
    @objc var endDate: Date { get }

    /// The original start of this occurrence of a repeating event, which stays the same if the
    /// occurrence is moved.
    /// - Example:
    /// ```js
    /// if (event.recurring) console.log(event.occurrenceDate.toLocaleString())
    /// ```
    @objc var occurrenceDate: Date? { get }

    /// Whether this is an all-day event.
    /// - Example:
    /// ```js
    /// if (event.allDay) console.log(event.title + " (all day)")
    /// ```
    @objc var allDay: Bool { get }

    /// The event's time zone (e.g. `"Europe/London"`), or `null` for a floating event that
    /// follows the Mac's time zone.
    /// - Example:
    /// ```js
    /// console.log(event.timeZone)
    /// ```
    @objc var timeZone: String? { get }

    /// Whether the event repeats.
    /// - Example:
    /// ```js
    /// console.log(event.recurring)
    /// ```
    @objc var recurring: Bool { get }

    /// Whether this occurrence of a repeating event has been changed from the rest.
    /// - Example:
    /// ```js
    /// console.log(event.detached)
    /// ```
    @objc var detached: Bool { get }

    /// The event's status: `"none"`, `"confirmed"`, `"tentative"` or `"canceled"`.
    /// - Example:
    /// ```js
    /// if (event.status === "canceled") console.log(event.title + " was cancelled")
    /// ```
    @objc var status: String { get }

    /// How the event shows on a schedule: `"busy"`, `"free"`, `"tentative"`, `"unavailable"`,
    /// or `"notSupported"` when its calendar doesn't support availability.
    /// - Example:
    /// ```js
    /// const busy = hs.eventkit.eventsToday().filter(e => e.availability === "busy")
    /// ```
    @objc var availability: String { get }

    /// The identifier of the event's calendar, as in `hs.eventkit.calendars()`.
    /// - Example:
    /// ```js
    /// console.log(event.calendarID)
    /// ```
    @objc var calendarID: String? { get }

    /// The title of the event's calendar.
    /// - Example:
    /// ```js
    /// console.log(event.calendarTitle + ": " + event.title)
    /// ```
    @objc var calendarTitle: String? { get }

    /// Returns a plain object holding all of the event's properties, for JSON serialisation.
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with every property of the event
    /// - Example:
    /// ```js
    /// console.log(JSON.stringify(hs.eventkit.eventsToday(), null, 2))
    /// ```
    @objc func toJSON() -> [String: Any]
}

@_documentation(visibility: private)
@MainActor
@objc class HSCalendarEvent: NSObject, HSCalendarEventAPI {
    @objc var typeName = "HSCalendarEvent"

    // Most of these properties (title, location, notes, url, timeZone, ...) are EKCalendarItem's,
    // which EKEvent inherits; the rest are EKEvent's own.
    let event: EKEvent

    init(event: EKEvent) {
        self.event = event
        super.init()
    }

    isolated deinit {
        AKGarbage("deinit of HSCalendarEvent")
    }

    @objc func toString() -> String {
        let when = startDate.formatted(date: .abbreviated, time: allDay ? .omitted : .shortened)
        return "<\(typeName): \(title) (\(when))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc var id: String { event.eventIdentifier ?? event.calendarItemIdentifier }
    @objc var externalID: String? { event.calendarItemExternalIdentifier }
    @objc var title: String { event.title ?? "" }
    @objc var location: String? { event.location }
    @objc var notes: String? { event.notes }
    @objc var url: String? { event.url?.absoluteString }
    // Never nil for an event fetched from the store; the fallback only guards the
    // implicitly unwrapped EventKit properties
    @objc var startDate: Date { event.startDate ?? .distantPast }
    @objc var endDate: Date { event.endDate ?? .distantPast }
    @objc var occurrenceDate: Date? { event.occurrenceDate }
    @objc var allDay: Bool { event.isAllDay }
    @objc var timeZone: String? { event.timeZone?.identifier }
    @objc var recurring: Bool { event.hasRecurrenceRules }
    @objc var detached: Bool { event.isDetached }
    @objc var status: String { Self.statusName(event.status) }
    @objc var availability: String { Self.availabilityName(event.availability) }
    @objc var calendarID: String? { event.calendar?.calendarIdentifier }
    @objc var calendarTitle: String? { event.calendar?.title }

    @objc func toJSON() -> [String: Any] {
        [
            "id": id,
            "externalID": externalID.orNSNull,
            "title": title,
            "location": location.orNSNull,
            "notes": notes.orNSNull,
            "url": url.orNSNull,
            "startDate": startDate,
            "endDate": endDate,
            "occurrenceDate": occurrenceDate.orNSNull,
            "allDay": allDay,
            "timeZone": timeZone.orNSNull,
            "recurring": recurring,
            "detached": detached,
            "status": status,
            "availability": availability,
            "calendarID": calendarID.orNSNull,
            "calendarTitle": calendarTitle.orNSNull,
        ]
    }

    /// Whether an event's title, location, notes or URL contain `query`, ignoring case.
    static func event(_ event: EKEvent, matches query: String) -> Bool {
        [event.title, event.location, event.notes, event.url?.absoluteString]
            .contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    static func statusName(_ status: EKEventStatus) -> String {
        switch status {
        case .none:      return "none"
        case .confirmed: return "confirmed"
        case .tentative: return "tentative"
        case .canceled:  return "canceled"
        @unknown default: return "none"
        }
    }

    static func availabilityName(_ availability: EKEventAvailability) -> String {
        switch availability {
        case .notSupported: return "notSupported"
        case .busy:         return "busy"
        case .free:         return "free"
        case .tentative:    return "tentative"
        case .unavailable:  return "unavailable"
        @unknown default:   return "notSupported"
        }
    }
}
