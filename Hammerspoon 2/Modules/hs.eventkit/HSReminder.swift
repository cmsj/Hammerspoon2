//
//  HSReminder.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import EventKit

/// A reminder from the Reminders app, as returned by `hs.eventkit.incompleteReminders()` and its
/// relatives.
///
/// Each property is read from the underlying reminder when you access it. A reminder is a snapshot:
/// if it changes in Reminders after you fetched it, fetch it again to see the change.
///
/// The properties are read-only; change a reminder with `update()`, which saves the change straight
/// away, and delete it with `remove()`.
///
/// Don't create these yourself; they come from `hs.eventkit`, and `hs.eventkit.createReminder()`
/// makes new ones.
///
/// - Example:
/// ```js
/// hs.eventkit.incompleteReminders().then(reminders => {
///     reminders.filter(r => r.dueDate && r.dueDate < new Date())
///              .forEach(r => console.log("Overdue: " + r.title))
/// })
/// ```
@objc protocol HSReminderAPI: HSTypeAPI, JSExport {
    /// The reminder's identifier on this Mac, which `hs.eventkit.reminder()` finds it by.
    /// - Example:
    /// ```js
    /// console.log(reminder.id)
    /// ```
    @objc var id: String { get }

    /// The identifier the server gives the reminder, which is the same on every device but isn't
    /// guaranteed to be unique.
    /// - Example:
    /// ```js
    /// console.log(reminder.externalID)
    /// ```
    @objc var externalID: String? { get }

    /// The reminder's title.
    /// - Example:
    /// ```js
    /// console.log(reminder.title)
    /// ```
    @objc var title: String { get }

    /// The reminder's notes.
    /// - Example:
    /// ```js
    /// if (reminder.notes) console.log(reminder.notes)
    /// ```
    @objc var notes: String? { get }

    /// The URL attached to the reminder.
    /// - Example:
    /// ```js
    /// if (reminder.url) hs.urlevent.openURL(reminder.url)
    /// ```
    @objc var url: String? { get }

    /// When the reminder is due, or `null` if it has no due date. For a reminder that is due on a
    /// day rather than at a time (see `isAllDay`), this is the start of that day.
    /// - Example:
    /// ```js
    /// if (reminder.dueDate) console.log("Due " + reminder.dueDate.toLocaleString())
    /// ```
    @objc var dueDate: Date? { get }

    /// Whether the reminder is due on a day, rather than at a particular time. Always `false` for a
    /// reminder with no due date.
    /// - Example:
    /// ```js
    /// console.log(reminder.isAllDay ? "Due today" : "Due at " + reminder.dueDate.toLocaleTimeString())
    /// ```
    @objc var isAllDay: Bool { get }

    /// The reminder's priority: `"none"`, `"low"`, `"medium"` or `"high"`.
    /// - Example:
    /// ```js
    /// if (reminder.priority === "high") console.log("Important: " + reminder.title)
    /// ```
    @objc var priority: String { get }

    /// Whether the reminder has been completed.
    /// - Example:
    /// ```js
    /// console.log(reminder.isCompleted)
    /// ```
    @objc var isCompleted: Bool { get }

    /// When the reminder was completed, or `null` if it hasn't been.
    /// - Example:
    /// ```js
    /// if (reminder.completionDate) console.log("Done " + reminder.completionDate.toLocaleString())
    /// ```
    @objc var completionDate: Date? { get }

    /// When the reminder's alerts go off. Only alerts at a set time are listed; Reminders can also
    /// have alerts for arriving at or leaving a place, which `update()` leaves alone.
    ///
    /// A due date doesn't produce a notification by itself: add an alert for that.
    /// - Example:
    /// ```js
    /// reminder.alarmDates.forEach(d => console.log("Alert at " + d.toLocaleString()))
    /// ```
    @objc var alarmDates: [Date] { get }

    /// Whether the reminder repeats.
    /// - Example:
    /// ```js
    /// console.log(reminder.isRecurring)
    /// ```
    @objc var isRecurring: Bool { get }

    /// The identifier of the reminder's list, as in `hs.eventkit.reminderLists()`.
    /// - Example:
    /// ```js
    /// console.log(reminder.listID)
    /// ```
    @objc var listID: String? { get }

    /// The title of the reminder's list.
    /// - Example:
    /// ```js
    /// console.log(reminder.listTitle + ": " + reminder.title)
    /// ```
    @objc var listTitle: String? { get }

    /// When the reminder was created.
    /// - Example:
    /// ```js
    /// console.log(reminder.creationDate)
    /// ```
    @objc var creationDate: Date? { get }

    /// When the reminder was last changed.
    /// - Example:
    /// ```js
    /// console.log(reminder.lastModifiedDate)
    /// ```
    @objc var lastModifiedDate: Date? { get }

    /// Changes some of the reminder's properties and saves the change.
    ///
    /// `changes` can hold any of these keys; the properties it leaves out are left as they are:
    /// - `title` (string)
    /// - `notes`, `url` (string, or `null` to clear)
    /// - `dueDate` (Date, or `null` to clear). Keeps the reminder's `isAllDay` unless `changes`
    ///   sets that too; clearing the due date also clears `isAllDay`.
    /// - `isAllDay` (boolean): `true` makes the reminder due on its due date's day, rather than at
    ///   its time. Needs a due date.
    /// - `priority` (`"none"`, `"low"`, `"medium"` or `"high"`)
    /// - `isCompleted` (boolean), which also sets or clears `completionDate`
    /// - `alarmDates` (array of Date): replaces the reminder's timed alerts; `[]` removes them
    /// - `listID` (string): moves the reminder to another list
    ///
    /// If anything in `changes` is invalid, or the change can't be saved, this throws and the
    /// reminder is left as it was.
    /// - Parameter changes: The properties to change
    /// - Returns: The reminder, for chaining
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     reminder.update({ isCompleted: true })
    ///     reminder.update({ dueDate: new Date(Date.now() + 3600000), priority: "high" })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func update(_ changes: [String: Any]) -> HSReminder?

    /// Deletes the reminder.
    ///
    /// The object keeps its properties afterwards, but it can't be updated or saved again.
    /// - Returns: true once the reminder has been deleted
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     reminder.remove()
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func remove() -> Bool

    /// Returns a plain object holding all of the reminder's properties, for JSON serialisation.
    ///
    /// `JSON.stringify()` calls this automatically, so you rarely need to call it yourself.
    /// - Returns: An object with every property of the reminder
    /// - Example:
    /// ```js
    /// hs.eventkit.incompleteReminders().then(r => console.log(JSON.stringify(r, null, 2)))
    /// ```
    @objc func toJSON() -> [String: Any]
}

@_documentation(visibility: private)
@MainActor
@objc class HSReminder: NSObject, HSReminderAPI {
    @objc var typeName = "HSReminder"

    let reminder: EKReminder
    /// The store the reminder came from, which saves its changes
    private let store: EKEventStore

    init(reminder: EKReminder, store: EKEventStore) {
        self.reminder = reminder
        self.store = store
        super.init()
    }

    isolated deinit {
        AKGarbage("deinit of HSReminder")
    }

    @objc func toString() -> String {
        "<\(typeName): \(title)\(isCompleted ? " (completed)" : "")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc var id: String { reminder.calendarItemIdentifier }
    @objc var externalID: String? { reminder.calendarItemExternalIdentifier }
    @objc var title: String { reminder.title ?? "" }
    @objc var notes: String? { reminder.notes }
    @objc var url: String? { reminder.url?.absoluteString }
    @objc var dueDate: Date? { Self.date(from: reminder.dueDateComponents) }
    @objc var isAllDay: Bool { Self.isAllDay(reminder.dueDateComponents) }
    @objc var priority: String { Self.priorityName(reminder.priority) }
    @objc var isCompleted: Bool { reminder.isCompleted }
    @objc var completionDate: Date? { reminder.completionDate }
    @objc var alarmDates: [Date] { (reminder.alarms ?? []).compactMap(\.absoluteDate) }
    @objc var isRecurring: Bool { reminder.hasRecurrenceRules }
    @objc var listID: String? { reminder.calendar?.calendarIdentifier }
    @objc var listTitle: String? { reminder.calendar?.title }
    @objc var creationDate: Date? { reminder.creationDate }
    @objc var lastModifiedDate: Date? { reminder.lastModifiedDate }

    @objc func update(_ changes: [String: Any]) -> HSReminder? {
        do {
            // Checks every change before making any, so a failure here has changed nothing
            try Self.apply(changes, to: reminder, in: store)
        } catch {
            throwEventKitError("HSReminder.update(): \(error.localizedDescription)")
            return nil
        }
        do {
            try store.save(reminder, commit: true)
            return self
        } catch {
            // Undo the changes, so the object still matches what's saved
            reminder.rollback()
            throwEventKitError("HSReminder.update(): \(error.localizedDescription)")
            return nil
        }
    }

    @objc func remove() -> Bool {
        do {
            try store.remove(reminder, commit: true)
            return true
        } catch {
            throwEventKitError("HSReminder.remove(): \(error.localizedDescription)")
            return false
        }
    }

    @objc func toJSON() -> [String: Any] {
        [
            "id": id,
            "externalID": externalID.orNSNull,
            "title": title,
            "notes": notes.orNSNull,
            "url": url.orNSNull,
            "dueDate": dueDate.orNSNull,
            "isAllDay": isAllDay,
            "priority": priority,
            "isCompleted": isCompleted,
            "completionDate": completionDate.orNSNull,
            "alarmDates": alarmDates,
            "isRecurring": isRecurring,
            "listID": listID.orNSNull,
            "listTitle": listTitle.orNSNull,
            "creationDate": creationDate.orNSNull,
            "lastModifiedDate": lastModifiedDate.orNSNull,
        ]
    }

    // MARK: - Applying changes

    /// Why a set of changes couldn't be applied
    struct InvalidChange: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let changeKeys: Set<String> = [
        "title", "notes", "url", "dueDate", "isAllDay", "priority", "isCompleted", "alarmDates", "listID",
    ]

    /// Applies `changes` (see `update()`) to `reminder`, without saving it. Checks every change
    /// before making any, so an invalid one leaves the reminder untouched.
    static func apply(_ changes: [String: Any], to reminder: EKReminder, in store: EKEventStore) throws {
        if let unknown = changes.keys.filter({ !changeKeys.contains($0) }).sorted().first {
            throw InvalidChange("unknown property '\(unknown)'")
        }

        let title = try string(changes, "title", nullable: false)
        let notes = try string(changes, "notes", nullable: true)
        let url = try string(changes, "url", nullable: true).map { value -> URL? in
            guard let value else { return nil }
            guard let url = URL(string: value) else { throw InvalidChange("'url' isn't a valid URL: \(value)") }
            return url
        }
        let dueDate = try date(changes, "dueDate")
        let isAllDay = try bool(changes, "isAllDay")
        let priority = try changes["priority"].map { value -> Int in
            guard let name = value as? String, let priority = priorityValue(name) else {
                throw InvalidChange("'priority' must be \"none\", \"low\", \"medium\" or \"high\"")
            }
            return priority
        }
        let isCompleted = try bool(changes, "isCompleted")
        let alarmDates = try changes["alarmDates"].map { value -> [Date] in
            guard let dates = value as? [Any], let result = dates as? [Date] else {
                throw InvalidChange("'alarmDates' must be an array of Dates")
            }
            return result
        }
        let list = try changes["listID"].map { value -> EKCalendar in
            guard let id = value as? String else { throw InvalidChange("'listID' must be a string") }
            guard let list = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) else {
                throw InvalidChange("no reminder list has the ID '\(id)'")
            }
            return list
        }

        // The due date and whether it's a day or a time are stored together, so work out both
        let newDueDate: Date? = if let dueDate { dueDate } else { Self.date(from: reminder.dueDateComponents) }
        // Clearing the due date clears isAllDay too, unless the change asks for it
        let newIsAllDay = isAllDay ?? (newDueDate != nil && Self.isAllDay(reminder.dueDateComponents))
        if newIsAllDay && newDueDate == nil {
            throw InvalidChange("'isAllDay' needs a due date")
        }

        if let title { reminder.title = title }
        if let notes { reminder.notes = notes }
        if let url { reminder.url = url }
        if dueDate != nil || isAllDay != nil {
            reminder.dueDateComponents = newDueDate.map { dueDateComponents(for: $0, isAllDay: newIsAllDay) }
        }
        if let priority { reminder.priority = priority }
        if let isCompleted { reminder.isCompleted = isCompleted }
        if let alarmDates {
            (reminder.alarms ?? []).filter { $0.absoluteDate != nil }.forEach(reminder.removeAlarm)
            alarmDates.forEach { reminder.addAlarm(EKAlarm(absoluteDate: $0)) }
        }
        if let list { reminder.calendar = list }
    }

    /// A string change: nil if `key` is absent, .some(nil) if it's null (when allowed)
    private static func string(_ changes: [String: Any], _ key: String, nullable: Bool) throws -> String?? {
        guard let value = changes[key] else { return nil }
        if nullable && value is NSNull { return .some(nil) }
        guard let string = value as? String else {
            throw InvalidChange("'\(key)' must be a string\(nullable ? " or null" : "")")
        }
        return .some(string)
    }

    /// A Date change: nil if `key` is absent, .some(nil) if it's null
    private static func date(_ changes: [String: Any], _ key: String) throws -> Date?? {
        guard let value = changes[key] else { return nil }
        if value is NSNull { return .some(nil) }
        guard let date = value as? Date else { throw InvalidChange("'\(key)' must be a Date or null") }
        return .some(date)
    }

    private static func bool(_ changes: [String: Any], _ key: String) throws -> Bool? {
        guard let value = changes[key] else { return nil }
        // JS booleans arrive as CFBoolean NSNumbers; don't accept other numbers as booleans
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw InvalidChange("'\(key)' must be a boolean")
        }
        return number.boolValue
    }

    // MARK: - Due dates

    /// The due date `components` describe, in the Mac's calendar
    static func date(from components: DateComponents?, calendar: Calendar = .current) -> Date? {
        guard let components else { return nil }
        // Date-only components (an all-day reminder) give the start of that day
        return calendar.date(from: components)
    }

    /// Whether `components` describe a day rather than a time
    static func isAllDay(_ components: DateComponents?) -> Bool {
        guard let components else { return false }
        return components.hour == nil
    }

    /// The components to store for a due date: the day alone for an all-day reminder (floating, so
    /// it's the same day in any time zone), or the time in the Mac's time zone
    static func dueDateComponents(for date: Date, isAllDay: Bool, calendar: Calendar = .current) -> DateComponents {
        if isAllDay {
            return calendar.dateComponents([.year, .month, .day], from: date)
        }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = calendar.timeZone
        return components
    }

    // MARK: - Priorities

    /// EventKit's priorities run from 1 (highest) to 9 (lowest), with 0 for none; Reminders uses 1,
    /// 5 and 9 for high, medium and low, and shows the rest of each third as the same.
    static func priorityName(_ priority: Int) -> String {
        switch priority {
        case 1...4: return "high"
        case 5:     return "medium"
        case 6...9: return "low"
        default:    return "none"
        }
    }

    static func priorityValue(_ name: String) -> Int? {
        switch name {
        case "none":   return 0
        case "high":   return 1
        case "medium": return 5
        case "low":    return 9
        default:       return nil
        }
    }
}

/// Throws `message` as a JS `Error` from the JS call that's running, and logs it
@MainActor
func throwEventKitError(_ message: String) {
    AKError(message)
    if let context = JSContext.current() {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }
}
