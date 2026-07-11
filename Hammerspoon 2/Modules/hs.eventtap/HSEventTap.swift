//
//  HSEventTap.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import CoreGraphics

// MARK: - Protocol

/// An event tap watcher that intercepts input events from the system.
///
/// Obtain instances via `hs.eventtap.addWatcher()` — do not instantiate directly.
///
/// ## Monitoring keyboard events
///
/// ```js
/// const tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
///     console.log("Key pressed: " + event.keyCode)
/// })
/// ```
@objc protocol HSEventTapAPI: HSTypeAPI, JSExport {
    /// A unique identifier for this tap
    /// - Example:
    /// ```js
    /// const tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {})
    /// console.log(tap.identifier)
    /// ```
    @objc var identifier: String { get }

    /// Start receiving events. Requires Accessibility permission.
    /// - Returns: This tap, for chaining
    /// - Example:
    /// ```js
    /// const tap = hs.eventtap.addWatcher([hs.eventtap.eventTypes.keyDown], (event) => {
    ///     console.log("Key: " + event.keyCode)
    /// })
    /// tap.start()
    /// ```
    @objc @discardableResult func start() -> HSEventTap

    /// Stop receiving events
    /// - Returns: This tap, for chaining
    /// - Example:
    /// ```js
    /// tap.stop()
    /// ```
    @objc @discardableResult func stop() -> HSEventTap

    /// Replace the callback function
    /// - Parameter callback: {(event: HSEventTapEvent) => boolean | undefined} A function called for each matching event. Return false to consume (suppress) the event; return anything else to pass it through.
    /// - Returns: This tap, for chaining
    /// - Example:
    /// ```js
    /// tap.setCallback((event) => {
    ///     console.log("Key: " + event.keyCode)
    ///     return false  // consume the event
    /// })
    /// ```
    @objc func setCallback(_ callback: JSFunction) -> HSEventTap

    /// Whether this tap is currently active
    /// - Returns: True if the tap is running
    /// - Example:
    /// ```js
    /// console.log("Running: " + tap.isEnabled())
    /// ```
    @objc func isEnabled() -> Bool
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@safe
@objc class HSEventTap: NSObject, HSEventTapAPI {
    @objc var typeName = "HSEventTap"
    @objc let identifier = UUID().uuidString

    private let eventMask: CGEventMask
    private var callback: JSCallback?
    private var hasWarnedAboutReturnValue = false

    // CFMachPort and its run loop source are C types; stored nonisolated(unsafe)
    // because they are only accessed on the MainActor (in start/stop/handleEvent)
    // and the static C callback guarantees main-thread delivery via CFRunLoopGetMain().
    nonisolated(unsafe) private var tapPort: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    private var running = false

    // Strong self-retain while tap is active so the C callback userInfo pointer is safe.
    // Written only on the MainActor; the C callback reads it from the main run loop thread.
    nonisolated(unsafe) private var selfRetain: HSEventTap?

    init(eventMask: CGEventMask) {
        self.eventMask = eventMask
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSEventTap(\(identifier))")
    }

    func destroy() {
        _ = stop()
        callback?.detach(from: self)
        callback = nil
    }

    // MARK: - HSEventTapAPI

    @objc @discardableResult func start() -> HSEventTap {
        guard !running else {
            AKWarning("hs.eventtap: tap \(identifier) is already running")
            return self
        }

        unsafe selfRetain = self

        let port = unsafe CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HSEventTap.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let port else {
            AKError("hs.eventtap: Failed to create event tap for \(identifier) — Accessibility permission may be required")
            unsafe selfRetain = nil
            return self
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        unsafe tapPort = port
        unsafe runLoopSource = source
        running = true
        AKTrace("hs.eventtap: tap \(identifier) started")
        return self
    }

    @objc @discardableResult func stop() -> HSEventTap {
        guard running else { return self }

        if let port = unsafe tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = unsafe runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        unsafe tapPort = nil
        unsafe runLoopSource = nil
        running = false
        unsafe selfRetain = nil
        AKTrace("hs.eventtap: tap \(identifier) stopped")
        return self
    }

    @objc func setCallback(_ fn: JSFunction) -> HSEventTap {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    @objc func isEnabled() -> Bool {
        return running
    }

    // MARK: - C callback bridge

    // Static @convention(c) function used as the CGEventTap callback.
    // Delivery is always on the main run loop thread (we use CFRunLoopGetMain()).
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = unsafe userInfo else {
            // CGEventTapCallBack receives a non-optional CGEvent; pass it through retained.
            return unsafe Unmanaged.passRetained(event)
        }
        let tap = unsafe Unmanaged<HSEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return unsafe tap.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that take too long; re-enable immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = unsafe tapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            AKWarning("hs.eventtap: tap \(identifier) was disabled by system — re-enabled")
            return unsafe Unmanaged.passRetained(event)
        }

        guard let callbackFn = callback?.value, !callbackFn.isNull else {
            return unsafe Unmanaged.passRetained(event)
        }

        let wrapper = HSEventTapEvent(cgEvent: event)
        let result = callbackFn.call(withArguments: [wrapper])

        if let context = callbackFn.context, let exc = context.exception, !exc.isUndefined {
            AKError("hs.eventtap: Error in tap callback: \(exc.toString() ?? "unknown")")
            context.exception = nil
        }

        // Warn once per tap if the callback does not explicitly return hs.eventtap.consume
        // (false) or hs.eventtap.emit (true).
        if !hasWarnedAboutReturnValue, result?.isBoolean != true {
            AKWarning("hs.eventtap(\(identifier)): callback did not return hs.eventtap.consume or hs.eventtap.emit — defaulting to emit (pass-through). Return false/hs.eventtap.consume to suppress events, or true/hs.eventtap.emit to pass them through.")
            hasWarnedAboutReturnValue = true
        }

        // Returning false from the callback suppresses (consumes) the event.
        if let result, result.isBoolean, !result.toBool() {
            return nil
        }

        // Return the event from the wrapper in case the callback modified any properties.
        return unsafe Unmanaged.passRetained(wrapper.cgEvent)
    }
}
