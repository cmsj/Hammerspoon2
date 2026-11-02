//
//  SpoonArchive.swift
//  Hammerspoon 2
//

import Foundation

/// One file or directory listed in a zip archive's central directory
nonisolated struct ZipEntry: Equatable, Sendable {
    let path: String
    let isSymlink: Bool
    let uncompressedSize: UInt64
}

/// A zip archive's central directory: what it contains, read without extracting anything
nonisolated struct ZipListing {
    let entries: [ZipEntry]
    /// The archive comment. `git archive` (and so GitHub) stores the commit SHA here.
    let comment: String

    /// The commit SHA the archive was made from, if its comment is one
    var commit: String? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: #/[0-9a-f]{40}|[0-9a-f]{64}/#) != nil ? trimmed : nil
    }

    /// Reads the central directory of the zip archive in `data`
    init(data: Data) throws {
        let reader = ByteReader(data: data)

        // The end of central directory record sits at the very end, followed only by the
        // (up to 64KB) archive comment, so search backwards for its signature.
        let eocdMinimum = 22
        guard data.count >= eocdMinimum else { throw Self.malformed("too short to be a zip file") }
        var eocd: Int?
        var candidate = data.count - eocdMinimum
        let lowest = max(0, data.count - eocdMinimum - 0xFFFF)
        while candidate >= lowest {
            if reader.uint32(at: candidate) == 0x0605_4B50 {
                eocd = candidate
                break
            }
            candidate -= 1
        }
        guard let eocd else { throw Self.malformed("no end of central directory record") }

        var entryCount = UInt64(reader.uint16(at: eocd + 10))
        var directoryOffset = UInt64(reader.uint32(at: eocd + 16))
        let commentLength = Int(reader.uint16(at: eocd + 20))
        guard eocd + 22 + commentLength <= data.count else { throw Self.malformed("truncated comment") }
        comment = String(decoding: data.subdata(in: (eocd + 22)..<(eocd + 22 + commentLength)), as: UTF8.self)

        // ZIP64: the real values live in a separate record, found via a locator just before
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = eocd - 20
            guard locator >= 0, reader.uint32(at: locator) == 0x0706_4B50 else {
                throw Self.malformed("missing ZIP64 locator")
            }
            let record = Int(clamping: reader.uint64(at: locator + 8))
            guard record >= 0, record + 56 <= data.count, reader.uint32(at: record) == 0x0606_4B50 else {
                throw Self.malformed("missing ZIP64 end of central directory record")
            }
            entryCount = reader.uint64(at: record + 32)
            directoryOffset = reader.uint64(at: record + 48)
        }

        guard entryCount <= 1_000_000 else { throw Self.malformed("too many entries") }

        var entries: [ZipEntry] = []
        var offset = Int(clamping: directoryOffset)
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, reader.uint32(at: offset) == 0x0201_4B50 else {
                throw Self.malformed("bad central directory entry")
            }
            let madeBy = reader.uint16(at: offset + 4)
            let flags = reader.uint16(at: offset + 8)
            var size = UInt64(reader.uint32(at: offset + 24))
            let nameLength = Int(reader.uint16(at: offset + 28))
            let extraLength = Int(reader.uint16(at: offset + 30))
            let commentLength = Int(reader.uint16(at: offset + 32))
            let externalAttributes = reader.uint32(at: offset + 38)
            let nameStart = offset + 46
            let extraStart = nameStart + nameLength
            let next = extraStart + extraLength + commentLength
            guard next <= data.count else { throw Self.malformed("truncated central directory entry") }

            let nameData = data.subdata(in: nameStart..<extraStart)
            let isUTF8 = flags & 0x0800 != 0
            let path = (isUTF8 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)

            // A ZIP64 extra field holds the real size when the 32-bit one is saturated
            if size == 0xFFFF_FFFF {
                var extra = extraStart
                while extra + 4 <= extraStart + extraLength {
                    let id = reader.uint16(at: extra)
                    let length = Int(reader.uint16(at: extra + 2))
                    if id == 0x0001, length >= 8 {
                        size = reader.uint64(at: extra + 4)
                        break
                    }
                    extra += 4 + length
                }
            }

            // Unix-made archives keep the file mode in the high 16 bits of the external attributes
            let hostIsUnix = madeBy >> 8 == 3
            let fileType = (externalAttributes >> 16) & 0o170000
            entries.append(ZipEntry(path: path, isSymlink: hostIsUnix && fileType == 0o120000, uncompressedSize: size))
            offset = next
        }
        self.entries = entries
    }

    /// Throws if extracting this archive could write outside the directory it's extracted into,
    /// or fill the disk. Symlinks themselves are allowed, since repositories often have them, but
    /// not entries that would be written through one. A Spoon that contains a symlink is refused
    /// when it's found (see `ExtractedSpoonArchive.findSpoons`).
    func checkSafeToExtract() throws {
        let symlinks = Set(entries.filter(\.isSymlink).map { Self.trimmingSlashes($0.path) })
        var total: UInt64 = 0
        for entry in entries {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            if entry.path.hasPrefix("/") || entry.path.contains("\\") || components.contains("..") {
                throw SpoonInstallError(.invalidSpoon, "The archive contains an unsafe path: \(entry.path)")
            }
            let parts = Self.trimmingSlashes(entry.path).split(separator: "/")
            for length in parts.indices.dropLast() {
                let ancestor = parts[...length].joined(separator: "/")
                if symlinks.contains(ancestor) {
                    throw SpoonInstallError(.invalidSpoon, "The archive writes \(entry.path) through the symbolic link \(ancestor)")
                }
            }
            total = total.addingReportingOverflow(entry.uncompressedSize).partialValue
        }
        if total > Self.maximumExtractedSize {
            throw SpoonInstallError(.invalidSpoon, "The archive is too large to install (\(total / 1_048_576) MB uncompressed)")
        }
    }

    private static func trimmingSlashes(_ path: String) -> String {
        var path = Substring(path)
        while path.hasSuffix("/") { path = path.dropLast() }
        return String(path)
    }

    static let maximumExtractedSize: UInt64 = 512 * 1_048_576

    private static func malformed(_ detail: String) -> SpoonInstallError {
        SpoonInstallError(.invalidSpoon, "The download isn't a valid zip file (\(detail))")
    }
}

/// Little-endian reads that return 0 rather than trapping when out of bounds, so a malformed
/// archive fails a signature check instead of crashing
nonisolated private struct ByteReader {
    let data: Data

    func uint16(at offset: Int) -> UInt16 {
        UInt16(truncatingIfNeeded: read(at: offset, count: 2))
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: read(at: offset, count: 4))
    }

    func uint64(at offset: Int) -> UInt64 {
        read(at: offset, count: 8)
    }

    private func read(at offset: Int, count: Int) -> UInt64 {
        guard offset >= 0, offset + count <= data.count else { return 0 }
        var value: UInt64 = 0
        let start = data.startIndex + offset
        for index in 0..<count {
            value |= UInt64(data[start + index]) << (8 * index)
        }
        return value
    }
}

/// A Spoon found inside an extracted archive
struct SpoonCandidate {
    let name: String
    let directory: URL
    let metadata: SpoonMetadata
}

/// A downloaded archive, extracted into a temporary directory that `cleanUp()` removes
struct ExtractedSpoonArchive: Sendable {
    let directory: URL
    let commit: String?

    /// Checks `data` is a safe zip, then extracts it into a new temporary directory
    @concurrent
    nonisolated static func extract(_ data: Data) async throws -> ExtractedSpoonArchive {
        let listing = try ZipListing(data: data)
        try listing.checkSafeToExtract()

        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("hs.spoons-\(UUID().uuidString)")
        let contents = workDirectory.appendingPathComponent("contents")
        let archive = workDirectory.appendingPathComponent("archive.zip")

        do {
            try fileManager.createDirectory(at: contents, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: archive)
            try runDitto(archive: archive, destination: contents)
            try fileManager.removeItem(at: archive)
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }

        return ExtractedSpoonArchive(directory: contents, commit: listing.commit)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    /// Finds the Spoons in the archive.
    ///
    /// If the archive holds a single directory (as GitHub's and most other hosts' repository
    /// archives do), that directory is its root. The Spoons are then every `*.spoon2` directory at
    /// the root or in a `Spoons` directory under it, or, if there are none, the root itself, if it's
    /// a Spoon (a repository that is a single Spoon).
    /// - Returns: The well-formed Spoons, and a description of each malformed one, keyed by name
    func findSpoons(validatingWith spoonManager: SpoonManager) -> (spoons: [SpoonCandidate], invalid: [String: String]) {
        let root = Self.archiveRoot(of: directory)

        var spoons: [SpoonCandidate] = []
        var invalid: [String: String] = [:]
        var seen = Set<String>()

        for searchDirectory in [root, root.appendingPathComponent("Spoons")] where !Self.isSymlink(searchDirectory) {
            for url in Self.childDirectories(of: searchDirectory) where url.pathExtension.lowercased() == "spoon2" {
                let name = url.deletingPathExtension().lastPathComponent
                guard !seen.contains(name) else {
                    AKWarning("hs.spoons: ignoring a second Spoon named '\(name)' at \(url.lastPathComponent)")
                    continue
                }
                seen.insert(name)
                if Self.containsSymlink(url) {
                    invalid[name] = Self.symlinkReason
                    continue
                }
                do {
                    let plan = try spoonManager.planInstall(of: url, named: name)
                    spoons.append(SpoonCandidate(name: name, directory: url, metadata: plan.newMetadata))
                } catch {
                    invalid[name] = error.localizedDescription
                }
            }
        }

        if seen.isEmpty, let metadata = try? spoonManager.validateSpoon(at: root) {
            if !SpoonManager.isValidSpoonName(metadata.name) {
                invalid[metadata.name] = SpoonImportError.invalidName(metadata.name).localizedDescription
            } else if Self.containsSymlink(root) {
                invalid[metadata.name] = Self.symlinkReason
            } else {
                spoons.append(SpoonCandidate(name: metadata.name, directory: root, metadata: metadata))
            }
        }

        return (spoons.sorted { $0.name < $1.name }, invalid)
    }

    // MARK: - Private

    private static let ignoredNames: Set<String> = ["__MACOSX", ".DS_Store"]
    private static let symlinkReason = "contains a symbolic link, which Spoons may not"

    private static func archiveRoot(of directory: URL) -> URL {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        let relevant = children.filter { !ignoredNames.contains($0.lastPathComponent) }
        if relevant.count == 1, let only = relevant.first, isRealDirectory(only),
           only.pathExtension.lowercased() != "spoon2" {
            return only
        }
        return directory
    }

    /// The directories in `directory`, not following symlinks
    private static func childDirectories(of directory: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        return children
            .filter(isRealDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Whether `directory` or anything in it is a symlink. Installing copies the Spoon, and a
    /// copied symlink could point anywhere.
    private static func containsSymlink(_ directory: URL) -> Bool {
        if isSymlink(directory) { return true }
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        )
        while let url = enumerator?.nextObject() as? URL {
            if isSymlink(url) { return true }
        }
        return false
    }

    nonisolated private static func runDitto(archive: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // Don't apply resource forks, extended attributes or ACLs from an untrusted archive. Without
        // --norsrc, ditto also turns __MACOSX/._* entries back into metadata, and fails on any it
        // can't parse.
        process.arguments = ["-x", "-k", "--norsrc", "--noextattr", "--noacl", archive.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpoonInstallError(.invalidSpoon, "Couldn't extract the archive: \(detail)")
        }
    }
}
