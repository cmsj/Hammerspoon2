//
//  hs2vnc.swift
//  Minimal RFB (VNC) client for driving Hammerspoon 2 test VMs from the host.
//
//  Talks to the Virtualization.framework VNC server that `tart run --vnc-experimental`
//  exposes, so screenshots need no Screen Recording grant inside the guest and never
//  touch the host's own display.
//
//  Usage:
//    hs2vnc <vnc-url> screenshot <out.png>
//
//  <vnc-url> is what tart prints, e.g. vnc://:password@127.0.0.1:59123
//

import Foundation
import CommonCrypto
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let debugEnabled = ProcessInfo.processInfo.environment["HS2VNC_DEBUG"] != nil
func debug(_ message: @autoclosure () -> String) {
    if debugEnabled { FileHandle.standardError.write(Data("hs2vnc: \(message())\n".utf8)) }
}

struct VNCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class RFBConnection {
    private let fd: Int32
    private(set) var width = 0
    private(set) var height = 0

    init(host: String, port: UInt16) throws {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                             ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let info = result else {
            throw VNCError("cannot resolve \(host)")
        }
        defer { freeaddrinfo(result) }
        fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw VNCError("socket() failed") }
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            close(fd)
            throw VNCError("cannot connect to \(host):\(port)")
        }
    }

    deinit { close(fd) }

    // MARK: Raw I/O

    func read(_ count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, count - offset) }
            guard n > 0 else { throw VNCError("connection closed by server") }
            offset += n
        }
        return buffer
    }

    func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, bytes.count - offset) }
            guard n > 0 else { throw VNCError("write failed") }
            offset += n
        }
    }

    func readU8() throws -> UInt8 { try read(1)[0] }
    func readU16() throws -> Int { let b = try read(2); return Int(b[0]) << 8 | Int(b[1]) }
    func readU32() throws -> Int {
        let b = try read(4)
        return Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
    }

    // MARK: Handshake

    func handshake(password: String?) throws {
        let version = String(decoding: try read(12), as: UTF8.self)
        guard version.hasPrefix("RFB 003.") else { throw VNCError("not an RFB server: \(version)") }
        try write(Array("RFB 003.008\n".utf8))

        let typeCount = Int(try readU8())
        if typeCount == 0 {
            throw VNCError("server refused connection: \(try readReason())")
        }
        let types = try read(typeCount)
        if types.contains(2), let password {
            try write([2])
            let challenge = try read(16)
            try write(try Self.vncAuthResponse(challenge: challenge, password: password))
        } else if types.contains(1) {
            try write([1])
        } else {
            throw VNCError("no supported security type in \(types) (password given: \(password != nil))")
        }
        if try readU32() != 0 {
            throw VNCError("authentication failed: \(try readReason())")
        }

        try write([1]) // ClientInit, shared session
        width = try readU16()
        height = try readU16()
        _ = try read(16) // server pixel format; we override it below
        _ = try read(try readU32()) // desktop name
        debug("server init \(width)x\(height)")

        // 32bpp little-endian true colour, red in bits 16-23: lands in memory as BGRX.
        try write([0, 0, 0, 0,
                   32, 24, 0, 1,
                   0, 255, 0, 255, 0, 255,
                   16, 8, 0,
                   0, 0, 0])
        // Raw, plus the DesktopSize and ExtendedDesktopSize pseudo-encodings. Virtualization.framework's
        // VNC server traps (killing the whole VM) if a client doesn't advertise the resize encodings.
        try write([2, 0] + Self.u16(3) + Self.s32(0) + Self.s32(-223) + Self.s32(-308))
    }

    static func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xff), UInt8(value & 0xff)] }
    static func s32(_ value: Int32) -> [UInt8] {
        let bits = UInt32(bitPattern: value)
        return [UInt8(bits >> 24), UInt8(bits >> 16 & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits & 0xff)]
    }

    private func readReason() throws -> String {
        String(decoding: try read(try readU32()), as: UTF8.self)
    }

    /// VNC authentication: DES-ECB encrypt the challenge with the password, whose
    /// bytes are bit-reversed (an RFB quirk) and padded/truncated to 8 bytes.
    static func vncAuthResponse(challenge: [UInt8], password: String) throws -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 8)
        for (i, byte) in password.utf8.prefix(8).enumerated() {
            var reversed: UInt8 = 0
            for bit in 0..<8 where byte & (1 << bit) != 0 {
                reversed |= 1 << (7 - bit)
            }
            key[i] = reversed
        }
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES),
                             CCOptions(kCCOptionECBMode), key, key.count, nil,
                             challenge, challenge.count, &out, out.count, &moved)
        guard status == kCCSuccess else { throw VNCError("DES failed: \(status)") }
        return out
    }

    // MARK: Framebuffer

    private func requestFullUpdate() throws {
        try write([3, 0, 0, 0, 0, 0] + Self.u16(width) + Self.u16(height))
    }

    /// Requests a full (non-incremental) update and returns it as BGRX pixels.
    /// If the server reports a desktop resize first, the request is repeated at the new size.
    func captureFramebuffer() throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try requestFullUpdate()
        while true {
            let type = try readU8()
            switch type {
            case 0: // FramebufferUpdate
                _ = try read(1)
                let rectCount = try readU16()
                var resized = false
                var gotPixels = false
                for _ in 0..<rectCount {
                    let x = try readU16(), y = try readU16()
                    let w = try readU16(), h = try readU16()
                    let encoding = Int32(bitPattern: UInt32(try readU32()))
                    debug("rect \(x),\(y) \(w)x\(h) encoding \(encoding)")
                    switch encoding {
                    case 0: // Raw
                        let rowBytes = w * 4
                        for row in 0..<h {
                            let line = try read(rowBytes)
                            let start = ((y + row) * width + x) * 4
                            pixels.replaceSubrange(start..<start + rowBytes, with: line)
                        }
                        gotPixels = true
                    case -223, -308: // DesktopSize, ExtendedDesktopSize
                        if encoding == -308 {
                            let screenCount = Int(try readU8())
                            _ = try read(3 + screenCount * 16)
                        }
                        if w != width || h != height {
                            width = w
                            height = h
                            pixels = [UInt8](repeating: 0, count: width * height * 4)
                            resized = true
                        }
                    default:
                        throw VNCError("unexpected encoding \(encoding)")
                    }
                }
                if resized {
                    try requestFullUpdate()
                } else if gotPixels {
                    return pixels
                }
            case 2: // Bell
                continue
            case 3: // ServerCutText
                _ = try read(3)
                _ = try read(try readU32())
            default:
                throw VNCError("unexpected server message \(type)")
            }
        }
    }
}

func writePNG(pixels: [UInt8], width: Int, height: Int, to path: String) throws {
    let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                            | CGImageAlphaInfo.noneSkipFirst.rawValue)
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: info, provider: provider, decode: nil,
                              shouldInterpolate: false, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                           UTType.png.identifier as CFString, 1, nil)
    else { throw VNCError("cannot create PNG") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw VNCError("cannot write \(path)") }
}

func run() throws {
    let args = CommandLine.arguments
    guard args.count >= 3, let url = URLComponents(string: args[1]), url.scheme == "vnc" else {
        throw VNCError("usage: hs2vnc vnc://:password@host:port screenshot <out.png>")
    }
    func connect() throws -> RFBConnection {
        let connection = try RFBConnection(host: url.host ?? "127.0.0.1", port: UInt16(url.port ?? 5900))
        try connection.handshake(password: url.password?.removingPercentEncoding)
        return connection
    }

    switch args[2] {
    case "screenshot":
        guard args.count == 4 else { throw VNCError("usage: hs2vnc <url> screenshot <out.png>") }
        // The first connection after a VM boots gets a placeholder all-black 1280x720 framebuffer;
        // reconnecting yields the real display.
        var attempt = 0
        while true {
            attempt += 1
            let connection = try connect()
            let pixels = try connection.captureFramebuffer()
            let isBlank = stride(from: 0, to: pixels.count, by: 4).allSatisfy {
                pixels[$0] == 0 && pixels[$0 + 1] == 0 && pixels[$0 + 2] == 0
            }
            if isBlank && attempt < 5 {
                debug("blank framebuffer on attempt \(attempt), reconnecting")
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            try writePNG(pixels: pixels, width: connection.width, height: connection.height, to: args[3])
            print("\(args[3]) (\(connection.width)x\(connection.height))")
            break
        }
    default:
        throw VNCError("unknown command \(args[2])")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("hs2vnc: \(error)\n".utf8))
    exit(1)
}
