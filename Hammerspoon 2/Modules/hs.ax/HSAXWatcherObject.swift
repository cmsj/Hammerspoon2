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
    // Owned by the module: this object isn't JS-exported, so it has no wrapper to keep a
    // callback alive, while the module's wrapper is pinned by ModuleRoot
    private let callback: JSCallback?
    private weak var owner: AnyObject?

    /// True if `element` is an application element. AX bubbles some notifications (e.g.
    /// AXWindowCreated) to application-level observers with the actual originating
    /// descendant element, not the application element itself, so this is used to match
    /// those notifications by PID rather than requiring an exact element match.
    let isApplicationElement: Bool

    init(element: UIElement, notification: UIElement.AXNotification, callback: JSFunction, owner: AnyObject, isApplicationElement: Bool) {
        self.element = element
        self.notification = notification
        self.callback = JSCallback(value: callback, owner: owner)
        self.owner = owner
        self.isApplicationElement = isApplicationElement
    }

    isolated deinit {
        if let owner { callback?.detach(from: owner) }
    }

    /// Handle the notification event by calling the JavaScript callback
    func handleEvent(element: HSAXElement, notification: String) {
        _ = callback?.call(withArguments: [notification, element])
    }
}
