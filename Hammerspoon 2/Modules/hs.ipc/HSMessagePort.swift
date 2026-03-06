//
//  HSMessagePort.swift
//  Hammerspoon 2
//
//  Created on 2025-12-27.
//  CFMessagePort wrapper for JavaScript bridge
//

@preconcurrency @unsafe import Foundation
@preconcurrency @unsafe import JavaScriptCore

/// Protocol for JavaScript export
@objc protocol HSMessagePortAPI: JSExport {
    /// Port name
    @objc var name: String { get }

    /// Check if port is valid
    @objc var isValid: Bool { get }

    /// Check if port is remote (vs local)
    @objc var isRemote: Bool { get }

    /// Send a message to the port
    @objc func sendMessage(_ data: JSValue, _ msgID: NSNumber, _ timeout: NSNumber?, _ oneWay: Bool) -> JSValue

    /// Delete and invalidate the port
    @objc func delete()
}

/// Message port wrapper class
@MainActor
@objc class HSMessagePort: NSObject, HSTypeAPI, HSMessagePortAPI {
    // MARK: - Properties

    /// Port name
    @objc let name: String

    /// Is this a remote port (vs local server port)
    @objc let isRemote: Bool

    /// Underlying CFMessagePort reference
    private var messagePort: CFMessagePort?

    /// JavaScript callback function (for local ports)
    private var callbackRef: JSValue?

    /// Run loop source for local ports
    private var runLoopSource: CFRunLoopSource?

    /// Recursive call depth tracking
    nonisolated(unsafe) private static var callDepth: Int = 0
    private static let maxCallDepth: Int = 5

    // MARK: - HSTypeAPI

    @objc var typeName: String { "HSMessagePort" }

    // MARK: - Initialization

    /// Initialize a local (server) message port
    init?(localPortName: String, callback: JSValue) {
        self.name = localPortName
        self.isRemote = false
        self.callbackRef = callback

        super.init()

        // Create context for callback
        // Use passUnretained + retain/release callbacks for proper memory management
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { (info: UnsafeRawPointer?) -> UnsafeRawPointer? in
                guard let info = info else { return nil }
                // Retain the HSMessagePort object
                _ = Unmanaged<HSMessagePort>.fromOpaque(info).retain()
                return info
            },
            release: { (info: UnsafeRawPointer?) in
                guard let info = info else { return }
                // Release the HSMessagePort object
                Unmanaged<HSMessagePort>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        // Create local port
        // DEFENSIVE: Returns nil if port creation fails (e.g., port name in use, OS limits)
        var shouldFreeInfo: DarwinBoolean = false
        guard let port = CFMessagePortCreateLocal(
            nil,
            localPortName as CFString,
            { port, msgID, data, info in
                return HSMessagePort.messagePortCallback(port, msgID, data, info)
            },
            &context,
            &shouldFreeInfo
        ) else {
            AKError("Failed to create local message port '\(localPortName)' - port may be in use or OS resource limit reached")
            return nil
        }

        self.messagePort = port

        // Add to run loop
        let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.runLoopSource = source

        AKTrace("Created local message port '\(localPortName)'")
    }

    /// Initialize a remote (client) message port
    init?(remotePortName: String) {
        self.name = remotePortName
        self.isRemote = true
        self.callbackRef = nil
        self.runLoopSource = nil

        super.init()

        // Create remote port
        // DEFENSIVE: Returns nil if port creation fails (e.g., hitting OS limits)
        guard let port = CFMessagePortCreateRemote(nil, remotePortName as CFString) else {
            AKError("Failed to create remote message port '\(remotePortName)' - possible OS resource limit")
            return nil
        }

        self.messagePort = port
        AKTrace("Created remote message port '\(remotePortName)'")
    }

    deinit {
        // Inline cleanup since deinit is nonisolated and cleanup() is MainActor-isolated
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        if let port = messagePort {
            CFMessagePortInvalidate(port)
        }
    }

    // MARK: - CFMessagePort Callback

    /// Static callback function for CFMessagePort
    private static func messagePortCallback(
        _ port: CFMessagePort?,
        _ msgID: Int32,
        _ data: CFData?,
        _ info: UnsafeMutableRawPointer?
    ) -> Unmanaged<CFData>? {
        // Check recursion depth
        guard callDepth < maxCallDepth else {
            AKError("Message port callback recursion depth exceeded (max: \(maxCallDepth))")
            let errorData = "Error: Recursion depth exceeded".data(using: .utf8)!
            return Unmanaged.passRetained(errorData as CFData)
        }

        callDepth += 1
        defer { callDepth -= 1 }

        // Get self reference
        guard let info = info else {
            AKError("Message port callback: missing info pointer")
            return nil
        }

        let messagePort = Unmanaged<HSMessagePort>.fromOpaque(info).takeUnretainedValue()

        // Get callback function
        guard let callback = messagePort.callbackRef, callback.isObject else {
            AKError("Message port callback: invalid callback function")
            return nil
        }

        // Convert data to JSValue
        let context = callback.context
        let dataValue: JSValue
        if let data = data {
            let nsData = data as Data
            if let string = String(data: nsData, encoding: .utf8) {
                dataValue = JSValue(object: string, in: context)
            } else {
                // If not valid UTF-8, pass as base64
                let base64 = nsData.base64EncodedString()
                dataValue = JSValue(object: base64, in: context)
            }
        } else {
            dataValue = JSValue(nullIn: context)
        }

        // Create port JSValue
        let portValue = JSValue(object: messagePort, in: context)

        // Create msgID JSValue
        let msgIDValue = JSValue(int32: msgID, in: context)

        // Invoke callback: callback(port, msgID, data)
        guard let result = callback.call(withArguments: [portValue as Any, msgIDValue as Any, dataValue as Any]) else {
            AKError("Message port callback invocation failed")
            return nil
        }

        // Convert result to CFData
        if result.isUndefined || result.isNull {
            return nil
        }

        // Convert to string
        let resultString = result.toString() ?? ""
        guard let resultData = resultString.data(using: .utf8) else {
            return nil
        }

        return Unmanaged.passRetained(resultData as CFData)
    }

    // MARK: - Public API

    /// Check if port is valid
    @objc var isValid: Bool {
        guard let port = messagePort else { return false }
        return CFMessagePortIsValid(port)
    }

    /// Send a message to the port
    @objc func sendMessage(_ data: JSValue, _ msgID: NSNumber, _ timeout: NSNumber?, _ oneWay: Bool) -> JSValue {
        guard let port = messagePort, isValid else {
            AKError("Port '\(name)' is invalid or nil")
            return JSValue(bool: false, in: data.context)
        }

        // Convert data to CFData
        let dataString = data.toString()
        guard let messageData = dataString?.data(using: .utf8) else {
            AKError("Failed to convert data to UTF8")
            return JSValue(bool: false, in: data.context)
        }

        let cfData = messageData as CFData
        let messageID = msgID.int32Value

        // Determine timeout
        let sendTimeout: CFTimeInterval = timeout?.doubleValue ?? 4.0
        let recvTimeout: CFTimeInterval = oneWay ? 0 : sendTimeout

        // Send message
        let result: Int32
        var returnDataPtr: Unmanaged<CFData>?

        if oneWay {
            result = CFMessagePortSendRequest(
                port,
                messageID,
                cfData,
                sendTimeout,
                0,
                nil,
                nil
            )
        } else {
            result = withUnsafeMutablePointer(to: &returnDataPtr) { ptr in
                CFMessagePortSendRequest(
                    port,
                    messageID,
                    cfData,
                    sendTimeout,
                    recvTimeout,
                    CFRunLoopMode.defaultMode.rawValue as CFString,
                    ptr
                )
            }
        }

        if result != kCFMessagePortSuccess {
            AKError("Failed to send message to port '\(name)': error code \(result)")
            return JSValue(bool: false, in: data.context)
        }

        // Return response if not one-way
        if !oneWay, let returnData = returnDataPtr {
            let responseData = returnData.takeRetainedValue() as Data
            if let responseString = String(data: responseData, encoding: .utf8) {
                return JSValue(object: responseString, in: data.context)
            }
        }

        return JSValue(bool: true, in: data.context)
    }

    /// Delete and invalidate the port
    @objc func delete() {
        cleanup()
    }

    // MARK: - Private Methods

    private func cleanup() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }

        if let port = messagePort {
            // Invalidate the port - this will trigger the release callback
            CFMessagePortInvalidate(port)
            messagePort = nil
        }

        callbackRef = nil
    }
}
