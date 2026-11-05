//
//  ZipFixture.swift
//  Hammerspoon 2Tests
//

import Foundation

/// Builds small, uncompressed zip archives in memory, for tests that need archives with exact
/// contents: particular layouts, an archive comment, symlinks, or unsafe paths no zip tool writes.
struct ZipFixture {
    private struct Entry {
        let path: String
        let data: Data
        let mode: UInt32
    }

    private var entries: [Entry] = []
    var comment = ""

    /// Adds a file, creating no directory entries for its parents (as many zip tools don't)
    mutating func file(_ path: String, _ contents: String) {
        entries.append(Entry(path: path, data: Data(contents.utf8), mode: 0o100644))
    }

    mutating func directory(_ path: String) {
        entries.append(Entry(path: path.hasSuffix("/") ? path : path + "/", data: Data(), mode: 0o040755))
    }

    mutating func symlink(_ path: String, to target: String) {
        entries.append(Entry(path: path, data: Data(target.utf8), mode: 0o120777))
    }

    /// Adds a well-formed Spoon at `directory` (pass "" for the archive's root)
    mutating func spoon(at directory: String, name: String, version: String = "1.0.0", initJS: String? = nil) {
        let prefix = directory.isEmpty ? "" : directory + "/"
        file(prefix + "spoon.json", """
            { "name": "\(name)", "author": "A. Developer", "version": "\(version)", "description": "The \(name) Spoon." }
            """)
        file(prefix + "init.js", initJS ?? "module.exports = { name: '\(name)', version: '\(version)' };")
    }

    var data: Data {
        var archive = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = Self.crc32(entry.data)
            let offset = UInt32(archive.count)

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)          // version needed
            archive.append(le16: 0x0800)      // UTF-8 names
            archive.append(le16: 0)           // stored
            archive.append(le16: 0)           // time
            archive.append(le16: 0x21)        // date: 1980-01-01
            archive.append(le32: crc)
            archive.append(le32: UInt32(entry.data.count))
            archive.append(le32: UInt32(entry.data.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(entry.data)

            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 3 << 8 | 20)  // made by Unix
            directory.append(le16: 20)
            directory.append(le16: 0x0800)
            directory.append(le16: 0)
            directory.append(le16: 0)
            directory.append(le16: 0x21)
            directory.append(le32: crc)
            directory.append(le32: UInt32(entry.data.count))
            directory.append(le32: UInt32(entry.data.count))
            directory.append(le16: UInt16(name.count))
            directory.append(le16: 0)         // extra
            directory.append(le16: 0)         // comment
            directory.append(le16: 0)         // disk
            directory.append(le16: 0)         // internal attributes
            directory.append(le32: entry.mode << 16)
            directory.append(le32: offset)
            directory.append(name)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        let commentData = Data(comment.utf8)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: directoryOffset)
        archive.append(le16: UInt16(commentData.count))
        archive.append(commentData)
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}
