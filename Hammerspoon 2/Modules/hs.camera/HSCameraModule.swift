//
//  HSCameraModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AVFoundation

// MARK: - JavaScript API Protocol

/// Module for discovering and interacting with camera devices.
///
/// This module lets you enumerate cameras, capture still images, and react to
/// device connect/disconnect events in real time.
///
/// Camera access requires user permission. Call `hs.permissions.requestCamera()`
/// before using ``captureImage()`` or reading ``isInUse``.
///
/// ## Enumerating cameras
///
/// ```javascript
/// const cameras = hs.camera.all()
/// cameras.forEach(cam => {
///     console.log(cam.name + " — " + (cam.isInUse ? "in use" : "idle"))
/// })
/// ```
///
/// ## Finding a specific camera
///
/// ```javascript
/// const cam = hs.camera.findByName("FaceTime HD Camera")
/// if (cam) {
///     cam.captureImage()
///         .then(img => img.saveToFile("/tmp/snapshot.png"))
///         .catch(err => console.error("Capture error: " + err))
/// }
/// ```
///
/// ## Watching for connect / disconnect events
///
/// ```javascript
/// const handler = (event, camera) => {
///     if (event === "connected")    console.log("Camera connected: " + camera.name)
///     if (event === "disconnected") console.log("Camera disconnected: " + camera.name)
/// }
/// hs.camera.addWatcher(handler)
/// // Later…
/// hs.camera.removeWatcher(handler)
/// ```
///
/// ## Watching a camera's in-use state
///
/// ```javascript
/// const cam = hs.camera.all()[0]
/// cam.addWatcher((isInUse) => {
///     console.log(cam.name + " is now " + (isInUse ? "in use" : "idle"))
/// })
/// ```
@objc protocol HSCameraModuleAPI: JSExport {

    /// All video camera devices currently connected to the system.
    /// - Returns: An array of `HSCamera` objects
    /// - Example:
    /// ```js
    /// hs.camera.all().forEach(c => console.log(c.name))
    /// ```
    @objc func all() -> [HSCamera]

    /// Find the first camera whose name matches the given string.
    /// - Parameter name: The device name to search for (exact match)
    /// - Returns: An `HSCamera` if found, `null` otherwise
    /// - Example:
    /// ```js
    /// const cam = hs.camera.findByName("FaceTime HD Camera")
    /// ```
    @objc func findByName(_ name: String) -> HSCamera?

    /// Find the camera with the given unique identifier.
    /// - Parameter uid: The device UID to search for
    /// - Returns: An `HSCamera` if found, `null` otherwise
    /// - Example:
    /// ```js
    /// const cam = hs.camera.findByUID("CC26C0000082005")
    /// ```
    @objc func findByUID(_ uid: String) -> HSCamera?

    /// Register a listener for camera device connect/disconnect events.
    ///
    /// The listener is called with two arguments:
    /// - `event` — either `"connected"` or `"disconnected"`
    /// - `camera` — an `HSCamera` representing the affected device
    ///
    /// - Parameter listener: A JavaScript function receiving `(event: string, camera: HSCamera)`
    /// - Example:
    /// ```js
    /// hs.camera.addWatcher((event, camera) => {
    ///     console.log(event + ": " + camera.name)
    /// })
    /// ```
    @objc func addWatcher(_ listener: JSValue)

    /// Remove a previously registered module-level event listener.
    /// - Parameter listener: The function originally passed to ``addWatcher(_:)``
    /// - Example:
    /// ```js
    /// hs.camera.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSValue)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSValue)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSValue? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSCameraModule: NSObject, HSModuleAPI, HSCameraModuleAPI {
    var name = "hs.camera"

    private var cameraCache: [String: HSCamera] = [:]
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    override required init() { super.init() }

    func shutdown() {
        _removeWatcher()
        for camera in cameraCache.values {
            camera._removeWatcher()
        }
        cameraCache.removeAll()
    }

    isolated deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Device Enumeration

    @objc func all() -> [HSCamera] {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map { camera(for: $0) }
    }

    @objc func findByName(_ name: String) -> HSCamera? {
        all().first { $0.name == name }
    }

    @objc func findByUID(_ uid: String) -> HSCamera? {
        all().first { $0.uid == uid }
    }

    private func camera(for device: AVCaptureDevice) -> HSCamera {
        if let cached = cameraCache[device.uniqueID] { return cached }
        let cam = HSCamera(device: device)
        cameraCache[device.uniqueID] = cam
        return cam
    }

    // MARK: - Module-level watcher

    @objc var _watcherEmitter: JSValue? = nil
    private var moduleCallback: JSValue? = nil

    @objc func addWatcher(_ listener: JSValue) {
        // invokeMethod doesn't propagate JS exceptions to the calling context's try-catch,
        // so we validate here and throw via context.exception before delegating.
        guard let context = JSContext.current() else { return }
        guard listener.isObject else {
            context.exception = JSValue(newErrorFromMessage: "hs.camera.addWatcher(): listener must be a function", in: context)
            return
        }
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSValue) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSValue) {
        guard moduleCallback == nil else {
            AKWarning("hs.camera._addWatcher(): Already watching. Refusing to create a second.")
            return
        }
        // Populate the cache now so any camera that disconnects before all() is ever
        // called still has an HSCamera entry — not a raw UID string — in the callback.
        _ = all()
        moduleCallback = callback

        let nc = NotificationCenter.default

        connectObserver = nc.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let device = notification.object as? AVCaptureDevice,
                  device.hasMediaType(.video) else { return }
            // Capture only the Sendable UID; re-look up the device inside assumeIsolated.
            let deviceUID = device.uniqueID
            MainActor.assumeIsolated {
                guard let connectedDevice = AVCaptureDevice(uniqueID: deviceUID) else { return }
                let cam = self.camera(for: connectedDevice)
                _ = self.moduleCallback?.call(withArguments: ["connected", cam])
            }
        }

        disconnectObserver = nc.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let device = notification.object as? AVCaptureDevice,
                  device.hasMediaType(.video) else { return }
            let uid = device.uniqueID  // String is Sendable
            MainActor.assumeIsolated {
                // Cache was primed in _addWatcher, so removeValue should always find the camera.
                if let cam = self.cameraCache.removeValue(forKey: uid) {
                    _ = self.moduleCallback?.call(withArguments: ["disconnected", cam])
                }
            }
        }

        AKTrace("hs.camera._addWatcher(): Started")
    }

    @objc func _removeWatcher() {
        guard moduleCallback != nil else { return }
        let nc = NotificationCenter.default
        if let obs = connectObserver { nc.removeObserver(obs); connectObserver = nil }
        if let obs = disconnectObserver { nc.removeObserver(obs); disconnectObserver = nil }
        moduleCallback = nil
        AKTrace("hs.camera._removeWatcher(): Stopped")
    }
}
