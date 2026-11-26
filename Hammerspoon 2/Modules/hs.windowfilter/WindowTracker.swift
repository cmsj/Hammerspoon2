//
//  WindowTracker.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import AXSwift

/// The process-wide, live picture of every window, shared by all window filters in all engines.
///
/// While anything is subscribed, it watches applications launching, quitting, activating,
/// hiding and unhiding (NSWorkspace), windows being created and focused (application-level AX
/// notifications), and each window being moved, resized, minimized, retitled or destroyed
/// (window-level AX notifications, through the shared `AXObserverHub`). It keeps a
/// `WindowState` for every window, and reports each change to a window to its subscribers as
/// the window's old and new state and the events that amounts to.
///
/// When nothing is subscribed it watches nothing, and `entries()` takes a one-off look instead.
///
/// An application can turn Accessibility off for itself (e.g. Firefox in kiosk mode), refusing
/// every request with `kAXErrorAPIDisabled`. The tracker takes that refusal as final until the
/// application quits, rather than asking again each time it's activated, and remembers it, so
/// `inaccessibleApplications()` can say which applications it can't see the windows of.
///
/// Hammerspoon's own windows are never included: its own process can't answer Accessibility
/// requests while its main thread is busy asking them.
@_documentation(visibility: private)
@MainActor
final class WindowTracker {
    static let shared = WindowTracker()

    /// One change to one window
    struct Change {
        let windowID: Int
        let old: WindowState?
        let new: WindowState?
        let events: [HSWindowFilterEvent]
        /// The window, still usable for its ID, title, etc. after it's destroyed
        let window: HSWindow
        /// A window that already existed, found late (e.g. its application couldn't be watched
        /// at first): subscribers should record it without emitting anything
        var isSilent = false
    }

    /// A window, with what a filter's `windows()` needs to sort it
    struct Entry {
        let state: WindowState
        let window: HSWindow
        let createdAt: Double
        let focusedAt: Double
    }

    typealias Handler = @MainActor (Change) -> Void
    typealias InaccessibleHandler = @MainActor (NSRunningApplication) -> Void

    /// Keeps a subscriber's handler registered until it's cancelled or released
    final class Subscription {
        fileprivate weak var tracker: WindowTracker?

        fileprivate init(tracker: WindowTracker) {
            self.tracker = tracker
        }

        isolated deinit {
            tracker?.unsubscribe(ObjectIdentifier(self))
        }

        func cancel() {
            tracker?.unsubscribe(ObjectIdentifier(self))
        }
    }

    /// How long a window must stop moving, resizing or changing its title before its new state
    /// is read. Internal so tests can shorten it.
    static var settleDelay: Duration = .milliseconds(200)

    /// Applications whose windows aren't worth asking for: helper processes that never have any
    static let ignoredBundleIDs: Set<String> = [
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.Networking",
        "com.apple.WebKit.GPU",
        "com.apple.universalcontrol",
        "com.apple.hiservices-xpcservice",
        "com.hnc.Discord.helper.Renderer",
    ]

    private struct TrackedApp {
        let app: NSRunningApplication
        let element: UIElement
    }

    private struct TrackedWindow {
        let element: UIElement
        var state: WindowState
        let createdAt: Double
        var focusedAt: Double
    }

    private var handlers: [ObjectIdentifier: Handler] = [:]
    private var inaccessibleHandlers: [ObjectIdentifier: InaccessibleHandler] = [:]
    private var axClient: AXObserverHub.Client?
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var screenObserver: (any NSObjectProtocol)?

    private var apps: [pid_t: TrackedApp] = [:]
    private var windows: [Int: TrackedWindow] = [:]
    private var windowIDs: [UIElement: Int] = [:]
    private var activePID: pid_t?
    private var focusedWindowID: Int?
    /// Applications that have refused Accessibility requests, until they quit
    private var inaccessibleApps: [pid_t: NSRunningApplication] = [:]

    /// Pending work: per-window settle delays, per-app watch retries, the Space-change refresh
    private var settleTasks: [Int: Task<Void, Never>] = [:]
    /// Windows that couldn't be read on their last refresh, and how many times that's happened
    private var refreshRetries: [Int: Int] = [:]
    private var retryTasks: [pid_t: Task<Void, Never>] = [:]
    private var refreshTask: Task<Void, Never>?

    private static let windowNotifications: [UIElement.AXNotification] = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification,
    ].map { UIElement.AXNotification(rawValue: $0 as String) }

    private init() {}

    var isRunning: Bool { axClient != nil }

    // MARK: - Subscribers

    /// Registers `handler` for every window change, starting to watch windows if nothing was
    func subscribe(_ handler: @escaping Handler) -> Subscription {
        let subscription = Subscription(tracker: self)
        handlers[ObjectIdentifier(subscription)] = handler
        if !isRunning {
            start()
        }
        return subscription
    }

    /// Registers `handler` for every application found to have turned Accessibility off after
    /// it starts watching (the ones it already knew of are in `inaccessibleApplications()`),
    /// starting to watch windows if nothing was
    func subscribeToInaccessibleApplications(_ handler: @escaping InaccessibleHandler) -> Subscription {
        let subscription = Subscription(tracker: self)
        inaccessibleHandlers[ObjectIdentifier(subscription)] = handler
        if !isRunning {
            start()
        }
        return subscription
    }

    private func unsubscribe(_ id: ObjectIdentifier) {
        guard handlers.removeValue(forKey: id) != nil || inaccessibleHandlers.removeValue(forKey: id) != nil else { return }
        if handlers.isEmpty && inaccessibleHandlers.isEmpty {
            stop()
        }
    }

    private func deliver(_ change: Change) {
        for handler in Array(handlers.values) {
            handler(change)
        }
    }

    // MARK: - Inaccessible applications

    /// Whether an Accessibility error means the application has turned Accessibility off for
    /// itself, so asking again is pointless until it quits. Hammerspoon not being trusted gives
    /// the same error for every application, so it only counts while Hammerspoon is trusted.
    nonisolated static func isFinalRefusal(_ error: AXError, isTrusted: Bool) -> Bool {
        error == .apiDisabled && isTrusted
    }

    /// The running applications that have turned Accessibility off, so their windows can't be
    /// seen: those found so far while running, or a one-off look otherwise
    func inaccessibleApplications() -> [NSRunningApplication] {
        guard AXIsProcessTrusted() else { return [] }
        let apps: [NSRunningApplication]
        if isRunning {
            apps = inaccessibleApps.values.filter { !$0.isTerminated }
        } else {
            apps = withShortTimeout {
                NSWorkspace.shared.runningApplications.filter { Self.isCandidate($0) && Self.refusesAccessibility($0) }
            }
        }
        return apps.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    /// Whether an application refuses Accessibility requests outright
    private static func refusesAccessibility(_ app: NSRunningApplication) -> Bool {
        var value: CFTypeRef?
        let error = unsafe AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                                         kAXWindowsAttribute as CFString, &value)
        return error == .apiDisabled
    }

    /// Remembers that an application has turned Accessibility off, telling subscribers if `announce`
    private func applicationRefused(_ app: NSRunningApplication, announce: Bool) {
        let pid = app.processIdentifier
        guard inaccessibleApps[pid] == nil else { return }
        inaccessibleApps[pid] = app
        AKDebug("WindowTracker: \(app.localizedName ?? "PID \(pid)") has turned Accessibility off; not asking again until it quits")
        guard announce else { return }
        for handler in Array(inaccessibleHandlers.values) {
            handler(app)
        }
    }

    // MARK: - Reading windows

    /// Every window, from the live picture while running, or a one-off look otherwise
    func entries() -> [Entry] {
        if isRunning {
            return windows.values.compactMap { tracked in
                guard let app = apps[tracked.state.pid] else { return nil }
                return Entry(state: tracked.state, window: makeWindow(tracked, app: app), createdAt: tracked.createdAt, focusedAt: tracked.focusedAt)
            }
        }
        return withShortTimeout {
            let snapshot = Snapshot()
            return snapshot.entries
        }
    }

    /// A window's state: the tracked one, or read now for a window that isn't tracked
    func state(of window: HSWindow) -> WindowState? {
        if let tracked = windows[window.id] {
            return tracked.state
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let focusedID = frontmost.flatMap { Self.focusedWindowID(of: $0) }
        return withShortTimeout {
            Self.readState(of: window.element, app: window.app, id: window.id,
                           currentSpaces: Self.currentSpaceIDs(), focusedWindowID: focusedID,
                           activePID: frontmost?.processIdentifier)
        }
    }

    /// The tracked window with this ID, if any
    func window(withID id: Int) -> HSWindow? {
        guard let tracked = windows[id], let app = apps[tracked.state.pid] else { return nil }
        return makeWindow(tracked, app: app)
    }

    private func makeWindow(_ tracked: TrackedWindow, app: TrackedApp) -> HSWindow {
        HSWindow(element: tracked.element, app: app.app, id: tracked.state.id)
    }

    // MARK: - Starting and stopping

    private func start() {
        AKDebug("WindowTracker: starting")
        axClient = AXObserverHub.shared.makeClient { [weak self] element, notification, pid in
            self?.handle(notification, element: element, pid: pid)
        }

        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ action: @escaping @MainActor (WindowTracker, NSRunningApplication) -> Void) {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let app = NSRunningApplication(processIdentifier: pid) ?? self.apps[pid]?.app else { return }
                    action(self, app)
                }
            })
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { $0.watch($1, attempt: 0, announce: true) }
        observe(NSWorkspace.didTerminateApplicationNotification) { $0.applicationTerminated($1.processIdentifier) }
        observe(NSWorkspace.didActivateApplicationNotification) { $0.applicationActivated($1) }
        observe(NSWorkspace.didHideApplicationNotification) { $0.applicationHiddenChanged($1.processIdentifier, hidden: true) }
        observe(NSWorkspace.didUnhideApplicationNotification) { $0.applicationHiddenChanged($1.processIdentifier, hidden: false) }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }

        withShortTimeout {
            let snapshot = Snapshot()
            activePID = snapshot.activePID
            focusedWindowID = snapshot.focusedWindowID
            for app in snapshot.apps {
                watch(app, attempt: 0, announce: false)
            }
            for entry in snapshot.tracked {
                guard apps[entry.state.pid] != nil else { continue }
                track(entry.element, state: entry.state, createdAt: entry.createdAt, focusedAt: entry.focusedAt)
            }
        }
        AKDebug("WindowTracker: tracking \(windows.count) windows in \(apps.count) applications")
    }

    private func stop() {
        AKDebug("WindowTracker: stopping")
        axClient?.invalidate()
        axClient = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        for task in settleTasks.values { task.cancel() }
        for task in retryTasks.values { task.cancel() }
        refreshTask?.cancel()
        settleTasks = [:]
        refreshRetries = [:]
        retryTasks = [:]
        refreshTask = nil
        apps = [:]
        inaccessibleApps = [:]
        windows = [:]
        windowIDs = [:]
        activePID = nil
        focusedWindowID = nil
    }

    // MARK: - Applications

    /// Whether an application might have windows worth tracking
    static func isCandidate(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != getpid(), app.activationPolicy != .prohibited, !app.isTerminated else { return false }
        if let bundleID = app.bundleIdentifier, ignoredBundleIDs.contains(bundleID) { return false }
        return true
    }

    /// Starts watching an application for new and focused windows. An application that has only
    /// just launched may not answer yet, so this retries a few times, backing off, as Hammerspoon 1
    /// did. With `announce`, its windows are reported as created; otherwise, they're tracked
    /// silently, as windows that already existed. The first attempt while starting up leaves its
    /// windows to `start()`, which already has them. An application that has turned
    /// Accessibility off isn't asked again until it quits; with `announce`, that's reported too.
    private func watch(_ app: NSRunningApplication, attempt: Int, announce: Bool) {
        let pid = app.processIdentifier
        guard let axClient, apps[pid] == nil, inaccessibleApps[pid] == nil, Self.isCandidate(app) else { return }
        retryTasks.removeValue(forKey: pid)?.cancel()

        let element = UIElement(AXUIElementCreateApplication(pid))
        do {
            try axClient.add(UIElement.AXNotification(rawValue: kAXWindowCreatedNotification as String), element: element, pid: pid)
            try axClient.add(UIElement.AXNotification(rawValue: kAXFocusedWindowChangedNotification as String), element: element, pid: pid)
        } catch {
            axClient.removeAll(pid: pid)
            if Self.isFinalRefusal(error, isTrusted: AXIsProcessTrusted()) {
                applicationRefused(app, announce: announce)
                return
            }
            guard attempt < 5, !app.isTerminated else {
                AKDebug("WindowTracker: giving up on watching \(app.localizedName ?? "PID \(pid)"): \(error)")
                return
            }
            retryTasks[pid] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                guard !Task.isCancelled else { return }
                self?.retryTasks.removeValue(forKey: pid)
                self?.watch(app, attempt: attempt + 1, announce: announce)
            }
            return
        }

        apps[pid] = TrackedApp(app: app, element: element)
        if announce || attempt > 0 {
            withShortTimeout {
                for windowElement in WindowEnumerator.windowElements(for: app) {
                    windowAppeared(windowElement, pid: pid, announce: announce)
                }
            }
        }
        // An application that was activated before it could be watched (e.g. one that has just
        // launched) had no focused window to read then
        if pid == activePID {
            syncFocusedWindow(of: app)
        }
    }

    /// Reads which of an application's windows is focused, tracking it first if it's new
    private func syncFocusedWindow(of app: NSRunningApplication) {
        let focused = withShortTimeout { Self.focusedWindowID(of: app) }
        if let focused, windows[focused] == nil, let element = Self.focusedWindowElement(of: app) {
            windowAppeared(element, pid: app.processIdentifier)
        }
        setFocusedWindow(focused)
    }

    private func applicationTerminated(_ pid: pid_t) {
        retryTasks.removeValue(forKey: pid)?.cancel()
        inaccessibleApps.removeValue(forKey: pid)
        for (id, tracked) in windows where tracked.state.pid == pid {
            windowDisappeared(id)
        }
        apps.removeValue(forKey: pid)
        axClient?.removeAll(pid: pid)
        if activePID == pid {
            activePID = nil
        }
    }

    private func applicationActivated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let previous = activePID
        activePID = pid
        if apps[pid] == nil {
            watch(app, attempt: 0, announce: true)
        }
        for (id, tracked) in windows where tracked.state.pid == pid || tracked.state.pid == previous {
            update(id) { $0.isAppActive = $0.pid == pid }
        }
        syncFocusedWindow(of: app)
    }

    private func applicationHiddenChanged(_ pid: pid_t, hidden: Bool) {
        for (id, tracked) in windows where tracked.state.pid == pid {
            update(id) { $0.isAppHidden = hidden }
        }
        // An application unhidden by activating it has no focused window to read until it's shown
        if !hidden, pid == activePID, let app = apps[pid]?.app {
            syncFocusedWindow(of: app)
        }
    }

    // MARK: - Windows

    private func handle(_ notification: UIElement.AXNotification, element: UIElement, pid: pid_t) {
        switch notification.rawValue {
        case kAXWindowCreatedNotification:
            windowAppeared(element, pid: pid)
        case kAXFocusedWindowChangedNotification:
            guard pid == activePID else { return }
            if windowIDs[element] == nil {
                windowAppeared(element, pid: pid)
            }
            setFocusedWindow(windowIDs[element])
        default:
            // The hub delivers every notification of these types in this process, including
            // ones other clients registered for on other elements, so only tracked windows count
            guard let id = windowIDs[element] else { return }
            switch notification.rawValue {
            case kAXUIElementDestroyedNotification:
                windowDisappeared(id)
            case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
                refresh(id)
            default:
                settle(id)
            }
        }
    }

    /// Starts tracking a new window, and reports it (or with `announce` false, tracks a window
    /// that already existed, without reporting it). A window's ID isn't always available the
    /// moment it's created, so this retries a few times, as Hammerspoon 1 did.
    private func windowAppeared(_ element: UIElement, pid: pid_t, announce: Bool = true, attempt: Int = 0) {
        guard windowIDs[element] == nil, let app = apps[pid] else { return }
        guard (try? element.role()) == .window else { return }

        let id = Int(WindowEnumerator.windowID(of: element))
        guard id > 0 else {
            guard attempt < 5 else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                self?.windowAppeared(element, pid: pid, announce: announce, attempt: attempt + 1)
            }
            return
        }
        guard windows[id] == nil,
              let state = Self.readState(of: element, app: app.app, id: id, currentSpaces: Self.currentSpaceIDs(),
                                         focusedWindowID: focusedWindowID, activePID: activePID) else { return }

        let now = Date().timeIntervalSince1970
        guard announce else {
            // Older than any window created since, as for those found when starting up
            track(element, state: state, createdAt: now - 1_000_000 + Double(id) / 1000, focusedAt: state.hasFocus ? now : 0)
            if let tracked = windows[id] {
                deliver(Change(windowID: id, old: nil, new: state, events: [], window: makeWindow(tracked, app: app), isSilent: true))
            }
            return
        }
        track(element, state: state, createdAt: now, focusedAt: state.hasFocus ? now : 0)
        if let tracked = windows[id] {
            deliver(Change(windowID: id, old: nil, new: state, events: HSWindowFilterEvent.changes(from: nil, to: state), window: makeWindow(tracked, app: app)))
        }
    }

    /// Records a window and registers for its notifications, without reporting it
    private func track(_ element: UIElement, state: WindowState, createdAt: Double, focusedAt: Double) {
        guard let axClient else { return }
        for notification in Self.windowNotifications {
            do {
                try axClient.add(notification, element: element, pid: state.pid)
            } catch {
                AKDebug("WindowTracker: \(state.appName) window \(state.id) doesn't support \(notification.rawValue): \(error)")
            }
        }
        windows[state.id] = TrackedWindow(element: element, state: state, createdAt: createdAt, focusedAt: focusedAt)
        windowIDs[element] = state.id
    }

    private func windowDisappeared(_ id: Int) {
        guard let tracked = windows.removeValue(forKey: id) else { return }
        windowIDs.removeValue(forKey: tracked.element)
        settleTasks.removeValue(forKey: id)?.cancel()
        refreshRetries.removeValue(forKey: id)
        axClient?.removeAll(element: tracked.element)
        if focusedWindowID == id {
            focusedWindowID = nil
        }
        guard let app = apps[tracked.state.pid] else { return }
        deliver(Change(windowID: id, old: tracked.state, new: nil, events: HSWindowFilterEvent.changes(from: tracked.state, to: nil), window: makeWindow(tracked, app: app)))
    }

    /// Changes part of a window's state, and reports it
    private func update(_ id: Int, _ change: (inout WindowState) -> Void) {
        guard var tracked = windows[id], let app = apps[tracked.state.pid] else { return }
        let old = tracked.state
        change(&tracked.state)
        guard tracked.state != old else { return }
        if tracked.state.hasFocus && !old.hasFocus {
            tracked.focusedAt = Date().timeIntervalSince1970
        }
        windows[id] = tracked
        deliver(Change(windowID: id, old: old, new: tracked.state, events: HSWindowFilterEvent.changes(from: old, to: tracked.state), window: makeWindow(tracked, app: app)))
    }

    /// Reads a window's state again, and reports any change. A window whose element AX says is
    /// invalid has gone. One that just can't be read right now (e.g. its application is busy)
    /// keeps its last state, and is tried again a few times.
    private func refresh(_ id: Int, currentSpaces: Set<Int>? = nil) {
        settleTasks.removeValue(forKey: id)?.cancel()
        guard let tracked = windows[id], let app = apps[tracked.state.pid] else { return }
        guard let state = Self.readState(of: tracked.element, app: app.app, id: id, currentSpaces: currentSpaces ?? Self.currentSpaceIDs(),
                                         focusedWindowID: focusedWindowID, activePID: activePID) else {
            if Self.isGone(tracked.element) {
                windowDisappeared(id)
            } else if refreshRetries[id, default: 0] < Self.maxRefreshRetries {
                refreshRetries[id, default: 0] += 1
                settle(id)
            }
            return
        }
        refreshRetries.removeValue(forKey: id)
        update(id) { $0 = state }
    }

    /// How many times to try again to read a window that can't be read right now
    private static let maxRefreshRetries = 3

    /// Whether AX says a window's element no longer exists, rather than just failing to answer
    static func isGone(_ element: UIElement) -> Bool {
        do {
            _ = try element.role()
            return false
        } catch {
            return error == .invalidUIElement
        }
    }

    /// Refreshes a window once it has stopped moving, resizing or changing its title for a moment
    private func settle(_ id: Int) {
        settleTasks[id]?.cancel()
        settleTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.refresh(id)
        }
    }

    private func setFocusedWindow(_ id: Int?) {
        guard id != focusedWindowID else { return }
        let previous = focusedWindowID
        focusedWindowID = id
        if let previous {
            update(previous) { $0.isFocused = false }
        }
        if let id {
            update(id) { $0.isFocused = true }
        }
    }

    /// Refreshes every window shortly after the Space or the screens change, and picks up any
    /// windows the change revealed (e.g. on a Space visited for the first time)
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            self.refreshAll()
        }
    }

    private func refreshAll() {
        withShortTimeout {
            let spaces = Self.currentSpaceIDs()
            for id in Array(windows.keys) {
                refresh(id, currentSpaces: spaces)
            }
            for (pid, app) in apps {
                for element in WindowEnumerator.windowElements(for: app.app) where windowIDs[element] == nil {
                    windowAppeared(element, pid: pid)
                }
            }
        }
    }

    // MARK: - Reading state

    private func withShortTimeout<T>(_ body: () -> T) -> T {
        // Keeps a hung or slow application from stalling everything
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        defer { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0) }
        return body()
    }

    /// The IDs of the Spaces currently shown, or nil if Spaces are unavailable
    static func currentSpaceIDs() -> Set<Int>? {
        guard HSSkyLight.shared != nil else { return nil }
        return Set(HSSpaces.shared.currentSpaces().values.map { Int($0) })
    }

    static func focusedWindowElement(of app: NSRunningApplication) -> UIElement? {
        guard let axApp = Application(app) else { return nil }
        return try? axApp.attribute(.focusedWindow)
    }

    static func focusedWindowID(of app: NSRunningApplication) -> Int? {
        guard let element = focusedWindowElement(of: app) else { return nil }
        let id = Int(WindowEnumerator.windowID(of: element))
        return id > 0 ? id : nil
    }

    /// Reads everything about a window. Nil if it can't be read at all, e.g. because it's gone.
    static func readState(of element: UIElement, app: NSRunningApplication, id: Int, currentSpaces: Set<Int>?,
                          focusedWindowID: Int?, activePID: pid_t?) -> WindowState? {
        guard let role = try? element.role(), role == .window else { return nil }

        let frame: CGRect = (try? element.attribute(.frame)) ?? .zero
        let screen = HSWindow.screen(containing: frame)
        let isOnCurrentSpace: Bool
        if let currentSpaces {
            let spaces = HSSkyLight.shared?.spaces(forWindow: CGWindowID(id)) ?? []
            isOnCurrentSpace = spaces.contains { currentSpaces.contains(Int($0)) }
        } else {
            isOnCurrentSpace = true
        }
        let zoomButton: UIElement? = try? element.attribute(.zoomButton)

        return WindowState(
            id: id,
            pid: app.processIdentifier,
            appName: app.localizedName ?? "",
            bundleID: app.bundleIdentifier,
            title: (try? element.attribute(.title)) ?? "",
            subrole: try? element.attribute(.subrole),
            frame: frame,
            screenUUID: screen.map { HSScreen(screen: $0).uuid },
            screenName: screen?.localizedName,
            isMinimized: (try? element.attribute(.minimized)) ?? false,
            isAppHidden: app.isHidden,
            isFullscreen: (try? element.attribute(.fullScreen)) ?? false,
            hasTitlebar: zoomButton != nil,
            isOnCurrentSpace: isOnCurrentSpace,
            isFocused: id == focusedWindowID,
            isAppActive: app.processIdentifier == activePID
        )
    }

    // MARK: - One-off look

    /// Every window, read once. Used to start tracking, and by `entries()` when not tracking.
    ///
    /// Windows that exist before Hammerspoon starts watching have no real creation or focus times,
    /// so, as in Hammerspoon 1, they're given made-up ones older than any real one: creation order
    /// follows window IDs, and focus order follows the windows' order on screen, front to back.
    private struct SnapshotWindow {
        let element: UIElement
        let app: NSRunningApplication
        let state: WindowState
        let createdAt: Double
        let focusedAt: Double
    }

    private struct Snapshot {
        let apps: [NSRunningApplication]
        let tracked: [SnapshotWindow]
        let activePID: pid_t?
        let focusedWindowID: Int?

        @MainActor
        init() {
            let frontmost = NSWorkspace.shared.frontmostApplication
            activePID = frontmost?.processIdentifier
            focusedWindowID = frontmost.flatMap { WindowTracker.focusedWindowID(of: $0) }
            apps = NSWorkspace.shared.runningApplications.filter(WindowTracker.isCandidate)

            let now = Date().timeIntervalSince1970
            var zOrder: [Int: Int] = [:]
            for (index, window) in WindowNeighbours.onScreenWindowIDs().enumerated() where zOrder[Int(window.id)] == nil {
                zOrder[Int(window.id)] = index
            }

            let spaces = WindowTracker.currentSpaceIDs()
            let windowServerIDs = WindowEnumerator.windowServerWindowIDs()
            var windows: [SnapshotWindow] = []
            for app in apps {
                for element in WindowEnumerator.windowElements(for: app, windowServerIDs: windowServerIDs) {
                    let id = Int(WindowEnumerator.windowID(of: element))
                    guard id > 0,
                          let state = WindowTracker.readState(of: element, app: app, id: id, currentSpaces: spaces,
                                                              focusedWindowID: focusedWindowID, activePID: activePID) else { continue }
                    let createdAt = now - 1_000_000 + Double(id) / 1000
                    let focusedAt = state.isFocused ? now : now - 1 - Double(zOrder[id] ?? (100_000 + id))
                    windows.append(SnapshotWindow(element: element, app: app, state: state, createdAt: createdAt, focusedAt: focusedAt))
                }
            }
            tracked = windows
        }

        var entries: [Entry] {
            tracked.map { Entry(state: $0.state, window: HSWindow(element: $0.element, app: $0.app, id: $0.state.id), createdAt: $0.createdAt, focusedAt: $0.focusedAt) }
        }
    }
}
