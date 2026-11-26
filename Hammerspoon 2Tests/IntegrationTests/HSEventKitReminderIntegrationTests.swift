//
//  HSEventKitReminderIntegrationTests.swift
//  Hammerspoon 2Tests
//

import EventKit
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

private nonisolated func hasReminderAccess() -> Bool {
    EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
}

/// Tests that create, change and delete real reminders only run on a throwaway machine (an hs2vm
/// VM, or a GitHub Actions runner), so they never touch the developer's own reminders.
/// xcodebuild only passes TEST_RUNNER_-prefixed variables to the test host, so neither is set by
/// accident on a developer's Mac.
private nonisolated func canWriteReminders() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return hasReminderAccess() && (environment["HS2_VM"] != nil || environment["CI"] != nil)
}

@Suite("hs.eventkit reminder tests")
@MainActor
struct HSEventKitReminderTests {

    private static func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSEventKitModule.self, as: "eventkit")
        return harness
    }

    /// An unsaved reminder, which needs no access to make or change
    private static func makeReminder() -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Water the plants"
        reminder.notes = "The ferns too"
        reminder.priority = 5
        return reminder
    }

    /// Puts an HSReminder for `reminder` into JS as the global `name`
    private static func expose(_ reminder: EKReminder, as name: String, in harness: JSTestHarness) {
        harness.context.setObject(HSReminder(reminder: reminder, store: EKEventStore()), forKeyedSubscript: name as NSString)
    }

    /// Converts a JS object literal to a dictionary the way JSExport does for an `[String: Any]` argument
    private static func changes(_ literal: String, in harness: JSTestHarness) throws -> [String: Any] {
        try #require(harness.evalValue("(\(literal))")?.toDictionary() as? [String: Any])
    }

    @Suite("API structure")
    @MainActor
    struct StructureTests {
        @Test("Reminder methods are exposed")
        func testAPI() {
            let harness = makeHarness()
            for name in ["reminderLists", "reminders", "incompleteReminders", "completedReminders", "reminder", "createReminder"] {
                #expect(harness.evalTypeOf("hs.eventkit.\(name)") == "function", "\(name)")
            }
        }

        @Test("Reminder permission is checked through hs.permissions")
        func testPermissionsAPI() {
            let harness = makeHarness()
            harness.loadModule(HSPermissionsModule.self, as: "permissions")
            #expect(harness.evalTypeOf("hs.permissions.requestReminders") == "function")
            harness.expectEqual("hs.permissions.checkReminders()", hasReminderAccess())
        }
    }

    @Suite("HSReminder bridging")
    @MainActor
    struct BridgingTests {
        @Test("Reminder properties reach JS with Date fields and nulls")
        func testReminderBridgesToJS() {
            let harness = makeHarness()
            let reminder = makeReminder()
            reminder.dueDateComponents = DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 26, hour: 9)
            reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 5_000)))
            expose(reminder, as: "r", in: harness)
            #expect(harness.evalString("r.typeName") == "HSReminder")
            #expect(harness.evalString("r.title") == "Water the plants")
            #expect(harness.evalString("r.notes") == "The ferns too")
            #expect(harness.evalString("r.priority") == "medium")
            #expect(harness.evalBool("r.isCompleted") == false)
            #expect(harness.evalBool("r.isAllDay") == false)
            #expect(harness.evalBool("r.isRecurring") == false)
            #expect(harness.evalString("r.dueDate.toISOString()") == "2026-11-26T09:00:00.000Z")
            harness.expectTrue("r.alarmDates.length === 1 && r.alarmDates[0] instanceof Date && r.alarmDates[0].getTime() === 5000000")
            harness.expectTrue("r.url === null && r.completionDate === null && r.listID === null && r.listTitle === null")
            harness.expectTrue("String(r) === '<HSReminder: Water the plants>'")
            #expect(!harness.hasException)
        }

        @Test("JSON.stringify serialises every property through toJSON()")
        func testToJSON() {
            let harness = makeHarness()
            expose(makeReminder(), as: "r", in: harness)
            harness.eval("var parsed = JSON.parse(JSON.stringify(r))")
            #expect(harness.evalString("parsed.title") == "Water the plants")
            harness.expectTrue("parsed.dueDate === null && Array.isArray(parsed.alarmDates)")
            #expect(harness.evalString("Object.keys(parsed).sort().join(',')") ==
                "alarmDates,completionDate,creationDate,dueDate,externalID,id,isAllDay,isCompleted,isRecurring,lastModifiedDate,listID,listTitle,notes,priority,title,url")
            #expect(!harness.hasException)
        }

        @Test("A reminder the caller drops is garbage collected")
        func testReminderIsCollected() {
            let harness = makeHarness()
            weak var weakReminder: HSReminder?
            autoreleasepool {
                let strong = HSReminder(reminder: makeReminder(), store: EKEventStore())
                weakReminder = strong
                harness.context.setObject(strong, forKeyedSubscript: "r" as NSString)
                harness.eval("r = null; void 0")
            }
            harness.collectGarbage()
            #expect(weakReminder == nil)
        }

        @Test("update() with an invalid change throws and leaves the reminder as it was")
        func testInvalidUpdateThrows() {
            let harness = makeHarness()
            expose(makeReminder(), as: "r", in: harness)
            harness.expectEqual("""
                (() => { try { r.update({ title: 'Changed', priority: 'urgent' }); return false } catch (e) { return true } })()
                """, true)
            #expect(harness.evalString("r.title") == "Water the plants")
        }

        @Test("update() that can't be saved throws")
        func testUnsavableUpdateThrows() {
            let harness = makeHarness()
            // No list, so saving fails whether or not there's access
            expose(makeReminder(), as: "r", in: harness)
            harness.expectEqual("""
                (() => { try { r.update({ title: 'Changed' }); return false } catch (e) { return true } })()
                """, true)
        }
    }

    @Suite("Applying changes")
    @MainActor
    struct ApplyTests {
        @Test("Changes from a JS object are applied")
        func testApply() throws {
            let harness = makeHarness()
            let reminder = makeReminder()
            reminder.addAlarm(EKAlarm(relativeOffset: -60))
            reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 1)))
            try HSReminder.apply(try changes("""
                { title: 'Feed the cat', notes: null, url: 'https://example.com/x', dueDate: new Date(1000000),
                  priority: 'high', isCompleted: true, alarmDates: [new Date(2000000), new Date(3000000)] }
                """, in: harness), to: reminder, in: EKEventStore())
            #expect(reminder.title == "Feed the cat")
            #expect(reminder.notes == nil)
            #expect(reminder.url?.absoluteString == "https://example.com/x")
            #expect(HSReminder.date(from: reminder.dueDateComponents) == Date(timeIntervalSince1970: 1_000))
            #expect(!HSReminder.isAllDay(reminder.dueDateComponents))
            #expect(reminder.priority == 1)
            #expect(reminder.isCompleted)
            #expect(reminder.completionDate != nil)
            // The relative alarm is kept; the timed one is replaced
            let alarms = reminder.alarms ?? []
            #expect(alarms.count == 3)
            #expect(alarms.compactMap(\.absoluteDate).sorted() == [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000)])
        }

        @Test("isAllDay keeps the due date's day and drops its time, in either order")
        func testAllDay() throws {
            let harness = makeHarness()
            let due = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 15, minute: 30)))
            let expected = Calendar.current.startOfDay(for: due)
            harness.context.setObject(due, forKeyedSubscript: "due" as NSString)

            let together = makeReminder()
            try HSReminder.apply(try changes("{ dueDate: due, isAllDay: true }", in: harness), to: together, in: EKEventStore())
            #expect(HSReminder.isAllDay(together.dueDateComponents))
            #expect(together.dueDateComponents?.timeZone == nil)
            #expect(HSReminder.date(from: together.dueDateComponents) == expected)

            // Setting the date on an all-day reminder keeps it all-day
            let separately = makeReminder()
            try HSReminder.apply(try changes("{ dueDate: new Date(0), isAllDay: true }", in: harness), to: separately, in: EKEventStore())
            try HSReminder.apply(try changes("{ dueDate: due }", in: harness), to: separately, in: EKEventStore())
            #expect(HSReminder.date(from: separately.dueDateComponents) == expected)

            // Turning isAllDay off gives a timed reminder at the start of that day
            try HSReminder.apply(try changes("{ isAllDay: false }", in: harness), to: separately, in: EKEventStore())
            #expect(!HSReminder.isAllDay(separately.dueDateComponents))
            #expect(HSReminder.date(from: separately.dueDateComponents) == expected)

            try HSReminder.apply(try changes("{ dueDate: null }", in: harness), to: separately, in: EKEventStore())
            #expect(separately.dueDateComponents == nil)
        }

        @Test("Invalid changes throw without changing anything", arguments: [
            "{ colour: 'red' }",
            "{ title: 5 }",
            "{ title: null }",
            "{ notes: 5 }",
            "{ dueDate: 'tomorrow' }",
            "{ isAllDay: true }",
            "{ isCompleted: 1 }",
            "{ priority: 'urgent' }",
            "{ alarmDates: [1, 2] }",
            "{ listID: 'no-such-list' }",
            "{ title: 'Changed', priority: 'urgent' }",
        ])
        func testInvalidChanges(_ literal: String) throws {
            let harness = makeHarness()
            let reminder = makeReminder()
            #expect(throws: HSReminder.InvalidChange.self) {
                try HSReminder.apply(try changes(literal, in: harness), to: reminder, in: EKEventStore())
            }
            #expect(reminder.title == "Water the plants")
            #expect(reminder.priority == 5)
        }

        @Test("Priorities map to and from EventKit's numbers")
        func testPriorities() {
            #expect([0, 1, 4, 5, 6, 9].map(HSReminder.priorityName) == ["none", "high", "high", "medium", "low", "low"])
            #expect(["none", "high", "medium", "low"].compactMap(HSReminder.priorityValue) == [0, 1, 5, 9])
            #expect(HSReminder.priorityValue("urgent") == nil)
        }

        @Test("Reminders sort by due date, undated last, then by creation")
        func testDueOrder() {
            func reminder(due day: Int?) -> EKReminder {
                let reminder = makeReminder()
                reminder.dueDateComponents = day.map { DateComponents(year: 2026, month: 11, day: $0) }
                return reminder
            }
            let sorted = [reminder(due: nil), reminder(due: 27), reminder(due: 26)].sorted(by: HSEventKitModule.dueOrder)
            #expect(sorted.map { $0.dueDateComponents?.day } == [26, 27, nil])
        }
    }

    @Suite("Without access", .disabled(if: hasReminderAccess(), "Reminders access is granted"))
    @MainActor
    struct NoAccessTests {
        @Test("Synchronous methods throw")
        func testThrows() {
            let harness = makeHarness()
            for call in ["reminderLists()", "reminder('x')", "createReminder({ title: 'x' })"] {
                harness.expectEqual("""
                    (() => { try { hs.eventkit.\(call); return false } catch (e) { return true } })()
                    """, true)
            }
        }

        @Test("Fetches reject")
        func testFetchesReject() async {
            let harness = makeHarness()
            var rejections = 0
            harness.registerCallback("rejected") { rejections += 1 }
            harness.eval("""
                hs.eventkit.reminders().catch(() => __test_callback('rejected'));
                hs.eventkit.incompleteReminders().catch(() => __test_callback('rejected'));
                hs.eventkit.completedReminders(new Date(0), new Date()).catch(() => __test_callback('rejected'));
                """)
            #expect(await harness.waitForAsync(timeout: 2) { rejections == 3 })
            #expect(!harness.hasException)
        }
    }

    @Suite("With access", .serialized, .enabled(if: hasReminderAccess(), "Reminders access is not granted"))
    @MainActor
    struct AccessTests {
        @Test("Reminder lists are listed, with one default")
        func testLists() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.eventkit.reminderLists())")
            harness.expectTrue("hs.eventkit.reminderLists().filter(l => l.isDefault).length <= 1")
            #expect(!harness.hasException)
        }

        @Test("List IDs that match nothing find no reminders")
        func testUnknownListIDs() async {
            let harness = makeHarness()
            var count: Int?
            harness.registerCallback("found") { (n: Int) in count = n }
            harness.eval("hs.eventkit.incompleteReminders(['no-such-list']).then(r => found(r.length))")
            #expect(await harness.waitForAsync(timeout: 5) { count != nil })
            #expect(count == 0)
        }

        @Test("An unknown id finds no reminder")
        func testUnknownID() {
            let harness = makeHarness()
            harness.expectTrue("hs.eventkit.reminder('no-such-reminder') === null")
        }

        @Test("A fetch still running at shutdown never settles")
        func testFetchDroppedAtShutdown() async {
            let harness = makeHarness()
            var settled = false
            harness.registerCallback("settled") { settled = true }
            harness.eval("hs.eventkit.reminders().then(() => __test_callback('settled'), () => __test_callback('settled'))")
            harness.shutdownForLeakTest()
            _ = await harness.waitForAsync(timeout: 1) { settled }
            #expect(!settled)
        }

        @Test("A reminder is created, found, completed and removed", .enabled(if: canWriteReminders(), "Only runs in an hs2vm VM or CI"))
        func testRoundTrip() async throws {
            let harness = makeHarness()
            let title = "hs.eventkit test \(UUID().uuidString)"
            harness.eval("""
                var r = hs.eventkit.createReminder({ title: '\(title)', notes: 'note', priority: 'low',
                                                     dueDate: new Date(Date.now() + 3600000) })
                """)
            #expect(!harness.hasException)
            let id = try #require(harness.evalString("r.id"))
            defer { harness.eval("try { hs.eventkit.reminder('\(id)')?.remove() } catch (e) {}") }
            harness.expectTrue("typeof r.listID === 'string' && r.creationDate instanceof Date")
            #expect(harness.evalString("hs.eventkit.reminder('\(id)').title") == title)

            var incomplete: Bool?
            harness.registerCallback("incomplete") { (found: Bool) in incomplete = found }
            harness.eval("hs.eventkit.incompleteReminders([r.listID]).then(all => incomplete(all.some(x => x.id === r.id)))")
            #expect(await harness.waitForAsync(timeout: 5) { incomplete != nil })
            #expect(incomplete == true)

            harness.eval("r.update({ isCompleted: true })")
            #expect(!harness.hasException)
            #expect(harness.evalBool("hs.eventkit.reminder('\(id)').isCompleted") == true)
            harness.expectTrue("hs.eventkit.reminder('\(id)').completionDate instanceof Date")

            var completed: Bool?
            harness.registerCallback("completed") { (found: Bool) in completed = found }
            harness.eval("""
                hs.eventkit.completedReminders(new Date(Date.now() - 60000), new Date(Date.now() + 60000))
                    .then(all => completed(all.some(x => x.id === r.id)))
                """)
            #expect(await harness.waitForAsync(timeout: 5) { completed != nil })
            #expect(completed == true)

            #expect(harness.evalBool("r.remove()") == true)
            harness.expectTrue("hs.eventkit.reminder('\(id)') === null")
            #expect(!harness.hasException)
        }

        @Test("createReminder() needs a title", .enabled(if: canWriteReminders(), "Only runs in an hs2vm VM or CI"))
        func testCreateNeedsTitle() {
            let harness = makeHarness()
            harness.expectEqual("""
                (() => { try { hs.eventkit.createReminder({ notes: 'x' }); return false } catch (e) { return true } })()
                """, true)
        }
    }
}
