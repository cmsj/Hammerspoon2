//
//  HSStreamDeckDevice.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import IOKit
import IOKit.hid
import AppKit
import SwiftUI

// MARK: - Input report callback (file-scope, IOKit C callback)

// This must be a file-scope function, not a closure literal inside a @MainActor method:
// IOHIDDeviceRegisterInputReportCallback invokes it synchronously on whatever thread IOKit
// delivers the report on, but a closure lexically inside a @MainActor method would inherit
// @MainActor isolation under this project's default actor isolation setting, tripping a
// runtime isolation check. A nonisolated file-scope function sidesteps that, mirroring
// HSSerialPort's read-source handler.
nonisolated private func hsStreamDeckInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context = unsafe context, reportLength > 0 else { return }
    let bytes = unsafe Array(UnsafeBufferPointer(start: report, count: reportLength))
    let device = unsafe Unmanaged<HSStreamDeckDevice>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        device.handleInputReport(bytes)
    }
}

// MARK: - Protocol

/// A Stream Deck device, obtained via `hs.streamdeck.all()` or a discovery watcher — do
/// not instantiate directly.
///
/// - Example:
/// ```js
/// const deck = hs.streamdeck.all()[0]
/// deck.setBrightness(50)
/// deck.buttonCallback((device, button, isDown) => {
///     if (isDown) device.setButtonColor(button, HSColor.named("red"))
/// })
/// ```
@objc protocol HSStreamDeckDeviceAPI: HSTypeAPI, JSExport {

    /// The unique identifier assigned to this device object.
    @objc var identifier: String { get }

    /// A human-readable description of the device model (e.g. `"Elgato Stream Deck (XL)"`).
    @objc var deckType: String { get }

    /// The device's serial number.
    @objc var serialNumber: String { get }

    /// The device's firmware version. Reads live from the hardware on every access.
    @objc var firmwareVersion: String { get }

    /// The number of button columns.
    @objc var keyColumns: Int { get }

    /// The number of button rows.
    @objc var keyRows: Int { get }

    /// The total number of buttons (`keyColumns * keyRows`).
    @objc var keyCount: Int { get }

    /// The number of rotary encoders (Stream Deck Plus only; `0` on other models).
    @objc var encoderColumns: Int { get }

    /// The number of encoder rows (Stream Deck Plus only; `0` on other models).
    @objc var encoderRows: Int { get }

    /// The total number of encoders (`encoderColumns * encoderRows`).
    @objc var encoderCount: Int { get }

    /// The pixel dimensions required for button images.
    /// - Example:
    /// ```js
    /// const size = hs.streamdeck.all()[0].imageSize
    /// console.log(size.w, size.h)
    /// ```
    @objc var imageSize: HSSize { get }

    /// Sets the device's brightness.
    /// - Parameter brightness: A whole number 0-100, the percentage brightness level
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].setBrightness(75)
    /// ```
    @objc @discardableResult func setBrightness(_ brightness: Int) -> HSStreamDeckDevice

    /// Resets the device to its power-on state (clears all button images).
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].reset()
    /// ```
    @objc @discardableResult func reset() -> HSStreamDeckDevice

    /// Sets a button's image.
    /// - Parameter button: The button number, from `1` to `keyCount`
    /// - Parameter image: An `HSImage` to display on the button. It is resized to fit.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// const deck = hs.streamdeck.all()[0]
    /// deck.setButtonImage(1, HSImage.fromPath("/path/to/icon.png"))
    /// ```
    @objc @discardableResult func setButtonImage(_ button: Int, _ image: HSImage) -> HSStreamDeckDevice

    /// Sets a button to a solid color.
    /// - Parameter button: The button number, from `1` to `keyCount`
    /// - Parameter color: An `HSColor`
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].setButtonColor(1, HSColor.named("red"))
    /// ```
    @objc @discardableResult func setButtonColor(_ button: Int, _ color: HSColor) -> HSStreamDeckDevice

    /// Sets the LCD strip image above one encoder (Stream Deck Plus only; a no-op on other models).
    /// - Parameter encoder: The encoder number, from `1` to `encoderColumns`
    /// - Parameter image: An `HSImage` to display. It is resized to fit.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].setScreenImage(1, HSImage.fromPath("/path/to/icon.png"))
    /// ```
    @objc @discardableResult func setScreenImage(_ encoder: Int, _ image: HSImage) -> HSStreamDeckDevice

    /// Sets the callback for button press/release events. Replaces any previously set callback.
    ///
    /// The callback receives: this device, the button number, and whether it is now pressed.
    /// - Parameter fn: {(device: HSStreamDeckDevice, button: number, isDown: boolean) => void} The function to call on button events
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].buttonCallback((device, button, isDown) => {
    ///     console.log("button " + button + (isDown ? " pressed" : " released"))
    /// })
    /// ```
    @objc @discardableResult func buttonCallback(_ fn: JSFunction) -> HSStreamDeckDevice

    /// Sets the callback for encoder press/release/rotation events (Stream Deck Plus only).
    /// Replaces any previously set callback.
    ///
    /// The callback receives: this device, the encoder number, whether it is now pressed,
    /// and two booleans indicating rotation direction (at most one is `true` per call).
    /// - Parameter fn: {(device: HSStreamDeckDevice, encoder: number, isDown: boolean, turningLeft: boolean, turningRight: boolean) => void} The function to call on encoder events
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].encoderCallback((device, encoder, isDown, left, right) => {
    ///     if (left) console.log("encoder " + encoder + " turned left")
    /// })
    /// ```
    @objc @discardableResult func encoderCallback(_ fn: JSFunction) -> HSStreamDeckDevice

    /// Sets the callback for LCD touch-screen events (Stream Deck Plus only). Replaces any
    /// previously set callback.
    ///
    /// The callback receives: this device, the event type (`"shortPress"`, `"longPress"`, or
    /// `"swipe"`), and the start/end X/Y coordinates (end coordinates are `0` unless swiping).
    /// - Parameter fn: {(device: HSStreamDeckDevice, eventType: string, startX: number, startY: number, endX: number, endY: number) => void} The function to call on screen events
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].screenCallback((device, eventType, startX, startY, endX, endY) => {
    ///     console.log(eventType + " at " + startX + "," + startY)
    /// })
    /// ```
    @objc @discardableResult func screenCallback(_ fn: JSFunction) -> HSStreamDeckDevice

    /// Stops delivering events and releases all callbacks. Called automatically when the
    /// device is disconnected or the module shuts down.
    /// - Example:
    /// ```js
    /// hs.streamdeck.all()[0].destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSStreamDeckDevice: NSObject, HSStreamDeckDeviceAPI {
    @objc var typeName = "HSStreamDeckDevice"
    @objc let identifier = UUID().uuidString

    let device: IOHIDDevice
    let model: HSStreamDeckModel
    private(set) var isValid = true

    // Self-retain while connected, so the object survives independent of JS references —
    // mirrors HSCamera's watcher selfRetain pattern. Cleared in destroy().
    private var selfRetain: HSStreamDeckDevice?

    private var serialNumberCache: String?
    private var buttonStateCache: [Int]
    private var encoderStateCache: [Int]

    private var buttonCallbackHandler: JSCallback?
    private var encoderCallbackHandler: JSCallback?
    private var screenCallbackHandler: JSCallback?

    // Fixed, persistently-allocated buffer IOKit writes input reports into. Must not move
    // for as long as IOHIDDeviceRegisterInputReportCallback is registered, so it can't be a
    // Swift Array (no pointer-stability guarantee) — matches v1's malloc'd input buffer.
    private static let reportBufferLength = 1024
    private let reportBuffer: UnsafeMutablePointer<UInt8>

    init(device: IOHIDDevice, model: HSStreamDeckModel) {
        self.device = device
        self.model = model
        unsafe self.reportBuffer = .allocate(capacity: HSStreamDeckDevice.reportBufferLength)
        unsafe self.reportBuffer.initialize(repeating: 0, count: HSStreamDeckDevice.reportBufferLength)
        self.buttonStateCache = Array(repeating: 0, count: model.keyCount + 1)
        self.encoderStateCache = Array(repeating: 0, count: model.encoderCount + 1)
        super.init()
    }

    isolated deinit {
        destroy()
        unsafe reportBuffer.deallocate()
        AKGarbage("Deinit of HSStreamDeckDevice(\(identifier))")
    }

    /// Begins delivering input reports. Called once by the module right after the device
    /// is discovered.
    func startReceivingInputReports() {
        selfRetain = self
        unsafe IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer, HSStreamDeckDevice.reportBufferLength,
            hsStreamDeckInputReportCallback, Unmanaged.passUnretained(self).toOpaque()
        )
    }

    @objc func destroy() {
        guard isValid else { return }
        isValid = false
        unsafe IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, HSStreamDeckDevice.reportBufferLength, nil, nil)
        buttonCallbackHandler?.detach(from: self)
        buttonCallbackHandler = nil
        encoderCallbackHandler?.detach(from: self)
        encoderCallbackHandler = nil
        screenCallbackHandler?.detach(from: self)
        screenCallbackHandler = nil
        selfRetain = nil
    }

    @objc func toString() -> String {
        "<\(typeName): \(model.deckType)>"
    }

    // NSObject's `description` requirement is nonisolated, but this class is @MainActor;
    // -description is only ever invoked from JS (main thread) or the console's REPL echo
    // path, both already on the main thread, so assumeIsolated is safe here.
    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Properties

    @objc var deckType: String { model.deckType }
    @objc var keyColumns: Int { model.keyColumns }
    @objc var keyRows: Int { model.keyRows }
    @objc var keyCount: Int { model.keyCount }
    @objc var encoderColumns: Int { model.encoderColumns }
    @objc var encoderRows: Int { model.encoderRows }
    @objc var encoderCount: Int { model.encoderCount }
    @objc var imageSize: HSSize { CGSize(width: model.imageWidth, height: model.imageHeight).toBridge() }

    @objc var serialNumber: String {
        if let cached = serialNumberCache { return cached }
        let value = readFeatureReport(resultLength: model.simpleReportLength,
                                       reportID: model.serialNumberCommand,
                                       readOffset: model.serialNumberReadOffset)
        // Only cache a successful read — an empty result usually means the device wasn't
        // ready yet (e.g. read immediately after connecting), and permanently caching that
        // would make serialNumber stay blank forever even once the device settles.
        if !value.isEmpty {
            serialNumberCache = value
        }
        return value
    }

    @objc var firmwareVersion: String {
        readFeatureReport(resultLength: model.simpleReportLength,
                           reportID: model.firmwareVersionCommand,
                           readOffset: model.firmwareReadOffset)
    }

    // MARK: - Commands

    @objc @discardableResult func setBrightness(_ brightness: Int) -> HSStreamDeckDevice {
        guard isValid else { return self }
        guard var command = model.setBrightnessCommand, !command.isEmpty else {
            AKWarning("hs.streamdeck.setBrightness(): not supported on \(model.deckType)")
            return self
        }
        command[command.count - 1] = UInt8(clamping: max(0, min(100, brightness)))
        writeSimpleReport(command)
        return self
    }

    @objc @discardableResult func reset() -> HSStreamDeckDevice {
        guard isValid else { return self }
        writeSimpleReport(model.resetCommand)
        return self
    }

    @objc @discardableResult func setButtonImage(_ button: Int, _ image: HSImage) -> HSStreamDeckDevice {
        guard isValid else { return self }
        guard model.imageCodec != .unsupported, model.keyCount > 0 else {
            AKWarning("hs.streamdeck.setButtonImage(): not supported on \(model.deckType)")
            return self
        }
        guard (1...model.keyCount).contains(button) else {
            AKWarning("hs.streamdeck.setButtonImage(): invalid button \(button)")
            return self
        }
        guard let data = HSStreamDeckImageRendering.renderForDevice(image.image, model: model) else {
            AKWarning("hs.streamdeck.setButtonImage(): failed to render image")
            return self
        }
        writeButtonImage(Array(data), button: model.transformKeyIndex(button))
        return self
    }

    @objc @discardableResult func setButtonColor(_ button: Int, _ color: HSColor) -> HSStreamDeckDevice {
        guard isValid else { return self }
        guard model.imageCodec != .unsupported, model.keyCount > 0 else {
            AKWarning("hs.streamdeck.setButtonColor(): not supported on \(model.deckType)")
            return self
        }
        let swatch = HSStreamDeckImageRendering.solidColorImage(
            NSColor(color.color), size: NSSize(width: model.imageWidth, height: model.imageHeight)
        )
        return setButtonImage(button, swatch.toBridge())
    }

    @objc @discardableResult func setScreenImage(_ encoder: Int, _ image: HSImage) -> HSStreamDeckDevice {
        guard isValid else { return self }
        guard model.hasScreen else {
            AKWarning("hs.streamdeck.setScreenImage(): not supported on \(model.deckType)")
            return self
        }
        guard (1...model.encoderColumns).contains(encoder) else {
            AKWarning("hs.streamdeck.setScreenImage(): invalid encoder \(encoder)")
            return self
        }
        guard let data = HSStreamDeckImageRendering.renderScreenImage(image.image, model: model) else {
            AKWarning("hs.streamdeck.setScreenImage(): failed to render image")
            return self
        }
        writeScreenImage(Array(data), encoder: encoder)
        return self
    }

    // MARK: - Callbacks

    @objc @discardableResult func buttonCallback(_ fn: JSFunction) -> HSStreamDeckDevice {
        buttonCallbackHandler?.detach(from: self)
        buttonCallbackHandler = JSCallback(value: fn, owner: self)
        return self
    }

    @objc @discardableResult func encoderCallback(_ fn: JSFunction) -> HSStreamDeckDevice {
        encoderCallbackHandler?.detach(from: self)
        encoderCallbackHandler = JSCallback(value: fn, owner: self)
        return self
    }

    @objc @discardableResult func screenCallback(_ fn: JSFunction) -> HSStreamDeckDevice {
        screenCallbackHandler?.detach(from: self)
        screenCallbackHandler = JSCallback(value: fn, owner: self)
        return self
    }

    // MARK: - Input report handling

    func handleInputReport(_ report: [UInt8]) {
        guard isValid, report.count > 1 else { return }
        switch report[1] {
        case 0x00, 0x01: handleButtonReport(report)
        case 0x02: handleScreenReport(report)
        case 0x03: handleEncoderReport(report)
        default: break
        }
    }

    private func handleButtonReport(_ report: [UInt8]) {
        guard model.keyCount > 0 else { return }
        guard let callback = buttonCallbackHandler?.value else {
            AKWarning("hs.streamdeck: received a button input, but no callback has been set. See buttonCallback()")
            return
        }
        let offset = model.dataKeyOffset
        guard report.count >= offset + model.keyCount else { return }

        var translated = [Int](repeating: 0, count: model.keyCount + 1)
        for button in 1...model.keyCount {
            translated[model.transformKeyIndex(button)] = Int(report[offset + button - 1])
        }

        for button in 1...model.keyCount where buttonStateCache[button] != translated[button] {
            buttonStateCache[button] = translated[button]
            _ = callback.call(withArguments: [self, button, translated[button] != 0])
        }
    }

    private func handleEncoderReport(_ report: [UInt8]) {
        guard model.encoderCount > 0, report.count > 4 else { return }
        let offset = model.dataEncoderOffset
        guard report.count >= offset + model.encoderCount else { return }

        switch report[4] {
        case 0x00: // press/release
            guard let callback = encoderCallbackHandler?.value else {
                AKWarning("hs.streamdeck: received an encoder input, but no callback has been set. See encoderCallback()")
                return
            }
            for encoder in 1...model.encoderCount {
                let raw = Int(report[offset + encoder - 1])
                guard encoderStateCache[encoder] != raw else { continue }
                encoderStateCache[encoder] = raw
                _ = callback.call(withArguments: [self, encoder, raw != 0, false, false])
            }
        case 0x01: // turn
            guard let callback = encoderCallbackHandler?.value else {
                AKWarning("hs.streamdeck: received an encoder turn, but no callback has been set. See encoderCallback()")
                return
            }
            for encoder in 1...model.encoderCount {
                let value = Int(report[offset + encoder - 1])
                guard value > 0 else { continue }
                let turningLeft = value >= 200
                _ = callback.call(withArguments: [self, encoder, false, turningLeft, !turningLeft])
            }
        default:
            break
        }
    }

    private func handleScreenReport(_ report: [UInt8]) {
        guard model.hasScreen, report.count > 9 else { return }
        guard let callback = screenCallbackHandler?.value else {
            AKWarning("hs.streamdeck: received a screen input, but no callback has been set. See screenCallback()")
            return
        }

        let eventType = report[4]
        let startX = Int(report[6]) | (Int(report[7]) << 8)
        let startY = Int(report[8]) | (Int(report[9]) << 8)
        var endX = 0
        var endY = 0
        let eventName: String

        switch eventType {
        case 0x01: eventName = "shortPress"
        case 0x02: eventName = "longPress"
        case 0x03:
            guard report.count > 13 else { return }
            eventName = "swipe"
            endX = Int(report[10]) | (Int(report[11]) << 8)
            endY = Int(report[12]) | (Int(report[13]) << 8)
        default: eventName = "unknown"
        }

        _ = callback.call(withArguments: [self, eventName, startX, startY, endX, endY])
    }

    // MARK: - HID I/O: simple feature reports (reset, brightness, serial/firmware reads)

    private func writeFeatureReport(_ bytes: [UInt8]) {
        guard let reportID = bytes.first else { return }
        let result = bytes.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return unsafe IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), base, ptr.count)
        }
        if result != kIOReturnSuccess {
            AKWarning("hs.streamdeck: failed to write command to \(model.deckType) (error \(result))")
        }
    }

    private func writeSimpleReport(_ command: [UInt8]) {
        guard model.simpleReportLength > 0, !command.isEmpty else { return }
        var padded = [UInt8](repeating: 0, count: model.simpleReportLength)
        padded.replaceSubrange(0..<min(command.count, padded.count), with: command.prefix(padded.count))
        writeFeatureReport(padded)
    }

    private func readFeatureReport(resultLength: Int, reportID: Int, readOffset: Int) -> String {
        guard resultLength > 0, reportID > 0 else { return "" }
        let totalLength = resultLength + readOffset
        var buffer = [UInt8](repeating: 0, count: totalLength)
        var actualLength = CFIndex(totalLength)
        let status = buffer.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return unsafe IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), base, &actualLength)
        }
        guard status == kIOReturnSuccess, buffer.count >= readOffset + resultLength else { return "" }
        let slice = buffer[readOffset..<(readOffset + resultLength)]
        let truncated = slice.prefix { $0 != 0x00 }
        return String(bytes: truncated, encoding: .utf8) ?? ""
    }

    // MARK: - HID I/O: button image writes (one shared function per wire format)

    private func writeOutputReport(_ bytes: [UInt8]) {
        guard let reportID = bytes.first else { return }
        let result = bytes.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return unsafe IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), base, ptr.count)
        }
        if result != kIOReturnSuccess {
            AKWarning("hs.streamdeck: failed to write image data to \(model.deckType) (error \(result))")
        }
    }

    private func writeButtonImage(_ data: [UInt8], button: Int) {
        switch model.imageWriteStyle {
        case .unsupported:
            return
        case .legacyHalves:
            writeLegacyHalvesImage(data, button: button)
        case .legacyPaginated:
            writeLegacyPaginatedImage(data, button: button)
        case .v2:
            writeV2ButtonImage(data, button: button)
        }
    }

    /// Original: exactly two pages, each half the image data.
    private func writeLegacyHalvesImage(_ data: [UInt8], button: Int) {
        let half = data.count / 2
        for (pageNumber, continuationFlag, offset) in [(1, 0, 0), (2, 1, half)] {
            var header = [UInt8](repeating: 0, count: model.reportHeaderLength)
            header[0] = 0x02
            header[1] = 0x01
            header[2] = UInt8(pageNumber)
            header[4] = UInt8(continuationFlag)
            header[5] = UInt8(truncatingIfNeeded: button)

            var report = [UInt8](repeating: 0, count: model.reportLength)
            report.replaceSubrange(0..<model.reportHeaderLength, with: header)
            let end = min(offset + half, data.count)
            if offset < end {
                report.replaceSubrange(model.reportHeaderLength..<(model.reportHeaderLength + (end - offset)), with: data[offset..<end])
            }
            writeOutputReport(report)
        }
    }

    /// Mini/MiniV2: paginated, page counter + last-page bool in the header.
    private func writeLegacyPaginatedImage(_ data: [UInt8], button: Int) {
        let payloadLength = model.reportLength - model.reportHeaderLength
        guard payloadLength > 0 else { return }
        var remaining = data.count
        var pageNumber = 0
        while remaining > 0 {
            let offset = pageNumber * payloadLength
            let thisPageLength = min(remaining, payloadLength)

            var header = [UInt8](repeating: 0, count: model.reportHeaderLength)
            header[0] = 0x02
            header[1] = 0x01
            header[2] = UInt8(truncatingIfNeeded: pageNumber)
            header[4] = remaining <= payloadLength ? 1 : 0
            header[5] = UInt8(truncatingIfNeeded: button)

            var report = [UInt8](repeating: 0, count: model.reportLength)
            report.replaceSubrange(0..<model.reportHeaderLength, with: header)
            report.replaceSubrange(model.reportHeaderLength..<(model.reportHeaderLength + thisPageLength), with: data[offset..<(offset + thisPageLength)])
            writeOutputReport(report)

            remaining -= thisPageLength
            pageNumber += 1
        }
    }

    /// OriginalV2/XL/XLV2/Mk2/Plus: little-endian page-length/page-number header fields,
    /// final-page bool.
    private func writeV2ButtonImage(_ data: [UInt8], button: Int) {
        let payloadLength = model.reportLength - model.reportHeaderLength
        guard payloadLength > 0 else { return }
        var remaining = data.count
        var pageNumber = 0
        while remaining > 0 {
            let offset = pageNumber * payloadLength
            let thisPageLength = min(remaining, payloadLength)

            var header = [UInt8](repeating: 0, count: model.reportHeaderLength)
            header[0] = 0x02
            header[1] = 0x07
            header[2] = UInt8(truncatingIfNeeded: button - 1)
            header[3] = remaining <= payloadLength ? 1 : 0
            header[4] = UInt8(thisPageLength & 0xFF)
            header[5] = UInt8((thisPageLength >> 8) & 0xFF)
            header[6] = UInt8(pageNumber & 0xFF)
            header[7] = UInt8((pageNumber >> 8) & 0xFF)

            var report = [UInt8](repeating: 0, count: model.reportLength)
            report.replaceSubrange(0..<model.reportHeaderLength, with: header)
            report.replaceSubrange(model.reportHeaderLength..<(model.reportHeaderLength + thisPageLength), with: data[offset..<(offset + thisPageLength)])
            writeOutputReport(report)

            remaining -= thisPageLength
            pageNumber += 1
        }
    }

    // MARK: - HID I/O: LCD strip writes (Stream Deck Plus)

    private func writeScreenImage(_ data: [UInt8], encoder: Int) {
        guard model.hasScreen, model.encoderColumns > 0 else { return }
        let encoderWidth = model.lcdStripWidth / model.encoderColumns
        let left = (encoderWidth * encoder) - encoderWidth
        let top = 0
        let width = encoderWidth
        let height = model.lcdStripHeight

        let payloadLength = model.lcdReportLength - model.lcdReportHeaderLength
        guard payloadLength > 0 else { return }
        var remaining = data.count
        var pageNumber = 0
        while remaining > 0 {
            let offset = pageNumber * payloadLength
            let thisPageLength = min(remaining, payloadLength)

            var header = [UInt8](repeating: 0, count: model.lcdReportHeaderLength)
            header[0] = 0x02
            header[1] = 0x0c
            header[2] = UInt8(left & 0xFF)
            header[3] = UInt8((left >> 8) & 0xFF)
            header[4] = UInt8(top & 0xFF)
            header[5] = UInt8((top >> 8) & 0xFF)
            header[6] = UInt8(width & 0xFF)
            header[7] = UInt8((width >> 8) & 0xFF)
            header[8] = UInt8(height & 0xFF)
            header[9] = UInt8((height >> 8) & 0xFF)
            header[10] = remaining <= payloadLength ? 1 : 0
            header[11] = UInt8(pageNumber & 0xFF)
            header[12] = UInt8((pageNumber >> 8) & 0xFF)
            header[13] = UInt8(thisPageLength & 0xFF)
            header[14] = UInt8((thisPageLength >> 8) & 0xFF)

            var report = [UInt8](repeating: 0, count: model.lcdReportLength)
            report.replaceSubrange(0..<model.lcdReportHeaderLength, with: header)
            report.replaceSubrange(model.lcdReportHeaderLength..<(model.lcdReportHeaderLength + thisPageLength), with: data[offset..<(offset + thisPageLength)])
            writeOutputReport(report)

            remaining -= thisPageLength
            pageNumber += 1
        }
    }
}
