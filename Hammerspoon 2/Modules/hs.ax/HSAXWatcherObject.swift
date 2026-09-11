//
//  AXObserverObject.swift
//  Hammerspoon 2
//
//  Created by Claude Code
//

import Foundation
import JavaScriptCore
import AXSwift

/// Watcher object that holds the element, notification, and callback for a specific watch
class HSAXWatcherObject {
    let element: UIElement
    let notification: UIElement.AXNotification
    let callback: JSFunction

    /// True if `element` is an application element. AX bubbles some notifications (e.g.
    /// AXWindowCreated) to application-level observers with the actual originating
    /// descendant element, not the application element itself, so this is used to match
    /// those notifications by PID rather than requiring an exact element match.
    let isApplicationElement: Bool

    init(element: UIElement, notification: UIElement.AXNotification, callback: JSFunction, isApplicationElement: Bool) {
        self.element = element
        self.notification = notification
        self.callback = callback
        self.isApplicationElement = isApplicationElement
    }

    /// Handle the notification event by calling the JavaScript callback
    func handleEvent(element: HSAXElement, notification: String) {
        callback.call(withArguments: [notification, element])
    }
}
