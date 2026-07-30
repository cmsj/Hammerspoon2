//
//  HSSerialPort.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin

// MARK: - ioctl constant

// IOSSIOSPEED is defined in <IOKit/serial/ioss.h> as the function-like macro
// _IOW('T', 2, speed_t), which the Clang importer does not expose to Swift.
// Computed manually here from the same _IOW formula so we don't depend on import support.
private let ioctlIOSSIOSPEED: UInt = {
    let group = UInt(UInt8(ascii: "T"))
    let number: UInt = 2
    let length = UInt(MemoryLayout<UInt32>.size)
    let ioc_in: UInt = 0x80000000
    return ioc_in | ((length & 0x1fff) << 16) | (group << 8) | number
}()

// MARK: - Protocol

/// A serial port, created via `hs.serial.createPortNamed()` or `hs.serial.createPortAtPath()`.
///
/// The port is not open until you call `open()`. Configure it (baud rate, data bits, etc.)
/// either before or after opening — configuration changes made while open are applied immediately.
///
/// Received data, and lifecycle events, are delivered via the callback registered with `setCallback()`.
/// - Example:
/// ```js
/// const port = hs.serial.createPortNamed(hs.serial.availablePortNames()[0])
/// port.baudRate = 9600
/// port.setCallback((event, data) => {
///     if (event === "received") console.log("Received: " + data)
///     if (event === "error") console.log("Error: " + data)
/// }).open()
/// port.sendData("AT\r\n")
/// ```
@objc protocol HSSerialPortAPI: HSTypeAPI, JSExport {

    /// The unique identifier assigned to this port object.
    /// - Example:
    /// ```js
    /// const port = hs.serial.createPortAtPath("/dev/cu.usbserial-1420")
    /// console.log(port.identifier)
    /// ```
    @objc var identifier: String { get }

    /// The port's name (e.g. `"usbserial-1420"`).
    /// - Example:
    /// ```js
    /// console.log(port.name)
    /// ```
    @objc var name: String { get }

    /// The port's device path (e.g. `"/dev/cu.usbserial-1420"`).
    /// - Example:
    /// ```js
    /// console.log(port.path)
    /// ```
    @objc var path: String { get }

    /// Whether the port is currently open.
    /// - Example:
    /// ```js
    /// console.log(port.isOpen)
    /// ```
    @objc var isOpen: Bool { get }

    /// The baud rate, in bits per second. Default is `115200`.
    ///
    /// Setting a non-standard value (i.e. not one of 300, 1200, 2400, 4800, 9600, 14400,
    /// 19200, 28800, 38400, 57600, 115200, 230400) is rejected unless `allowNonStandardBaudRates`
    /// is `true`.
    /// - Example:
    /// ```js
    /// port.baudRate = 9600
    /// ```
    @objc var baudRate: Int { get set }

    /// Whether `baudRate` may be set to a value outside the standard set. Default is `false`.
    /// - Example:
    /// ```js
    /// port.allowNonStandardBaudRates = true
    /// port.baudRate = 123456
    /// ```
    @objc var allowNonStandardBaudRates: Bool { get set }

    /// The number of data bits, 5–8. Default is `8`.
    /// - Example:
    /// ```js
    /// port.dataBits = 7
    /// ```
    @objc var dataBits: Int { get set }

    /// The number of stop bits, 1 or 2. Default is `1`.
    /// - Example:
    /// ```js
    /// port.stopBits = 2
    /// ```
    @objc var stopBits: Int { get set }

    /// The parity mode: `"none"`, `"odd"`, or `"even"`. Default is `"none"`.
    /// - Example:
    /// ```js
    /// port.parity = "even"
    /// ```
    @objc var parity: String { get set }

    /// The state of the DTR (Data Terminal Ready) control line. Default is `false`.
    /// - Example:
    /// ```js
    /// port.dtr = true
    /// ```
    @objc var dtr: Bool { get set }

    /// The state of the RTS (Request To Send) control line. Default is `false`.
    /// - Example:
    /// ```js
    /// port.rts = true
    /// ```
    @objc var rts: Bool { get set }

    /// Whether to use hardware RTS/CTS flow control. Default is `false`.
    /// - Example:
    /// ```js
    /// port.usesRTSCTSFlowControl = true
    /// ```
    @objc var usesRTSCTSFlowControl: Bool { get set }

    /// Whether to use hardware DTR/DSR flow control. Default is `false`.
    /// - Example:
    /// ```js
    /// port.usesDTRDSRFlowControl = true
    /// ```
    @objc var usesDTRDSRFlowControl: Bool { get set }

    /// Whether data sent with `sendData()` is also delivered back to the callback
    /// as a `"received"` event, simulating local echo. Default is `false`.
    /// - Example:
    /// ```js
    /// port.shouldEchoReceivedData = true
    /// ```
    @objc var shouldEchoReceivedData: Bool { get set }

    /// Opens the port using its current configuration.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// port.setCallback((event, data) => console.log(event, data)).open()
    /// ```
    @objc @discardableResult func open() -> HSSerialPort

    /// Closes the port.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// port.close()
    /// ```
    @objc @discardableResult func close() -> HSSerialPort

    /// Sends data through the port.
    ///
    /// The string is transmitted as raw bytes: each character's code point (0–255) becomes
    /// one byte on the wire. This lets you round-trip arbitrary binary data — build the string
    /// with `String.fromCharCode()` for non-text payloads.
    /// - Parameter value: The data to send
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// port.sendData("AT\r\n")
    /// ```
    @objc @discardableResult func sendData(_ value: String) -> HSSerialPort

    /// Sets the callback invoked for port lifecycle events and received data.
    ///
    /// The callback receives two arguments: an event type string and a data string.
    /// - `"opened"` — the port was opened; data is empty
    /// - `"closed"` — the port was closed; data is empty
    /// - `"received"` — data arrived; data holds the received bytes (see `sendData()` for encoding)
    /// - `"removed"` — the underlying device disappeared; the port is closed automatically
    /// - `"error"` — an error occurred; data holds a description
    /// - Parameter fn: {(event: string, data: string) => void} Called on port events
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// port.setCallback((event, data) => console.log(event, data))
    /// ```
    @objc func setCallback(_ fn: JSFunction) -> HSSerialPort

    /// Closes the port and releases all resources. Called automatically during shutdown.
    /// - Example:
    /// ```js
    /// port.destroy()
    /// ```
    @objc func destroy()
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSSerialPort: NSObject, HSSerialPortAPI {
    @objc var typeName = "HSSerialPort"
    @objc let identifier = UUID().uuidString
    @objc let name: String
    @objc let path: String

    static let standardBaudRates: Set<Int> = [300, 1200, 2400, 4800, 9600, 14400, 19200, 28800, 38400, 57600, 115200, 230400]
    private static let ioQueue = DispatchQueue(label: "hs.serial.io", qos: .utility)

    // Written from the main actor only; read from ioQueue in the read source's event handler.
    // Safe without atomics: open() writes fd/generation before resuming the read source
    // (happens-before all its events); close() writes after ioQueue.sync (happens-after all
    // in-flight reads), mirroring the pattern in HSPathWatcher.
    nonisolated(unsafe) private var fd: Int32 = -1
    nonisolated(unsafe) fileprivate var generation: Int = 0

    private var readSource: DispatchSourceRead?
    private var callback: JSCallback?
    private var selfRetain: HSSerialPort?

    @objc var isOpen: Bool { fd != -1 }

    private var _baudRate = 115200
    @objc var baudRate: Int {
        get { _baudRate }
        set {
            guard newValue > 0 else {
                AKWarning("hs.serial: invalid baudRate \(newValue)")
                return
            }
            if !allowNonStandardBaudRates && !HSSerialPort.standardBaudRates.contains(newValue) {
                AKWarning("hs.serial: baudRate \(newValue) is non-standard; set allowNonStandardBaudRates = true to use it")
                return
            }
            _baudRate = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    @objc var allowNonStandardBaudRates = false

    private var _dataBits = 8
    @objc var dataBits: Int {
        get { _dataBits }
        set {
            guard (5...8).contains(newValue) else {
                AKWarning("hs.serial: invalid dataBits \(newValue) (must be 5-8)")
                return
            }
            _dataBits = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    private var _stopBits = 1
    @objc var stopBits: Int {
        get { _stopBits }
        set {
            guard newValue == 1 || newValue == 2 else {
                AKWarning("hs.serial: invalid stopBits \(newValue) (must be 1 or 2)")
                return
            }
            _stopBits = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    private var _parity = "none"
    @objc var parity: String {
        get { _parity }
        set {
            guard ["none", "odd", "even"].contains(newValue) else {
                AKWarning("hs.serial: invalid parity '\(newValue)' (must be 'none', 'odd', or 'even')")
                return
            }
            _parity = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    private var _dtr = false
    @objc var dtr: Bool {
        get { _dtr }
        set {
            _dtr = newValue
            if isOpen { applyControlLine(bit: TIOCM_DTR, enabled: newValue) }
        }
    }

    private var _rts = false
    @objc var rts: Bool {
        get { _rts }
        set {
            _rts = newValue
            if isOpen { applyControlLine(bit: TIOCM_RTS, enabled: newValue) }
        }
    }

    private var _usesRTSCTSFlowControl = false
    @objc var usesRTSCTSFlowControl: Bool {
        get { _usesRTSCTSFlowControl }
        set {
            _usesRTSCTSFlowControl = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    private var _usesDTRDSRFlowControl = false
    @objc var usesDTRDSRFlowControl: Bool {
        get { _usesDTRDSRFlowControl }
        set {
            _usesDTRDSRFlowControl = newValue
            if isOpen { applyTermiosSettings() }
        }
    }

    @objc var shouldEchoReceivedData = false

    init(name: String, path: String) {
        self.name = name
        self.path = path
        super.init()
    }

    isolated deinit {
        destroy()
        AKDebug("deinit of HSSerialPort(\(identifier))")
    }

    // MARK: - API

    @objc @discardableResult func open() -> HSSerialPort {
        guard !isOpen else { return self }

        let openedFD = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
        guard openedFD != -1 else {
            let message = String(cString: strerror(errno))
            AKError("hs.serial: failed to open \(path): \(message)")
            fireCallback(event: "error", data: "Failed to open port: \(message)")
            return self
        }

        fd = openedFD
        generation &+= 1
        applyTermiosSettings()
        applyControlLine(bit: TIOCM_DTR, enabled: _dtr)
        applyControlLine(bit: TIOCM_RTS, enabled: _rts)
        startReading()
        selfRetain = self
        AKTrace("HSSerialPort(\(identifier)): opened \(path)")
        fireCallback(event: "opened", data: "")
        return self
    }

    @objc @discardableResult func close() -> HSSerialPort {
        guard isOpen else { return self }
        performClose()
        fireCallback(event: "closed", data: "")
        return self
    }

    @objc @discardableResult func sendData(_ value: String) -> HSSerialPort {
        guard isOpen else {
            fireCallback(event: "error", data: "Cannot send data: port is not open")
            return self
        }
        guard let data = value.data(using: .isoLatin1) else {
            fireCallback(event: "error", data: "Cannot send data: string contains characters outside Latin-1 range")
            return self
        }

        let localFD = fd
        let capturedGeneration = generation
        let echo = shouldEchoReceivedData
        let bytes = [UInt8](data)

        HSSerialPort.ioQueue.async {
            var remaining = bytes[...]
            var attempts = 0
            while !remaining.isEmpty && attempts < 2000 {
                let written = remaining.withUnsafeBufferPointer { ptr -> Int in
                    Darwin.write(localFD, ptr.baseAddress, ptr.count)
                }
                if written > 0 {
                    remaining = remaining.dropFirst(written)
                    attempts = 0
                    continue
                }
                let err = errno
                if written == -1 && (err == EAGAIN || err == EWOULDBLOCK || err == EINTR) {
                    attempts += 1
                    usleep(1000)
                    continue
                }
                let message = String(cString: strerror(err))
                Task { @MainActor [weak self] in
                    guard let self, self.generation == capturedGeneration else { return }
                    self.fireCallback(event: "error", data: "Write failed: \(message)")
                }
                return
            }

            if !remaining.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == capturedGeneration else { return }
                    self.fireCallback(event: "error", data: "Write timed out")
                }
                return
            }

            if echo {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == capturedGeneration else { return }
                    self.fireCallback(event: "received", data: value)
                }
            }
        }
        return self
    }

    @objc func setCallback(_ fn: JSFunction) -> HSSerialPort {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    @objc func destroy() {
        performClose()
        callback?.detach(from: self)
        callback = nil
    }

    // MARK: - Private: teardown

    fileprivate func performClose() {
        guard isOpen else { return }
        readSource?.cancel()
        HSSerialPort.ioQueue.sync {}  // drain in-flight reads/writes before invalidating fd
        generation &+= 1
        Darwin.close(fd)
        fd = -1
        readSource = nil
        selfRetain = nil
        AKTrace("HSSerialPort(\(identifier)): closed")
    }

    // MARK: - Private: termios / control lines

    private func applyTermiosSettings() {
        guard isOpen else { return }
        var options = termios()
        tcgetattr(fd, &options)
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)

        options.c_cflag &= ~tcflag_t(CSIZE)
        switch _dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        default: options.c_cflag |= tcflag_t(CS8)
        }

        if _stopBits == 2 {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }

        switch _parity {
        case "odd":
            options.c_cflag |= tcflag_t(PARENB | PARODD)
        case "even":
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        default:
            options.c_cflag &= ~tcflag_t(PARENB)
        }

        if _usesRTSCTSFlowControl {
            options.c_cflag |= tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        } else {
            options.c_cflag &= ~tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        }

        if _usesDTRDSRFlowControl {
            options.c_cflag |= tcflag_t(CDTR_IFLOW | CDSR_OFLOW)
        } else {
            options.c_cflag &= ~tcflag_t(CDTR_IFLOW | CDSR_OFLOW)
        }

        tcsetattr(fd, TCSANOW, &options)

        var speed = UInt32(_baudRate)
        _ = withUnsafeMutablePointer(to: &speed) { ptr in
            ioctl(fd, ioctlIOSSIOSPEED, ptr)
        }
    }

    private func applyControlLine(bit: Int32, enabled: Bool) {
        guard isOpen else { return }
        var status: Int32 = 0
        guard ioctl(fd, UInt(TIOCMGET), &status) == 0 else { return }
        if enabled {
            status |= bit
        } else {
            status &= ~bit
        }
        _ = ioctl(fd, UInt(TIOCMSET), &status)
    }

    // MARK: - Private: reading

    private func startReading() {
        let localFD = fd
        let capturedGeneration = unsafe generation
        let source = DispatchSource.makeReadSource(fileDescriptor: localFD, queue: HSSerialPort.ioQueue)
        source.setEventHandler(handler: hsSerialPortReadHandler(fd: localFD, generation: capturedGeneration, port: self))
        source.resume()
        readSource = source
    }

    // MARK: - Fileprivate: callback (called from the file-scope read handler below)

    fileprivate func fireCallback(event: String, data: String) {
        _ = callback?.value?.call(withArguments: [event, data])
    }
}

// MARK: - Background read handler

// This must be a file-scope function, not a closure written inline in an @MainActor
// method: DispatchSourceRead invokes its handler synchronously on HSSerialPort.ioQueue,
// but a closure literal lexically inside a @MainActor method inherits @MainActor
// isolation under this project's default actor isolation setting. That mismatch trips
// a runtime isolation check (dispatch_assert_queue) and crashes. A nonisolated file-scope
// function sidesteps the inference entirely, mirroring HSPathWatcher's top-level C callback.
nonisolated private func hsSerialPortReadHandler(fd: Int32, generation: Int, port: HSSerialPort) -> () -> Void {
    return {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = buffer.withUnsafeMutableBytes { ptr -> Int in
            unsafe Darwin.read(fd, ptr.baseAddress, ptr.count)
        }

        if count > 0 {
            let text = String(bytes: buffer[0..<count], encoding: .isoLatin1) ?? ""
            Task { @MainActor in
                guard unsafe port.generation == generation else { return }
                port.fireCallback(event: "received", data: text)
            }
        } else if count == 0 {
            Task { @MainActor in
                guard unsafe port.generation == generation else { return }
                port.fireCallback(event: "removed", data: "")
                port.performClose()
            }
        } else {
            let err = errno
            guard err != EAGAIN && err != EWOULDBLOCK && err != EINTR else { return }
            let message = unsafe String(cString: strerror(err))
            Task { @MainActor in
                guard unsafe port.generation == generation else { return }
                port.fireCallback(event: "error", data: message)
                port.performClose()
            }
        }
    }
}
