//
//  HSDistributedNotificationsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Module for receiving and posting macOS distributed notifications.
///
/// Distributed notifications are broadcast between processes through
/// `NSDistributedNotificationCenter`. Many applications announce their changes this way: for
/// example, Music posts `com.apple.Music.playerInfo` whenever its player changes state, with
/// details such as `Player State`, `Name` and `Artist` in the notification's `userInfo`.
///
/// Notifications are delivered as soon as they're posted, even while Hammerspoon 2 is in the
/// background.
///
/// - Note: macOS only delivers notifications to observers that name the notification they want,
///   so there is no way to listen for every distributed notification.
@objc protocol HSDistributedNotificationsModuleAPI: JSExport {

    /// Post a distributed notification, for other applications to receive.
    ///
    /// The notification is delivered immediately, even to applications that are in the
    /// background.
    /// - Parameters:
    ///   - name: The name of the notification, e.g. `"com.example.myapp.somethingHappened"`
    ///   - object?: An optional string identifying the sender, which observers receive as the
    ///     notification's `object`
    ///   - userInfo?: An optional object of extra information. Its values must be property list
    ///     types: strings, numbers, booleans, Dates, arrays or objects of those types
    /// - Returns: true if the notification was posted, false if the name was empty or `userInfo`
    ///   contained a value that can't be sent
    /// - Example:
    /// ```js
    /// hs.distributednotifications.post("com.example.hammerspoon.ping", "hammerspoon", { count: 1 })
    /// ```
    @objc func post(_ name: String, _ object: String?, _ userInfo: [String: Any]?) -> Bool

    // NOTE: These are private API for the companion JS file only
    /// SKIP_DOCS
    @objc(_addWatcher::) func _addWatcher(_ name: String, listener: JSFunction) -> Bool
    /// SKIP_DOCS
    @objc func _removeWatcher(_ name: String)
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.distributednotifications.js. They must be real, pre-declared properties
    // (not dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSDistributedNotificationsModule: NSObject, HSModuleAPI, HSDistributedNotificationsModuleAPI {
    var moduleName = "hs.distributednotifications"
    let engineID: UUID

    /// One native observer per watched notification name, with the JS function it calls.
    private struct Watcher {
        let observer: DistributedNotificationObserver
        let callback: JSCallback
    }
    private var watchers: [String: Watcher] = [:]

    @objc var _watcherEmitter: JSFunction?
    @objc var on: JSFunction?
    @objc var off: JSFunction?
    @objc var once: JSFunction?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        for name in Array(watchers.keys) {
            _removeWatcher(name)
        }
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
        shutdown()
    }

    @objc func toString() -> String {
        let n = watchers.count
        return "<\(moduleName): \(n) watched notification\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Posting

    @objc func post(_ name: String, _ object: String?, _ userInfo: [String: Any]?) -> Bool {
        guard !name.isEmpty, name != "undefined" else {
            AKError("hs.distributednotifications.post(): A notification name is required")
            return false
        }
        // An omitted trailing String? argument arrives as the literal string "undefined"
        let object = (object == "undefined") ? nil : object
        if let userInfo, !PropertyListSerialization.propertyList(userInfo, isValidFor: .binary) {
            AKError("hs.distributednotifications.post(): userInfo for '\(name)' contains a value that isn't a string, number, boolean, Date, array or object")
            return false
        }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name),
            object: object,
            userInfo: userInfo,
            deliverImmediately: true
        )
        return true
    }

    // MARK: - Watchers

    @objc(_addWatcher::) func _addWatcher(_ name: String, listener: JSFunction) -> Bool {
        guard !name.isEmpty, name != "undefined" else {
            AKError("hs.distributednotifications.on(): A notification name is required")
            return false
        }
        guard watchers[name] == nil else {
            AKWarning("hs.distributednotifications.on(): Already watching '\(name)'. Refusing to create a second.")
            return false
        }
        guard let callback = JSCallback(value: listener, owner: self) else {
            AKError("hs.distributednotifications.on(): Unable to store the listener for '\(name)'")
            return false
        }
        let observer = DistributedNotificationObserver(name: Notification.Name(name)) { [weak self] notification in
            self?.deliver(notification)
        }
        watchers[name] = Watcher(observer: observer, callback: callback)
        AKDebug("hs.distributednotifications.on(): Started watching '\(name)'")
        return true
    }

    @objc func _removeWatcher(_ name: String) {
        guard let watcher = watchers.removeValue(forKey: name) else { return }
        // Releasing the observer removes it from the notification center
        watcher.callback.detach(from: self)
        AKDebug("hs.distributednotifications.off(): Stopped watching '\(name)'")
    }

    private func deliver(_ notification: Notification) {
        let name = notification.name.rawValue
        guard let callback = watchers[name]?.callback else { return }
        // Distributed notification objects are always strings, or nil
        let object: Any = (notification.object as? String) ?? NSNull()
        var userInfo: [String: Any] = [:]
        for (key, value) in notification.userInfo ?? [:] {
            userInfo[String(describing: key)] = value
        }
        _ = callback.call(withArguments: [name, object, userInfo])
    }
}
