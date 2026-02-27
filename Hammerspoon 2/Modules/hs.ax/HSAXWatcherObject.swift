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
    let callback: JSValue

    init(element: UIElement, notification: UIElement.AXNotification, callback: JSValue) {
        self.element = element
        self.notification = notification
        self.callback = callback
    }

    /// Handle the notification event by calling the JavaScript callback
    func handleEvent(element: HSAXElement, notification: String) {
        callback.call(withArguments: [notification, element])
    }
}
