//
//  WindowEnumerator.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import AppKit
import AXSwift

// Private API: creates an AXUIElement for a given element ID in another process. Used (as in
// alt-tab-macos) to reach windows that an app's AXWindows attribute doesn't report.
private let _AXUIElementCreateWithRemoteToken = unsafe unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementCreateWithRemoteToken"), to: (@convention(c) (CFData) -> Unmanaged<AXUIElement>?)?.self)

// Private SkyLight API: the Spaces a set of windows is on. Used to ignore windows that exist in the
// WindowServer but aren't on any Space (ordered-out helper windows, closed-but-retained windows).
private let CGSMainConnectionID = unsafe unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID"), to: (@convention(c) () -> Int32)?.self)
private let CGSCopySpacesForWindows = unsafe unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "CGSCopySpacesForWindows"), to: (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?)?.self)
private let kCGSAllSpacesMask: Int32 = 0x7

/// Finds an application's windows across all Spaces.
///
/// An app's `AXWindows` attribute only lists windows on the currently visible Space(s), so a
/// window in native fullscreen (which lives on its own Space), or on another Space, is missing
/// from it. To fill the gap this:
///
/// 1. Starts with `AXWindows`.
/// 2. Adds `AXMainWindow` and `AXFocusedWindow`, which the app reports regardless of Space.
/// 3. Asks the WindowServer (`CGWindowListCopyWindowInfo`, which isn't limited to the current
///    Space) for the app's off-screen, normal-layer windows. Any that are still missing are
///    looked up among the window elements found by earlier calls, and if any that are on a Space
///    are still missing after that, the app's AX element IDs are probed for them with
///    `_AXUIElementCreateWithRemoteToken`.
///
/// The probe in step 3 only runs when the WindowServer reports a window that nothing else
/// found. It can only find windows whose AX element the app has already handed to some
/// accessibility client, e.g. because they were looked at while their Space was visible, and
/// only up to `maxProbedElementID`; windows that have never been looked at stay hidden until
/// their Space is visited. Window IDs a complete probe couldn't find are remembered, so they
/// don't trigger it again, until they turn up some other way.
enum WindowEnumerator {
    /// The highest AX element ID probed when looking for missing windows
    private static let maxProbedElementID: UInt64 = 2000

    /// How long the probe may spend on a single application
    private static let probeTimeBudget: TimeInterval = 0.25

    /// Window IDs, per PID, that the probe has already failed to find
    private static var unresolvableWindowIDs: [pid_t: Set<CGWindowID>] = [:]

    /// Every window element found so far, per PID and window ID, so a window stays reachable after
    /// it leaves the visible Space(s), wherever the probe would (or wouldn't) find it
    private static var knownWindows: [pid_t: [CGWindowID: UIElement]] = [:]

    /// The IDs of off-screen, normal-layer windows the WindowServer knows about, across all Spaces,
    /// grouped by owning PID. Windows on the visible Space(s) are left out: `AXWindows` reports those.
    static func windowServerWindowIDs() -> [pid_t: Set<CGWindowID>] {
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [pid_t: Set<CGWindowID>] = [:]
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  (window[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 1, bounds.height > 1 else {
                continue
            }
            result[pid, default: []].insert(id)
        }

        // Forget about processes that have gone away
        unresolvableWindowIDs = unresolvableWindowIDs.filter { result[$0.key] != nil }
        knownWindows = knownWindows.filter { NSRunningApplication(processIdentifier: $0.key) != nil }

        return result
    }

    /// All of an application's windows, including those on other Spaces and in native fullscreen.
    /// - Parameters:
    ///   - app: The application
    ///   - windowServerIDs: The result of `windowServerWindowIDs()`, if the caller has already fetched it
    static func windowElements(for app: NSRunningApplication, windowServerIDs: [pid_t: Set<CGWindowID>]? = nil) -> [UIElement] {
        guard let axApp = Application(app) else {
            return []
        }

        var windows: [UIElement] = []
        var found: [CGWindowID: UIElement] = [:]
        var foundIDs: Set<CGWindowID> { Set(found.keys) }

        func add(_ element: UIElement) {
            let id = windowID(of: element)
            if id != 0 {
                guard found[id] == nil else { return }
                found[id] = element
            } else if windows.contains(where: { CFEqual($0.element, element.element) }) {
                return
            }
            windows.append(element)
        }

        do {
            (try axApp.windows() ?? []).forEach(add)
        } catch {
            AKDebug("Failed to get windows for \(app.localizedName ?? "unknown"): \(error.localizedDescription)")
        }

        for attribute in [Attribute.mainWindow, Attribute.focusedWindow] {
            if let element: UIElement = try? axApp.attribute(attribute),
               (try? element.role()) == .window {
                add(element)
            }
        }

        let pid = app.processIdentifier
        let serverIDs = (windowServerIDs ?? windowServerWindowIDs())[pid] ?? []

        // Windows found before, which are still around but weren't reported this time. Elements of
        // windows that have since closed are invalid, and report no window ID; windows that have
        // been ordered out but kept alive are on no Space.
        for (id, element) in knownWindows[pid] ?? [:] where serverIDs.contains(id) && found[id] == nil {
            if windowID(of: element) == id, isOnAnySpace(id) {
                add(element)
            }
        }

        // Windows that turned up after all (e.g. their Space was visited) no longer count as unresolvable
        unresolvableWindowIDs[pid]?.subtract(foundIDs)
        let missing = serverIDs.subtracting(foundIDs).subtracting(unresolvableWindowIDs[pid] ?? []).filter(isOnAnySpace)
        if !missing.isEmpty {
            let (probed, completed) = probeWindows(pid: pid, ids: missing)
            probed.forEach(add)
            // Only remember windows a complete scan couldn't find, so a scan that ran out of
            // time (e.g. because the app was busy) gets another chance next time.
            if completed {
                let unresolved = missing.subtracting(probed.map { windowID(of: $0) })
                unresolvableWindowIDs[pid, default: []].formUnion(unresolved)
            }
        }

        // Remember what was found, and forget windows that have closed
        knownWindows[pid] = found

        return windows
    }

    /// The window ID of an AX window element, or 0 if it can't be determined
    static func windowID(of element: UIElement) -> CGWindowID {
        var id: CGWindowID = 0
        if let _AXUIElementGetWindow = unsafe _AXUIElementGetWindow {
            _ = unsafe _AXUIElementGetWindow(element.element, &id)
        }
        return id
    }

    /// Whether the WindowServer has the window on any Space
    private static func isOnAnySpace(_ id: CGWindowID) -> Bool {
        guard let mainConnectionID = unsafe CGSMainConnectionID,
              let copySpacesForWindows = unsafe CGSCopySpacesForWindows else {
            return true
        }
        guard let spaces = unsafe copySpacesForWindows(mainConnectionID(), kCGSAllSpacesMask, [id] as CFArray)?.takeRetainedValue() else {
            return false
        }
        return CFArrayGetCount(spaces) > 0
    }

    /// Walks a process's AX element IDs looking for window elements with the given window IDs.
    ///
    /// An AX remote token is 20 bytes: the PID (4), zero (4), the magic "coco" (4) and the element ID (8).
    /// - Returns: The window elements found, and whether the scan finished (rather than running out of time)
    private static func probeWindows(pid: pid_t, ids: Set<CGWindowID>) -> (found: [UIElement], completed: Bool) {
        guard let createWithRemoteToken = unsafe _AXUIElementCreateWithRemoteToken else {
            return ([], false)
        }

        var token = Data(count: 20)
        unsafe token.withUnsafeMutableBytes { bytes in
            unsafe bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            unsafe bytes.storeBytes(of: 0, toByteOffset: 4, as: Int32.self)
            unsafe bytes.storeBytes(of: 0x636f636f, toByteOffset: 8, as: Int32.self)
        }

        var found: [UIElement] = []
        var remaining = ids
        let deadline = Date().addingTimeInterval(probeTimeBudget)

        for elementID in 0..<maxProbedElementID {
            unsafe token.withUnsafeMutableBytes { bytes in
                unsafe bytes.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
            }
            if let axElement = unsafe createWithRemoteToken(token as CFData)?.takeRetainedValue() {
                let element = UIElement(axElement)
                let id = windowID(of: element)
                if id != 0, remaining.contains(id), (try? element.role()) == .window {
                    remaining.remove(id)
                    found.append(element)
                    if remaining.isEmpty { return (found, true) }
                }
            }
            if Date() > deadline {
                AKDebug("hs.window: gave up looking for \(remaining.count) window(s) of PID \(pid) after \(elementID) elements")
                return (found, false)
            }
        }

        return (found, true)
    }
}
