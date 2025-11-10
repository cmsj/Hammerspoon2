//
//  AXObserverObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import ApplicationServices
import AXSwift

// MARK: - AX Observer API

/// Object representing an Accessibility observer that can watch for notifications on AX elements
@objc protocol HSAXObserverAPI: JSExport {
    /// Start the observer
    /// - Returns: The observer object for chaining
    @objc func start() -> HSAXObserver

    /// Stop the observer
    /// - Returns: The observer object for chaining
    @objc func stop() -> HSAXObserver

    /// Check if the observer is currently running
    /// - Returns: true if the observer is running, false otherwise
    @objc func isRunning() -> Bool

    /// Add a watcher for a specific notification on an element
    /// - Parameters:
    ///   - element: The AX element to watch
    ///   - notification: The notification name to watch for (e.g., "AXFocusedUIElementChanged")
    /// - Returns: The observer object for chaining
    @objc(addWatcher::) func addWatcher(_ element: HSAXElement, notification: String) -> HSAXObserver

    /// Remove a watcher for a specific notification on an element
    /// - Parameters:
    ///   - element: The AX element to stop watching
    ///   - notification: The notification name to stop watching for
    /// - Returns: The observer object for chaining
    @objc(removeWatcher::) func removeWatcher(_ element: HSAXElement, notification: String) -> HSAXObserver

    /// Get or set the callback function that will be invoked when notifications occur
    /// - Parameter callback: Optional callback function. If provided, sets the callback. If not, returns the current callback.
    /// - Returns: The observer object (when setting) or the current callback function (when getting)
    @objc func callback(_ callback: JSValue?) -> Any

    /// Get the process ID this observer is watching
    /// - Returns: The process ID
    @objc var pid: Int { get }
}

// MARK: - Observer Implementation

@_documentation(visibility: private)
@objc class HSAXObserver: NSObject, HSAXObserverAPI {
    private let observer: AXObserver
    private let _pid: pid_t
    private var callback: JSValue?
    private var running: Bool = false
    private var watchers: [String: Set<String>] = [:] // element hash -> set of notifications

    init?(pid: pid_t) {
        self._pid = pid
        var observerRef: AXObserver?

        let result = unsafe AXObserverCreate(self._pid, { (observer, element, notification, refcon) in
            // This is the callback from the accessibility system
            guard let refcon = unsafe refcon else { return }
            let observerObject = unsafe Unmanaged<HSAXObserver>.fromOpaque(refcon).takeUnretainedValue()
            observerObject.handleNotification(element: element, notification: notification as String)
        }, &observerRef)

        guard result == .success, let observerRef = observerRef else {
            AKError("hs.ax.observer: Failed to create observer for PID \(pid): \(result.rawValue)")
            return nil
        }

        self.observer = observerRef
        super.init()
    }

    deinit {
        // Note: Cannot call AKTrace or stop() from deinit due to actor isolation
        // The observer will be cleaned up automatically
        watchers.removeAll()
    }

    @objc func start() -> HSAXObserver {
        if running {
            AKTrace("hs.ax.observer.start(): Observer already running")
            return self
        }

        let runLoop = CFRunLoopGetMain()
        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(runLoop, runLoopSource, .defaultMode)
        running = true

        AKTrace("hs.ax.observer.start(): Started observer for PID \(_pid)")
        return self
    }

    @objc func stop() -> HSAXObserver {
        if !running {
            AKTrace("hs.ax.observer.stop(): Observer not running")
            return self
        }

        let runLoop = CFRunLoopGetMain()
        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopRemoveSource(runLoop, runLoopSource, .defaultMode)
        running = false

        AKTrace("hs.ax.observer.stop(): Stopped observer for PID \(_pid)")
        return self
    }

    @objc func isRunning() -> Bool {
        return running
    }

    @objc(addWatcher::) func addWatcher(_ element: HSAXElement, notification: String) -> HSAXObserver {
        let axElement = element.element.element
        let elementHash = String(describing: axElement)

        // Check if we're already watching this notification for this element
        if let notifications = watchers[elementHash], notifications.contains(notification) {
            AKTrace("hs.ax.observer.addWatcher(): Already watching \(notification) for element")
            return self
        }

        // Add the notification to the observer
        let result = unsafe AXObserverAddNotification(self.observer, axElement, notification as CFString,
                                               Unmanaged.passUnretained(self).toOpaque())

        if result == .success {
            if watchers[elementHash] == nil {
                watchers[elementHash] = Set<String>()
            }
            watchers[elementHash]?.insert(notification)
            AKTrace("hs.ax.observer.addWatcher(): Added watcher for \(notification)")
        } else {
            AKError("hs.ax.observer.addWatcher(): Failed to add watcher: \(result.rawValue)")
        }

        return self
    }

    @objc(removeWatcher::) func removeWatcher(_ element: HSAXElement, notification: String) -> HSAXObserver {
        let axElement = element.element.element
        let elementHash = String(describing: axElement)

        guard var notifications = watchers[elementHash], notifications.contains(notification) else {
            AKTrace("hs.ax.observer.removeWatcher(): Not watching \(notification) for element")
            return self
        }

        // Remove the notification from the observer
        let result = AXObserverRemoveNotification(observer, axElement, notification as CFString)

        if result == .success {
            notifications.remove(notification)
            if notifications.isEmpty {
                watchers.removeValue(forKey: elementHash)
            } else {
                watchers[elementHash] = notifications
            }
            AKTrace("hs.ax.observer.removeWatcher(): Removed watcher for \(notification)")
        } else {
            AKError("hs.ax.observer.removeWatcher(): Failed to remove watcher: \(result.rawValue)")
        }

        return self
    }

    @objc func callback(_ callback: JSValue?) -> Any {
        if let callback = callback {
            // Setter
            if !callback.isUndefined && !callback.isNull {
                self.callback = callback
            }
            return self
        } else {
            // Getter
            return self.callback ?? NSNull()
        }
    }

    @objc var pid: Int {
        return Int(_pid)
    }

    private func handleNotification(element: AXUIElement, notification: String) {
        guard let callback = self.callback else {
            AKTrace("hs.ax.observer: Received notification but no callback set")
            return
        }

        // Create an HSAXElement from the raw AXUIElement
        let wrappedElement = HSAXElement(element: UIElement(element))

        // Call the JavaScript callback with: observer, element, notification
        callback.call(withArguments: [self, wrappedElement, notification])
    }
}
