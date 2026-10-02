//
//  HSCameraModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
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
/// hs.camera.on("connected", camera => console.log("Camera connected: " + camera.name))
/// hs.camera.on("disconnected", camera => console.log("Camera disconnected: " + camera.name))
/// ```
///
/// ## Watching a camera's in-use state
///
/// ```javascript
/// const cam = hs.camera.all()[0]
/// cam.on(() => {
///     console.log(cam.name + " is now " + (cam.isInUse ? "in use" : "idle"))
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

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var _makeCameraEmitter: JSFunction? { get set }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.camera.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
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
@objc class HSCameraModule: NSObject, HSModuleAPI, HSCameraModuleAPI {
    var moduleName = "hs.camera"
    let engineID: UUID

    private var cameraCache: [String: HSCamera] = [:]
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        for camera in cameraCache.values {
            camera._removeWatcher()
        }
        cameraCache.removeAll()
        _watcherEmitter = nil
        _makeCameraEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = all().count
        return "<\(moduleName): \(n) \(n == 1 ? "camera" : "cameras")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
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
        let cam = HSCamera(device: device, cameraModule: self)
        cameraCache[device.uniqueID] = cam
        return cam
    }

    // MARK: - Module-level watcher

    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _makeCameraEmitter: JSFunction? = nil
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var moduleCallback: JSFunction? = nil

    @objc(_addWatcher:) func _addWatcher(_ listener: JSFunction) {
        guard moduleCallback == nil else {
            AKWarning("hs.camera._addWatcher(): Already watching. Refusing to create a second.")
            return
        }
        // Populate the cache now so any camera that disconnects before all() is ever
        // called still has an HSCamera entry — not a raw UID string — in the callback.
        _ = all()
        moduleCallback = listener

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

        AKDebug("hs.camera._addWatcher(): Started")
    }

    @objc func _removeWatcher() {
        guard moduleCallback != nil else { return }
        let nc = NotificationCenter.default
        if let obs = connectObserver { nc.removeObserver(obs); connectObserver = nil }
        if let obs = disconnectObserver { nc.removeObserver(obs); disconnectObserver = nil }
        moduleCallback = nil
        AKDebug("hs.camera._removeWatcher(): Stopped")
    }
}
