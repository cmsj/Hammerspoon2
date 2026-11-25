//
//  DistributedNotificationObserver.swift
//  Hammerspoon 2
//

import Foundation

/// Observes a distributed notification, calling a closure on the main thread as soon as it's posted,
/// even while Hammerspoon 2 isn't the active app.
///
/// AppKit suspends distributed notification delivery while an app is inactive, which Hammerspoon 2
/// almost always is. Observers added with `addObserver(forName:object:queue:using:)` get the default
/// `.coalesce` suspension behaviour, so a system event such as an input source change can be held
/// back until the next one arrives or the user brings Hammerspoon 2 to the front.
/// Asking for `.deliverImmediately` needs the selector-based API, which this wraps.
///
/// Observing stops when this object is released.
final class DistributedNotificationObserver: NSObject {
    private let handler: () -> Void

    init(name: Notification.Name, handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(didReceive(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // Distributed notifications are delivered on the main thread.
    @objc private func didReceive(_ notification: Notification) {
        handler()
    }
}
