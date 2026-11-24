//
//  SpoonInstaller.swift
//  Hammerspoon 2
//

import Foundation
import CryptoKit

/// Downloads the file at a URL. Injectable so tests never touch the network.
typealias SpoonFetcher = @Sendable (URL) async throws -> Data

/// Where an installed Spoon came from, so `update()` knows where to fetch it from again. Stored
/// in the Spoon's own directory, so anything that replaces or removes the Spoon (a Finder import,
/// a manual copy, `uninstall()`) takes its record with it.
struct SpoonSourceRecord: Codable, Equatable {
    /// What the user passed as `source`, normalised: `"owner/repo"` or a URL
    var source: String
    var ref: String?
    var sha256: String?
    /// The commit the archive was made from, if it said
    var commit: String?
    /// The URL that was downloaded
    var url: String
    var installedAt: Date
}

/// An installed Spoon, as reported to JS
struct InstalledSpoon {
    let name: String
    let metadata: SpoonMetadata
    let record: SpoonSourceRecord?

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "name": name,
            "version": metadata.version,
            "author": metadata.author,
            "description": metadata.description,
        ]
        if let record {
            // A nil dictionary value would just drop the key, which JS sees as undefined
            result["source"] = record.source
            result["ref"] = record.ref ?? NSNull()
            result["commit"] = record.commit ?? NSNull()
        }
        return result
    }
}

/// What happened to one Spoon in `updateAll()`
struct SpoonUpdateResult {
    enum Status: String {
        /// A newer version was installed
        case updated
        /// The source had the same version
        case upToDate
        /// It wasn't installed by `install()`, so there's nowhere to update it from
        case skipped
        /// Updating it failed; see `error`
        case failed
    }

    let name: String
    let status: Status
    let error: SpoonInstallError?

    var dictionary: [String: Any] {
        [
            "name": name,
            "status": status.rawValue,
            // A nil dictionary value would just drop the key, which JS sees as undefined
            "error": error.map { ["code": $0.code.rawValue, "message": $0.message] } ?? NSNull(),
        ]
    }
}

/// A download of an archive, and the `SpoonInstaller.withArchive()` calls waiting for or using it
@MainActor
private final class SharedDownload {
    struct Key: Hashable {
        let url: URL
        let sha256: String?
    }

    let task: Task<ExtractedSpoonArchive, Error>
    /// Every call still waiting for, or using, the archive
    var callers: Set<UUID> = []
    /// Those of `callers` that have been cancelled
    var cancelledCallers: Set<UUID> = []

    init(task: Task<ExtractedSpoonArchive, Error>) {
        self.task = task
    }
}

/// Installs, updates and removes Spoons from GitHub repositories and zip URLs. Used by
/// `HSSpoonsModule`; holds no JS state.
@MainActor
final class SpoonInstaller {
    let spoonManager: SpoonManager
    private let fetch: SpoonFetcher
    /// Downloads in progress, shared by every `withArchive()` call that wants the same archive
    private var downloads: [SharedDownload.Key: SharedDownload] = [:]

    init(spoonManager: SpoonManager, fetch: @escaping SpoonFetcher) {
        self.spoonManager = spoonManager
        self.fetch = fetch
    }

    /// A fetcher that downloads with `session`, mapping failures to `SpoonInstallError`s
    static func fetcher(using session: URLSession) -> SpoonFetcher {
        { url in
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(from: url)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw SpoonInstallError(.network, "Couldn't download \(url.absoluteString): \(error.localizedDescription)")
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SpoonInstallError(
                    http.statusCode == 404 ? .notFound : .network,
                    "Couldn't download \(url.absoluteString) (HTTP \(http.statusCode))"
                )
            }
            return data
        }
    }

    // MARK: - Operations

    /// The well-formed Spoons in a source
    func available(source: String, ref: String?, sha256: String?) async throws -> [SpoonCandidate] {
        let source = try SpoonSource(parsing: source)
        let url = try source.downloadURL(ref: ref)
        let sha256 = try Self.normalizedHash(sha256)
        return try await withArchive(from: url, sha256: sha256) { archive in
            let found = archive.findSpoons(validatingWith: spoonManager)
            for (name, reason) in found.invalid {
                AKWarning("hs.spoons: skipping '\(name)' in \(source.displayString): \(reason)")
            }
            return found.spoons
        }
    }

    /// Downloads `source` and installs the Spoon called `name` from it
    func install(name: String, source: String, ref: String?, sha256: String?, force: Bool) async throws -> InstalledSpoon {
        try Self.checkName(name)
        let source = try SpoonSource(parsing: source)
        let url = try source.downloadURL(ref: ref)
        let sha256 = try Self.normalizedHash(sha256)

        // Fail before downloading anything, if we can
        if !force, isInstalled(name) {
            throw Self.alreadyInstalled(name)
        }

        return try await withArchive(from: url, sha256: sha256) { archive in
            let candidate = try Self.find(name, in: archive, from: source.displayString, spoonManager: spoonManager)
            let plan = try spoonManager.planInstall(of: candidate.directory, named: name)
            // Something may have been installed there while we were downloading
            switch plan.conflict {
            case .none: break
            case .existingSpoon, .existingUnreadable:
                if !force { throw Self.alreadyInstalled(name) }
            }
            try spoonManager.performImport(plan)

            let record = SpoonSourceRecord(
                source: source.displayString, ref: ref, sha256: sha256,
                commit: archive.commit, url: url.absoluteString, installedAt: .now
            )
            try saveRecord(record, for: name)
            AKInfo("hs.spoons: installed \(name) \(plan.newMetadata.version) from \(source.displayString)")
            return InstalledSpoon(name: name, metadata: plan.newMetadata, record: record)
        }
    }

    /// Downloads an installed Spoon from where it was installed from, and reinstalls it if its
    /// version has changed
    /// - Returns: Whether it was reinstalled
    func update(name: String) async throws -> Bool {
        try Self.checkName(name)
        guard let installed = try? spoonManager.validateSpoon(at: destination(of: name)) else {
            throw SpoonInstallError(.notInstalled, "No Spoon named '\(name)' is installed")
        }
        guard let record = loadRecord(for: name), let url = URL(string: record.url) else {
            throw SpoonInstallError(.noSource, "'\(name)' wasn't installed by hs.spoons.install(), so there's nowhere to update it from")
        }

        return try await withArchive(from: url, sha256: record.sha256) { archive in
            // The Spoon may have been uninstalled or reinstalled while we were downloading, and
            // this update mustn't undo that. Nothing can change it between here and the write.
            guard isInstalled(name) else {
                throw SpoonInstallError(.notInstalled, "'\(name)' was uninstalled while it was being updated")
            }
            guard loadRecord(for: name) == record else {
                throw SpoonInstallError(.canceled, "'\(name)' was replaced while it was being updated, so the update was abandoned")
            }
            let candidate = try Self.find(name, in: archive, from: record.source, spoonManager: spoonManager)
            guard candidate.metadata.version != installed.version else {
                AKDebug("hs.spoons: \(name) is up to date (\(installed.version))")
                return false
            }
            try spoonManager.performImport(spoonManager.planInstall(of: candidate.directory, named: name))
            var updated = record
            updated.commit = archive.commit
            updated.installedAt = .now
            try saveRecord(updated, for: name)
            AKInfo("hs.spoons: updated \(name) from \(installed.version) to \(candidate.metadata.version)")
            return true
        }
    }

    /// Updates every installed Spoon that was installed from a source, one at a time, carrying on
    /// past any that fail, and skipping any that weren't installed from a source
    /// - Parameter report: Called with what happened to each Spoon, in name order, as it finishes
    /// - Returns: What happened to each Spoon, in name order
    func updateAll(_ report: (SpoonUpdateResult) -> Void) async throws -> [SpoonUpdateResult] {
        var results: [SpoonUpdateResult] = []
        for spoon in installed() {
            let result: SpoonUpdateResult
            if spoon.record == nil {
                result = SpoonUpdateResult(name: spoon.name, status: .skipped, error: nil)
            } else {
                do {
                    let updated = try await update(name: spoon.name)
                    result = SpoonUpdateResult(name: spoon.name, status: updated ? .updated : .upToDate, error: nil)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let error = error as? SpoonInstallError ?? SpoonInstallError(.io, error.localizedDescription)
                    result = SpoonUpdateResult(name: spoon.name, status: .failed, error: error)
                }
            }
            report(result)
            results.append(result)
        }
        return results
    }

    /// Removes an installed Spoon
    /// - Returns: false if it wasn't installed
    func uninstall(name: String) throws -> Bool {
        try Self.checkName(name)
        let destination = destination(of: name)
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        try FileManager.default.removeItem(at: destination)
        AKInfo("hs.spoons: uninstalled \(name)")
        return true
    }

    /// Every well-formed Spoon in the Spoons directory, by name
    func installed() -> [InstalledSpoon] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: spoonManager.spoonsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return children.compactMap { url -> InstalledSpoon? in
            let name = url.lastPathComponent
            guard SpoonManager.isValidSpoonName(name),
                  let metadata = try? spoonManager.validateSpoon(at: url) else { return nil }
            return InstalledSpoon(name: name, metadata: metadata, record: loadRecord(for: name))
        }
        .sorted { $0.name < $1.name }
    }

    func isInstalled(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: destination(of: name).path)
    }

    // MARK: - Private

    private func destination(of name: String) -> URL {
        spoonManager.spoonsDirectory.appendingPathComponent(name)
    }

    /// Downloads and extracts the archive at `url`, passes it to `body`, then removes it.
    ///
    /// Calls for the same `url` and `sha256` made while a download is in progress share it, and
    /// its extracted archive, rather than each downloading it again: a config that `use()`s
    /// several Spoons from one repository downloads it once on its first run. Nothing is kept
    /// once the last of them has finished, so a later call downloads afresh.
    private func withArchive<T>(
        from url: URL,
        sha256: String?,
        _ body: (ExtractedSpoonArchive) throws -> T
    ) async throws -> T {
        let key = SharedDownload.Key(url: url, sha256: sha256)
        let shared: SharedDownload
        if let existing = downloads[key] {
            AKDebug("hs.spoons: sharing the download of \(url.absoluteString) already in progress")
            shared = existing
        } else {
            AKDebug("hs.spoons: downloading \(url.absoluteString)")
            shared = SharedDownload(task: Task { [fetch] in
                try await Self.download(url, sha256: sha256, using: fetch)
            })
            downloads[key] = shared
        }

        let caller = UUID()
        shared.callers.insert(caller)
        let result = await withTaskCancellationHandler {
            await shared.task.result
        } onCancel: {
            Task { @MainActor [weak self] in self?.abandon(key, shared, by: caller) }
        }
        defer { leave(key, shared, caller: caller, result: result) }

        let archive = try result.get()
        try Task.checkCancellation()
        return try body(archive)
    }

    /// Fetches, checks and extracts an archive
    private static func download(_ url: URL, sha256: String?, using fetch: SpoonFetcher) async throws -> ExtractedSpoonArchive {
        let data = try await fetch(url)
        try Task.checkCancellation()

        if let sha256 {
            let actual = SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
            guard actual == sha256 else {
                throw SpoonInstallError(.integrity, "\(url.absoluteString) has SHA-256 \(actual), not the expected \(sha256)")
            }
        }

        let archive = try await ExtractedSpoonArchive.extract(data)
        guard !Task.isCancelled else {
            archive.cleanUp()
            throw CancellationError()
        }
        return archive
    }

    /// A caller of `withArchive()` was cancelled. The download is cancelled once every caller
    /// still waiting for it has been, and forgotten so that a new caller starts a new one.
    private func abandon(_ key: SharedDownload.Key, _ shared: SharedDownload, by caller: UUID) {
        guard shared.callers.contains(caller) else { return }
        shared.cancelledCallers.insert(caller)
        if shared.callers.isSubset(of: shared.cancelledCallers) {
            shared.task.cancel()
            if downloads[key] === shared { downloads[key] = nil }
        }
    }

    /// A caller of `withArchive()` has finished with the archive, which is removed once the last
    /// one has
    private func leave(_ key: SharedDownload.Key, _ shared: SharedDownload, caller: UUID, result: Result<ExtractedSpoonArchive, Error>) {
        shared.callers.remove(caller)
        shared.cancelledCallers.remove(caller)
        guard shared.callers.isEmpty else { return }
        if downloads[key] === shared { downloads[key] = nil }
        if case .success(let archive) = result { archive.cleanUp() }
    }

    /// How many calls are waiting for, or using, a download. For tests.
    var downloadCallerCount: Int {
        downloads.values.reduce(0) { $0 + $1.callers.count }
    }

    private static func find(_ name: String, in archive: ExtractedSpoonArchive, from source: String, spoonManager: SpoonManager) throws -> SpoonCandidate {
        let found = archive.findSpoons(validatingWith: spoonManager)
        if let candidate = found.spoons.first(where: { $0.name == name }) {
            return candidate
        }
        if let reason = found.invalid[name] {
            throw SpoonInstallError(.invalidSpoon, "'\(name)' in \(source) \(reason)")
        }
        let names = found.spoons.map(\.name)
        let contents = names.isEmpty ? "no Spoons" : "only " + names.joined(separator: ", ")
        throw SpoonInstallError(.notFound, "\(source) has no Spoon named '\(name)' (it has \(contents))")
    }

    private static func checkName(_ name: String) throws {
        guard SpoonManager.isValidSpoonName(name) else {
            throw SpoonInstallError(.invalidArgument, SpoonImportError.invalidName(name).localizedDescription)
        }
    }

    private static func normalizedHash(_ sha256: String?) throws -> String? {
        guard let sha256 else { return nil }
        let normalized = sha256.lowercased()
        guard normalized.wholeMatch(of: #/[0-9a-f]{64}/#) != nil else {
            throw SpoonInstallError(.invalidArgument, "'\(sha256)' is not a SHA-256 hash (64 hexadecimal digits)")
        }
        return normalized
    }

    private static func alreadyInstalled(_ name: String) -> SpoonInstallError {
        SpoonInstallError(.exists, "A Spoon named '\(name)' is already installed. Pass force: true to replace it.")
    }

    // MARK: - Source records

    private func recordURL(for name: String) -> URL {
        destination(of: name).appendingPathComponent(SpoonManager.sourceRecordFilename)
    }

    private func loadRecord(for name: String) -> SpoonSourceRecord? {
        let url = recordURL(for: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SpoonSourceRecord.self, from: data)
        } catch {
            AKError("hs.spoons: ignoring unreadable \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private func saveRecord(_ record: SpoonSourceRecord, for name: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: recordURL(for: name), options: .atomic)
    }
}
