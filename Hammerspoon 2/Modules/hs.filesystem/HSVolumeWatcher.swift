//
//  HSVolumeWatcher.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

// MARK: - Watcher API protocol

/// A volume event watcher that monitors filesystem mount/unmount/rename events.
///
/// Create via `hs.fs.addVolumeWatcher()`. Set a callback with `setCallback()`, then
/// call `start()` to begin receiving events.
///
/// The callback receives `(event, info)`:
///
/// | Event | Info keys |
/// |-------|-----------|
/// | `"didMount"` | `path: string` |
/// | `"didUnmount"` | `path: string` |
/// | `"willUnmount"` | `path: string` |
/// | `"didRename"` | `path: string`, `name: string`, `oldPath?: string`, `oldName?: string` |
///
/// Example:
/// ```js
/// const w = hs.fs.addVolumeWatcher()
/// w.setCallback((event, info) => {
///     console.log(event + ": " + info.path)
/// }).start()
/// ```
@objc protocol HSVolumeWatcherAPI: HSTypeAPI, JSExport {

    /// The unique identifier assigned to this watcher.
    /// - Example:
    /// ```js
    /// const w = hs.fs.addVolumeWatcher()
    /// console.log(w.identifier)
    /// ```
    @objc var identifier: String { get }

    /// Starts monitoring volume events.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// const w = hs.fs.addVolumeWatcher()
    /// w.setCallback((ev, info) => console.log(ev)).start()
    /// ```
    @objc @discardableResult func start() -> HSVolumeWatcher

    /// Stops monitoring volume events.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.stop()
    /// ```
    @objc @discardableResult func stop() -> HSVolumeWatcher

    /// Sets the callback function invoked when volume events occur.
    /// - Parameter fn: {(event: string, info: Record<string, any>) => void} Called with the event name and an info dictionary; see type documentation for event names and info keys.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// w.setCallback((event, info) => {
    ///     if (event === "didMount") console.log("Mounted: " + info.path)
    /// })
    /// ```
    @objc func setCallback(_ fn: JSFunction) -> HSVolumeWatcher

    /// Stops the watcher and releases all resources. Called automatically during shutdown.
    /// - Example:
    /// ```js
    /// w.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSVolumeWatcher: NSObject, HSVolumeWatcherAPI {
    @objc var typeName = "HSVolumeWatcher"
    @objc let identifier = UUID().uuidString
    private var callback: JSCallback?
    private var isRunning = false

    override init() {
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSVolumeWatcher(\(identifier))")
    }

    // MARK: - API

    @objc @discardableResult func start() -> HSVolumeWatcher {
        guard !isRunning else { return self }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(onVolumeDidMount(_:)),
                           name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(onVolumeDidUnmount(_:)),
                           name: NSWorkspace.didUnmountNotification, object: nil)
        center.addObserver(self, selector: #selector(onVolumeWillUnmount(_:)),
                           name: NSWorkspace.willUnmountNotification, object: nil)
        center.addObserver(self, selector: #selector(onVolumeDidRename(_:)),
                           name: NSWorkspace.didRenameVolumeNotification, object: nil)
        AKTrace("HSVolumeWatcher(\(identifier)): started")
        return self
    }

    @objc @discardableResult func stop() -> HSVolumeWatcher {
        guard isRunning else { return self }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self, name: NSWorkspace.didMountNotification, object: nil)
        center.removeObserver(self, name: NSWorkspace.didUnmountNotification, object: nil)
        center.removeObserver(self, name: NSWorkspace.willUnmountNotification, object: nil)
        center.removeObserver(self, name: NSWorkspace.didRenameVolumeNotification, object: nil)
        AKTrace("HSVolumeWatcher(\(identifier)): stopped")
        return self
    }

    @objc func setCallback(_ fn: JSFunction) -> HSVolumeWatcher {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    @objc func destroy() {
        _ = stop()
        callback?.detach(from: self)
        callback = nil
    }

    // MARK: - Notification handlers
    // NSWorkspace volume notifications are guaranteed to arrive on the main thread.

    @objc private func onVolumeDidMount(_ notification: Notification) {
        MainActor.assumeIsolated {
            fire(event: "didMount", userInfo: notification.userInfo)
        }
    }

    @objc private func onVolumeDidUnmount(_ notification: Notification) {
        MainActor.assumeIsolated {
            fire(event: "didUnmount", userInfo: notification.userInfo)
        }
    }

    @objc private func onVolumeWillUnmount(_ notification: Notification) {
        MainActor.assumeIsolated {
            fire(event: "willUnmount", userInfo: notification.userInfo)
        }
    }

    @objc private func onVolumeDidRename(_ notification: Notification) {
        MainActor.assumeIsolated {
            fire(event: "didRename", userInfo: notification.userInfo)
        }
    }

    // MARK: - Private helpers

    private func fire(event: String, userInfo: [AnyHashable: Any]?) {
        guard let info = buildInfo(event: event, userInfo: userInfo) else { return }
        _ = callback?.value?.call(withArguments: [event, info])
    }

    private func buildInfo(event: String, userInfo: [AnyHashable: Any]?) -> [String: Any]? {
        var info: [String: Any] = [:]

        switch event {
        case "didMount", "didUnmount", "willUnmount":
            info["path"] = (userInfo?["NSDevicePath"] as? String) ?? ""

        case "didRename":
            if let url = userInfo?["NSWorkspaceVolumeURL"] as? URL {
                info["path"] = url.path
            }
            if let name = userInfo?["NSWorkspaceVolumeLocalizedName"] as? String {
                info["name"] = name
            }
            if let oldURL = userInfo?["NSWorkspaceVolumeOldURL"] as? URL {
                info["oldPath"] = oldURL.path
            }
            if let oldName = userInfo?["NSWorkspaceVolumeOldLocalizedName"] as? String {
                info["oldName"] = oldName
            }
            guard info["path"] != nil else { return nil }

        default:
            return nil
        }

        return info
    }
}
