//
//  HSNetworkPing.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import Darwin

// MARK: - ICMP constants

private let kICMPv4EchoRequestType: UInt8 = 8
private let kICMPv4EchoReplyType: UInt8 = 0
private let kICMPv6EchoRequestType: UInt8 = 128
private let kICMPv6EchoReplyType: UInt8 = 129

// MARK: - File-scope ICMP helpers (unsafe ops live here, not in the @MainActor class)

/// Builds an ICMP (v4 or v6) Echo Request packet with the given identifier and sequence number.
/// For IPv4 the checksum is computed; for IPv6 the kernel computes it (field left as 0).
private func buildICMPPacket(identifier: UInt16, sequence: UInt16, isIPv6: Bool) -> Data {
    let requestType: UInt8 = isIPv6 ? kICMPv6EchoRequestType : kICMPv4EchoRequestType
    let payloadSize = 56  // 64-byte ping − 8-byte ICMP header

    var packet = Data(capacity: 8 + payloadSize)
    packet.append(requestType)
    packet.append(0)  // code
    packet.append(0)  // checksum hi (placeholder)
    packet.append(0)  // checksum lo (placeholder)
    packet.append(UInt8(identifier >> 8))
    packet.append(UInt8(identifier & 0xFF))
    packet.append(UInt8(sequence >> 8))
    packet.append(UInt8(sequence & 0xFF))
    for i in 0..<payloadSize { packet.append(UInt8(i & 0xFF)) }

    if !isIPv6 {
        let ck = icmpChecksum(packet)
        packet[2] = UInt8(ck >> 8)
        packet[3] = UInt8(ck & 0xFF)
    }
    return packet
}

private func icmpChecksum(_ data: Data) -> UInt16 {
    var padded = data
    if padded.count % 2 != 0 { padded.append(0) }
    var sum: UInt32 = 0
    for i in stride(from: 0, to: padded.count, by: 2) {
        sum += UInt32(padded[i]) << 8 | UInt32(padded[i + 1])
    }
    while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
    return ~UInt16(truncatingIfNeeded: sum)
}

/// Creates an unprivileged ICMP datagram socket. Returns (fd, nil) on success or (-1, errorString).
/// On macOS, SOCK_DGRAM + IPPROTO_ICMP does not require root for non-sandboxed apps.
private func createICMPSocket(family: Int32) -> (fd: Int32, error: String?) {
    let proto: Int32 = family == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
    let fd = Darwin.socket(family, SOCK_DGRAM, proto)
    guard fd >= 0 else { return unsafe (-1, String(cString: unsafe strerror(errno))) }
    var ttl: Int32 = 64
    let ttlOpt: Int32 = family == AF_INET6 ? IPV6_UNICAST_HOPS : IP_TTL
    let ttlLevel: Int32 = family == AF_INET6 ? IPPROTO_IPV6 : IPPROTO_IP
    unsafe setsockopt(fd, ttlLevel, ttlOpt, &ttl, socklen_t(MemoryLayout<Int32>.size))
    return (fd, nil)
}

/// Sends `packet` to `targetAddr` via `fd`. Returns an error string on failure, nil on success.
private func sendICMPPacket(fd: Int32, packet: Data, targetAddr: Data) -> String? {
    let result = unsafe targetAddr.withUnsafeBytes { addrRaw -> Int in
        guard let addrBase = addrRaw.baseAddress else { return -1 }
        return unsafe packet.withUnsafeBytes { pktRaw -> Int in
            guard let pktBase = pktRaw.baseAddress else { return -1 }
            let sa = unsafe addrBase.assumingMemoryBound(to: sockaddr.self)
            return unsafe sendto(fd, pktBase, packet.count, 0, sa, socklen_t(targetAddr.count))
        }
    }
    return unsafe result < 0 ? String(cString: unsafe strerror(errno)) : nil
}

/// Reads one pending ICMP packet from `fd`, validates it, and returns (sequence, identifier, ttl).
/// For IPv4, received data includes the IP header; for IPv6 it does not.
/// Returns nil if the packet is not a valid echo reply for `expectedIdentifier`.
private func readICMPReply(fd: Int32, family: Int32,
                            expectedIdentifier: UInt16) -> (sequence: UInt16, identifier: UInt16, ttl: UInt8)? {
    var buffer = [UInt8](repeating: 0, count: 2048)
    let bytesRead = unsafe Darwin.recv(fd, &buffer, buffer.count, 0)
    guard bytesRead >= 8 else { return nil }

    if family == AF_INET {
        // Received: IP header + ICMP header + payload
        let ipHeaderLen = Int(buffer[0] & 0x0F) * 4
        let ttl: UInt8 = bytesRead >= 9 ? buffer[8] : 0
        guard bytesRead >= ipHeaderLen + 8 else { return nil }
        guard buffer[ipHeaderLen] == kICMPv4EchoReplyType,
              buffer[ipHeaderLen + 1] == 0 else { return nil }
        let identifier = UInt16(buffer[ipHeaderLen + 4]) << 8 | UInt16(buffer[ipHeaderLen + 5])
        guard identifier == expectedIdentifier else { return nil }
        let sequence = UInt16(buffer[ipHeaderLen + 6]) << 8 | UInt16(buffer[ipHeaderLen + 7])
        return (sequence: sequence, identifier: identifier, ttl: ttl)
    } else {
        // IPv6: received data starts directly with ICMPv6 header (no IP header)
        guard buffer[0] == kICMPv6EchoReplyType, buffer[1] == 0 else { return nil }
        let identifier = UInt16(buffer[4]) << 8 | UInt16(buffer[5])
        guard identifier == expectedIdentifier else { return nil }
        let sequence = UInt16(buffer[6]) << 8 | UInt16(buffer[7])
        return (sequence: sequence, identifier: identifier, ttl: 0)
    }
}

// MARK: - Protocol

/// Object representing an active or completed ICMP ping operation.
/// Create instances with `hs.network.ping()`.
@objc protocol HSNetworkPingAPI: HSTypeAPI, JSExport {

    /// Always `"HSNetworkPing"`.
    @objc var typeName: String { get }

    /// The resolved IP address of the target, or `"<unresolved address>"` if DNS has not yet completed.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// setTimeout(() => console.log(p.address), 500)
    /// ```
    @objc var address: String { get }

    /// The hostname or IP address string originally passed to `hs.network.ping()`.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// console.log(p.server)  // "example.com"
    /// ```
    @objc var server: String { get }

    /// The number of ICMP Echo Requests sent so far.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// setTimeout(() => console.log(p.sent + " sent"), 3000)
    /// ```
    @objc var sent: Int { get }

    /// The total number of ICMP Echo Requests to send. May be increased while the ping is running
    /// provided the new value is greater than the number already sent.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// p.count = 10
    /// ```
    @objc var count: Int { get set }

    /// Returns packet statistics for all sent packets, or for a single packet by its zero-based sequence number.
    ///
    /// Each packet object contains:
    /// - `sequenceNumber` (number) — zero-based index
    /// - `icmpIdentifier` (number) — the ICMP identifier used (may be kernel-assigned)
    /// - `status` (string) — `"sent"`, `"received"`, or `"timeout"`
    /// - `rtt` (number | null) — round-trip time in seconds, or `null` if no reply was received
    ///
    /// - Parameter sequenceNumber?: {number} Omit to get all packets as an array; pass an integer to get a single packet object, or `null` if that sequence does not exist.
    /// - Returns: {any} An array of packet objects when called without arguments, or a single packet object (or `null`).
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com", {
    ///   callback: (ping, event) => {
    ///     if (event === "didFinish") console.log(ping.packets())
    ///   }
    /// })
    /// ```
    @objc func packets(_ sequenceNumber: JSValue) -> JSValue?

    /// Returns a human-readable summary of the ping results in standard ping format.
    /// - Returns: A multi-line string with transmission statistics and round-trip timing.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com", {
    ///   callback: (ping, event) => {
    ///     if (event === "didFinish") console.log(ping.summary())
    ///   }
    /// })
    /// ```
    @objc func summary() -> String

    /// `true` while the ping is actively sending and waiting for replies.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// setTimeout(() => console.log(p.isRunning), 500)
    /// ```
    @objc var isRunning: Bool { get }

    /// `true` when the ping has been suspended with `pause()`.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// p.pause()
    /// console.log(p.isPaused)  // true
    /// ```
    @objc var isPaused: Bool { get }

    /// Suspends the ping. No further packets are sent until `resume()` is called.
    /// - Returns: This ping object if still active, or `null` if the ping has already finished.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// setTimeout(() => p.pause(), 2000)
    /// ```
    @objc @discardableResult func pause() -> HSNetworkPing?

    /// Resumes a paused ping, continuing from where it left off.
    /// - Returns: This ping object if still active, or `null` if the ping has already finished.
    /// - Example:
    /// ```js
    /// p.pause()
    /// setTimeout(() => p.resume(), 5000)
    /// ```
    @objc @discardableResult func resume() -> HSNetworkPing?

    /// Immediately stops the ping, firing the `"didFinish"` callback with statistics collected so far.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com", { count: 100 })
    /// setTimeout(() => p.cancel(), 3000)
    /// ```
    @objc func cancel()

    /// Replaces the ping's callback function.
    ///
    /// The callback receives `(ping, event, info)`:
    /// - `"didStart"` — info is the resolved IP address string.
    /// - `"didFail"` — info is an error message string.
    /// - `"sendPacketFailed"` — info is `[packetObject, errorString]`.
    /// - `"receivedPacket"` — info is the packet object.
    /// - `"didFinish"` — info is the summary string.
    ///
    /// - Parameter callback: {(ping: HSNetworkPing, event: string, info: any) => void} The new callback function.
    /// - Returns: This ping object for chaining.
    /// - Example:
    /// ```js
    /// const p = hs.network.ping("example.com")
    /// p.setCallback((ping, event, info) => {
    ///   if (event === "receivedPacket") {
    ///     console.log("RTT: " + (info.rtt * 1000).toFixed(1) + " ms")
    ///   }
    /// })
    /// ```
    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkPing
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc final class HSNetworkPing: NSObject, HSNetworkPingAPI {
    @objc var typeName = "HSNetworkPing"

    // MARK: Immutable config (set in init)
    private let _server: String
    private let _interval: TimeInterval
    private let _timeout: TimeInterval
    private let _preferFamily: Int32
    let pingID: UInt16  // internal — package-visible for tests

    // MARK: JS-visible state
    @objc private(set) var address: String = "<unresolved address>"
    @objc private(set) var server: String
    @objc private(set) var sent: Int = 0
    @objc private(set) var isRunning: Bool = false
    @objc private(set) var isPaused: Bool = false

    @objc var count: Int {
        didSet {
            if count < max(1, sent + (sent < oldValue ? 1 : 0)) { count = oldValue }
        }
    }

    // MARK: Internal state
    private var _isDone: Bool = false
    private var _received: Int = 0
    private var _pendingReplies: Int = 0
    private var _packets: [Int: [String: Any]] = [:]
    private var _sendDates: [Int: Date] = [:]
    private var _callback: JSCallback?

    // MARK: Socket & dispatch sources (all on main queue)
    private var socketFD: Int32 = -1
    private var targetAddress: Data?
    private var targetFamily: Int32 = AF_INET
    private var readSource: DispatchSourceRead?
    private var intervalSource: DispatchSourceTimer?
    private var timeoutSources: [Int: DispatchSourceTimer] = [:]
    private var nextSequence: Int = 0

    // MARK: Init

    init(server: String, count: Int, interval: TimeInterval, timeout: TimeInterval,
         preferFamily: Int32, callbackValue: JSValue?) {
        _server = server
        self.server = server
        self.count = max(1, count)
        _interval = max(0.1, interval)
        _timeout = max(0.1, timeout)
        _preferFamily = preferFamily
        pingID = UInt16.random(in: 1...UInt16.max)
        super.init()

        if let cbVal = callbackValue, cbVal.isFunction {
            _callback = JSCallback(value: cbVal, owner: self)
        }
        startResolvingAndPing()
    }

    isolated deinit {
        teardown(fireFinish: false)
        AKDebug("deinit HSNetworkPing(\(_server))")
    }

    // MARK: - HSNetworkPingAPI

    @objc func packets(_ sequenceNumber: JSValue) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        if sequenceNumber.isUndefined || sequenceNumber.isNull {
            let all = _packets.sorted { $0.key < $1.key }.map(\.value)
            return JSValue(object: all, in: context)
        }
        let seq = Int(sequenceNumber.toInt32())
        if let pkt = _packets[seq] {
            return JSValue(object: pkt, in: context)
        }
        return JSValue(nullIn: context)
    }

    @objc func summary() -> String {
        let loss = sent > 0 ? Int(100.0 * Double(sent - _received) / Double(sent)) : 0
        var lines = ["\(_server) (\(address)): \(sent) packets transmitted, \(_received) received, \(loss)% packet loss"]
        let rtts = _packets.values.compactMap { $0["rtt"] as? Double }
        if !rtts.isEmpty {
            let mn = (rtts.min() ?? 0) * 1000
            let mx = (rtts.max() ?? 0) * 1000
            let avg = rtts.reduce(0, +) / Double(rtts.count) * 1000
            unsafe lines.append(String(format: "round-trip min/avg/max = %.3f/%.3f/%.3f ms", mn, avg, mx))
        }
        return lines.joined(separator: "\n")
    }

    @objc @discardableResult func pause() -> HSNetworkPing? {
        guard !_isDone else { return nil }
        guard !isPaused else { return self }
        isPaused = true
        intervalSource?.suspend()   // nil-safe: no-op if timer not yet set up
        return self
    }

    @objc @discardableResult func resume() -> HSNetworkPing? {
        guard !_isDone else { return nil }
        guard isPaused else { return self }
        isPaused = false
        intervalSource?.resume()
        return self
    }

    @objc func cancel() {
        teardown(fireFinish: true)
    }

    @objc @discardableResult func setCallback(_ callback: JSFunction) -> HSNetworkPing {
        _callback?.detach(from: self)
        _callback = JSCallback(value: callback, owner: self)
        return self
    }

    // MARK: - Private: resolution & setup

    private func startResolvingAndPing() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let addresses = try await resolveHostnameToAddresses(_server, aiFamily: _preferFamily)
                guard !_isDone else { return }
                guard let firstAddr = addresses.first else {
                    handleFatalError("No addresses found for '\(_server)'")
                    return
                }
                targetAddress = firstAddr
                targetFamily = networkAddressFamily(from: firstAddr)
                address = networkAddressString(from: firstAddr) ?? "<unknown>"

                try openSocket()
                setupReadSource()
                setupIntervalTimer()
                isRunning = true
                fireCallback("didStart", address)
            } catch {
                guard !_isDone else { return }
                handleFatalError(error.localizedDescription)
            }
        }
    }

    private func openSocket() throws {
        let (fd, errMsg) = createICMPSocket(family: targetFamily)
        if let errMsg {
            throw NSError(domain: "hs.network.ping", code: 0,
                         userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        socketFD = fd
    }

    private func setupReadSource() {
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleReadEvent() }
        }
        // The cancel handler closes the socket so the FD is always closed exactly once.
        let fdToClose = socketFD
        source.setCancelHandler {
            if fdToClose >= 0 { _ = Darwin.close(fdToClose) }
        }
        source.resume()
        readSource = source
    }

    private func setupIntervalTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: _interval)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleIntervalFired() }
        }
        intervalSource = source
        if !isPaused {
            source.resume()
        }
        // If pause() was called before resolution completed, leave source suspended.
        // resume() will call intervalSource?.resume() when the caller is ready.
    }

    // MARK: - Private: ping cycle

    private func handleIntervalFired() {
        guard isRunning && !isPaused && !_isDone else { return }
        if sent >= count {
            intervalSource?.cancel()
            intervalSource = nil
            return
        }
        sendNextPing()
    }

    private func sendNextPing() {
        let seq = nextSequence
        nextSequence += 1
        let isIPv6 = targetFamily == AF_INET6

        guard let targetAddr = targetAddress else { return }
        let packet = buildICMPPacket(identifier: pingID, sequence: UInt16(seq & 0xFFFF), isIPv6: isIPv6)

        if let errMsg = sendICMPPacket(fd: socketFD, packet: packet, targetAddr: targetAddr) {
            let pktInfo = makePacketInfo(seq: seq, status: "error", rtt: nil)
            _packets[seq] = pktInfo
            sent += 1
            fireCallback("sendPacketFailed", [pktInfo, errMsg])
            checkIfDone()
        } else {
            _packets[seq] = makePacketInfo(seq: seq, status: "sent", rtt: nil)
            _sendDates[seq] = Date()
            _pendingReplies += 1
            sent += 1
            startTimeoutTimer(for: seq)
        }
    }

    private func startTimeoutTimer(for seq: Int) {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + _timeout)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleTimeout(seq: seq) }
        }
        source.resume()
        timeoutSources[seq] = source
    }

    private func handleTimeout(seq: Int) {
        timeoutSources.removeValue(forKey: seq)?.cancel()
        guard _packets[seq]?["status"] as? String == "sent" else { return }
        _packets[seq] = makePacketInfo(seq: seq, status: "timeout", rtt: nil)
        _sendDates.removeValue(forKey: seq)
        _pendingReplies -= 1
        checkIfDone()
    }

    private func handleReadEvent() {
        guard !_isDone else { return }
        guard let reply = readICMPReply(fd: socketFD, family: targetFamily,
                                        expectedIdentifier: pingID) else { return }
        let seq = Int(reply.sequence)
        guard _packets[seq]?["status"] as? String == "sent",
              let sendDate = _sendDates.removeValue(forKey: seq) else { return }

        let rtt = Date().timeIntervalSince(sendDate)
        timeoutSources.removeValue(forKey: seq)?.cancel()
        _pendingReplies -= 1
        _received += 1

        _packets[seq] = makePacketInfo(seq: seq, status: "received", rtt: rtt)
        fireCallback("receivedPacket", _packets[seq]!)
        checkIfDone()
    }

    private func checkIfDone() {
        guard !_isDone, sent >= count, _pendingReplies == 0 else { return }
        teardown(fireFinish: true)
    }

    // MARK: - Private: teardown

    private func teardown(fireFinish: Bool) {
        guard !_isDone else { return }
        _isDone = true
        isRunning = false
        isPaused = false

        intervalSource?.cancel()
        intervalSource = nil

        for (_, src) in timeoutSources { src.cancel() }
        timeoutSources = [:]

        // readSource cancel handler closes socketFD
        readSource?.cancel()
        readSource = nil
        socketFD = -1

        if fireFinish {
            fireCallback("didFinish", summary())
        }
        _callback?.detach(from: self)
        _callback = nil
    }

    private func handleFatalError(_ message: String) {
        guard !_isDone else { return }
        _isDone = true
        fireCallback("didFail", message)
        _callback?.detach(from: self)
        _callback = nil
    }

    // MARK: - Private: helpers

    private func fireCallback(_ event: String, _ info: Any?) {
        _ = _callback?.call(withArguments: [self, event, info ?? NSNull()])
    }

    private func makePacketInfo(seq: Int, status: String, rtt: Double?) -> [String: Any] {
        var d: [String: Any] = [
            "sequenceNumber": seq,
            "icmpIdentifier": Int(pingID),
            "status": status
        ]
        d["rtt"] = rtt.map { $0 as Any } ?? NSNull()
        return d
    }
}
