//
//  ExtensionBinary.swift
//  Hammerspoon 2
//

import Foundation

/// What an extension's compiled code says about where it can run, read from its Mach-O header and
/// load commands without loading it.
nonisolated struct ExtensionBinary: Equatable {
    /// The CPU types of the slices in the binary
    let architectures: [Int32]

    /// The oldest macOS the slice that would run here runs on. Nil if the binary has no slice for
    /// this Mac, or the slice doesn't say.
    let minimumOS: BuildVersion?

    static let cpuTypeARM64: Int32 = 0x0100_000C
    static let cpuTypeX86_64: Int32 = 0x0100_0007

    /// The CPU type this process runs as
    static var hostArchitecture: Int32 {
        #if arch(arm64)
        cpuTypeARM64
        #else
        cpuTypeX86_64
        #endif
    }

    enum ParseError: Error, Equatable {
        case unreadable
        case notMachO
        case truncated
    }

    /// Reads the binary at a URL.
    /// - Parameters:
    ///   - url: The binary
    ///   - architecture: The CPU type whose slice to read the deployment target from
    /// - Throws: `ParseError` if it isn't a readable 64-bit Mach-O file
    /// - Returns: What it says about where it can run
    static func read(at url: URL, architecture: Int32 = hostArchitecture) throws(ParseError) -> ExtensionBinary {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { throw .unreadable }
        return try parse(data, architecture: architecture)
    }

    /// Parses a Mach-O file, either thin or universal.
    static func parse(_ data: Data, architecture: Int32 = hostArchitecture) throws(ParseError) -> ExtensionBinary {
        let bytes = Bytes(data)
        let magic = try bytes.uint32BE(at: 0)

        // Universal binaries have a big-endian header listing each slice
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let is64 = magic == 0xCAFE_BABF
            let count = Int(try bytes.uint32BE(at: 4))
            let entrySize = is64 ? 32 : 20
            var architectures: [Int32] = []
            var slice: (offset: Int, size: Int)?
            for index in 0..<count {
                let entry = 8 + index * entrySize
                let cpuType = Int32(bitPattern: try bytes.uint32BE(at: entry))
                let offset = is64 ? Int(try bytes.uint64BE(at: entry + 8)) : Int(try bytes.uint32BE(at: entry + 8))
                let size = is64 ? Int(try bytes.uint64BE(at: entry + 16)) : Int(try bytes.uint32BE(at: entry + 12))
                architectures.append(cpuType)
                if cpuType == architecture {
                    slice = (offset, size)
                }
            }
            guard let slice else {
                return ExtensionBinary(architectures: architectures, minimumOS: nil)
            }
            guard slice.offset >= 0, slice.size >= 0, slice.offset + slice.size <= data.count else { throw .truncated }
            return ExtensionBinary(architectures: architectures, minimumOS: try thinMinimumOS(bytes, base: slice.offset))
        }

        let cpuType = Int32(bitPattern: try bytes.uint32LE(at: 4))
        guard try bytes.uint32LE(at: 0) == 0xFEED_FACF else { throw .notMachO }
        guard cpuType == architecture else {
            return ExtensionBinary(architectures: [cpuType], minimumOS: nil)
        }
        return ExtensionBinary(architectures: [cpuType], minimumOS: try thinMinimumOS(bytes, base: 0))
    }

    /// The deployment target of a 64-bit Mach-O image starting at `base`, from its
    /// LC_BUILD_VERSION (or, in old binaries, LC_VERSION_MIN_MACOSX) load command
    private static func thinMinimumOS(_ bytes: Bytes, base: Int) throws(ParseError) -> BuildVersion? {
        guard try bytes.uint32LE(at: base) == 0xFEED_FACF else { throw .notMachO }
        let commandCount = Int(try bytes.uint32LE(at: base + 16))
        var offset = base + 32  // sizeof(mach_header_64)
        for _ in 0..<commandCount {
            let command = try bytes.uint32LE(at: offset)
            let size = Int(try bytes.uint32LE(at: offset + 4))
            guard size >= 8 else { throw .truncated }
            switch command {
            case 0x32:  // LC_BUILD_VERSION: platform, minos, sdk, ntools
                return version(try bytes.uint32LE(at: offset + 12))
            case 0x24:  // LC_VERSION_MIN_MACOSX: version, sdk
                return version(try bytes.uint32LE(at: offset + 8))
            default:
                offset += size
            }
        }
        return nil
    }

    /// Decodes a Mach-O version, packed as xxxx.yy.zz in nibbles
    private static func version(_ packed: UInt32) -> BuildVersion {
        BuildVersion(Int(packed >> 16), Int((packed >> 8) & 0xFF), Int(packed & 0xFF))
    }

    /// Bounds-checked integer reads from a Mach-O file
    private struct Bytes {
        let data: Data

        init(_ data: Data) {
            self.data = data
        }

        private func bytes(at offset: Int, count: Int) throws(ParseError) -> [UInt8] {
            guard offset >= 0, offset + count <= data.count else { throw .truncated }
            let start = data.startIndex + offset
            return Array(data[start..<(start + count)])
        }

        func uint32LE(at offset: Int) throws(ParseError) -> UInt32 {
            try bytes(at: offset, count: 4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        func uint32BE(at offset: Int) throws(ParseError) -> UInt32 {
            try bytes(at: offset, count: 4).reduce(0) { $0 << 8 | UInt32($1) }
        }

        func uint64BE(at offset: Int) throws(ParseError) -> UInt64 {
            try bytes(at: offset, count: 8).reduce(0) { $0 << 8 | UInt64($1) }
        }
    }
}

/// A macOS version, such as a binary's deployment target
nonisolated struct BuildVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// The version this copy of macOS is
    static var currentOS: BuildVersion {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return BuildVersion(version.majorVersion, version.minorVersion, version.patchVersion)
    }

    var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    static func < (lhs: BuildVersion, rhs: BuildVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
