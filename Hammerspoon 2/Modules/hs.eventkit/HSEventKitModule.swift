//
//  HSEventKitModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import EventKit

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
/// | `id` | `string` | The event's identifier |
/// | `title` | `string` | The event's title |
/// | `location` | `string` or `null` | The event's location, which often holds a Zoom or Teams link |
/// | `notes` | `string` or `null` | The event's notes (description), which often holds a meeting link |
/// | `url` | `string` or `null` | The URL attached to the event |
/// | `startDate` | `Date` | When the event starts |
/// | `endDate` | `Date` | When the event ends |
/// | `allDay` | `boolean` | Whether it's an all-day event |
/// | `calendarID` | `string` | The identifier of the event's calendar |
/// | `calendarTitle` | `string` | The title of the event's calendar |
///
/// ## Finding meeting links for today
/// ```js
/// const start = new Date(); start.setHours(0, 0, 0, 0)
/// const end = new Date(start.getTime() + 86400000)
/// hs.eventkit.events(start, end).forEach(e => {
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
    /// - Returns: {{id: string, title: string, location: string | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, allDay: boolean, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
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
    /// - Returns: {{id: string, title: string, location: string | null, notes: string | null, url: string | null, startDate: Date, endDate: Date, allDay: boolean, calendarID: string | null, calendarTitle: string | null}[]} An array of event objects
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
    @objc func search(_ query: String, _ start: Date, _ end: Date) -> [[String: Any]]
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

    @objc func search(_ query: String, _ start: Date, _ end: Date) -> [[String: Any]] {
        guard checkAccess("search") else { return [] }
        return fetch(start, end, nil).filter { Self.event($0, matches: query) }.map(Self.eventToDict)
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

    static func event(_ event: EKEvent, matches query: String) -> Bool {
        [event.title, event.location, event.notes, event.url?.absoluteString]
            .contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    static func eventToDict(_ event: EKEvent) -> [String: Any] {
        [
            "id": event.eventIdentifier ?? event.calendarItemIdentifier,
            "title": event.title ?? "",
            "location": event.location ?? NSNull(),
            "notes": event.notes ?? NSNull(),
            "url": event.url?.absoluteString ?? NSNull(),
            "startDate": event.startDate ?? NSNull(),
            "endDate": event.endDate ?? NSNull(),
            "allDay": event.isAllDay,
            "calendarID": event.calendar?.calendarIdentifier ?? NSNull(),
            "calendarTitle": event.calendar?.title ?? NSNull()
        ]
    }
}
