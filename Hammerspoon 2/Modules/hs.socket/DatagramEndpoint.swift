//
//  DatagramEndpoint.swift
//  Hammerspoon 2
//

import Foundation
import Darwin

// The BSD socket plumbing shared by HSUDPSocket and HSUnixDatagramSocket.

/// Whether a datagram socket is delivering datagrams to its callback.
enum DatagramReceiveMode {
    case off, continuous, once

    var isActive: Bool {
        switch self {
        case .off:
            return false
        case .continuous, .once:
            return true
        }
    }
}

/// The object that reads from a `DatagramEndpoint` when it becomes readable.
@MainActor
protocol DatagramEndpointOwner: AnyObject {
    func readDatagram(from endpoint: DatagramEndpoint)
}

/// One system datagram socket, monitored for incoming datagrams on the main run loop.
///
/// This uses CFSocket rather than a dispatch source because invalidating a CFSocket closes the
/// system socket immediately, so its port (or path) is free as soon as `close()` returns. A
/// dispatch source's descriptor may only be closed from its cancel handler, which runs later.
@MainActor
final class DatagramEndpoint {
    let fd: Int32
    let family: Int32
    weak var owner: (any DatagramEndpointOwner)?
    private var socket: CFSocket?
    private var isReading = false

    /// Takes ownership of `fd`, which is closed by `close()`, or straight away if this fails.
    init?(fd: Int32, family: Int32, owner: any DatagramEndpointOwner) {
        self.fd = fd
        self.family = family
        self.owner = owner
        var context = unsafe CFSocketContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                             retain: nil, release: nil, copyDescription: nil)
        guard let socket = unsafe CFSocketCreateWithNative(nil, fd, CFSocketCallBackType.readCallBack.rawValue,
                                                           datagramEndpointReadable, &context) else {
            _ = Darwin.close(fd)
            return nil
        }
        CFSocketDisableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
        let source = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.socket = socket
    }

    func startReading() {
        guard !isReading, let socket else { return }
        CFSocketEnableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
        isReading = true
    }

    func stopReading() {
        guard isReading, let socket else { return }
        CFSocketDisableCallBacks(socket, CFSocketCallBackType.readCallBack.rawValue)
        isReading = false
    }

    isolated deinit {
        close()
    }

    /// Removes the socket from the run loop and closes it.
    func close() {
        guard let socket else { return }
        CFSocketInvalidate(socket)
        self.socket = nil
        isReading = false
    }

    /// Receives one datagram, or returns `nil` if none is waiting.
    /// - Returns: The datagram and the sender's address, or why it couldn't be received. A
    ///   datagram larger than `maximumSize` is discarded and reported as an error, rather than
    ///   delivered cut short.
    func receive(maximumSize: Int) -> Result<(data: [UInt8], address: Data), DatagramReceiveError>? {
        // One byte more than allowed, so a larger datagram shows itself by filling it
        var buffer = [UInt8](repeating: 0, count: maximumSize + 1)
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let count = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &storage) { pointer in
                unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    unsafe recvfrom(fd, bytes.baseAddress, bytes.count, 0, address, &length)
                }
            }
        }
        guard count >= 0 else {
            let code = errno
            guard code != EAGAIN && code != EWOULDBLOCK && code != EINTR else { return nil }
            return .failure(.system(code))
        }
        guard count <= maximumSize else {
            return .failure(.tooLarge(maximumSize))
        }
        buffer.removeSubrange(count...)
        return .success((buffer, unsafe Data(bytes: &storage, count: Int(length))))
    }
}

/// Why a datagram couldn't be received.
enum DatagramReceiveError: Error {
    /// `recvfrom()` failed with this errno
    case system(Int32)
    /// The datagram was larger than this many bytes, so it was discarded
    case tooLarge(Int)

    var message: String {
        switch self {
        case .system(let code):
            return socketErrorMessage(code)
        case .tooLarge(let maximumSize):
            return "Discarded a datagram larger than \(maximumSize) bytes"
        }
    }
}

/// Called on the main run loop when one of a `DatagramEndpoint`'s sockets is readable.
///
/// `nonisolated` and at file scope, since CFSocket calls it as a C function.
nonisolated private func datagramEndpointReadable(_ socket: CFSocket?, _ type: CFSocketCallBackType, _ address: CFData?,
                                                  _ data: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) {
    guard let info = unsafe info else { return }
    let endpoint = unsafe Unmanaged<DatagramEndpoint>.fromOpaque(info).takeUnretainedValue()
    MainActor.assumeIsolated {
        endpoint.owner?.readDatagram(from: endpoint)
    }
}

// MARK: - Helpers

nonisolated func socketErrorMessage(_ code: Int32) -> String {
    unsafe String(cString: strerror(code))
}

nonisolated func currentSocketErrorMessage() -> String {
    socketErrorMessage(errno)
}

nonisolated func setSocketOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ value: Int32) {
    var value = value
    _ = unsafe setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
}

/// The longest Unix domain socket path, in bytes. `sun_path` also holds a terminating NUL.
nonisolated let maximumUnixSocketPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

/// A `sockaddr_un` for `path`, or `nil` if the path is empty or too long.
nonisolated func unixSocketAddress(path: String) -> Data? {
    let pathBytes = Array(path.utf8)
    guard !pathBytes.isEmpty, pathBytes.count <= maximumUnixSocketPathLength else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        unsafe buffer.copyBytes(from: pathBytes)
    }
    return unsafe Data(bytes: &address, count: MemoryLayout<sockaddr_un>.size)
}

/// The path in a `sockaddr_un`, or `nil` if it has none (e.g. it's from an unbound sender).
nonisolated func unixSocketPath(from address: Data) -> String? {
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
    guard address.count > pathOffset else { return nil }
    let pathBytes = address[(address.startIndex + pathOffset)...].prefix { $0 != 0 }
    guard !pathBytes.isEmpty else { return nil }
    return String(decoding: pathBytes, as: UTF8.self)
}

/// Whether something may be using the Unix domain socket at `path`, found by trying to connect:
/// a stream socket's listener accepts the connection, and a datagram socket that's still bound
/// accepts it as its peer. Only a socket file left behind by a socket that has gone refuses it
/// (`ECONNREFUSED`); anything else, such as a socket of the other type (`EPROTOTYPE`), or a
/// check that couldn't be made, counts as in use.
nonisolated func unixSocketIsInUse(at path: String, type: Int32) -> Bool {
    guard let address = unixSocketAddress(path: path) else { return true }
    let fd = socket(AF_UNIX, type, 0)
    guard fd >= 0 else { return true }
    defer { close(fd) }
    // Non-blocking, so a listener with a full backlog can't stall the main thread
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    let result = unsafe address.withUnsafeBytes { raw in
        // swiftlint:disable:next force_unwrapping
        unsafe connect(fd, raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count))
    }
    return result == 0 || (errno != ECONNREFUSED && errno != ENOENT)
}

/// Removes a socket file left at `path` by a socket that has gone, so its path can be reused.
/// - Returns: `false` if something is still using it
nonisolated func removeStaleUnixSocketFile(at path: String, type: Int32) -> Bool {
    var info = stat()
    guard unsafe lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return true }
    guard !unixSocketIsInUse(at: path, type: type) else { return false }
    unsafe unlink(path)
    return true
}
