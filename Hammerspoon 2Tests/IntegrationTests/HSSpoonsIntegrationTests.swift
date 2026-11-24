//
//  HSSpoonsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import JavaScriptCoreExtras
import CryptoKit
import Synchronization
@testable import Hammerspoon_2

// MARK: - Fixtures

/// Serves archives to `HSSpoonsModule` in place of the network, recording what was requested
private final class FakeDownloads: Sendable {
    private let state = Mutex<(archives: [URL: Data], requested: [URL])>(([:], []))
    private let gate = Mutex<(closed: Set<URL>, waiting: [(url: URL, continuation: CheckedContinuation<Void, Never>)])>(([], []))
    /// When set, a download waits until cancelled instead of answering
    let hangs: Bool

    init(hangs: Bool = false) {
        self.hangs = hangs
    }

    func serve(_ archive: Data, at url: String) {
        state.withLock { $0.archives[URL(string: url)!] = archive }
    }

    var requested: [URL] { state.withLock { $0.requested } }

    /// Makes downloads of `url` wait, once requested, until it's opened again
    func close(_ url: String) {
        _ = gate.withLock { $0.closed.insert(URL(string: url)!) }
    }

    func open(_ url: String) {
        let url = URL(string: url)!
        let released = gate.withLock { gate in
            gate.closed.remove(url)
            defer { gate.waiting.removeAll { $0.url == url } }
            return gate.waiting.filter { $0.url == url }
        }
        released.forEach { $0.continuation.resume() }
    }

    /// How many downloads are waiting for a closed URL
    var waitingCount: Int { gate.withLock { $0.waiting.count } }

    func fetch(_ url: URL) async throws -> Data {
        await withCheckedContinuation { continuation in
            let wait = gate.withLock { gate in
                if gate.closed.contains(url) { gate.waiting.append((url, continuation)) }
                return gate.closed.contains(url)
            }
            if !wait { continuation.resume() }
        }
        state.withLock { $0.requested.append(url) }
        if hangs {
            try await Task.sleep(for: .seconds(60))
        }
        guard let data = state.withLock({ $0.archives[url] }) else {
            throw SpoonInstallError(.notFound, "Couldn't download \(url.absoluteString) (HTTP 404)")
        }
        return data
    }
}

/// A JSTestHarness with hs.spoons (and its hs.spoons.js) loaded against a temporary config
/// directory, downloading from a FakeDownloads
@MainActor
private final class SpoonsTestContext {
    let harness = JSTestHarness()
    let downloads: FakeDownloads
    let configDir: URL
    let module: HSSpoonsModule

    var spoonsDir: URL { configDir.appendingPathComponent("Spoons") }

    init(downloads: FakeDownloads = FakeDownloads()) throws {
        self.downloads = downloads
        configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs_spoons_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let settings = MockSettingsManager()
        settings.configLocation = configDir.appendingPathComponent("init.js")
        module = HSSpoonsModule(
            engineID: UUID(),
            spoonManager: SpoonManager(settings: settings),
            fetch: { [downloads] url in try await downloads.fetch(url) }
        )

        try harness.context.install([NodeBuiltinModulesInstaller(), RequireInstaller()])
        harness.loadModule(module, as: "spoons")
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: configDir)
    }

    /// Evaluates `expression`, a Promise, and waits for it to settle
    /// - Returns: The value it resolved with, or nil if it rejected or didn't settle
    @discardableResult
    func settle(_ expression: String, timeout: TimeInterval = 5) async -> JSValue? {
        start(expression)
        return await settled(timeout: timeout)
    }

    /// Evaluates `expression`, a Promise, without waiting for it: see `settled()`
    func start(_ expression: String) {
        harness.eval("""
            globalThis.__settled = false; globalThis.__value = undefined; globalThis.__error = undefined;
            (\(expression)).then(
                v => { __value = v; __settled = true; },
                e => { __error = e; __settled = true; }
            );
            """)
    }

    /// Waits for the Promise from the last `start()` to settle
    /// - Returns: The value it resolved with, or nil if it rejected or didn't settle
    func settled(timeout: TimeInterval = 5) async -> JSValue? {
        let settled = await harness.waitForAsync(timeout: timeout) { [harness] in harness.evalBool("__settled") == true }
        #expect(settled, "The Promise didn't settle")
        return harness.evalBool("__error === undefined") == true ? harness.evalValue("__value") : nil
    }

    /// The `code` of the error the last `settle()` rejected with
    var errorCode: String? { harness.evalString("__error && __error.code") }

    func isInstalled(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: spoonsDir.appendingPathComponent("\(name)/init.js").path)
    }

    func installedVersion(_ name: String) throws -> String {
        try SpoonManager(settings: MockSettingsManager()).validateSpoon(at: spoonsDir.appendingPathComponent(name)).version
    }
}

private let commitSHA = "5c20bcecc380acff5f0f5df7a718c5679aaaf62a"

/// A repository archive as GitHub serves it: everything inside one `<repo>-<ref>` directory, with
/// the commit SHA as the archive's comment
private func repositoryArchive(version: String = "1.0.0") -> Data {
    var zip = ZipFixture()
    zip.comment = commitSHA
    zip.directory("hs2-spoons-main")
    zip.file("hs2-spoons-main/README.md", "# Spoons")
    zip.spoon(at: "hs2-spoons-main/Greeter.spoon2", name: "Greeter", version: version)
    zip.spoon(at: "hs2-spoons-main/Spoons/Clock.spoon2", name: "Clock")
    zip.file("hs2-spoons-main/Broken.spoon2/init.js", "module.exports = {};")
    return zip.data
}

private let repositoryURL = "https://github.com/jane/hs2-spoons/archive/HEAD.zip"

private extension Data {
    mutating func replace(at offset: Int, with bytes: [UInt8]) {
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}

// MARK: - Tests

@Suite("hs.spoons tests", .serialized)
struct HSSpoonsTests {

    @Suite("sources")
    struct SourceTests {

        @Test("GitHub shorthand and repository URLs download the repository's archive")
        func testGitHubSources() throws {
            for string in ["jane/hs2-spoons", "https://github.com/jane/hs2-spoons", "https://github.com/jane/hs2-spoons.git", " jane/hs2-spoons.git "] {
                let source = try SpoonSource(parsing: string)
                #expect(source == .gitHub(owner: "jane", repository: "hs2-spoons"), "\(string)")
                #expect(try source.downloadURL(ref: nil).absoluteString == repositoryURL)
            }
            let source = try SpoonSource(parsing: "jane/hs2-spoons")
            #expect(try source.downloadURL(ref: "v1.2.0").absoluteString == "https://github.com/jane/hs2-spoons/archive/v1.2.0.zip")
            #expect(source.displayString == "jane/hs2-spoons")
        }

        @Test("any other https URL is a zip file, downloaded as it is")
        func testZipSources() throws {
            for string in ["https://example.com/Greeter.zip", "https://gitlab.com/joe/spoons/-/archive/main/spoons-main.zip", "https://github.com/jane/hs2-spoons/releases/download/v1/Greeter.zip"] {
                let source = try SpoonSource(parsing: string)
                #expect(source == .zip(URL(string: string)!), "\(string)")
                #expect(try source.downloadURL(ref: nil).absoluteString == string)
            }
        }

        @Test("non-https URLs and unparseable sources are rejected")
        func testInvalidSources() {
            for string in ["http://example.com/Greeter.zip", "file:///tmp/Greeter.zip", "not a source", "", "jane/hs2-spoons/extra"] {
                #expect(throws: SpoonInstallError.self, "\(string)") { try SpoonSource(parsing: string) }
            }
        }

        @Test("a ref is rejected for a zip URL, and when it isn't a valid ref")
        func testInvalidRefs() throws {
            let zip = try SpoonSource(parsing: "https://example.com/Greeter.zip")
            #expect(throws: SpoonInstallError(.invalidArgument, "'ref' can only be used with a GitHub repository, not a zip URL")) {
                try zip.downloadURL(ref: "main")
            }
            let gitHub = try SpoonSource(parsing: "jane/hs2-spoons")
            for ref in ["../main", "-main", "a b", "main/", "a//b"] {
                #expect(throws: SpoonInstallError.self, "\(ref)") { try gitHub.downloadURL(ref: ref) }
            }
            #expect(try gitHub.downloadURL(ref: "feature/new-thing").lastPathComponent == "new-thing.zip")
        }
    }

    @Suite("zip archives")
    struct ArchiveTests {

        @Test("the central directory lists every entry, and the comment's commit SHA")
        func testListing() throws {
            let listing = try ZipListing(data: repositoryArchive())
            #expect(listing.entries.map(\.path).contains("hs2-spoons-main/Greeter.spoon2/spoon.json"))
            #expect(listing.entries.count == 7)
            #expect(listing.commit == commitSHA)
            try listing.checkSafeToExtract()
        }

        @Test("an archive comment that isn't a commit SHA isn't reported as one")
        func testNonCommitComment() throws {
            var zip = ZipFixture()
            zip.comment = "made by hand"
            zip.spoon(at: "", name: "Greeter")
            #expect(try ZipListing(data: zip.data).commit == nil)
        }

        @Test("absolute paths, paths escaping the archive, and writing through a symlink are refused")
        func testUnsafeArchives() throws {
            var throughSymlink = ZipFixture()
            throughSymlink.symlink("etc", to: "/etc")
            throughSymlink.file("etc/hosts", "")
            var escaping = ZipFixture()
            escaping.file("../../outside.js", "")
            var absolute = ZipFixture()
            absolute.file("/tmp/outside.js", "")

            for archive in [throughSymlink, escaping, absolute] {
                let listing = try ZipListing(data: archive.data)
                #expect(throws: SpoonInstallError.self) { try listing.checkSafeToExtract() }
            }
        }

        @Test("writing through a symlink is refused however the path is spelled")
        func testSymlinkPathSpellings() throws {
            for path in ["./link/file", "link//file", "LINK/file", "./LINK/./file"] {
                var zip = ZipFixture()
                zip.symlink("link", to: "/tmp")
                zip.file(path, "")
                let listing = try ZipListing(data: zip.data)
                #expect(throws: SpoonInstallError.self, "\(path)") { try listing.checkSafeToExtract() }
            }
        }

        @Test("offsets pointing far outside the archive are refused, not trusted")
        func testHugeOffsets() throws {
            var zip = ZipFixture()
            zip.spoon(at: "", name: "Greeter")
            let data = zip.data
            let eocd = data.count - 22

            // A central directory offset past the end of the data
            var badDirectory = data
            badDirectory.replace(at: eocd + 16, with: [0xFE, 0xFF, 0xFF, 0xFF])
            #expect(throws: SpoonInstallError.self) { try ZipListing(data: badDirectory) }

            // ZIP64, with the record's offset at the very top of the range
            var zip64 = data.prefix(eocd)
            zip64.append(contentsOf: [0x50, 0x4B, 0x06, 0x07, 0, 0, 0, 0])
            zip64.append(contentsOf: [UInt8](repeating: 0xFF, count: 8))
            zip64.append(contentsOf: [1, 0, 0, 0])
            var eocdRecord = data.suffix(22)
            eocdRecord.replace(at: eocdRecord.startIndex + 16, with: [0xFF, 0xFF, 0xFF, 0xFF])
            zip64.append(eocdRecord)
            #expect(throws: SpoonInstallError.self) { try ZipListing(data: Data(zip64)) }
        }

        @Test("an archive may contain symlinks, which are reported as such")
        func testSymlinksAllowed() throws {
            var zip = ZipFixture()
            zip.spoon(at: "Greeter.spoon2", name: "Greeter")
            zip.symlink("docs/latest", to: "../docs")
            let listing = try ZipListing(data: zip.data)
            #expect(listing.entries.filter(\.isSymlink).map(\.path) == ["docs/latest"])
            try listing.checkSafeToExtract()
        }

        @Test("data that isn't a zip file is refused")
        func testNotAZip() {
            for data in [Data(), Data("<html>Not found</html>".utf8), Data(repeating: 0x50, count: 100)] {
                #expect(throws: SpoonInstallError.self) { try ZipListing(data: data) }
            }
        }
    }

    @Suite("install()")
    @MainActor
    struct InstallTests {

        @Test("installs one Spoon from a GitHub repository and records where it came from")
        func testInstallFromGitHub() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)

            let info = await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")
            #expect(info?.forProperty("name").toString() == "Greeter")
            #expect(info?.forProperty("version").toString() == "1.0.0")
            #expect(info?.forProperty("source").toString() == "jane/hs2-spoons")
            #expect(info?.forProperty("commit").toString() == commitSHA)
            #expect(info?.forProperty("ref").isNull == true)
            #expect(ctx.downloads.requested == [URL(string: repositoryURL)!])
            #expect(ctx.isInstalled("Greeter"))
            #expect(!ctx.isInstalled("Clock"))

            #expect(ctx.harness.evalString("JSON.stringify(hs.spoons.installed().map(s => [s.name, s.source, s.commit]))")
                    == #"[["Greeter","jane/hs2-spoons","\#(commitSHA)"]]"#)
            #expect(ctx.harness.evalString("hs.spoons.load('Greeter').name") == "Greeter")
        }

        @Test("finds Spoons in a Spoons directory, and passes a ref through")
        func testInstallFromSpoonsDirectory() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: "https://github.com/jane/hs2-spoons/archive/v2.zip")

            await ctx.settle("hs.spoons.install('Clock', { source: 'https://github.com/jane/hs2-spoons', ref: 'v2' })")
            #expect(ctx.isInstalled("Clock"))
            #expect(ctx.harness.evalString("hs.spoons.installed()[0].ref") == "v2")
        }

        @Test("installs a repository that is itself a Spoon, named from its spoon.json")
        func testInstallSingleSpoonRepository() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "Weather-main", name: "Weather")
            ctx.downloads.serve(zip.data, at: "https://github.com/jane/Weather/archive/HEAD.zip")

            await ctx.settle("hs.spoons.install('Weather', { source: 'jane/Weather' })")
            #expect(ctx.isInstalled("Weather"))
        }

        @Test("installs from a zip of a Spoon made in Finder, from any host")
        func testInstallFinderZip() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "Greeter.spoon2", name: "Greeter")
            zip.file("__MACOSX/Greeter.spoon2/._init.js", "")
            ctx.downloads.serve(zip.data, at: "https://example.com/Greeter.zip")

            let info = await ctx.settle("hs.spoons.install('Greeter', { source: 'https://example.com/Greeter.zip' })")
            #expect(info?.forProperty("source").toString() == "https://example.com/Greeter.zip")
            #expect(info?.forProperty("commit").isNull == true)
            #expect(ctx.isInstalled("Greeter"))
        }

        @Test("a Spoon the source doesn't have rejects with ENOTFOUND, naming those it does have")
        func testMissingSpoon() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)

            await ctx.settle("hs.spoons.install('Nope', { source: 'jane/hs2-spoons' })")
            #expect(ctx.errorCode == "ENOTFOUND")
            #expect(ctx.harness.evalString("__error.message")?.contains("Clock, Greeter") == true)
        }

        @Test("a malformed Spoon rejects with EINVALIDSPOON")
        func testMalformedSpoon() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)

            await ctx.settle("hs.spoons.install('Broken', { source: 'jane/hs2-spoons' })")
            #expect(ctx.errorCode == "EINVALIDSPOON")
            #expect(!ctx.isInstalled("Broken"))
        }

        @Test("a source that can't be downloaded rejects with ENOTFOUND")
        func testDownloadFails() async throws {
            let ctx = try SpoonsTestContext()
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/missing' })")
            #expect(ctx.errorCode == "ENOTFOUND")
        }

        @Test("an installed Spoon is only replaced with force: true")
        func testExistingSpoon() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(version: "1.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")

            ctx.downloads.serve(repositoryArchive(version: "2.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")
            #expect(ctx.errorCode == "EEXISTS")
            #expect(ctx.downloads.requested.count == 1, "should fail before downloading")
            #expect(try ctx.installedVersion("Greeter") == "1.0.0")

            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', force: true })")
            #expect(try ctx.installedVersion("Greeter") == "2.0.0")
        }

        @Test("sha256 must match the download")
        func testSHA256() async throws {
            let ctx = try SpoonsTestContext()
            let archive = repositoryArchive()
            ctx.downloads.serve(archive, at: repositoryURL)
            let hash = sha256Hex(archive)

            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', sha256: '\(String(repeating: "0", count: 64))' })")
            #expect(ctx.errorCode == "EINTEGRITY")
            #expect(!ctx.isInstalled("Greeter"))

            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', sha256: '\(hash.uppercased())' })")
            #expect(ctx.isInstalled("Greeter"))
        }

        @Test("bad arguments reject with EINVALIDARG without downloading")
        func testInvalidArguments() async throws {
            let ctx = try SpoonsTestContext()
            for call in [
                "hs.spoons.install('Greeter', {})",
                "hs.spoons.install('Greeter', { source: 42 })",
                "hs.spoons.install('../Greeter', { source: 'jane/hs2-spoons' })",
                "hs.spoons.install('Greeter', { source: 'https://example.com/Greeter.zip', ref: 'main' })",
                "hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', sha256: 'abc' })",
                "hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', force: 'yes' })",
            ] {
                await ctx.settle(call)
                #expect(ctx.errorCode == "EINVALIDARG", "\(call)")
            }
            #expect(ctx.downloads.requested.isEmpty)
        }

        @Test("a Spoon containing a symlink isn't installed, but others in the same archive are")
        func testSymlinkArchive() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "repo-main/Greeter.spoon2", name: "Greeter")
            zip.symlink("repo-main/Greeter.spoon2/secrets", to: "/etc")
            zip.spoon(at: "repo-main/Clock.spoon2", name: "Clock")
            zip.symlink("repo-main/docs/latest", to: "../README.md")
            ctx.downloads.serve(zip.data, at: "https://example.com/repo.zip")

            await ctx.settle("hs.spoons.install('Greeter', { source: 'https://example.com/repo.zip' })")
            #expect(ctx.errorCode == "EINVALIDSPOON")
            #expect(!ctx.isInstalled("Greeter"))

            await ctx.settle("hs.spoons.install('Clock', { source: 'https://example.com/repo.zip' })")
            #expect(ctx.isInstalled("Clock"))
        }

        @Test("a symlinked Spoons directory isn't followed")
        func testSymlinkedSpoonsDirectory() async throws {
            let ctx = try SpoonsTestContext()
            let outside = ctx.configDir.appendingPathComponent("outside/Secret.spoon2")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try #"{ "name": "Secret", "author": "Me", "version": "1", "description": "Not for you" }"#
                .write(to: outside.appendingPathComponent("spoon.json"), atomically: true, encoding: .utf8)
            try "module.exports = {};".write(to: outside.appendingPathComponent("init.js"), atomically: true, encoding: .utf8)

            var zip = ZipFixture()
            zip.spoon(at: "repo-main/Clock.spoon2", name: "Clock")
            zip.symlink("repo-main/Spoons", to: outside.deletingLastPathComponent().path)
            ctx.downloads.serve(zip.data, at: "https://example.com/repo.zip")

            await ctx.settle("hs.spoons.install('Secret', { source: 'https://example.com/repo.zip' })")
            #expect(ctx.errorCode == "ENOTFOUND")
            #expect(!ctx.isInstalled("Secret"))
        }
    }

    @Suite("available(), update(), uninstall()")
    @MainActor
    struct ManagementTests {

        @Test("available() lists the well-formed Spoons in a source without installing them")
        func testAvailable() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)

            let spoons = await ctx.settle("hs.spoons.available('jane/hs2-spoons').then(s => s.map(x => x.name + ' ' + x.version).join(','))")
            #expect(spoons?.toString() == "Clock 1.0.0,Greeter 1.0.0")
            #expect(!ctx.isInstalled("Greeter"))
        }

        @Test("update() reinstalls from the recorded source only when the version changed")
        func testUpdate() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(version: "1.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")

            #expect(await ctx.settle("hs.spoons.update('Greeter')")?.toBool() == false)

            ctx.downloads.serve(repositoryArchive(version: "1.1.0"), at: repositoryURL)
            #expect(await ctx.settle("hs.spoons.update('Greeter')")?.toBool() == true)
            #expect(try ctx.installedVersion("Greeter") == "1.1.0")
            #expect(ctx.downloads.requested.allSatisfy { $0.absoluteString == repositoryURL })
        }

        @Test("update() keeps checking a pinned sha256")
        func testUpdatePinnedHash() async throws {
            let ctx = try SpoonsTestContext()
            let archive = repositoryArchive(version: "1.0.0")
            let hash = sha256Hex(archive)
            ctx.downloads.serve(archive, at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', sha256: '\(hash)' })")

            ctx.downloads.serve(repositoryArchive(version: "1.1.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.update('Greeter')")
            #expect(ctx.errorCode == "EINTEGRITY")
            #expect(try ctx.installedVersion("Greeter") == "1.0.0")
        }

        @Test("update() rejects for a Spoon that isn't installed, or wasn't installed from a source")
        func testUpdateErrors() async throws {
            let ctx = try SpoonsTestContext()
            await ctx.settle("hs.spoons.update('Greeter')")
            #expect(ctx.errorCode == "ENOTINSTALLED")

            let local = ctx.spoonsDir.appendingPathComponent("Local")
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            try #"{ "name": "Local", "author": "Me", "version": "1", "description": "Mine" }"#
                .write(to: local.appendingPathComponent("spoon.json"), atomically: true, encoding: .utf8)
            try "module.exports = {};".write(to: local.appendingPathComponent("init.js"), atomically: true, encoding: .utf8)
            await ctx.settle("hs.spoons.update('Local')")
            #expect(ctx.errorCode == "ENOSOURCE")
        }

        @Test("update() sets isUpdating until it finishes")
        func testUpdateIsUpdating() async throws {
            let ctx = try SpoonsTestContext()
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == false)
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")

            ctx.downloads.close(repositoryURL)
            ctx.start("hs.spoons.update('Greeter')")
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.downloads.waitingCount == 1 })
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == true)
            ctx.downloads.open(repositoryURL)
            await ctx.settled()
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == false)
        }

        @Test("updateAll() updates every Spoon installed from a source, logging and resolving with what happened")
        func testUpdateAll() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(version: "1.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")
            await ctx.settle("hs.spoons.install('Clock', { source: 'jane/hs2-spoons' })")
            // Unique, so this test's log messages can be told apart from any other's
            let otherURL = "https://example.com/\(UUID().uuidString)/Alarm.zip"
            var other = ZipFixture()
            other.spoon(at: "Alarm.spoon2", name: "Alarm")
            ctx.downloads.serve(other.data, at: otherURL)
            await ctx.settle("hs.spoons.install('Alarm', { source: '\(otherURL)' })")

            // Installed without a source, so skipped
            let local = ctx.spoonsDir.appendingPathComponent("Local")
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            try #"{ "name": "Local", "author": "Me", "version": "1", "description": "Mine" }"#
                .write(to: local.appendingPathComponent("spoon.json"), atomically: true, encoding: .utf8)
            try "module.exports = {};".write(to: local.appendingPathComponent("init.js"), atomically: true, encoding: .utf8)

            ctx.downloads.serve(repositoryArchive(version: "1.1.0"), at: repositoryURL)
            var renamed = ZipFixture()
            renamed.spoon(at: "Alarms.spoon2", name: "Alarms")
            ctx.downloads.serve(renamed.data, at: otherURL)

            // Alarm is updated first, then Clock waits for its download
            ctx.downloads.close(repositoryURL)
            ctx.start("hs.spoons.updateAll().then(r => r.map(x => `${x.name}:${x.status}:${x.error === null ? 'ok' : x.error.code}`).join(','))")
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == true)
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.downloads.waitingCount == 1 })
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == true)
            ctx.downloads.open(repositoryURL)
            #expect(await ctx.settled()?.toString() == "Alarm:failed:ENOTFOUND,Clock:upToDate:ok,Greeter:updated:ok,Local:skipped:ok")
            #expect(ctx.harness.evalBool("hs.spoons.isUpdating") == false)

            #expect(try ctx.installedVersion("Greeter") == "1.1.0")
            #expect(try ctx.installedVersion("Clock") == "1.0.0")
            #expect(try ctx.installedVersion("Alarm") == "1.0.0")
            #expect(!ctx.downloads.requested.contains { $0.absoluteString.contains("Local") })

            func logged(_ fragment: String) -> Bool {
                HammerspoonLog.shared.entries(minimumLevel: .Info).contains { $0.msg.contains(fragment) }
            }
            #expect(await ctx.harness.waitForAsync(timeout: 5) {
                logged("couldn't update Alarm: \(otherURL) has no Spoon named 'Alarm'")
                    && logged("skipped Local, which wasn't installed by hs.spoons.install()")
                    && logged("finished: 1 updated (Greeter), 1 up to date, 1 skipped, 1 failed")
            })
        }

        @Test("a Spoon replaced by opening a .spoon2 file forgets where it was installed from")
        func testImportForgetsSource() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")

            // A bundle that was copied from an installed Spoon, so it has a source record too
            let bundle = ctx.configDir.appendingPathComponent("Greeter.spoon2")
            try FileManager.default.copyItem(at: ctx.spoonsDir.appendingPathComponent("Greeter"), to: bundle)
            try ctx.module.installer.spoonManager.performImport(ctx.module.installer.spoonManager.planImport(from: bundle))

            #expect(ctx.harness.evalBool("hs.spoons.installed()[0].source === undefined") == true)
            await ctx.settle("hs.spoons.update('Greeter')")
            #expect(ctx.errorCode == "ENOSOURCE")
        }

        @Test("update() doesn't undo an uninstall that happened while it was downloading")
        func testUpdateAfterUninstall() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(version: "1.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")
            ctx.downloads.serve(repositoryArchive(version: "1.1.0"), at: repositoryURL)

            ctx.downloads.close(repositoryURL)
            ctx.start("hs.spoons.update('Greeter')")
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.downloads.waitingCount == 1 })
            #expect(ctx.harness.evalBool("hs.spoons.uninstall('Greeter')") == true)
            ctx.downloads.open(repositoryURL)

            await ctx.settled()
            #expect(ctx.errorCode == "ENOTINSTALLED")
            #expect(!FileManager.default.fileExists(atPath: ctx.spoonsDir.appendingPathComponent("Greeter").path))
        }

        @Test("update() doesn't undo a reinstall that happened while it was downloading")
        func testUpdateAfterReinstall() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(version: "1.0.0"), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")
            ctx.downloads.serve(repositoryArchive(version: "1.1.0"), at: repositoryURL)
            let otherURL = "https://example.com/Greeter.zip"
            var other = ZipFixture()
            other.spoon(at: "Greeter.spoon2", name: "Greeter", version: "0.9.0")
            ctx.downloads.serve(other.data, at: otherURL)

            ctx.downloads.close(repositoryURL)
            ctx.harness.eval("""
                globalThis.__update = undefined;
                hs.spoons.update('Greeter').then(v => { __update = String(v) }, e => { __update = e.code });
                """)
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.downloads.waitingCount == 1 })
            await ctx.settle("hs.spoons.install('Greeter', { source: '\(otherURL)', force: true })")
            ctx.downloads.open(repositoryURL)

            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.harness.evalBool("__update !== undefined") == true })
            #expect(ctx.harness.evalString("__update") == "ECANCELED")
            #expect(try ctx.installedVersion("Greeter") == "0.9.0")
            #expect(ctx.harness.evalString("hs.spoons.installed()[0].source") == otherURL)
        }

        @Test("uninstall() removes the Spoon and its source record")
        func testUninstall() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' })")

            #expect(ctx.harness.evalBool("hs.spoons.uninstall('Greeter')") == true)
            #expect(!ctx.isInstalled("Greeter"))
            #expect(ctx.harness.evalInt("hs.spoons.installed().length") == 0)
            #expect(ctx.harness.evalBool("hs.spoons.uninstall('Greeter')") == false)
            #expect(!FileManager.default.fileExists(atPath: ctx.spoonsDir.appendingPathComponent("Greeter").path))

            ctx.harness.eval("hs.spoons.uninstall('../Greeter')")
            #expect(ctx.harness.hasException)
        }

        @Test("shutting down cancels a download in progress, without settling its Promise")
        func testShutdownCancels() async throws {
            let ctx = try SpoonsTestContext(downloads: FakeDownloads(hangs: true))
            ctx.harness.eval("""
                globalThis.__settled = false;
                hs.spoons.install('Greeter', { source: 'jane/hs2-spoons' }).then(() => { __settled = true }, () => { __settled = true });
                """)
            #expect(await ctx.harness.waitForAsync(timeout: 2) { ctx.downloads.requested.count == 1 })
            ctx.module.shutdown()
            await JSTestHarness.drainMainActorQueue()
            #expect(ctx.harness.evalBool("__settled") == false)
            #expect(!ctx.isInstalled("Greeter"))
        }
    }

    @Suite("shared downloads")
    @MainActor
    struct SharedDownloadTests {

        /// Installs each of `names` from the fake repository at once, resolving with each one's
        /// name, or its error's code
        private static func installAll(_ names: [String], options: String = "{ source: 'jane/hs2-spoons' }") -> String {
            let list = names.map { "'\($0)'" }.joined(separator: ", ")
            return """
                Promise.allSettled([\(list)].map(name => hs.spoons.install(name, \(options))))
                    .then(results => results.map(r => r.status === 'fulfilled' ? r.value.name : r.reason.code))
                """
        }

        /// The archives extracted into the temporary directory and not yet removed
        private static func extractedArchives() throws -> Set<String> {
            let names = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            return Set(names.filter { $0.hasPrefix("hs.spoons-") })
        }

        @Test("installs started together from one source share one download, and nothing is kept afterwards")
        func testConcurrentInstallsShareDownload() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.serve(repositoryArchive(), at: repositoryURL)
            let archivesBefore = try Self.extractedArchives()

            ctx.downloads.close(repositoryURL)
            ctx.start(Self.installAll(["Greeter", "Clock", "Nope"]))
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.module.installer.downloadCallerCount == 3 })
            #expect(ctx.downloads.waitingCount == 1)
            ctx.downloads.open(repositoryURL)

            // A Spoon the source doesn't have fails on its own, without affecting the others
            let results = await ctx.settled()
            #expect(results?.toArray() as? [String] == ["Greeter", "Clock", "ENOTFOUND"])
            #expect(ctx.downloads.requested == [URL(string: repositoryURL)!])
            #expect(ctx.isInstalled("Greeter"))
            #expect(ctx.isInstalled("Clock"))
            #expect(ctx.module.installer.downloadCallerCount == 0)
            #expect(try Self.extractedArchives() == archivesBefore)

            // The archive isn't cached: a later install downloads it again
            await ctx.settle("hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', force: true })")
            #expect(ctx.downloads.requested.count == 2)
        }

        @Test("a shared download that fails rejects every install waiting for it")
        func testSharedDownloadFails() async throws {
            let ctx = try SpoonsTestContext()
            ctx.downloads.close(repositoryURL)
            ctx.start(Self.installAll(["Greeter", "Clock"]))
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.module.installer.downloadCallerCount == 2 })
            ctx.downloads.open(repositoryURL)

            let results = await ctx.settled()
            #expect(results?.toArray() as? [String] == ["ENOTFOUND", "ENOTFOUND"])
            #expect(ctx.downloads.requested.count == 1)
            #expect(ctx.module.installer.downloadCallerCount == 0)
        }

        @Test("installs expecting different SHA-256s don't share a download")
        func testDifferentHashesDontShare() async throws {
            let ctx = try SpoonsTestContext()
            let archive = repositoryArchive()
            ctx.downloads.serve(archive, at: repositoryURL)
            let wrongHash = String(repeating: "0", count: 64)

            ctx.downloads.close(repositoryURL)
            ctx.start("""
                Promise.allSettled([
                    hs.spoons.install('Greeter', { source: 'jane/hs2-spoons', sha256: '\(sha256Hex(archive))' }),
                    hs.spoons.install('Clock', { source: 'jane/hs2-spoons', sha256: '\(wrongHash)' }),
                ]).then(results => results.map(r => r.status === 'fulfilled' ? r.value.name : r.reason.code))
                """)
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.downloads.waitingCount == 2 })
            ctx.downloads.open(repositoryURL)

            let results = await ctx.settled()
            #expect(results?.toArray() as? [String] == ["Greeter", "EINTEGRITY"])
            #expect(ctx.downloads.requested.count == 2)
        }

        @Test("shutting down cancels a shared download, so none of its installs are left waiting")
        func testShutdownCancelsSharedDownload() async throws {
            let ctx = try SpoonsTestContext(downloads: FakeDownloads(hangs: true))
            ctx.harness.eval("""
                globalThis.__settled = false;
                \(Self.installAll(["Greeter", "Clock"])).then(() => { __settled = true });
                """)
            #expect(await ctx.harness.waitForAsync(timeout: 2) {
                ctx.module.installer.downloadCallerCount == 2 && ctx.downloads.requested.count == 1
            })

            ctx.module.shutdown()
            // The download hangs for a minute unless it's cancelled
            #expect(await ctx.harness.waitForAsync(timeout: 5) { ctx.module.installer.downloadCallerCount == 0 })
            await JSTestHarness.drainMainActorQueue()
            #expect(ctx.harness.evalBool("__settled") == false)
            #expect(!ctx.isInstalled("Greeter"))
            #expect(!ctx.isInstalled("Clock"))
        }
    }

    @Suite("use()")
    @MainActor
    struct UseTests {

        private static let configurableSpoon = """
            module.exports = {
                log: [],
                message: "default",
                defaultHotkeys: { show: "default-mapping" },
                init() { this.log.push("init:" + this.message); },
                bindHotkeys(mapping) { this.log.push("bindHotkeys:" + JSON.stringify(mapping)); },
                start() { this.log.push("start:" + this.message); }
            };
            """

        @Test("an installed Spoon is loaded and configured before use() returns, without downloading")
        func testUseInstalled() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "Greeter.spoon2", name: "Greeter", initJS: Self.configurableSpoon)
            ctx.downloads.serve(zip.data, at: "https://example.com/Greeter.zip")
            await ctx.settle("hs.spoons.install('Greeter', { source: 'https://example.com/Greeter.zip' })")

            ctx.harness.eval("""
                var p = hs.spoons.use('Greeter', {
                    source: 'https://example.com/Greeter.zip',
                    config: { message: 'configured' },
                    hotkeys: 'default',
                    fn: (s) => s.log.push('fn:' + s.version),
                    start: true
                });
                var logNow = hs.spoons.Greeter.log.join('|');
                """)
            #expect(!ctx.harness.hasException)
            #expect(ctx.harness.evalString("logNow") == #"init:default|bindHotkeys:{"show":"default-mapping"}|fn:1.0.0|start:configured"#)
            #expect(await ctx.settle("p")?.forProperty("message").toString() == "configured")
            #expect(ctx.downloads.requested.count == 1)
        }

        @Test("an error in a Spoon's init.js is reported even when nothing catches use()'s Promise")
        func testUseErrorIsReportedWithoutCatch() async throws {
            let ctx = try SpoonsTestContext()
            var reported: [JSValue] = []
            try ctx.harness.context.install([UnhandledRejectionInstaller { reported.append($0) }])
            var zip = ZipFixture()
            zip.spoon(at: "Broken.spoon2", name: "Broken", initJS: "undefinedFunction();\nmodule.exports = {};")
            ctx.downloads.serve(zip.data, at: "https://example.com/Broken.zip")
            await ctx.settle("hs.spoons.install('Broken', { source: 'https://example.com/Broken.zip' })")

            ctx.harness.eval("hs.spoons.use('Broken', { start: true })")

            #expect(await ctx.harness.waitForAsync(timeout: 2) { !reported.isEmpty })
            let reason = try #require(reported.first)
            #expect(reason.toString() == "ReferenceError: Can't find variable: undefinedFunction")
            #expect(reason.forProperty("stack").toString().contains("Spoons/Broken/init.js"))
        }

        @Test("a Spoon that isn't installed is installed from its source, then configured")
        func testUseInstalls() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "Greeter.spoon2", name: "Greeter", initJS: Self.configurableSpoon)
            ctx.downloads.serve(zip.data, at: "https://example.com/Greeter.zip")

            let spoon = await ctx.settle("hs.spoons.use('Greeter', { source: 'https://example.com/Greeter.zip', hotkeys: { show: 1 }, start: true })")
            #expect(spoon?.forProperty("log").toArray() as? [String] == ["init:default", #"bindHotkeys:{"show":1}"#, "start:default"])
            #expect(ctx.isInstalled("Greeter"))
            #expect(ctx.harness.evalTypeOf("hs.spoons.Greeter") == "object")
        }

        @Test("path wins over source: the Spoon is loaded from it and configured, without installing anything")
        func testUsePathWinsOverSource() async throws {
            let ctx = try SpoonsTestContext()
            let devDir = ctx.configDir.appendingPathComponent("dev/Greeter.spoon2")
            try FileManager.default.createDirectory(at: devDir, withIntermediateDirectories: true)
            try #"{ "name": "Greeter", "author": "A. Developer", "version": "2.0.0-dev", "description": "Dev copy." }"#
                .write(to: devDir.appendingPathComponent("spoon.json"), atomically: true, encoding: .utf8)
            try Self.configurableSpoon.write(to: devDir.appendingPathComponent("init.js"), atomically: true, encoding: .utf8)

            let spoon = await ctx.settle("""
                hs.spoons.use('Greeter', {
                    source: 'jane/hs2-spoons',
                    ref: 'v1.0.0',
                    path: 'dev/Greeter.spoon2',
                    config: { message: 'configured' },
                    start: true
                })
                """)
            #expect(spoon?.forProperty("version").toString() == "2.0.0-dev")
            #expect(spoon?.forProperty("log").toArray() as? [String] == ["init:default", "start:configured"])
            #expect(ctx.downloads.requested.isEmpty)
            #expect(!ctx.isInstalled("Greeter"))
        }

        @Test("a path that doesn't exist rejects with ENOTFOUND, rather than falling back to source")
        func testUseMissingPath() async throws {
            let ctx = try SpoonsTestContext()
            await ctx.settle("hs.spoons.use('Greeter', { source: 'jane/hs2-spoons', path: 'dev/Nope.spoon2' })")
            #expect(ctx.errorCode == "ENOTFOUND")
            #expect(ctx.downloads.requested.isEmpty)
        }

        @Test("a Spoon that isn't installed and has no source rejects with ENOTINSTALLED")
        func testUseWithoutSource() async throws {
            let ctx = try SpoonsTestContext()
            await ctx.settle("hs.spoons.use('Greeter')")
            #expect(ctx.errorCode == "ENOTINSTALLED")
        }

        @Test("disable: true does nothing")
        func testUseDisabled() async throws {
            let ctx = try SpoonsTestContext()
            let result = await ctx.settle("hs.spoons.use('Greeter', { source: 'jane/hs2-spoons', disable: true })")
            #expect(result?.isNull == true)
            #expect(ctx.downloads.requested.isEmpty)
        }

        @Test("a configuration error rejects use()'s Promise, rather than throwing")
        func testUseConfigurationError() async throws {
            let ctx = try SpoonsTestContext()
            var zip = ZipFixture()
            zip.spoon(at: "Plain.spoon2", name: "Plain")
            ctx.downloads.serve(zip.data, at: "https://example.com/Plain.zip")
            await ctx.settle("hs.spoons.install('Plain', { source: 'https://example.com/Plain.zip' })")

            await ctx.settle("hs.spoons.use('Plain', { start: true })")
            #expect(ctx.harness.evalString("__error.message")?.contains("no start() method") == true)
            await ctx.settle("hs.spoons.use('Plain', { fn: 'not a function' })")
            #expect(ctx.errorCode == "EINVALIDARG")
        }
    }

    @Suite("bindHotkeys()")
    @MainActor
    struct BindHotkeysTests {

        // Unlikely to clash with anything else bound on the machine running the tests
        private static let mods = #"["cmd", "alt", "ctrl", "shift"]"#

        private static let actionsSpoon = """
            const log = [];
            module.exports = {
                log,
                bindings: {
                    show: () => log.push("show"),
                    hide: {
                        pressed: () => log.push("hide:pressed"),
                        released: () => log.push("hide:released"),
                        repeat: () => log.push("hide:repeat"),
                        message: "Hide"
                    }
                }
            };
            """

        /// A context with hs.hotkey loaded too, whose hs.hotkey.bind() records its arguments in
        /// `__binds` before binding, and a Spoon called Actions installed
        private func makeContext(initJS: String = Self.actionsSpoon) throws -> SpoonsTestContext {
            let ctx = try SpoonsTestContext()
            ctx.harness.loadModule(HSHotkeyModule.self, as: "hotkey")
            ctx.harness.eval("""
                globalThis.__binds = [];
                const realBind = hs.hotkey.bind;
                hs.hotkey.bind = function(...args) { __binds.push(args); return realBind.apply(hs.hotkey, args); };
                """)
            let dir = ctx.spoonsDir.appendingPathComponent("Actions")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try #"{ "name": "Actions", "author": "A. Developer", "version": "1.0.0", "description": "Actions." }"#
                .write(to: dir.appendingPathComponent("spoon.json"), atomically: true, encoding: .utf8)
            try initJS.write(to: dir.appendingPathComponent("init.js"), atomically: true, encoding: .utf8)
            return ctx
        }

        /// The hotkeys that are bound, as "key:message"
        private func boundHotkeys(_ ctx: SpoonsTestContext) -> [String] {
            let hotkeys = ctx.harness.evalValue("hs.hotkey.getHotkeys().map(h => h.key + ':' + h.message).sort()")
            return hotkeys?.toArray() as? [String] ?? []
        }

        @Test("a Spoon that exports bindings gets a bindHotkeys() that binds both hotkey forms to them")
        func testBindsBothForms() throws {
            let ctx = try makeContext()
            ctx.harness.eval("""
                var spoon = hs.spoons.load('Actions');
                var returned = spoon.bindHotkeys({
                    show: [\(Self.mods), "f17"],
                    hide: { mods: \(Self.mods), key: "f18" }
                });
                """)
            #expect(!ctx.harness.hasException)
            #expect(ctx.harness.evalBool("returned === spoon") == true)
            #expect(boundHotkeys(ctx) == ["f17:null", "f18:null"])

            // A plain function is the pressed callback; an object's callbacks are passed as they are
            ctx.harness.eval("__binds.forEach(([, , pressed, released, repeat]) => { pressed?.(); released?.(); repeat?.(); })")
            #expect(ctx.harness.evalValue("spoon.log")?.toArray() as? [String] == ["show", "hide:pressed", "hide:released", "hide:repeat"])
        }

        @Test("a hotkey has the user's message, or the Spoon's own, prefixed with its name, for true")
        func testMessages() throws {
            let ctx = try makeContext()
            ctx.harness.eval("""
                hs.spoons.load('Actions').bindHotkeys({
                    show: [\(Self.mods), "f17", "Show it"],
                    hide: [\(Self.mods), "f18", true]
                });
                """)
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f17:Show it", "f18:Actions: Hide"])
        }

        @Test("binding an action again replaces its hotkey, and null unbinds it")
        func testRebinding() throws {
            let ctx = try makeContext()
            ctx.harness.eval("var spoon = hs.spoons.load('Actions'); spoon.bindHotkeys({ show: [\(Self.mods), 'f17'], hide: [\(Self.mods), 'f18'] })")
            ctx.harness.eval("spoon.bindHotkeys({ show: [\(Self.mods), 'f19'] })")
            #expect(boundHotkeys(ctx) == ["f18:null", "f19:null"])
            ctx.harness.eval("spoon.bindHotkeys({ hide: null })")
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f19:null"])
        }

        @Test("two actions can swap hotkeys in one call")
        func testSwapping() throws {
            let ctx = try makeContext()
            ctx.harness.eval("var spoon = hs.spoons.load('Actions'); spoon.bindHotkeys({ show: [\(Self.mods), 'f17', 'show'], hide: [\(Self.mods), 'f18', 'hide'] })")
            ctx.harness.eval("spoon.bindHotkeys({ show: [\(Self.mods), 'f18', 'show'], hide: [\(Self.mods), 'f17', 'hide'] })")
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f17:hide", "f18:show"])
        }

        @Test("an action can have the name of an Object.prototype property")
        func testPrototypeNamedAction() throws {
            let ctx = try makeContext(initJS: "module.exports = { bindings: { constructor() {}, toString() {} } };")
            ctx.harness.eval("var spoon = hs.spoons.load('Actions'); spoon.bindHotkeys({ constructor: [\(Self.mods), 'f17'], toString: [\(Self.mods), 'f18'] })")
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f17:null", "f18:null"])
        }

        @Test("a mistake in the mapping throws EINVALIDARG without binding any of it")
        func testInvalidMappings() throws {
            let ctx = try makeContext()
            ctx.harness.eval("var spoon = hs.spoons.load('Actions')")
            for mapping in [
                "{ show: [\(Self.mods), 'f17'], shwo: [\(Self.mods), 'f18'] }",
                "{ show: [\(Self.mods), 'f17'], hide: ['cmd', 'f18'] }",
                "{ show: [\(Self.mods), 'f17'], hide: [\(Self.mods)] }",
                "{ show: 'cmd-f17' }",
                "{ show: [\(Self.mods), 'f17', 42] }",
                "null",
            ] {
                ctx.harness.eval("var code = null; try { spoon.bindHotkeys(\(mapping)) } catch (e) { code = e.code }")
                #expect(ctx.harness.evalString("code") == "EINVALIDARG", "\(mapping)")
            }
            #expect(boundHotkeys(ctx).isEmpty)
            #expect(ctx.harness.evalBool("spoon.bindHotkeys({}) === spoon") == true)
        }

        @Test("a binding that isn't a function or an object with callbacks throws when it's bound")
        func testInvalidBinding() throws {
            let ctx = try makeContext(initJS: "module.exports = { bindings: { show: 'nope', hide: { message: 'Hide' } } };")
            ctx.harness.eval("var spoon = hs.spoons.load('Actions')")
            for action in ["show", "hide"] {
                ctx.harness.eval("var code = null; try { spoon.bindHotkeys({ \(action): [\(Self.mods), 'f17'] }) } catch (e) { code = e.code }")
                #expect(ctx.harness.evalString("code") == "EINVALIDARG", "\(action)")
            }
            #expect(boundHotkeys(ctx).isEmpty)
        }

        @Test("unbindHotkeys() unbinds the named actions' hotkeys, or all of them")
        func testUnbinding() throws {
            let ctx = try makeContext()
            ctx.harness.eval("var spoon = hs.spoons.load('Actions'); spoon.bindHotkeys({ show: [\(Self.mods), 'f17'], hide: [\(Self.mods), 'f18'] })")
            #expect(ctx.harness.evalBool("spoon.unbindHotkeys(['hide']) === spoon") == true)
            #expect(boundHotkeys(ctx) == ["f17:null"])

            // An action that has no hotkey is skipped
            ctx.harness.eval("spoon.unbindHotkeys(['hide'])")
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f17:null"])

            ctx.harness.eval("spoon.bindHotkeys({ hide: [\(Self.mods), 'f18'] })")
            #expect(ctx.harness.evalBool("spoon.unbindHotkeys() === spoon") == true)
            #expect(boundHotkeys(ctx).isEmpty)

            // Its actions can be bound again afterwards
            ctx.harness.eval("spoon.bindHotkeys({ show: [\(Self.mods), 'f19'] })")
            #expect(!ctx.harness.hasException)
            #expect(boundHotkeys(ctx) == ["f19:null"])
        }

        @Test("a mistake in unbindHotkeys()'s actions throws EINVALIDARG without unbinding any of them")
        func testInvalidUnbinding() throws {
            let ctx = try makeContext()
            ctx.harness.eval("var spoon = hs.spoons.load('Actions'); spoon.bindHotkeys({ show: [\(Self.mods), 'f17'], hide: [\(Self.mods), 'f18'] })")
            for actions in ["['show', 'shwo']", "'show'", "[42]", "{ show: true }"] {
                ctx.harness.eval("var code = null; try { spoon.unbindHotkeys(\(actions)) } catch (e) { code = e.code }")
                #expect(ctx.harness.evalString("code") == "EINVALIDARG", "\(actions)")
            }
            #expect(boundHotkeys(ctx) == ["f17:null", "f18:null"])
        }

        @Test("bindings replace a Spoon's own bindHotkeys() and unbindHotkeys(), which are kept only without bindings")
        func testBindingsTakePrecedence() throws {
            let both = try makeContext(initJS: """
                module.exports = { bindings: { show() {} }, bindHotkeys() { return 'own' }, unbindHotkeys() { return 'own' } };
                """)
            both.harness.eval("var spoon = hs.spoons.load('Actions'); var returned = spoon.bindHotkeys({ show: [\(Self.mods), 'f17'] })")
            #expect(!both.harness.hasException)
            #expect(both.harness.evalBool("returned === spoon") == true)
            #expect(boundHotkeys(both) == ["f17:null"])
            #expect(both.harness.evalBool("spoon.unbindHotkeys() === spoon") == true)
            #expect(boundHotkeys(both).isEmpty)

            let own = try makeContext(initJS: "module.exports = { bindHotkeys() { return 'own' }, unbindHotkeys() { return 'own' } };")
            own.harness.eval("var spoon = hs.spoons.load('Actions')")
            #expect(own.harness.evalString("spoon.bindHotkeys({})") == "own")
            #expect(own.harness.evalString("spoon.unbindHotkeys()") == "own")

            let plain = try makeContext(initJS: "module.exports = {};")
            plain.harness.eval("var spoon = hs.spoons.load('Actions')")
            #expect(plain.harness.evalTypeOf("spoon.bindHotkeys") == "undefined")
            #expect(plain.harness.evalTypeOf("spoon.unbindHotkeys") == "undefined")
        }

        @Test("init() can bind hotkeys, and loading again doesn't replace bindHotkeys() or its hotkeys")
        func testFromInitAndReload() throws {
            let ctx = try makeContext(initJS: """
                module.exports = {
                    bindings: { show() {} },
                    init() { this.bindHotkeys({ show: [\(Self.mods), "f17"] }); }
                };
                """)
            ctx.harness.eval("var first = hs.spoons.load('Actions').bindHotkeys")
            ctx.harness.eval("var second = hs.spoons.load('Actions').bindHotkeys")
            #expect(!ctx.harness.hasException)
            #expect(ctx.harness.evalBool("first === second") == true)
            #expect(boundHotkeys(ctx) == ["f17:null"])
        }

        @Test("use()'s hotkeys option binds through the generic bindHotkeys()")
        func testUse() async throws {
            let ctx = try makeContext(initJS: Self.actionsSpoon.replacingOccurrences(
                of: "module.exports = {", with: "module.exports = { defaultHotkeys: { show: [\(Self.mods), 'f17'] },"))
            await ctx.settle("hs.spoons.use('Actions', { hotkeys: 'default' })")
            #expect(boundHotkeys(ctx) == ["f17:null"])
            await ctx.settle("hs.spoons.use('Actions', { hotkeys: { hide: [\(Self.mods), 'f18', true] } })")
            #expect(boundHotkeys(ctx) == ["f17:null", "f18:Actions: Hide"])
        }
    }
}
