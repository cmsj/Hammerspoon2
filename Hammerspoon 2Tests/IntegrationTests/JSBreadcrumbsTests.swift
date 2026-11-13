//
//  JSBreadcrumbsTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import JavaScriptCore
import Testing
@testable import Hammerspoon_2

/// Tests of the recorder of what JavaScript is running (Engine/JSBreadcrumbs.swift). Each test
/// records into its own file, and makes it the current recorder only for as long as it runs.
/// The tests are synchronous on the main actor, so no other test can call into JavaScript
/// while one of them is recording.
@Suite("JavaScript breadcrumbs tests")
@MainActor
struct JSBreadcrumbsTests {
    let directory: URL
    let recorder: JSBreadcrumbs

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "JSBreadcrumbsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recorder = try JSBreadcrumbs(file: JSBreadcrumbs.file(forProcess: 42, in: directory))
    }

    // The files are only temporary, so this doesn't need to be isolated.
    nonisolated func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// What's in the recorder's file now, as the next launch would read it.
    func snapshot() throws -> JSBreadcrumbs.Snapshot {
        try #require(JSBreadcrumbs.snapshot(forProcess: 42, in: directory))
    }

    /// Runs `body` with the test's recorder as the one the hooks write to.
    func recording(_ body: () throws -> Void) rethrows {
        JSBreadcrumbs.installHooks()
        let previous = JSBreadcrumbs.current
        JSBreadcrumbs.current = recorder
        defer { JSBreadcrumbs.current = previous }
        try body()
    }

    /// A harness with a `snapshot()` function that records the labels of what's running, in
    /// `running`.
    func harness(capturingInto running: SnapshotBox) -> JSTestHarness {
        let harness = JSTestHarness()
        let capture: @convention(block) () -> Void = { [directory] in
            running.labels = JSBreadcrumbs.snapshot(forProcess: 42, in: directory)?.running.map(\.label) ?? []
        }
        harness.context.setObject(capture, forKeyedSubscript: "snapshot" as NSString)
        return harness
    }

    final class SnapshotBox {
        var labels: [String] = []
    }

    // MARK: - The file

    @Test("Running entries are recorded until they finish, and all are kept as recent")
    func testRunningAndRecent() throws {
        defer { cleanUp() }
        recorder.push("outer")
        recorder.push("inner")
        #expect(try snapshot().running.map(\.label) == ["outer", "inner"])

        recorder.pop()
        let afterPop = try snapshot()
        #expect(afterPop.running.map(\.label) == ["outer"])
        #expect(afterPop.recent.map(\.label) == ["outer", "inner"])
        #expect(abs(afterPop.recent[0].time.timeIntervalSinceNow) < 60)
    }

    @Test("Only the newest recent entries are kept, oldest first")
    func testRecentWrapsAround() throws {
        defer { cleanUp() }
        let count = JSBreadcrumbs.recentCapacity + 5
        for index in 0..<count {
            recorder.push("entry \(index)")
            recorder.pop()
        }
        let recent = try snapshot().recent.map(\.label)
        #expect(recent == (5..<count).map { "entry \($0)" })
        #expect(try snapshot().running.isEmpty)
    }

    @Test("Running entries beyond the file's capacity are counted")
    func testDeepNesting() throws {
        defer { cleanUp() }
        let depth = JSBreadcrumbs.runningCapacity + 3
        for index in 0..<depth {
            recorder.push("level \(index)")
        }
        let snapshot = try snapshot()
        #expect(snapshot.running.map(\.label) == (0..<JSBreadcrumbs.runningCapacity).map { "level \($0)" })
        #expect(snapshot.omittedRunning == 3)

        for _ in 0..<depth {
            recorder.pop()
        }
        recorder.push("after")
        #expect(try self.snapshot().running.map(\.label) == ["after"])
    }

    @Test("Long labels are cut short")
    func testLongLabel() throws {
        defer { cleanUp() }
        recorder.push(String(repeating: "x", count: 500))
        #expect(try snapshot().running.first?.label.count == JSBreadcrumbs.labelCapacity)
    }

    @Test("Files that aren't breadcrumbs are ignored")
    func testRejectsOtherFiles() {
        defer { cleanUp() }
        #expect(JSBreadcrumbs.snapshot(of: Data(count: JSBreadcrumbs.fileSize)) == nil)
        #expect(JSBreadcrumbs.snapshot(of: Data("hello".utf8)) == nil)
        #expect(JSBreadcrumbs.snapshot(forProcess: 43, in: directory) == nil)
    }

    // MARK: - Hooks

    @Test("Calls from native code into JavaScript are recorded by function name")
    func testNativeCallsAreRecorded() throws {
        defer { cleanUp() }
        let running = SnapshotBox()
        let harness = harness(capturingInto: running)
        harness.eval("""
            function toggleMute() { snapshot(); }
            var anonymous = (() => () => snapshot())();
            var object = { method: function () { snapshot(); } };
            """)

        try recording {
            harness.evalValue("toggleMute")?.call(withArguments: [])
            #expect(running.labels == ["call toggleMute"])

            harness.evalValue("anonymous")?.call(withArguments: [])
            #expect(running.labels == ["call anonymous function"])

            harness.evalValue("object")?.invokeMethod("method", withArguments: [])
            #expect(running.labels == ["call .method"])

            harness.evalValue("toggleMute()")
            #expect(running.labels == ["evaluate script"])
        }
        #expect(try snapshot().running.isEmpty)
        #expect(!harness.hasException)
    }

    @Test("Scripts are named by path, with the home folder abbreviated")
    func testScriptNames() {
        defer { cleanUp() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(JSBreadcrumbs.scriptName(home.appending(path: ".config/Hammerspoon2/init.js")) == "~/.config/Hammerspoon2/init.js")
        #expect(JSBreadcrumbs.scriptName(URL(fileURLWithPath: "/opt/config.js")) == "/opt/config.js")
        #expect(JSBreadcrumbs.scriptName(nil) == "script")
        if let engine = Bundle.main.url(forResource: "engine", withExtension: "js") {
            #expect(JSBreadcrumbs.scriptName(engine) == "engine.js")
        }
    }

    @Test("Event listeners are recorded with their emitter and event")
    func testListenersAreRecorded() throws {
        defer { cleanUp() }
        let running = SnapshotBox()
        let harness = harness(capturingInto: running)
        harness.eval("""
            var emitter = new EventEmitter();
            emitter._label = "hs.test";
            emitter.on("ping", function onPing() { snapshot(); });
            emitter.once("pong", function onPong() { snapshot(); });
            emitter.on("fail", function () { throw new Error("listener failed"); });
            """)

        try recording {
            harness.evalValue("emitter")?.invokeMethod("emit", withArguments: ["ping"])
            #expect(running.labels == ["call .emit", #"hs.test "ping" listener onPing"#])

            harness.evalValue("emitter")?.invokeMethod("emit", withArguments: ["pong"])
            #expect(running.labels == ["call .emit", #"hs.test "pong" listener onPong"#])

            // A listener that throws still finishes.
            harness.eval(#"try { emitter.emit("fail"); } catch (e) {}"#)
        }
        #expect(try snapshot().running.isEmpty)
        #expect(try snapshot().recent.map(\.label).contains(#"hs.test "fail" listener anonymous function"#))
    }

    @Test("A listener or function whose name can't be read still runs")
    func testThrowingNameGetter() throws {
        defer { cleanUp() }
        let running = SnapshotBox()
        let harness = harness(capturingInto: running)
        harness.eval("""
            function badName() { snapshot(); }
            Object.defineProperty(badName, "name", { get: function () { throw new Error("no name"); } });
            var emitter = new EventEmitter();
            emitter._label = "hs.test";
            emitter.once("ping", badName);
            """)
        #expect(!harness.hasException)

        try recording {
            harness.evalValue("emitter")?.invokeMethod("emit", withArguments: ["ping"])
            #expect(running.labels == ["call .emit", #"hs.test "ping" listener wrapped"#])

            harness.evalValue("badName")?.call(withArguments: [])
            #expect(running.labels == ["call anonymous function"])
        }
        #expect(!harness.hasException)
    }

    @Test("engine.js doesn't leave its breadcrumb functions in the global scope")
    func testFunctionsAreHidden() {
        defer { cleanUp() }
        let harness = JSTestHarness()
        harness.expectEqual("typeof _hs_breadcrumbEnter", "undefined")
        harness.expectEqual("typeof _hs_breadcrumbExit", "undefined")
    }

    @Test("Nothing is recorded without a recorder")
    func testNoRecorder() throws {
        defer { cleanUp() }
        JSBreadcrumbs.installHooks()
        let previous = JSBreadcrumbs.current
        JSBreadcrumbs.current = nil
        defer { JSBreadcrumbs.current = previous }

        let harness = JSTestHarness()
        harness.eval("function f() { return 1; }")
        #expect(harness.evalValue("f")?.call(withArguments: []).toInt32() == 1)
        #expect(try snapshot().recent.isEmpty)
    }

    // MARK: - Crash reports

    static let crashSnapshot = JSBreadcrumbs.Snapshot(
        running: [
            .init(time: Date(timeIntervalSince1970: 1_000), label: "call .emit"),
            .init(time: Date(timeIntervalSince1970: 1_000.25), label: #"hs.usb "added" listener onUSB"#),
        ],
        omittedRunning: 0,
        recent: (0..<12).map { .init(time: Date(timeIntervalSince1970: 990 + Double($0)), label: "call timer\($0)") })

    @Test("A crash report shows the JavaScript that was running, and what ran before it")
    func testReportSummary() throws {
        defer { cleanUp() }
        let report = try CrashReportTests.fixture("abort").adding(javaScript: Self.crashSnapshot)
        let summary = report.summary(version: "0.1.0")
        #expect(summary.contains("JavaScript running (innermost last):"))
        #expect(summary.contains(#"hs.usb "added" listener onUSB"#))
        #expect(summary.contains("call timer11"))
        #expect(!summary.contains("call timer1\n"), "only the last 10 recent entries")

        let compact = try CrashReport(text: report.compactText())
        #expect(compact.summary(version: "0.1.0").contains(#"hs.usb "added" listener onUSB"#))
    }

    @Test("A crash outside JavaScript says so")
    func testReportWithNothingRunning() throws {
        defer { cleanUp() }
        let snapshot = JSBreadcrumbs.Snapshot(running: [], omittedRunning: 0, recent: Self.crashSnapshot.recent)
        let report = try CrashReportTests.fixture("abort").adding(javaScript: snapshot)
        #expect(report.summary(version: "0.1.0").contains("JavaScript running: none"))
        #expect(try !CrashReportTests.fixture("abort").summary(version: "0.1.0").contains("JavaScript"))
    }

    @Test("The app's crash reports get its breadcrumbs, its helpers' don't")
    func testManagerAddsBreadcrumbs() throws {
        let found = try findReports(breadcrumbsSecondsAfterLaunch: 0.2)
        let app = try #require(found.first { $0.processName == "Hammerspoon 2" })
        let helper = try #require(found.first { $0.processName == "HammerspoonIPCBroker" })
        #expect(app.summary(version: nil).contains("call onCrash"))
        #expect(!helper.summary(version: nil).contains("JavaScript"))
    }

    @Test("Breadcrumbs left by an earlier or later process with the same pid aren't added",
          arguments: [-3_600.0, 3_600.0])
    func testManagerChecksProcessLifetime(secondsAfterLaunch: Double) throws {
        let found = try findReports(breadcrumbsSecondsAfterLaunch: secondsAfterLaunch)
        let app = try #require(found.first { $0.processName == "Hammerspoon 2" })
        #expect(!app.summary(version: nil).contains("JavaScript"))
    }

    @Test("Reports say when their process launched and crashed")
    func testReportDates() throws {
        defer { cleanUp() }
        let report = try CrashReportTests.fixture("abort")
        let launch = try #require(report.launchDate)
        let capture = try #require(report.captureDate)
        #expect(abs(capture.timeIntervalSince(launch) - 0.398) < 0.001)
    }

    /// Writes both fixture reports, and breadcrumbs for each recorded `seconds` after its
    /// process launched, then finds them as the app would.
    func findReports(breadcrumbsSecondsAfterLaunch seconds: Double) throws -> [CrashReport] {
        let reports = directory.appending(path: "Reports", directoryHint: .isDirectory)
        let suiteName = "JSBreadcrumbsTests-\(UUID().uuidString)"
        defer {
            cleanUp()
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(Date.distantPast, forKey: CrashReportManager.lastCheckedKey)

        for fixture in ["abort", "uncaught-exception"] {
            try CrashReportTests.fixtureText(fixture).write(to: reports.appending(path: "\(fixture).ips"), atomically: true, encoding: .utf8)
            let report = try CrashReportTests.fixture(fixture)
            let pid = try #require(report.pid)
            let launch = try #require(report.launchDate)
            let breadcrumbs = try JSBreadcrumbs(file: JSBreadcrumbs.file(forProcess: pid, in: directory))
            breadcrumbs.push("call onCrash", at: launch.addingTimeInterval(seconds))
        }

        let manager = CrashReportManager(reportsDirectory: reports, breadcrumbsDirectory: directory, defaults: defaults)
        return manager.newCrashReports(bundleIdentifier: CrashReportTests.bundleIdentifier).map(\.report)
    }
}
