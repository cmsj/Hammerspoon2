//
//  CrashReportTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import Testing
@testable import Hammerspoon_2

/// The fixtures in Fixtures/CrashReports are real crash reports macOS wrote for a small program,
/// renamed to look like Hammerspoon 2 (`abort.ips`) and its IPC broker (`uncaught-exception.ips`),
/// with a fake home directory of /Users/someone. scripts/tests/symbolicate-crash.test.js uses
/// them too, to check they symbolicate.
@Suite("Crash reporting tests")
struct CrashReportTests {
    nonisolated static let bundleIdentifier = "net.tenshu.Hammerspoon-2"
    nonisolated static let home = "/Users/someone"

    static func fixtureText(_ name: String) throws -> String {
        let url = try #require(Bundle(for: JSTestHarness.self).url(forResource: name, withExtension: "ips"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func fixture(_ name: String) throws -> CrashReport {
        try CrashReport(text: fixtureText(name), redactingHomeDirectory: home)
    }

    /// abort.ips with `count` extra application-specific messages, each `length` copies of
    /// `character`.
    static func fixtureWithLongMessages(count: Int, length: Int, character: Character) throws -> CrashReport {
        let message = String(repeating: character, count: length)
        let messages = Array(repeating: "\"\(message)\"", count: count).joined(separator: ", ")
        let text = try fixtureText("abort").replacingOccurrences(of: #""abort() called""#, with: #""abort() called", "# + messages)
        return try CrashReport(text: text, redactingHomeDirectory: home)
    }

    @Suite("Parsing .ips files")
    struct ParsingTests {
        @Test("Reads what crashed from the app's report")
        func testAppReport() throws {
            let report = try fixture("abort")
            #expect(report.processName == "Hammerspoon 2")
            #expect(report.appVersion == "0.1.0")
            #expect(report.buildVersion == "1234")
            #expect(report.osVersion == "macOS 27.0.1 (26A434)")
            #expect(report.exceptionDescription == "EXC_CRASH (SIGABRT)")
            #expect(report.applicationSpecificInformation.contains("libsystem_c.dylib: abort() called"))
            #expect(report.lastExceptionBacktrace.isEmpty)
        }

        @Test("A helper's report has no version, but an exception backtrace")
        func testHelperReport() throws {
            let report = try fixture("uncaught-exception")
            #expect(report.processName == "HammerspoonIPCBroker")
            #expect(report.appVersion == nil)
            #expect(report.lastExceptionBacktrace.map(\.symbol).prefix(2) == ["__exceptionPreprocess", "objc_exception_throw"])
        }

        @Test("Crashes belong to the app and its helpers, not apps with a similar identifier",
              arguments: [
                ("abort", bundleIdentifier, true),
                ("uncaught-exception", bundleIdentifier, true),
                ("abort", "net.tenshu.Hammerspoon", false),
                ("abort", "net.tenshu.Hammerspoon-2.HammerspoonIPCBroker", false),
              ])
        func testBelongsToBundle(fixtureName: String, identifier: String, belongs: Bool) throws {
            #expect(try fixture(fixtureName).belongs(toBundleIdentifier: identifier) == belongs)
        }

        @Test("Crashed thread frames have their images and addresses")
        func testCrashedThreadFrames() throws {
            let frames = try fixture("abort").crashedThreadFrames
            #expect(frames.map(\.imageName) == [
                "libsystem_kernel.dylib", "libsystem_pthread.dylib", "libsystem_c.dylib",
                "Hammerspoon 2", "Hammerspoon 2", "dyld",
            ])
            #expect(frames[0].symbol == "__pthread_kill")
            // Release builds are stripped, so our own frames have no symbols until the
            // crash-report workflow symbolicates them.
            #expect(frames[3].symbol == nil)
            #expect(frames[3].address == 4_334_698_496 + 2220)
        }

        @Test("Text that isn't an .ips file is rejected")
        func testRejectsNonIPS() {
            #expect(throws: CrashReport.ParseError.notAnIPSFile) { try CrashReport(text: "Not a crash report") }
            #expect(throws: CrashReport.ParseError.notAnIPSFile) { try CrashReport(text: "{}\nnot json") }
        }

        @Test("Reports that aren't crashes are rejected")
        func testRejectsOtherReportTypes() throws {
            let hang = try fixtureText("abort").replacingOccurrences(of: #""bug_type":"309""#, with: #""bug_type":"288""#)
            #expect(throws: CrashReport.ParseError.notACrash) { try CrashReport(text: hang) }
        }
    }

    @Suite("Redaction and compact reports")
    struct CompactReportTests {
        @Test("The home directory and identifiers are removed",
              arguments: ["abort", "uncaught-exception"])
        func testRedaction(fixtureName: String) throws {
            let original = try fixtureText(fixtureName)
            #expect(original.contains(home))
            #expect(original.contains("crashReporterKey"))

            let compact = try fixture(fixtureName).compactText()
            #expect(!compact.contains(home))
            #expect(compact.contains("~/Applications/Hammerspoon 2.app/Contents/MacOS/"))
            #expect(compact.contains("~/.config/Hammerspoon2/init.js"))
            for key in CrashReport.identifyingKeys {
                #expect(!compact.contains("\"\(key)\""), "\(key) is still in the report")
            }
        }

        @Test("Only whole path components of the home directory are redacted")
        func testRedactsWholeComponents() throws {
            let text = try fixtureText("abort").replacingOccurrences(of: "/Users/someone/.config", with: "/Users/someoneelse/.config")
            let compact = try CrashReport(text: text, redactingHomeDirectory: home).compactText()
            #expect(compact.contains("/Users/someoneelse/.config"))
        }

        @Test("A compact report is still an .ips file with the same backtraces",
              arguments: ["abort", "uncaught-exception"])
        func testCompactRoundTrip(fixtureName: String) throws {
            let report = try fixture(fixtureName)
            let compact = try CrashReport(text: report.compactText())
            #expect(compact.incidentID == report.incidentID)
            #expect(compact.crashedThreadFrames == report.crashedThreadFrames)
            #expect(compact.lastExceptionBacktrace == report.lastExceptionBacktrace)
            #expect(compact.summary(version: "0.1.0") == report.summary(version: "0.1.0"))
        }

        @Test("A report that's too long loses its other threads, but keeps the crashed one")
        func testCompactDropsOtherThreads() throws {
            let report = try fixture("abort")
            let full = report.compactText()
            #expect(full.contains("fixture.worker"))

            let short = report.compactText(maximumLength: full.count - 1)
            #expect(!short.contains("fixture.worker"))
            let reparsed = try CrashReport(text: short)
            #expect(reparsed.crashedThreadFrames == report.crashedThreadFrames)
            #expect(short.contains(#""omittedThreads":1"#))
        }

        @Test("Long or many messages are cut short when nothing else makes the report fit",
              arguments: [(100, 2_000), (10_000, 20)])
        func testCompactCutsLongMessages(count: Int, length: Int) throws {
            let report = try fixtureWithLongMessages(count: count, length: length, character: "x")
            let compact = report.compactText()
            #expect(compact.count <= CrashReport.maximumCompactLength)
            let reparsed = try CrashReport(text: compact)
            #expect(reparsed.crashedThreadFrames == report.crashedThreadFrames)
            #expect(reparsed.applicationSpecificInformation.contains("libsystem_c.dylib: abort() called"))
        }
    }

    @Suite("GitHub issues")
    struct IssueTests {
        static let repository = URL(string: "https://github.com/cmsj/Hammerspoon2")!

        static func fields(_ url: URL) throws -> [String: String] {
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        }

        @Test("The issue URL fills in the crash report template")
        func testIssueURL() throws {
            let report = try fixture("abort")
            let url = try #require(CrashReportIssue.url(for: report, repository: Self.repository,
                                                        version: "0.1.0", crashLogPlaceholder: "Paste it here"))
            #expect(url.absoluteString.hasPrefix("https://github.com/cmsj/Hammerspoon2/issues/new?"))
            #expect(url.absoluteString.count <= CrashReportIssue.maximumURLLength)

            let fields = try Self.fields(url)
            #expect(fields["template"] == "crash_report.yml")
            #expect(fields["title"] == "Crash: EXC_CRASH (SIGABRT) in Hammerspoon 2 0.1.0")
            #expect(fields[CrashReportIssue.Field.version] == "0.1.0")
            #expect(fields[CrashReportIssue.Field.macOSVersion] == "macOS 27.0.1 (26A434)")
            #expect(fields[CrashReportIssue.Field.summary] == report.summary(version: "0.1.0"))
            #expect(fields[CrashReportIssue.Field.crashLog] == "Paste it here")
        }

        @Test("Plus signs are percent-encoded, so GitHub doesn't read them as spaces")
        func testPlusIsEncoded() throws {
            let report = try fixture("abort")
            let url = try #require(CrashReportIssue.url(for: report, repository: Self.repository,
                                                        version: "0.1.0", crashLogPlaceholder: "a+b"))
            #expect(!url.absoluteString.contains("+"))
            #expect(try Self.fields(url)[CrashReportIssue.Field.crashLog] == "a+b")
        }

        @Test("The summary is cut down to keep the URL short enough for GitHub")
        func testLongSummaryIsShortened() throws {
            let report = try fixture("abort")
            // Just too long for the URL with the whole summary in it.
            let fullURL = try #require(CrashReportIssue.url(for: report, repository: Self.repository,
                                                            version: "0.1.0", crashLogPlaceholder: ""))
            let longPlaceholder = String(repeating: "x", count: CrashReportIssue.maximumURLLength - fullURL.absoluteString.count + 1)
            let url = try #require(CrashReportIssue.url(for: report, repository: Self.repository,
                                                        version: "0.1.0", crashLogPlaceholder: longPlaceholder))
            let summary = try #require(try Self.fields(url)[CrashReportIssue.Field.summary])
            #expect(summary != report.summary(version: "0.1.0"))
            #expect(summary.contains("Exception:   EXC_CRASH (SIGABRT)"))
        }

        @Test("Long messages are cut short when dropping frames isn't enough")
        func testLongMessagesAreShortened() throws {
            // Each "é" is 6 characters once percent-encoded.
            let report = try fixtureWithLongMessages(count: 20, length: 500, character: "é")
            let url = try #require(CrashReportIssue.url(for: report, repository: Self.repository,
                                                        version: "0.1.0", crashLogPlaceholder: "Paste it here"))
            #expect(url.absoluteString.count <= CrashReportIssue.maximumURLLength)
            let summary = try #require(try Self.fields(url)[CrashReportIssue.Field.summary])
            #expect(summary.hasPrefix("Process:     Hammerspoon 2"))
            #expect(summary.hasSuffix("(cut short; the crash log has the rest)"))
        }
    }

    @Suite("Finding new crash reports", .serialized)
    @MainActor
    struct ManagerTests {
        let directory: URL
        let defaults: UserDefaults
        let suiteName = "CrashReportTests-\(UUID().uuidString)"

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "CrashReportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory.appending(path: "Retired"), withIntermediateDirectories: true)
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        // The files are only temporary, so this doesn't need to be isolated.
        nonisolated func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        func write(_ fixtureName: String, as fileName: String, in subdirectory: String? = nil,
                   replacing target: String? = nil, with replacement: String = "") throws {
            var text = try fixtureText(fixtureName)
            if let target {
                text = text.replacingOccurrences(of: target, with: replacement)
            }
            let folder = subdirectory.map { directory.appending(path: $0) } ?? directory
            try text.write(to: folder.appending(path: fileName), atomically: true, encoding: .utf8)
        }

        @Test("The first check only records when it happened")
        func testFirstCheckFindsNothing() throws {
            defer { cleanUp() }
            try write("abort", as: "Hammerspoon 2-2026-10-20-120000.ips")
            let manager = CrashReportManager(reportsDirectory: directory, defaults: defaults)
            let now = Date()
            #expect(manager.newCrashReports(bundleIdentifier: bundleIdentifier, now: now).isEmpty)
            #expect(defaults.object(forKey: CrashReportManager.lastCheckedKey) as? Date == now)
        }

        @Test("Later checks find our crashes since the last one, oldest first, once each")
        func testFindsNewCrashes() throws {
            defer { cleanUp() }
            defaults.set(Date.distantPast, forKey: CrashReportManager.lastCheckedKey)

            try write("uncaught-exception", as: "HammerspoonIPCBroker-2026-10-20-120000.ips")
            try write("abort", as: "Hammerspoon 2-2026-10-20-120001.ips")
            // macOS may move a report it's sent to Apple into Retired; it's still the same crash.
            try write("abort", as: "Hammerspoon 2-2026-10-20-120001.ips", in: "Retired")
            try write("abort", as: "Other-2026-10-20-120002.ips",
                      replacing: #""codeSigningID": "net.tenshu.Hammerspoon-2""#,
                      with: #""codeSigningID": "com.example.other""#)
            try write("abort", as: "Hammerspoon 2-2026-10-20-120003.txt")

            let manager = CrashReportManager(reportsDirectory: directory, defaults: defaults)
            let found = manager.newCrashReports(bundleIdentifier: bundleIdentifier)
            #expect(found.map(\.report.processName) == ["HammerspoonIPCBroker", "Hammerspoon 2"])
            #expect(manager.newCrashReports(bundleIdentifier: bundleIdentifier).isEmpty)
        }

        @Test("Found reports are redacted")
        func testFoundReportsAreRedacted() throws {
            defer { cleanUp() }
            defaults.set(Date.distantPast, forKey: CrashReportManager.lastCheckedKey)
            let realHome = FileManager.default.homeDirectoryForCurrentUser.path
            try write("abort", as: "Hammerspoon 2-2026-10-20-120000.ips", replacing: home, with: realHome)

            let manager = CrashReportManager(reportsDirectory: directory, defaults: defaults)
            let report = try #require(manager.newCrashReports(bundleIdentifier: bundleIdentifier).first?.report)
            #expect(!report.compactText().contains(realHome + "/"))
        }
    }
}
