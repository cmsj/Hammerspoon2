//
//  HSCamera.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AVFoundation
import CoreMediaIO
import AppKit

// MARK: - Private: still-image capture delegate

private class CameraCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    typealias Completion = @Sendable (Result<NSImage, Error>) -> Void
    // nonisolated(unsafe): written once in init before any cross-thread access;
    // read exactly once in the one-shot delegate callback. No actual data races.
    nonisolated(unsafe) private var completion: Completion?
    nonisolated(unsafe) private var strongSelf: CameraCaptureDelegate?

    init(completion: @escaping Completion) {
        unsafe self.completion = completion
        super.init()
        unsafe strongSelf = self
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let c = unsafe completion
        unsafe completion = nil   // prevent any accidental double-call
        unsafe strongSelf = nil   // break retain cycle
        if let error {
            c?(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let nsImage = NSImage(data: data) else {
            c?(.failure(NSError(
                domain: "HSCamera", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode captured photo data"]
            )))
            return
        }
        c?(.success(nsImage))
    }
}

// MARK: - JavaScript API Protocol

/// A camera device attached to the system.
///
/// Obtain instances via the ``hs.camera`` module — do not instantiate directly.
///
/// ## Reading camera properties
///
/// ```javascript
/// const cam = hs.camera.all()[0]
/// console.log(cam.name + " uid=" + cam.uid + " inUse=" + cam.isInUse)
/// ```
///
/// ## Watching for in-use state changes
///
/// ```javascript
/// const cam = hs.camera.all()[0]
/// const fn = (isInUse) => {
///     console.log(cam.name + " is now " + (isInUse ? "in use" : "not in use"))
/// }
/// cam.addWatcher(fn)
/// // later…
/// cam.removeWatcher(fn)
/// ```
///
/// ## Capturing a still image
///
/// ```javascript
/// const cam = hs.camera.all()[0]
/// cam.captureImage()
///     .then(img => img.saveToFile("/tmp/shot.png"))
///     .catch(err => console.error("Capture failed: " + err))
/// ```
@objc protocol HSCameraAPI: HSTypeAPI, JSExport {

    /// The type name for JavaScript introspection. Always `"HSCamera"`.
    @objc var typeName: String { get }

    /// The persistent unique identifier for this camera.
    /// - Example:
    /// ```js
    /// console.log(hs.camera.all()[0].uid)
    /// ```
    @objc var uid: String { get }

    /// The human-readable name of this camera (e.g. `"FaceTime HD Camera"`).
    /// - Example:
    /// ```js
    /// console.log(hs.camera.all()[0].name)
    /// ```
    @objc var name: String { get }

    /// Whether this camera is currently being used by any application.
    ///
    /// Queries the underlying CoreMediaIO device state each time it is read.
    /// - Example:
    /// ```js
    /// if (hs.camera.all()[0].isInUse) console.log("Camera is busy")
    /// ```
    @objc var isInUse: Bool { get }

    /// Register a listener that fires whenever this camera's in-use state changes.
    ///
    /// The listener receives one argument: a boolean that is `true` when the camera
    /// starts being used and `false` when it is released.
    ///
    /// - Parameter listener: A JavaScript function receiving `(isInUse: boolean)`
    /// - Example:
    /// ```js
    /// const cam = hs.camera.all()[0]
    /// cam.addWatcher((inUse) => {
    ///     console.log(cam.name + " is " + (inUse ? "now in use" : "no longer in use"))
    /// })
    /// ```
    @objc func addWatcher(_ listener: JSFunction)

    /// Remove a previously registered per-camera in-use listener.
    /// - Parameter listener: The function originally passed to ``addWatcher(_:)``
    /// - Example:
    /// ```js
    /// cam.removeWatcher(myHandler)
    /// ```
    @objc func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// Capture a still image from this camera.
    ///
    /// Camera permission must be granted via `hs.permissions.requestCamera()` before calling
    /// this method. The returned `HSImage` can be saved, displayed in a UI element, or
    /// passed to other image-processing APIs.
    ///
    /// - Returns: {Promise<HSImage>} A Promise that resolves to an `HSImage`, or rejects on error
    /// - Example:
    /// ```js
    /// const img = await hs.camera.all()[0].captureImage()
    /// img.saveToFile("/tmp/snapshot.png")
    /// ```
    @objc func captureImage() -> JSPromise?
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSCamera: NSObject, HSCameraAPI {
    @objc var typeName = "HSCamera"

    let device: AVCaptureDevice

    init(device: AVCaptureDevice) {
        self.device = device
        super.init()
    }

    isolated deinit {
        _removeWatcher()
    }

    // MARK: - Properties

    @objc var uid: String { device.uniqueID }
    @objc var name: String { device.localizedName }

    @objc var isInUse: Bool {
        guard let cmioID = HSCamera.cmioDeviceID(matchingUID: device.uniqueID) else { return false }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var isRunning: UInt32 = 0
        // CMIOObjectGetPropertyData takes separate inDataSize (value) and outDataSize (pointer).
        let inDataSize = UInt32(MemoryLayout<UInt32>.size)
        var outDataSize = inDataSize
        guard unsafe CMIOObjectGetPropertyData(cmioID, &address, 0, nil, inDataSize, &outDataSize, &isRunning) == noErr else {
            return false
        }
        return isRunning != 0
    }

    // MARK: - Per-camera watcher

    @objc var _watcherEmitter: JSFunction? = nil
    private var watcherCallback: JSFunction? = nil
    private var cmioListenerBlock: CMIOObjectPropertyListenerBlock? = nil
    private var watcherCMIOID: CMIOObjectID? = nil
    // Self-retain while a watcher is active — keeps the object alive across GC cycles.
    private var selfRetain: HSCamera? = nil

    @objc func addWatcher(_ listener: JSFunction) {
        // invokeMethod doesn't propagate JS exceptions to the calling context's try-catch,
        // so we validate here and throw via context.exception before delegating.
        guard let ctx = JSContext.current() else { return }
        guard listener.isObject else {
            ctx.exception = JSValue(newErrorFromMessage: "hs.camera device.addWatcher(): listener must be a function", in: ctx)
            return
        }
        if _watcherEmitter == nil {
            let cameraModule = ctx.objectForKeyedSubscript("hs")?.objectForKeyedSubscript("camera")
            _watcherEmitter = cameraModule?.invokeMethod("_makeCameraEmitter", withArguments: [self])
        }
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    @objc func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard watcherCallback == nil else {
            AKWarning("hs.camera._addWatcher(): Already watching '\(name)'. Refusing to create a second.")
            return
        }
        guard let cmioID = HSCamera.cmioDeviceID(matchingUID: device.uniqueID) else {
            AKError("hs.camera._addWatcher(): Cannot find CMIO device for '\(name)'")
            return
        }

        watcherCallback = callback
        watcherCMIOID = cmioID
        selfRetain = self

        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let inUse = self.isInUse
                _ = self.watcherCallback?.call(withArguments: [inUse])
            }
        }
        unsafe cmioListenerBlock = block
        unsafe CMIOObjectAddPropertyListenerBlock(cmioID, &address, .main, block)
        AKTrace("hs.camera._addWatcher(): Started watching '\(name)'")
    }

    @objc func _removeWatcher() {
        _watcherEmitter = nil
        guard watcherCallback != nil,
              let cmioID = watcherCMIOID,
              let block = unsafe cmioListenerBlock else { return }

        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        unsafe CMIOObjectRemovePropertyListenerBlock(cmioID, &address, .main, block)
        unsafe cmioListenerBlock = nil
        watcherCMIOID = nil
        watcherCallback = nil
        selfRetain = nil
        AKTrace("hs.camera._removeWatcher(): Stopped watching '\(name)'")
    }

    // MARK: - Image Capture

    @objc func captureImage() -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let captureDevice = self.device
        return wrapAsyncInJSPromise(in: context) { holder in
            Task {
                do {
                    let nsImage = try await HSCamera.captureStillImage(from: captureDevice)
                    // toBridge() requires @MainActor; resume on main.
                    await MainActor.run { holder.resolveWith(nsImage.toBridge()) }
                } catch {
                    await MainActor.run { holder.rejectWithMessage(error.localizedDescription) }
                }
            }
        }
    }

    // Runs on cooperative thread pool — blocking session.startRunning() must not be on main.
    private static func captureStillImage(from device: AVCaptureDevice) async throws -> NSImage {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "HSCamera", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add input for '\(device.localizedName)'"])
        }
        session.addInput(input)

        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw NSError(domain: "HSCamera", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output for '\(device.localizedName)'"])
        }
        session.addOutput(photoOutput)
        session.startRunning()
        defer { session.stopRunning() }

        // Give auto-exposure time to converge. Without this the capture fires before
        // AE has run even one adjustment cycle and the result is heavily underexposed.
        await waitForAutoExposure(device: input.device)

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = CameraCaptureDelegate { result in
                continuation.resume(with: result)
            }
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    // Waits for the camera's auto-exposure to converge after session start.
    // Uses a 500 ms initial hold (gives AE time to kick in), then polls
    // isAdjustingExposure with a 2-second ceiling.
    private static func waitForAutoExposure(device: AVCaptureDevice) async {
        try? await Task.sleep(for: .milliseconds(500))
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline && device.isAdjustingExposure {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - CoreMediaIO helpers

    /// Returns the `CMIOObjectID` for the CMIO device whose UID matches the given string,
    /// or `nil` if no match is found.
    static func cmioDeviceID(matchingUID uid: String) -> CMIOObjectID? {
        let systemID = CMIOObjectID(kCMIOObjectSystemObject)
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard unsafe CMIOObjectGetPropertyDataSize(systemID, &devicesAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var deviceIDs = [CMIOObjectID](repeating: CMIOObjectID(0), count: count)
        let inDataSize = dataSize
        var outDataSize = inDataSize
        guard unsafe CMIOObjectGetPropertyData(systemID, &devicesAddress, 0, nil, inDataSize, &outDataSize, &deviceIDs) == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var uidRef: Unmanaged<CFString>? = nil
            let uidInSize = unsafe UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var uidOutSize = uidInSize

            guard unsafe CMIOObjectGetPropertyData(deviceID, &uidAddress, 0, nil, uidInSize, &uidOutSize, &uidRef) == noErr,
                  unsafe uidRef != nil else { continue }
            let deviceUID = unsafe uidRef!.takeRetainedValue() as String

            if deviceUID == uid { return deviceID }
        }
        return nil
    }
}
