//
//  HSMissionControl.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import ApplicationServices

/// Drives Mission Control's user interface through the Accessibility API.
///
/// Only the Dock may add, remove, or switch to managed spaces - SkyLight offers no function that
/// does any of those from another process in a way the Dock notices. So hs.spaces does what a
/// user would: opens Mission Control and presses the buttons in its Spaces bar.
///
/// None of this UI is documented. The tree below was observed on macOS 27, and matches what
/// Hammerspoon 1 relied on in earlier versions, apart from which process owns it:
///
/// ```
/// WindowManager (macOS 27+) / Dock "mc" group (earlier)
///   mc.display (AXDisplayID = CGDirectDisplayID)   one per display
///     mc.spaces                                    the Spaces bar
///       mc.spaces.list                             one button per space, in Mission Control order;
///                                                  AXPress switches to it, AXRemoveDesktop removes it
///       mc.spaces.add                              the "add desktop" button
/// ```
@_documentation(visibility: private)
enum HSMissionControl {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let appURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private static let ownerBundleIDs = ["com.apple.WindowManager", "com.apple.dock"]

    /// How long to wait for Mission Control or SkyLight to catch up with a request
    static let timeout: Duration = .seconds(3)
    private static let pollInterval: Duration = .milliseconds(50)

    private static let pressAction = kAXPressAction as String
    static let removeDesktopAction = "AXRemoveDesktop"

    // MARK: - Opening and closing

    /// Whether Mission Control is currently showing
    static var isOpen: Bool {
        !displayGroups().isEmpty
    }

    /// Shows Mission Control, waiting until its UI is available
    static func open() async throws {
        guard !isOpen else { return }
        toggle()
        try await waitUntil("Mission Control did not open") { isOpen }
    }

    /// Hides Mission Control, waiting until it has gone
    static func close() async throws {
        guard isOpen else { return }
        toggle()
        try await waitUntil("Mission Control did not close") { !isOpen }
    }

    /// Launching Mission Control.app toggles Mission Control, exactly like its keyboard shortcut
    private static func toggle() {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Finding the Spaces bar

    /// The Spaces bar parts for one display
    struct SpacesBar {
        let spaceButtons: [AXUIElement]
        let addButton: AXUIElement?
    }

    /// The Spaces bar for a display, once Mission Control is open and its desktop list has caught
    /// up with SkyLight's `expectedCount` spaces for that display. When all displays share one set
    /// of spaces there may not be a bar for the requested display, so any bar is used instead.
    static func spacesBar(for displayID: CGDirectDisplayID, expectedCount: Int) async throws -> SpacesBar {
        var bar: SpacesBar?
        try await waitUntil("Mission Control's desktop list for display \(displayID) did not appear") {
            let groups = displayGroups()
            let group = groups.first { (attribute($0, "AXDisplayID") as? NSNumber)?.uint32Value == displayID } ?? groups.first
            guard let group, let found = spacesBar(in: group), found.spaceButtons.count == expectedCount else { return false }
            bar = found
            return true
        }
        guard let bar else { throw Failure("Mission Control's desktop list for display \(displayID) did not appear") }
        return bar
    }

    private static func spacesBar(in displayGroup: AXUIElement) -> SpacesBar? {
        guard let spaces = children(of: displayGroup).first(where: { identifier(of: $0) == "mc.spaces" }) else { return nil }
        let parts = children(of: spaces)
        guard let list = parts.first(where: { identifier(of: $0) == "mc.spaces.list" }) else { return nil }
        return SpacesBar(spaceButtons: children(of: list),
                         addButton: parts.first { identifier(of: $0) == "mc.spaces.add" })
    }

    /// Every "mc.display" element, from whichever process owns Mission Control's UI
    private static func displayGroups() -> [AXUIElement] {
        for bundleID in ownerBundleIDs {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            var groups: [AXUIElement] = []
            for child in children(of: AXUIElementCreateApplication(app.processIdentifier)) {
                switch identifier(of: child) {
                case "mc.display": groups.append(child)
                case "mc": groups += children(of: child).filter { identifier(of: $0) == "mc.display" }
                default: break
                }
            }
            if !groups.isEmpty { return groups }
        }
        return []
    }

    // MARK: - Actions

    static func press(_ element: AXUIElement) throws {
        try perform(pressAction, on: element)
    }

    static func perform(_ action: String, on element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, action as CFString)
        guard result == .success else {
            throw Failure("Mission Control refused \(action) (AXError \(result.rawValue))")
        }
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard unsafe AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    // MARK: - Helpers

    /// Polls `condition` until it's true, throwing `message` if that takes longer than `timeout`
    static func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(message) }
            try await Task.sleep(for: pollInterval)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard unsafe AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func identifier(of element: AXUIElement) -> String? {
        attribute(element, kAXIdentifierAttribute) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
