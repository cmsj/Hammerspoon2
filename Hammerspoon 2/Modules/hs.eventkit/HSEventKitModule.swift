//
//  HSEventKitModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import EventKit

// MARK: - JavaScript API

/// Read calendar events, and read and change reminders, from the macOS Calendar and Reminders
/// databases (EventKit).
///
/// Events need full access to calendars: call `hs.permissions.requestCalendars()` to ask for it,
/// and `hs.permissions.checkCalendars()` to see whether it has been granted. Reminders need access
/// to reminders, from `hs.permissions.requestReminders()` and `hs.permissions.checkReminders()`.
/// Every method here throws (or, for one that returns a Promise, rejects) while the access it
/// needs hasn't been granted.
///
/// Events are `HSCalendarEvent` objects, and reminders are `HSReminder` objects.
///
/// ## Finding meeting links for today
/// ```js
/// hs.eventkit.eventsToday().forEach(e => {
///     const text = [e.location, e.notes, e.url].join(" ")
///     const link = text.match(/https:\/\/[\w.-]*(zoom\.us|teams\.microsoft\.com)\/\S+/)
///     if (link) console.log(e.title + ": " + link[0])
/// })
/// ```
///
/// ## Adding a reminder and ticking it off
/// ```js
/// const r = hs.eventkit.createReminder({
///     title: "Water the plants",
///     dueDate: new Date(Date.now() + 3600000),
///     alarmDates: [new Date(Date.now() + 3600000)]
/// })
/// // ...later
/// r.update({ isCompleted: true })
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
    /// - Returns: {HSCalendarEvent[]} The events
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
    @objc func events(_ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [HSCalendarEvent]

    /// The events in a date range whose title, location, notes or URL contain some text
    /// (ignoring case), sorted by start date.
    /// - Parameter query: The text to look for
    /// - Parameter start: The start of the range
    /// - Parameter end: The end of the range
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {HSCalendarEvent[]} The events
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
    @objc func search(_ query: String, _ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [HSCalendarEvent]

    /// The events that overlap today (from midnight to midnight, including any that have already
    /// finished), sorted by start date.
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {HSCalendarEvent[]} The events
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.eventkit.eventsToday().forEach(e => console.log(e.startDate.toLocaleTimeString() + " " + e.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func eventsToday(_ calendarIDs: [String]?) -> [HSCalendarEvent]

    /// The events that overlap tomorrow (from midnight to midnight), sorted by start date.
    /// - Parameter calendarIDs?: The `id`s of the calendars to search (default: all of them)
    /// - Returns: {HSCalendarEvent[]} The events
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     console.log(hs.eventkit.eventsTomorrow().length + " events tomorrow")
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func eventsTomorrow(_ calendarIDs: [String]?) -> [HSCalendarEvent]

    /// The lists that hold reminders.
    ///
    /// Each entry is an object with `id`, `title`, `source` (the account, e.g. "iCloud") and
    /// `isDefault` (whether new reminders go there unless told otherwise) keys.
    /// - Returns: {{id: string, title: string, source: string | null, isDefault: boolean}[]} An array of reminder list objects
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.eventkit.reminderLists().forEach(l => console.log(l.source + ": " + l.title))
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func reminderLists() -> [[String: Any]]

    /// All reminders, completed or not.
    ///
    /// Sorted like `incompleteReminders()`.
    /// - Parameter listIDs?: The `id`s of the lists to search (default: all of them)
    /// - Returns: {Promise<HSReminder[]>} A Promise resolving to the reminders
    /// - Example:
    /// ```js
    /// hs.eventkit.reminders().then(r => console.log(r.length + " reminders"))
    /// ```
    @objc func reminders(_ listIDs: [String]?) -> JSPromise?

    /// The reminders that haven't been completed, sorted by due date (those without one last),
    /// then by when they were created.
    /// - Parameter listIDs?: The `id`s of the lists to search (default: all of them)
    /// - Returns: {Promise<HSReminder[]>} A Promise resolving to the reminders
    /// - Example:
    /// ```js
    /// hs.eventkit.incompleteReminders().then(reminders => {
    ///     reminders.forEach(r => console.log(r.title + (r.dueDate ? " (due " + r.dueDate.toLocaleString() + ")" : "")))
    /// })
    /// ```
    @objc func incompleteReminders(_ listIDs: [String]?) -> JSPromise?

    /// The reminders that were completed during a date range, sorted by when they were completed.
    /// - Parameter start: The start of the range
    /// - Parameter end: The end of the range
    /// - Parameter listIDs?: The `id`s of the lists to search (default: all of them)
    /// - Returns: {Promise<HSReminder[]>} A Promise resolving to the reminders
    /// - Example:
    /// ```js
    /// const weekAgo = new Date(Date.now() - 7 * 86400000)
    /// hs.eventkit.completedReminders(weekAgo, new Date()).then(r => console.log(r.length + " done this week"))
    /// ```
    @objc func completedReminders(_ start: Date, _ end: Date, _ listIDs: [String]?) -> JSPromise?

    /// The reminder with an identifier, such as one saved from a reminder's `id` earlier.
    /// - Parameter id: The reminder's `id`
    /// - Returns: The reminder, or `null` if there isn't one with that `id`
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const r = hs.eventkit.reminder(hs.settings.get("reminderID"))
    ///     if (r && !r.isCompleted) console.log("Still to do: " + r.title)
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func reminder(_ id: String) -> HSReminder?

    /// Creates and saves a new reminder.
    ///
    /// `properties` must have a `title`, and can have any of the other keys `HSReminder.update()`
    /// takes. Without a `listID`, the reminder goes in the default list for new reminders.
    ///
    /// A due date doesn't produce a notification by itself; add `alarmDates` for that.
    /// - Parameter properties: The new reminder's properties
    /// - Returns: The new reminder
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const tomorrow = new Date(Date.now() + 86400000)
    ///     hs.eventkit.createReminder({ title: "Call the dentist", dueDate: tomorrow, isAllDay: true, priority: "high" })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func createReminder(_ properties: [String: Any]) -> HSReminder?
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
    /// The same, for reminders. Separate from `store`, since access to reminders can be granted
    /// after access to calendars.
    private var _reminderStore: EKEventStore?
    private var reminderStore: EKEventStore {
        if let _reminderStore { return _reminderStore }
        let store = EKEventStore()
        _reminderStore = store
        return store
    }

    /// Reminder fetches that haven't finished, holding their promises until they do
    private var pendingFetches: [UUID: PendingReminderFetch] = [:]

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        // Drop the promises of unfinished fetches, so a late result never reaches the old JSContext
        for fetch in pendingFetches.values {
            if let request = fetch.request { fetch.store.cancelFetchRequest(request) }
        }
        pendingFetches.removeAll()
        _store = nil
        _reminderStore = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        func describe(_ permType: PermissionsType) -> String {
            PermissionsManager.shared.check(permType) ? "granted" : "not granted"
        }
        return "<\(moduleName): calendars \(describe(.calendars)), reminders \(describe(.reminders))>"
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

    @objc func events(_ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [HSCalendarEvent] {
        guard checkAccess("events") else { return [] }
        return fetch(start, end, calendarIDs)
    }

    @objc func search(_ query: String, _ start: Date, _ end: Date, _ calendarIDs: [String]?) -> [HSCalendarEvent] {
        guard checkAccess("search") else { return [] }
        return fetch(start, end, calendarIDs) { HSCalendarEvent.event($0, matches: query) }
    }

    @objc func eventsToday(_ calendarIDs: [String]?) -> [HSCalendarEvent] {
        guard checkAccess("eventsToday") else { return [] }
        let day = Self.day(offsetFromToday: 0)
        return fetch(day.start, day.end, calendarIDs)
    }

    @objc func eventsTomorrow(_ calendarIDs: [String]?) -> [HSCalendarEvent] {
        guard checkAccess("eventsTomorrow") else { return [] }
        let day = Self.day(offsetFromToday: 1)
        return fetch(day.start, day.end, calendarIDs)
    }

    @objc func reminderLists() -> [[String: Any]] {
        guard checkAccess("reminderLists", to: .reminders) else { return [] }
        let defaultID = reminderStore.defaultCalendarForNewReminders()?.calendarIdentifier
        return reminderStore.calendars(for: .reminder).map {
            ["id": $0.calendarIdentifier, "title": $0.title, "source": $0.source?.title ?? NSNull(),
             "isDefault": $0.calendarIdentifier == defaultID]
        }
    }

    @objc func reminders(_ listIDs: [String]?) -> JSPromise? {
        fetchReminders("reminders", listIDs, sortedBy: Self.dueOrder) { store, lists in
            store.predicateForReminders(in: lists)
        }
    }

    @objc func incompleteReminders(_ listIDs: [String]?) -> JSPromise? {
        fetchReminders("incompleteReminders", listIDs, sortedBy: Self.dueOrder) { store, lists in
            store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        }
    }

    @objc func completedReminders(_ start: Date, _ end: Date, _ listIDs: [String]?) -> JSPromise? {
        fetchReminders("completedReminders", listIDs, sortedBy: Self.completionOrder) { store, lists in
            store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: lists)
        }
    }

    @objc func reminder(_ id: String) -> HSReminder? {
        guard checkAccess("reminder", to: .reminders) else { return nil }
        guard let reminder = reminderStore.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        return HSReminder(reminder: reminder, store: reminderStore)
    }

    @objc func createReminder(_ properties: [String: Any]) -> HSReminder? {
        guard checkAccess("createReminder", to: .reminders) else { return nil }
        guard properties["title"] is String else {
            throwEventKitError("hs.eventkit.createReminder(): a title is required")
            return nil
        }
        let store = reminderStore
        let reminder = EKReminder(eventStore: store)
        do {
            if properties["listID"] == nil {
                guard let list = store.defaultCalendarForNewReminders() else {
                    throw HSReminder.InvalidChange("there's no default reminder list, so a listID is required")
                }
                reminder.calendar = list
            }
            try HSReminder.apply(properties, to: reminder, in: store)
            try store.save(reminder, commit: true)
        } catch {
            throwEventKitError("hs.eventkit.createReminder(): \(error.localizedDescription)")
            return nil
        }
        return HSReminder(reminder: reminder, store: store)
    }

    // MARK: - Helpers

    private func fetch(_ start: Date, _ end: Date, _ calendarIDs: [String]?,
                       where include: (EKEvent) -> Bool = { _ in true }) -> [HSCalendarEvent] {
        let calendars = calendarIDs.map { ids in store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) } }
        // Never hand EventKit an empty calendar list: IDs that match no calendar must find no events
        if let calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter(include)
            .sorted { $0.startDate < $1.startDate }
            .map(HSCalendarEvent.init(event:))
    }

    private func checkAccess(_ method: String, to permType: PermissionsType = .calendars) -> Bool {
        guard let message = Self.accessError(method, permType) else { return true }
        throwEventKitError(message)
        return false
    }

    /// Why `method` can't run, if it doesn't have the access it needs
    private static func accessError(_ method: String, _ permType: PermissionsType) -> String? {
        guard !PermissionsManager.shared.check(permType) else { return nil }
        let what = permType == .reminders ? "reminders" : "calendar events"
        return "hs.eventkit.\(method)(): no access to \(what), call hs.permissions.request\(permType.displayName)() first"
    }

    /// Fetches reminders from the lists with `listIDs` (or all lists), returning a Promise for them
    private func fetchReminders(_ method: String, _ listIDs: [String]?,
                                sortedBy order: @escaping (EKReminder, EKReminder) -> Bool,
                                predicate makePredicate: (EKEventStore, [EKCalendar]?) -> NSPredicate) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        if let message = Self.accessError(method, .reminders) {
            AKError(message)
            return context.createRejectedPromise(with: message)
        }
        let store = reminderStore
        let lists = listIDs.map { ids in store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) } }
        // Never hand EventKit an empty list of lists: IDs that match no list must find nothing
        if let lists, lists.isEmpty { return context.createResolvedPromise(with: [HSReminder]()) }
        let predicate = makePredicate(store, lists)

        let id = UUID()
        let promise = wrapAsyncInJSPromise(in: context) { holder in
            self.pendingFetches[id] = PendingReminderFetch(holder: holder, store: store)
        }
        let request = store.fetchReminders(matching: predicate, completion: Self.fetchCompletion { [weak self] reminders in
            guard let fetch = self?.pendingFetches.removeValue(forKey: id) else { return }
            fetch.holder.resolveWith(reminders.sorted(by: order).map { HSReminder(reminder: $0, store: store) })
        })
        pendingFetches[id]?.request = request
        return promise
    }

    /// EventKit calls a fetch's completion on a queue of its own, so it can't be main-actor isolated
    private nonisolated static func fetchCompletion(
        _ deliver: @escaping @MainActor @Sendable ([EKReminder]) -> Void
    ) -> @Sendable ([EKReminder]?) -> Void {
        { reminders in
            // EventKit is done with them, and only the main actor touches them from here on
            nonisolated(unsafe) let unsafeReminders = reminders ?? []
            Task { @MainActor in deliver(unsafe unsafeReminders) }
        }
    }

    /// By due date, those without one last, then by when they were created
    static func dueOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        let lhsDue = HSReminder.date(from: lhs.dueDateComponents)
        let rhsDue = HSReminder.date(from: rhs.dueDateComponents)
        if lhsDue != rhsDue {
            guard let lhsDue else { return false }
            guard let rhsDue else { return true }
            return lhsDue < rhsDue
        }
        return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
    }

    static func completionOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        (lhs.completionDate ?? .distantPast) < (rhs.completionDate ?? .distantPast)
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
}

/// A reminder fetch started by `hs.eventkit`, until it finishes
@MainActor
private final class PendingReminderFetch {
    let holder: JSPromiseHolder
    let store: EKEventStore
    /// EventKit's handle for the fetch, which cancels it
    var request: Any?

    init(holder: JSPromiseHolder, store: EKEventStore) {
        self.holder = holder
        self.store = store
    }
}
