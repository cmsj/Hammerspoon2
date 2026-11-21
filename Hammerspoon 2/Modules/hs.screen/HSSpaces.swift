//
//  HSSpaces.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import JavaScriptCore

/// Everything Hammerspoon does with Spaces, shared by HSScreen, HSWindow and HSSpace and their
/// modules.
///
/// Spaces aren't a module of their own: JS reaches them through screens (`screen.spaces`) and
/// windows (`window.spaces`), which it can get without loading any particular module. So this is
/// one process-wide service rather than module state. That suits Mission Control anyway: there's
/// only one, so operations from every engine must queue behind each other. Each operation
/// remembers the JSContext that started it, so shutting an engine down can cancel its own - see
/// `cancelOperations(in:)`.
@_documentation(visibility: private)
@MainActor
final class HSSpaces {
    static let shared = HSSpaces()

    @safe private struct Operation {
        let contextRef: JSGlobalContextRef
        let task: Task<Void, Never>
    }

    /// Operations in flight, so cancelOperations(in:) can cancel them
    private var operations: [UUID: Operation] = [:]
    /// The most recent Mission Control operation. Each one waits for the previous one to finish,
    /// since they'd otherwise fight over opening and closing Mission Control.
    private var lastMissionControlTask: Task<Void, Never>?

    private init() {}

    static let unavailableReason = "Spaces are unavailable on this version of macOS"

    // MARK: - Displays and spaces

    /// The UUID of the screen a managed display identifier refers to. When displays share
    /// spaces, SkyLight reports them all as one display called "Main" - attribute that to the
    /// primary screen.
    static func screenUUID(forDisplayIdentifier identifier: String) -> String {
        if identifier == HSSkyLight.sharedSpacesDisplayIdentifier, let primary = NSScreen.screens.first {
            return HSScreen(screen: primary).uuid
        }
        return identifier
    }

    /// The screen a managed display identifier refers to, if it's connected
    static func screen(forDisplayIdentifier identifier: String) -> HSScreen? {
        let uuid = screenUUID(forDisplayIdentifier: identifier)
        return NSScreen.screens.lazy.map { HSScreen(screen: $0) }.first { $0.uuid == uuid }
    }

    func managedDisplay(withIdentifier identifier: String) -> HSSkyLight.ManagedDisplay? {
        HSSkyLight.shared?.managedDisplays().first { $0.identifier == identifier }
    }

    /// The managed display holding a screen's spaces. When displays share spaces, every screen
    /// shows the one shared display's spaces.
    func managedDisplay(forScreenUUID uuid: String) -> HSSkyLight.ManagedDisplay? {
        let displays = HSSkyLight.shared?.managedDisplays() ?? []
        return displays.first { $0.identifier == uuid }
            ?? displays.first { $0.identifier == HSSkyLight.sharedSpacesDisplayIdentifier }
    }

    /// Every space on every display, display by display, each in Mission Control's order
    func allSpaces() -> [HSSpace] {
        (HSSkyLight.shared?.managedDisplays() ?? []).flatMap(\.spaces).map { HSSpace(id: $0.id) }
    }

    /// A space and the display it's on, if it exists. SkyLight happily answers questions about
    /// made-up space IDs, so everything is checked against the list of managed displays first.
    func locate(_ spaceID: HSSkyLight.SpaceID) -> (space: HSSkyLight.Space, display: HSSkyLight.ManagedDisplay)? {
        for display in HSSkyLight.shared?.managedDisplays() ?? [] {
            if let space = display.spaces.first(where: { $0.id == spaceID }) {
                return (space, display)
            }
        }
        return nil
    }

    /// The space with `id`, if it exists
    func space(withID id: Int) -> HSSpace? {
        guard let spaceID = HSSkyLight.SpaceID(exactly: id), locate(spaceID) != nil else { return nil }
        return HSSpace(id: spaceID)
    }

    /// Mission Control's "Desktop N" number for a desktop. It numbers desktops (not fullscreen
    /// spaces) from 1, carrying on from one display to the next in SkyLight's display order.
    func desktopNumber(of spaceID: HSSkyLight.SpaceID) -> Int? {
        let desktops = (HSSkyLight.shared?.managedDisplays() ?? [])
            .flatMap(\.spaces)
            .filter { $0.kind == .desktop }
        return desktops.firstIndex { $0.id == spaceID }.map { $0 + 1 }
    }

    /// Each managed display's current space, by identifier
    func currentSpaces() -> [String: HSSkyLight.SpaceID] {
        var result: [String: HSSkyLight.SpaceID] = [:]
        for display in HSSkyLight.shared?.managedDisplays() ?? [] {
            result[display.identifier] = display.currentSpace
        }
        return result
    }

    // MARK: - Windows

    /// The IDs of the ordinary windows on a space, front to back
    func windowIDs(onSpace spaceID: HSSkyLight.SpaceID) -> [Int] {
        guard let skyLight = HSSkyLight.shared, locate(spaceID) != nil else { return [] }

        // SkyLight lists every window on the space, including menus, the menu bar, panels, etc.
        // Keep only those in the normal window layer, which is what users mean by "windows".
        let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let normalWindows = Set(info.compactMap { window -> CGWindowID? in
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })

        return skyLight.windows(onSpace: spaceID)
            .filter { normalWindows.contains($0) }
            .map { Int($0) }
    }

    /// The spaces a window is on
    func spaces(forWindowID windowID: Int) -> [HSSpace] {
        guard let skyLight = HSSkyLight.shared, let id = CGWindowID(exactly: windowID), id != 0 else { return [] }
        return skyLight.spaces(forWindow: id).filter { locate($0) != nil }.map { HSSpace(id: $0) }
    }

    /// Moves a window to a space, without Mission Control. `name` is the JS function, for errors.
    func moveWindow(_ windowID: Int, toSpace space: HSSpace, function name: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let spaceID = space.spaceID
        func reject(_ reason: String) -> JSPromise? {
            context.createRejectedPromise(with: "\(name): \(reason)")
        }

        guard let skyLight = HSSkyLight.shared else { return reject(Self.unavailableReason) }
        guard let (target, _) = locate(spaceID) else { return reject("space \(spaceID) no longer exists") }
        guard target.kind == .desktop else { return reject("windows can only be moved to a desktop, not a fullscreen space") }
        guard let window = CGWindowID(exactly: windowID), window != 0 else { return reject("no such window: \(windowID)") }

        let sources = skyLight.spaces(forWindow: window)
        guard !sources.isEmpty else { return reject("window \(windowID) isn't on any space") }
        guard sources.count == 1 else { return reject("window \(windowID) appears on every space, so it can't be moved") }
        guard locate(sources[0])?.space.kind == .desktop else {
            return reject("window \(windowID) is in a fullscreen space, so it can't be moved")
        }
        if sources == [spaceID] {
            return context.createResolvedPromise(with: JSValue(undefinedIn: context))
        }

        guard skyLight.moveWindows([window], toSpace: spaceID) else {
            return reject("moving windows between spaces is unavailable on this version of macOS")
        }

        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            self.track(in: context) {
                do {
                    try await HSMissionControl.waitUntil("macOS did not move window \(windowID) to space \(spaceID)") {
                        skyLight.spaces(forWindow: window) == [spaceID]
                    }
                    holder.resolveWith(JSValue(undefinedIn: context))
                } catch is CancellationError {
                    // The engine is shutting down - the Promise's context is going away with it
                } catch {
                    AKWarning("\(name): \(error.localizedDescription)")
                    holder.rejectWithMessage("\(name): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Operations

    /// Runs `body` in a Task, after `previous` (if any) has finished, that cancelOperations(in:)
    /// can cancel
    @discardableResult
    private func track(in context: JSContext,
                       after previous: Task<Void, Never>? = nil,
                       _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await body()
            self?.operations[id] = nil
        }
        operations[id] = unsafe Operation(contextRef: context.jsGlobalContextRef, task: task)
        return task
    }

    /// Cancels every operation started from `context`, whose engine is shutting down: their
    /// Promises' context is going away, so there's nothing left to settle them for. Each one
    /// still gets to close Mission Control if it opened it.
    func cancelOperations(in context: JSContext) {
        for (id, operation) in operations where unsafe operation.contextRef == context.jsGlobalContextRef {
            operation.task.cancel()
            operations[id] = nil
        }
    }

    // MARK: - Mission Control

    func gotoSpace(_ spaceID: HSSkyLight.SpaceID) -> JSPromise? {
        runInMissionControl("HSSpace.goto()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure(Self.unavailableReason) }
            let display = try self.display(holding: spaceID)
            guard display.currentSpace != spaceID else { return nil }

            guard let index = display.spaceIDs.firstIndex(of: spaceID) else { throw HSMissionControl.Failure("space \(spaceID) no longer exists") }
            let bar = try await self.openSpacesBar(for: display)
            try HSMissionControl.press(bar.spaceButtons[index])

            // Clicking a space closes Mission Control. Wait for it to finish animating away too, so
            // nothing toggles Mission Control again mid-animation.
            try await HSMissionControl.waitUntil("macOS did not switch to space \(spaceID)") {
                self.managedDisplay(withIdentifier: display.identifier)?.currentSpace == spaceID
                    && HSMissionControl.isClosed
            }
            return nil
        }
    }

    func addSpace(toScreenUUID uuid: String) -> JSPromise? {
        runInMissionControl("HSScreen.addSpace()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure(Self.unavailableReason) }
            guard let display = self.managedDisplay(forScreenUUID: uuid) else {
                throw HSMissionControl.Failure("macOS has no spaces for screen \(uuid)")
            }

            let bar = try await self.openSpacesBar(for: display)
            guard let addButton = bar.addButton else { throw HSMissionControl.Failure("Mission Control has no add desktop button") }
            try HSMissionControl.press(addButton)

            let existing = Set(display.spaceIDs)
            var added: HSSkyLight.SpaceID?
            try await HSMissionControl.waitUntil("macOS did not add a desktop") {
                added = self.managedDisplay(withIdentifier: display.identifier)?.spaceIDs.first { !existing.contains($0) }
                return added != nil
            }
            return added.map { HSSpace(id: $0) }
        }
    }

    func removeSpace(_ spaceID: HSSkyLight.SpaceID) -> JSPromise? {
        runInMissionControl("HSSpace.remove()") { [weak self] in
            guard let self else { throw HSMissionControl.Failure(Self.unavailableReason) }
            let display = try self.display(holding: spaceID)
            let desktops = display.spaces.filter { $0.kind == .desktop }.map(\.id)
            guard desktops.contains(spaceID) else { throw HSMissionControl.Failure("space \(spaceID) is not a desktop") }
            guard desktops.count > 1 else { throw HSMissionControl.Failure("space \(spaceID) is the only desktop on its display") }
            guard display.currentSpace != spaceID else {
                throw HSMissionControl.Failure("space \(spaceID) is the one its display is showing")
            }

            guard let index = display.spaceIDs.firstIndex(of: spaceID),
                  let desktopIndex = desktops.firstIndex(of: spaceID) else { throw HSMissionControl.Failure("space \(spaceID) no longer exists") }
            let bar = try await self.openSpacesBar(for: display)
            let button = bar.spaceButtons[index]
            // Removing is destructive, so double check this really is the right button: Mission
            // Control titles desktops "Desktop N". Accept either numbering across all displays
            // (desktopNumber's rule) or within this display, in case Mission Control's differs.
            let expectedNumbers = Set([desktopIndex + 1, self.desktopNumber(of: spaceID) ?? 0])
            if let number = HSMissionControl.desktopNumber(of: button), !expectedNumbers.contains(number) {
                throw HSMissionControl.Failure("Mission Control's desktop \(number) doesn't look like space \(spaceID); not removing it")
            }
            guard HSMissionControl.actions(of: button).contains(HSMissionControl.removeDesktopAction) else {
                throw HSMissionControl.Failure("Mission Control won't remove space \(spaceID)")
            }
            try HSMissionControl.perform(HSMissionControl.removeDesktopAction, on: button)

            try await HSMissionControl.waitUntil("macOS did not remove space \(spaceID)") {
                self.locate(spaceID) == nil
            }
            return nil
        }
    }

    func missionControlNames() -> JSPromise? {
        runInMissionControl("hs.screen.missionControlNames()") { [weak self] in
            guard let self, let skyLight = HSSkyLight.shared else { throw HSMissionControl.Failure(Self.unavailableReason) }
            try await HSMissionControl.open()

            var names: [String: String] = [:]
            for display in skyLight.managedDisplays() {
                let bar = try await self.spacesBar(for: display)
                for (space, button) in zip(display.spaceIDs, bar.spaceButtons) {
                    names[String(space)] = HSMissionControl.name(of: button)
                }
            }
            return names
        }
    }

    func openMissionControl() -> JSPromise? {
        runInMissionControl("hs.screen.openMissionControl()", leaveOpen: true) {
            try await HSMissionControl.open()
            return nil
        }
    }

    func closeMissionControl() -> JSPromise? {
        runInMissionControl("hs.screen.closeMissionControl()") {
            try await HSMissionControl.close()
            return nil
        }
    }

    /// Runs `operation` once any earlier Mission Control operation has finished, settling the
    /// returned Promise with its result. Failures reject with "<name>: <reason>". Whether it
    /// succeeds or not, Mission Control is closed afterwards unless it was already open or
    /// `leaveOpen` is set (switching spaces closes it regardless, as clicking a space always does).
    private func runInMissionControl(_ name: String,
                                     leaveOpen: Bool = false,
                                     _ operation: @escaping @MainActor () async throws -> Any?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        guard HSSkyLight.shared != nil else {
            return context.createRejectedPromise(with: "\(name): \(Self.unavailableReason)")
        }
        guard AXIsProcessTrusted() else {
            return context.createRejectedPromise(with: "\(name): Accessibility permission is required")
        }

        return wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            self.lastMissionControlTask = self.track(in: context, after: self.lastMissionControlTask) {
                let result: Result<Any?, any Error>
                // Stays nil if the task was cancelled (or never settled) before reading the state,
                // in which case Mission Control is left alone
                var wasOpen: Bool?
                do {
                    try Task.checkCancellation()
                    // Let any opening/closing animation finish first, or it's unclear which it'll end up as
                    try await HSMissionControl.waitUntilSettled()
                    wasOpen = HSMissionControl.isOpen
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                if wasOpen == false && !leaveOpen {
                    // In a Task of its own, because this one may have been cancelled by an engine
                    // shutdown part way through opening Mission Control, which would make every wait
                    // in close() throw straight away and leave Mission Control open. It's awaited, so
                    // the next queued operation still starts only once Mission Control has closed.
                    await Task { @MainActor in
                        do {
                            try await HSMissionControl.close()
                        } catch {
                            AKWarning("\(name): \(error.localizedDescription)")
                        }
                    }.value
                }

                switch result {
                case .success(let value):
                    // A nil result would reach JS as null - Promise<void> should give undefined
                    holder.resolveWith(value ?? JSValue(undefinedIn: context))
                case .failure(is CancellationError):
                    // The engine is shutting down - the Promise's context is going away with it
                    break
                case .failure(let error):
                    AKWarning("\(name): \(error.localizedDescription)")
                    holder.rejectWithMessage("\(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// The managed display holding `spaceID`
    private func display(holding spaceID: HSSkyLight.SpaceID) throws -> HSSkyLight.ManagedDisplay {
        guard let display = locate(spaceID)?.display else {
            throw HSMissionControl.Failure("space \(spaceID) no longer exists")
        }
        return display
    }

    /// Opens Mission Control and finds the Spaces bar for `display`
    private func openSpacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        try await HSMissionControl.open()
        return try await spacesBar(for: display)
    }

    /// The Spaces bar for `display`, once Mission Control is open
    private func spacesBar(for display: HSSkyLight.ManagedDisplay) async throws -> HSMissionControl.SpacesBar {
        guard let screen = Self.screen(forDisplayIdentifier: display.identifier) else {
            throw HSMissionControl.Failure("no screen for display \(display.identifier)")
        }
        return try await HSMissionControl.spacesBar(for: screen.displayID, expectedCount: display.spaces.count)
    }
}
