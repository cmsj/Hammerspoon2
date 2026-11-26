//
//  HSEventKitModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import EventKit
import CoreLocation

// MARK: - JavaScript API

/// Read calendar events from the macOS Calendar database (EventKit).
///
/// Hammerspoon needs full access to calendars: call `hs.permissions.requestCalendars()` to ask for
/// it, and `hs.permissions.checkCalendars()` to see whether it has been granted. Every method here
/// throws while access hasn't been granted.
///
/// Each event is a plain object with the following keys:
///
/// | Key | Type | Description |
/// |-----|------|-------------|
/// | `id` | `string` | The event's identifier on this Mac. Every occurrence of a repeating event has the same `id`, so use it together with `occurrenceDate` (or `startDate`) to tell occurrences apart |
/// | `externalID` | `string` or `null` | The identifier the calendar server gives the event, which is the same on every device but isn't guaranteed to be unique |
/// | `title` | `string` | The event's title |
/// | `location` | `string` or `null` | The event's location, which often holds a Zoom or Teams link |
/// | `structuredLocation` | `object` or `null` | The location as a place, present whenever `location` is: `title`, `latitude` and `longitude` (`null` unless the location was picked as a place with coordinates), and `radius` in metres (`0` for the default) |
/// | `notes` | `string` or `null` | The event's notes (description), which often holds a meeting link |
/// | `url` | `string` or `null` | The URL attached to the event |
/// | `startDate` | `Date` | When the event starts |
/// | `endDate` | `Date` | When the event ends |
/// | `occurrenceDate` | `Date` or `null` | The original start of this occurrence of a repeating event, which doesn't change if the occurrence is moved |
/// | `allDay` | `boolean` | Whether it's an all-day event |
/// | `timeZone` | `string` or `null` | The event's time zone (e.g. `"Europe/London"`), or `null` for a floating event that follows the Mac's time zone |
/// | `recurring` | `boolean` | Whether the event repeats |
/// | `detached` | `boolean` | Whether this occurrence of a repeating event has been changed from the rest |
/// | `status` | `string` | `"none"`, `"confirmed"`, `"tentative"` or `"canceled"` |
/// | `availability` | `string` | How the event shows on a schedule: `"busy"`, `"free"`, `"tentative"`, `"unavailable"`, or `"notSupported"` when its calendar doesn't support availability |
/// | `organizer` | `object` or `null` | The participant who organised the event (see below) |
/// | `attendees` | `object[]` | The event's attendees (see below), empty if it has none |
/// | `hasAlarms` | `boolean` | Whether the event has any alarms |
/// | `birthdayContactID` | `string` or `null` | For an event in the Birthdays calendar, the identifier of the contact whose birthday it is |
/// | `creationDate` | `Date` or `null` | When the event was created |
/// | `lastModifiedDate` | `Date` or `null` | When the event was last changed |
/// | `calendarID` | `string` or `null` | The identifier of the event's calendar |
/// | `calendarTitle` | `string` or `null` | The title of the event's calendar |
///
/// The organizer and each attendee is an object with these keys:
///
/// | Key | Type | Description |
/// |-----|------|-------------|
/// | `name` | `string` or `null` | Their name |
/// | `url` | `string` | Their address, usually a `mailto:` URL |
/// | `email` | `string` or `null` | Their email address, when `url` is a `mailto:` URL |
/// | `status` | `string` | Their response: `"unknown"`, `"pending"`, `"accepted"`, `"declined"`, `"tentative"`, `"delegated"`, `"completed"` or `"inProcess"` |
/// | `role` | `string` | `"unknown"`, `"required"`, `"optional"`, `"chair"` or `"nonParticipant"` |
/// | `type` | `string` | `"unknown"`, `"person"`, `"room"`, `"resource"` or `"group"` |
/// | `currentUser` | `boolean` | Whether this participant is the Mac's user |
///
/// ## Finding meeting links for today
/// ```js
/// hs.eventkit.eventsToday().forEach(e => {
///     const text = [e.location, e.notes, e.url].join(" ")
///     const link = text.match(/https:\/\/[\w.-]*(zoom\.us|teams\.microsoft\.com)\/\S+/)
///     if (link) console.log(e.title + ": " + link[0])
/// })
/// ```
@objc protocol HSEventKitModuleAPI: JSExport {
    /// The calendars that hold events.
    ///
    /// Each entry is an object with `id`, `title` and `source` (the account, e.g. "iCloud") keys.
    /// - Returns: {{id: string, title: string, source: string | null}[]} An array of calendar objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.eventkit.calendars().forEach(c => console.log(c.source + ": " + c.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func calendars() -> [[String: Any]]

    /// The events that overlap a date range, sorted by start date.
    ///
    /// EventKit only searches up to four years at a time; a longer range is cut short.
    /// - Parameter start: The start of the range
    /// - Parameter end: The end of the range
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {{id: string, externalID: string | null, title: string, location: string | null, structuredLocation: {title: string | null, latitude: number | null, longitude: number | null, radius: number} | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, occurrenceDate: Date | null, allDay: boolean, timeZone: string | null, recurring: boolean, detached: boolean, status: "none" | "confirmed" | "tentative" | "canceled", availability: "notSupported" | "busy" | "free" | "tentative" | "unavailable", organizer: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean} | null, attendees: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean}[], hasAlarms: boolean, birthdayContactID: string | null, creationDate: Date | null, lastModifiedDate: Date | null, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const now = new Date()
    ///     const later = new Date(now.getTime() + 3600000)
    ///     hs.eventkit.events(now, later).forEach(e => console.log(e.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func events(_ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [[String: Any]]

    /// The events in a date range whose title, location, notes or URL contain some text
    /// (ignoring case), sorted by start date.
    /// - Parameter query: The text to look for
    /// - Parameter start: The start of the range
    /// - Parameter end: The end of the range
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {{id: string, externalID: string | null, title: string, location: string | null, structuredLocation: {title: string | null, latitude: number | null, longitude: number | null, radius: number} | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, occurrenceDate: Date | null, allDay: boolean, timeZone: string | null, recurring: boolean, detached: boolean, status: "none" | "confirmed" | "tentative" | "canceled", availability: "notSupported" | "busy" | "free" | "tentative" | "unavailable", organizer: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean} | null, attendees: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean}[], hasAlarms: boolean, birthdayContactID: string | null, creationDate: Date | null, lastModifiedDate: Date | null, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const now = new Date()
    ///     const nextWeek = new Date(now.getTime() + 7 * 86400000)
    ///     hs.eventkit.search("zoom.us", now, nextWeek).forEach(e => console.log(e.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func search(_ query: String, _ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [[String: Any]]

    /// The events that overlap today (from midnight to midnight, including any that have already
    /// finished), sorted by start date.
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {{id: string, externalID: string | null, title: string, location: string | null, structuredLocation: {title: string | null, latitude: number | null, longitude: number | null, radius: number} | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, occurrenceDate: Date | null, allDay: boolean, timeZone: string | null, recurring: boolean, detached: boolean, status: "none" | "confirmed" | "tentative" | "canceled", availability: "notSupported" | "busy" | "free" | "tentative" | "unavailable", organizer: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean} | null, attendees: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean}[], hasAlarms: boolean, birthdayContactID: string | null, creationDate: Date | null, lastModifiedDate: Date | null, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.eventkit.eventsToday().forEach(e => console.log(e.startDate.toLocaleTimeString() + " " + e.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func eventsToday(_ calendarIDs: [String]?) -> [[String: Any]]

    /// The events that overlap tomorrow (from midnight to midnight), sorted by start date.
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {{id: string, externalID: string | null, title: string, location: string | null, structuredLocation: {title: string | null, latitude: number | null, longitude: number | null, radius: number} | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, occurrenceDate: Date | null, allDay: boolean, timeZone: string | null, recurring: boolean, detached: boolean, status: "none" | "confirmed" | "tentative" | "canceled", availability: "notSupported" | "busy" | "free" | "tentative" | "unavailable", organizer: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean} | null, attendees: {name: string | null, url: string, email: string | null, status: string, role: string, type: string, currentUser: boolean}[], hasAlarms: boolean, birthdayContactID: string | null, creationDate: Date | null, lastModifiedDate: Date | null, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     console.log(hs.eventkit.eventsTomorrow().length + " events tomorrow")
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func eventsTomorrow(_ calendarIDs: [String]?) -> [[String: Any]]
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSEventKitModule: NSObject, HSModuleAPI, HSEventKitModuleAPI {
    var moduleName = "hs.eventkit"
    let engineID: UUID
    /// Created on first use, which is only once access has been granted: a store created before
    /// then can keep returning no calendars after the user grants access.
    private var _store: EKEventStore?
    private var store: EKEventStore {
        if let _store { return _store }
        let store = EKEventStore()
        _store = store
        return store
    }

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _store = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName): access \(hasAccess ? "granted" : "not granted")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Public API

    @objc func calendars() -> [[String: Any]] {
        guard checkAccess("calendars") else { return [] }
        return store.calendars(for: .event).map {
            ["id": $0.calendarIdentifier, "title": $0.title, "source": $0.source?.title ?? NSNull()]
        }
    }

    @objc func events(_ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [[String: Any]] {
        guard checkAccess("events") else { return [] }
        return fetch(start, end, calendarIDs).map(Self.eventToDict)
    }

    @objc func search(_ query: String, _ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [[String: Any]] {
        guard checkAccess("search") else { return [] }
        return fetch(start, end, calendarIDs).filter { Self.event($0, matches: query) }.map(Self.eventToDict)
    }

    @objc func eventsToday(_ calendarIDs: [String]?) -> [[String: Any]] {
        guard checkAccess("eventsToday") else { return [] }
        let day = Self.day(offsetFromToday: 0)
        return fetch(day.start, day.end, calendarIDs).map(Self.eventToDict)
    }

    @objc func eventsTomorrow(_ calendarIDs: [String]?) -> [[String: Any]] {
        guard checkAccess("eventsTomorrow") else { return [] }
        let day = Self.day(offsetFromToday: 1)
        return fetch(day.start, day.end, calendarIDs).map(Self.eventToDict)
    }

    // MARK: - Helpers

    private var hasAccess: Bool {
        PermissionsManager.shared.check(.calendars)
    }

    private func fetch(_ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [EKEvent] {
        let calendars = calendarIDs.map { ids in store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) } }
        // Never hand EventKit an empty calendar list: IDs that match no calendar must find no events
        if let calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private func checkAccess(_ method: String) -> Bool {
        guard !hasAccess else { return true }
        let message = "hs.eventkit.\(method)(): no access to calendar events, call hs.permissions.requestCalendars() first"
        AKError(message)
        if let context = JSContext.current() {
            context.exception = JSValue(newErrorFromMessage: message, in: context)
        }
        return false
    }

    /// The whole of the local day `offset` days from today. Calendar arithmetic, not 86400 seconds,
    /// so a day with a daylight saving change is still covered exactly.
    static func day(offsetFromToday offset: Int, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        // swiftlint:disable:next force_unwrapping
        let day = calendar.date(byAdding: .day, value: offset, to: today)!
        // swiftlint:disable:next force_unwrapping
        return calendar.dateInterval(of: .day, for: day)!
    }

    static func event(_ event: EKEvent, matches query: String) -> Bool {
        [event.title, event.location, event.notes, event.url?.absoluteString]
            .contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    // Most of these properties (title, location, notes, url, attendees, timeZone, ...) are
    // EKCalendarItem's, which EKEvent inherits; the rest are EKEvent's own.
    static func eventToDict(_ event: EKEvent) -> [String: Any] {
        [
            "id": event.eventIdentifier ?? event.calendarItemIdentifier,
            "externalID": event.calendarItemExternalIdentifier ?? NSNull(),
            "title": event.title ?? "",
            "location": event.location ?? NSNull(),
            "structuredLocation": event.structuredLocation.map(locationToDict) ?? NSNull(),
            "notes": event.notes ?? NSNull(),
            "url": event.url?.absoluteString ?? NSNull(),
            "startDate": event.startDate ?? NSNull(),
            "endDate": event.endDate ?? NSNull(),
            "occurrenceDate": event.occurrenceDate ?? NSNull(),
            "allDay": event.isAllDay,
            "timeZone": event.timeZone?.identifier ?? NSNull(),
            "recurring": event.hasRecurrenceRules,
            "detached": event.isDetached,
            "status": statusName(event.status),
            "availability": availabilityName(event.availability),
            "organizer": event.organizer.map(participantToDict) ?? NSNull(),
            "attendees": (event.attendees ?? []).map(participantToDict),
            "hasAlarms": event.hasAlarms,
            "birthdayContactID": event.birthdayContactIdentifier ?? NSNull(),
            "creationDate": event.creationDate ?? NSNull(),
            "lastModifiedDate": event.lastModifiedDate ?? NSNull(),
            "calendarID": event.calendar?.calendarIdentifier ?? NSNull(),
            "calendarTitle": event.calendar?.title ?? NSNull()
        ]
    }

    static func locationToDict(_ location: EKStructuredLocation) -> [String: Any] {
        let coordinate = location.geoLocation?.coordinate
        return [
            "title": location.title ?? NSNull(),
            "latitude": coordinate?.latitude ?? NSNull(),
            "longitude": coordinate?.longitude ?? NSNull(),
            "radius": location.radius
        ]
    }

    static func participantToDict(_ participant: EKParticipant) -> [String: Any] {
        let url = participant.url
        let email = url.scheme?.lowercased() == "mailto"
            ? url.absoluteString.dropFirst("mailto:".count).removingPercentEncoding
            : nil
        return [
            "name": participant.name ?? NSNull(),
            "url": url.absoluteString,
            "email": email ?? NSNull(),
            "status": participantStatusName(participant.participantStatus),
            "role": participantRoleName(participant.participantRole),
            "type": participantTypeName(participant.participantType),
            "currentUser": participant.isCurrentUser
        ]
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

    static func participantStatusName(_ status: EKParticipantStatus) -> String {
        switch status {
        case .unknown:   return "unknown"
        case .pending:   return "pending"
        case .accepted:  return "accepted"
        case .declined:  return "declined"
        case .tentative: return "tentative"
        case .delegated: return "delegated"
        case .completed: return "completed"
        case .inProcess: return "inProcess"
        @unknown default: return "unknown"
        }
    }

    static func participantRoleName(_ role: EKParticipantRole) -> String {
        switch role {
        case .unknown:        return "unknown"
        case .required:       return "required"
        case .optional:       return "optional"
        case .chair:          return "chair"
        case .nonParticipant: return "nonParticipant"
        @unknown default:     return "unknown"
        }
    }

    static func participantTypeName(_ type: EKParticipantType) -> String {
        switch type {
        case .unknown:  return "unknown"
        case .person:   return "person"
        case .room:     return "room"
        case .resource: return "resource"
        case .group:    return "group"
        @unknown default: return "unknown"
        }
    }
}
