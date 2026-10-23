//
//  TestAppControl.swift
//  Hammerspoon 2Tests
//

import AppKit
import Testing

/// Launches and drives the "Hammerspoon 2 Test App" from the tests (the app itself is a
/// separate program). It is the app tests launch, hide, quit and open windows in when they need
/// a real other application, instead of Finder or Chess. It starts in about 0.2 s, shows nothing
/// personal, and its window says which test is running.
///
/// Two ways to use it. A suite that only needs the app to be there takes the `.testApp` trait:
/// one copy runs for the whole suite, and `pid` names it (in JS: `hs.application.fromPID(pid)`).
/// A test about launching or quitting calls `launch(detail:)` itself and quits what it launched.
/// Every copy is addressed by its pid, so suites running side by side don't disturb each other.
///
/// Its source is `TestApp.swift` next to this file; `build-test-app.sh`, also here, builds it into
/// the build products as part of the test target's build. A missing app fails the tests that need
/// it rather than skipping them.
nonisolated enum TestAppControl {
    static let bundleID = "net.tenshu.Hammerspoon-2.TestApp"

    /// The built app, or nil when it's missing. The test target's "Build Test App" phase builds it
    /// next to the app that hosts the tests, so it travels with the build products (`hs2vm test`,
    /// `xcodebuild test-without-building`) instead of depending on the source tree.
    static let url: URL? = {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Hammerspoon 2 Test App.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    /// The copy the `.testApp` trait launched for the running suite; nil outside such a suite.
    @TaskLocal static var pid: pid_t?

    /// Why the `.testApp` trait has no copy for the running suite; each of its tests records it.
    @TaskLocal static var suiteLaunchFailure: String?

    /// Launches a new copy in the background and waits until its window is on screen. Only then
    /// is it ready: `hide()` right after `isFinishedLaunching` does nothing.
    /// - Parameter detail: What the test checks; shown in the app's window below the test's name
    /// - Returns: The running app, or nil when it's missing, couldn't be launched or showed no
    ///   window in time; all three are recorded as an issue, so a caller that returns early still fails
    @MainActor
    static func launch(detail: String = "") async -> NSRunningApplication? {
        switch await start(detail: detail) {
        case .success(let app):
            return app
        case .failure(let failure):
            Issue.record(Comment(rawValue: failure.reason))
            return nil
        }
    }

    /// Why a copy couldn't be started.
    struct LaunchFailure: Error {
        let reason: String
    }

    /// `launch(detail:)` without recording an issue, for the `.testApp` trait: an issue can't be
    /// recorded for a suite, only for a test. Returns the pid, since the app object can't leave
    /// the main actor.
    @MainActor
    fileprivate static func launchedPID(detail: String) async -> Result<pid_t, LaunchFailure> {
        await start(detail: detail).map(\.processIdentifier)
    }

    @MainActor
    private static func start(detail: String) async -> Result<NSRunningApplication, LaunchFailure> {
        guard let url else {
            return .failure(LaunchFailure(reason: "The test app is missing from the build products; the test target's \"Build Test App\" phase should have built it next to \(Bundle.main.bundleURL.lastPathComponent)"))
        }
        _ = leftoversQuit
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-test", currentTestName, "-detail", detail]
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            return .failure(LaunchFailure(reason: "The test app could not be launched: \(error.localizedDescription)"))
        }
        let deadline = Date().addingTimeInterval(5)
        while !isReady(app), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard isReady(app) else {
            app.terminate()
            return .failure(LaunchFailure(reason: "The test app showed no window within 5 s"))
        }
        return .success(app)
    }

    /// Copies an earlier, aborted test run left behind are quit before the first launch of this run.
    @MainActor
    private static let leftoversQuit: Void = {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }.forEach { $0.terminate() }
    }()

    private static var currentTestName: String { Test.current?.displayName ?? Test.current?.name ?? "" }

    private static func isReady(_ app: NSRunningApplication) -> Bool {
        app.isFinishedLaunching && hasWindowOnScreen(app)
    }

    private static func hasWindowOnScreen(_ app: NSRunningApplication) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
    }

    // MARK: - Commands to a running copy

    /// Shows the running test's name in the suite's copy, and what it checks.
    static func showCurrentTest(detail: String = "") {
        send("show", to: pid, ["test": currentTestName, "detail": detail])
    }

    /// Has a copy open one more window.
    /// - Parameter pid: The copy; the suite's copy by default
    static func openWindow(in pid: pid_t? = TestAppControl.pid) {
        send("newWindow", to: pid)
    }

    /// Has a copy open a window titled "Fullscreen test window" and put it in native fullscreen
    /// (a Space of its own). This activates the copy and switches to that Space.
    /// - Parameter pid: The copy; the suite's copy by default
    static func openFullScreenWindow(in pid: pid_t? = TestAppControl.pid) {
        send("fullScreenWindow", to: pid)
    }

    /// Has a copy close the windows `openWindow` and `openFullScreenWindow` opened.
    /// - Parameter pid: The copy; the suite's copy by default
    static func closeWindows(in pid: pid_t? = TestAppControl.pid) {
        send("closeWindows", to: pid)
    }

    private static func send(_ command: String, to pid: pid_t?, _ arguments: [String: String] = [:]) {
        guard let pid else { return }
        var userInfo = arguments
        userInfo["command"] = command
        userInfo["pid"] = String(pid)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("\(bundleID).command"), object: nil, userInfo: userInfo, deliverImmediately: true)
    }
}

/// Runs one copy of the test app for the whole suite; `TestAppControl.pid` names it.
///
/// It also scopes each test in the suite: Swift Testing can't record an issue for a suite, so when
/// the copy can't be started, each test records why instead of the suite's tests silently not running.
nonisolated struct TestAppTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    /// Scopes every suite and every test case. Being both a suite and a test trait, the default
    /// would scope only test cases, and the suite's copy would never start.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        test.isSuite || testCase != nil ? self : nil
    }

    @concurrent
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        guard test.isSuite else {
            if let reason = TestAppControl.suiteLaunchFailure {
                Issue.record(Comment(rawValue: reason))
                return
            }
            try await function()
            return
        }
        // A nested suite shares its parent's copy (or its parent's failure)
        guard TestAppControl.pid == nil, TestAppControl.suiteLaunchFailure == nil else {
            try await function()
            return
        }
        switch await TestAppControl.launchedPID(detail: "One copy for the whole suite") {
        case .success(let pid):
            defer { NSRunningApplication(processIdentifier: pid)?.terminate() }
            try await TestAppControl.$pid.withValue(pid) { try await function() }
        case .failure(let failure):
            try await TestAppControl.$suiteLaunchFailure.withValue(failure.reason) { try await function() }
        }
    }
}

nonisolated extension Trait where Self == TestAppTrait {
    /// Runs one copy of the Hammerspoon 2 Test App for the whole suite.
    static var testApp: Self { Self() }
}
