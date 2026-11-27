//
//  OwnWindowNotifier.swift
//  Hammerspoon 2
//

import AppKit
import ApplicationServices
import AXSwift

/// Posts the AX window notifications Hammerspoon's own windows would send, made from AppKit's
/// window notifications, for `AXObserverHub` to deliver.
///
/// AX won't observe the process it's asked from (`AXObserverAddNotification` refuses it), so
/// this is how window filters and `hs.ax` watchers hear about Hammerspoon's own windows. As AX
/// does, it reports a window that's ordered out (e.g. a hidden canvas) as destroyed, and one
/// that's ordered back in as created, since only windows on screen (or minimized) are among the
/// application's AX windows.
///
/// Each notification is posted asynchronously, as AX's would be, so e.g. showing a canvas from
/// JavaScript doesn't call back into JavaScript before `show()` has returned.
@_documentation(visibility: private)
@MainActor
final class OwnWindowNotifier {
    typealias Post = @MainActor (_ element: UIElement, _ notification: UIElement.AXNotification) -> Void

    /// The notifications it can post
    static let notifications: Set<UIElement.AXNotification> = Set([
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification,
    ].map { UIElement.AXNotification(rawValue: $0 as String) })

    private let post: Post
    private var observers: [any NSObjectProtocol] = []
    /// The AX element of each window it has reported as existing, by window number
    private var known: [Int: UIElement] = [:]
    /// Windows found not to be AX windows (e.g. menus, the status item's), until they go off screen
    private var notAXWindows: Set<Int> = []
    private var titleObservations: [Int: NSKeyValueObservation] = [:]

    init(post: @escaping Post) {
        self.post = post

        // Windows already on screen exist already: nothing is posted for them
        for window in NSApp.windows where Self.isListed(window) {
            if let element = Self.element(for: window) {
                remember(window, element: element)
            }
        }

        observe(NSWindow.didChangeOcclusionStateNotification) { $0.sync($1) }
        observe(NSWindow.willCloseNotification) { $0.forget($1) }
        observe(NSWindow.didMoveNotification) { $0.postForKnown($1, kAXWindowMovedNotification) }
        observe(NSWindow.didResizeNotification) { $0.postForKnown($1, kAXWindowResizedNotification) }
        observe(NSWindow.didMiniaturizeNotification) { $0.postForKnown($1, kAXWindowMiniaturizedNotification) }
        observe(NSWindow.didDeminiaturizeNotification) { notifier, number in
            notifier.sync(number)
            notifier.postForKnown(number, kAXWindowDeminiaturizedNotification)
        }
        observe(NSWindow.didBecomeKeyNotification) { notifier, number in
            notifier.sync(number)
            notifier.postForKnown(number, kAXFocusedWindowChangedNotification)
        }
    }

    /// Stops posting anything
    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        for observation in titleObservations.values {
            observation.invalidate()
        }
        titleObservations = [:]
        known = [:]
        notAXWindows = []
    }

    /// Calls `action` on the main queue, after the notification, with the window's number. Only
    /// the number crosses over: the window may be gone by then.
    private func observe(_ name: Notification.Name, _ action: @escaping @MainActor (OwnWindowNotifier, Int) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
            // AppKit posts window notifications on the main thread
            let window = notification.object as? NSWindow
            let number = MainActor.assumeIsolated { window?.windowNumber ?? 0 }
            guard number > 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.observers.isEmpty else { return }
                    action(self, number)
                }
            }
        })
    }

    /// Whether AX lists a window among the application's windows: it's on screen, or minimized
    private static func isListed(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized
    }

    /// A window's AX element, found among the application's AX windows. This is a request to
    /// Hammerspoon's own process, which is answered directly on the main thread.
    private static func element(for window: NSWindow) -> UIElement? {
        let app = UIElement(AXUIElementCreateApplication(AXSelfRequestGuard.ownProcessID))
        let windows: [UIElement] = (try? app.arrayAttribute(.windows)) ?? []
        return windows.first { Int(WindowEnumerator.windowID(of: $0)) == window.windowNumber }
    }

    private func remember(_ window: NSWindow, element: UIElement) {
        let number = window.windowNumber
        known[number] = element
        titleObservations[number] = window.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.postForKnown(number, kAXTitleChangedNotification)
                }
            }
        }
    }

    /// Reports a window as created if it has just appeared, or destroyed if it has just gone
    private func sync(_ number: Int) {
        guard let window = NSApp.window(withWindowNumber: number), Self.isListed(window) else {
            forget(number)
            return
        }
        guard known[number] == nil, !notAXWindows.contains(number) else { return }
        guard let element = Self.element(for: window) else {
            notAXWindows.insert(number)
            return
        }
        remember(window, element: element)
        post(element, UIElement.AXNotification(rawValue: kAXWindowCreatedNotification as String))
    }

    /// Reports a window as destroyed, if it was known
    private func forget(_ number: Int) {
        notAXWindows.remove(number)
        titleObservations.removeValue(forKey: number)?.invalidate()
        guard let element = known.removeValue(forKey: number) else { return }
        post(element, UIElement.AXNotification(rawValue: kAXUIElementDestroyedNotification as String))
    }

    private func postForKnown(_ number: Int, _ notification: String) {
        guard let element = known[number] else { return }
        post(element, UIElement.AXNotification(rawValue: notification))
    }
}
