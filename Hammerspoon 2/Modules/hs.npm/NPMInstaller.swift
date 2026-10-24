//
//  NPMInstaller.swift
//  Hammerspoon 2
//

import Foundation
import CryptoKit

nonisolated struct NPMError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Installs the `dependencies` of `<projectDir>/package.json` into `<projectDir>/node_modules`
/// straight from the registries named in `.npmrc`. No npm or node binary is involved: the
/// registry document is fetched over HTTPS, a version is picked, and the `.tgz` is downloaded,
/// checked against its `integrity` hash and unpacked with the system `tar`.
nonisolated final class NPMInstaller: Sendable {
    let projectDir: URL
    let npmrc: NPMRC
    let session: URLSession

    init(projectDir: URL, npmrc: NPMRC? = nil, session: URLSession = .shared) {
        self.projectDir = projectDir
        self.npmrc = npmrc ?? NPMRC.load(projectDir: projectDir)
        self.session = session
    }

    var nodeModules: URL { projectDir.appendingPathComponent("node_modules") }

    @MainActor private static var inFlight: [String: Task<[String], Error>] = [:]

    /// Installs every dependency of `<projectDir>/package.json`, and their dependencies, that
    /// isn't already present in a satisfying version. Returns every package now installed as
    /// `name@version`. Installs are serialised per project directory: a second one (a reload
    /// mid-download, or two `hs.npm.install()` calls) waits for the first to finish, so two
    /// extractions never race on the same `node_modules`.
    @MainActor
    static func install(projectDir: URL) async throws -> [String] {
        let key = projectDir.standardizedFileURL.path
        let previous = inFlight[key]
        let task = Task {
            _ = await previous?.result   // whatever its outcome
            return try await NPMInstaller(projectDir: projectDir).run()
        }
        inFlight[key] = task
        defer { if inFlight[key] == task { inFlight[key] = nil } }
        return try await task.value
    }

    @concurrent
    private func run() async throws -> [String] {
        let packageJSON = projectDir.appendingPathComponent("package.json")
        guard let root = try? NPMInstaller.readJSON(packageJSON) else {
            throw NPMError("No readable package.json at \(packageJSON.path)")
        }
        // ponytail: flat node_modules, first version of a name wins; nest conflicting versions
        // the way npm does if a wanted package ever needs it
        var queue = NPMInstaller.dependencies(of: root)
        var installed: [String: String] = [:]
        while !queue.isEmpty {
            let (name, range) = queue.removeFirst()
            if let have = installed[name] {
                // Already handled in this install: a conflicting second request loses.
                if !(SemVer(have)?.satisfies(range) ?? false) {
                    await MainActor.run { AKWarning("hs.npm: \(name)@\(have) already chosen; ignoring conflicting request for '\(range)'") }
                }
                continue
            }
            // On disk from an earlier install: reuse it only while it still satisfies the request,
            // so changing package.json from ^1 to ^2 replaces the installed 1.x. Its dependencies
            // are queued too, so one that failed to download last time is retried.
            if let manifest = installedManifest(of: name), let have = manifest["version"] as? String,
               SemVer(have)?.satisfies(range) ?? false {
                installed[name] = have
                queue += NPMInstaller.dependencies(of: manifest)
                continue
            }
            let manifest = try await resolve(name, range)
            guard let version = manifest["version"] as? String else {
                throw NPMError("Registry document for \(name) has no version")
            }
            await MainActor.run { AKInfo("hs.npm: installing \(name)@\(version)") }
            try await download(manifest, into: nodeModules.appendingPathComponent(name))
            installed[name] = version
            queue += NPMInstaller.dependencies(of: manifest)
        }
        return installed.map { "\($0.key)@\($0.value)" }.sorted()
    }

    /// The `dependencies` of a package.json / registry manifest, in a stable order.
    static func dependencies(of manifest: [String: Any]) -> [(name: String, range: String)] {
        (manifest["dependencies"] as? [String: String] ?? [:])
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, range: $0.value) }
    }

    /// Picks the version to install from a registry document's version list: a dist-tag
    /// (`latest`, or the default for an empty range) by name, otherwise the highest release
    /// satisfying the range.
    static func selectVersion(from versions: [String], tags: [String: String], range: String) -> String? {
        let wanted = range.trimmingCharacters(in: .whitespaces)
        if let tagged = tags[wanted.isEmpty ? "latest" : wanted], versions.contains(tagged) { return tagged }
        return versions
            .compactMap { key in SemVer(key).map { (version: $0, key: key) } }
            .filter { $0.version.satisfies(wanted) }
            .max { $0.version < $1.version }?
            .key
    }

    // MARK: - Private

    private func installedManifest(of name: String) -> [String: Any]? {
        try? NPMInstaller.readJSON(nodeModules.appendingPathComponent(name).appendingPathComponent("package.json"))
    }

    private static func readJSON(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw NPMError("\(url.path) is not a JSON object")
        }
        return object
    }

    /// Fetches the registry document for `name` and returns the manifest of the chosen version.
    private func resolve(_ name: String, _ range: String) async throws -> [String: Any] {
        guard let url = npmrc.metadataURL(for: name) else { throw NPMError("Bad package name '\(name)'") }
        // The abbreviated document is much smaller and has everything needed (versions, dist, dependencies)
        let data = try await fetch(url, accept: "application/vnd.npm.install-v1+json")
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versions = doc["versions"] as? [String: [String: Any]] else {
            throw NPMError("Unexpected registry response for \(name) from \(url)")
        }
        let tags = doc["dist-tags"] as? [String: String] ?? [:]
        guard let chosen = NPMInstaller.selectVersion(from: Array(versions.keys), tags: tags, range: range),
              let manifest = versions[chosen] else {
            throw NPMError("No version of \(name) satisfies '\(range)' (available: \(versions.keys.sorted().joined(separator: ", ")))")
        }
        return manifest
    }

    private func download(_ manifest: [String: Any], into dir: URL) async throws {
        guard let dist = manifest["dist"] as? [String: Any],
              let tarball = (dist["tarball"] as? String).flatMap(URL.init) else {
            throw NPMError("Manifest for \(manifest["name"] ?? "?") has no dist.tarball")
        }
        // fetch() looks the Authorization up by host, so a tarball served by the registry's own
        // host (GitHub Packages, Artifactory, ...) gets the registry's token.
        let data = try await fetch(tarball)
        try NPMInstaller.verify(data, integrity: dist["integrity"] as? String, shasum: dist["shasum"] as? String)
        try await NPMInstaller.extract(data, into: dir)
    }

    private func fetch(_ url: URL, accept: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        if let auth = npmrc.authorization(for: url) { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw NPMError("HTTP \(status) fetching \(url)")
        }
        return data
    }

    /// Checks the tarball against the registry's `integrity` (SRI, e.g. `sha512-<base64>`) or,
    /// failing that, its legacy `shasum` (SHA-1 hex). Neither present: nothing to check.
    static func verify(_ data: Data, integrity: String?, shasum: String?) throws {
        if let integrity, let dash = integrity.firstIndex(of: "-") {
            let algorithm = integrity[..<dash]
            let expected = Data(base64Encoded: String(integrity[integrity.index(after: dash)...].prefix { !$0.isWhitespace }))
            let actual: Data?
            switch algorithm {
            case "sha512": actual = Data(SHA512.hash(data: data))
            case "sha256": actual = Data(SHA256.hash(data: data))
            case "sha1": actual = Data(Insecure.SHA1.hash(data: data))
            default: actual = nil
            }
            guard let actual, actual == expected else { throw NPMError("Integrity check (\(algorithm)) failed") }
        } else if let shasum {
            let actual = Insecure.SHA1.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
            guard actual == shasum.lowercased() else { throw NPMError("Integrity check (shasum) failed") }
        }
    }

    /// Replaces `dir` with the tarball's contents, minus its top-level `package/` directory.
    private static func extract(_ data: Data, into dir: URL) async throws {
        let fm = FileManager.default
        let tgz = fm.temporaryDirectory.appendingPathComponent("hs-npm-\(UUID().uuidString).tgz")
        try data.write(to: tgz)
        defer { try? fm.removeItem(at: tgz) }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        // macOS ships bsdtar, which already refuses absolute and ".." member paths.
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tgz.path, "-C", dir.path, "--strip-components=1"]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tar.terminationHandler = { _ in continuation.resume() }
            do { try tar.run() } catch { continuation.resume(throwing: error) }
        }
        guard tar.terminationStatus == 0 else {
            throw NPMError("tar failed (exit \(tar.terminationStatus)) unpacking into \(dir.path)")
        }
    }
}
