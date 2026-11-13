//
//  CrashReport.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 20/10/2026.
//

import Foundation

/// A crash report that macOS wrote to `~/Library/Logs/DiagnosticReports`.
///
/// These are `.ips` files: one line of JSON metadata (the header), then the report itself as
/// JSON (the body). Every crash gets one, whether or not the user shares analytics, so
/// reading them needs no SDK and sends nothing anywhere. The report is turned into a
/// redacted, size-limited copy that the user attaches to a GitHub issue, where
/// `.github/workflows/crash-report.yml` symbolicates it against the release's dSYMs.
@_documentation(visibility: private)
nonisolated struct CrashReport {
    enum ParseError: Error {
        case notAnIPSFile
        case notACrash
    }

    /// The `.ips` `bug_type` of a crash. Hangs, jetsam events and so on have other types.
    static let crashBugType = "309"

    /// Body keys that identify the Mac or the user rather than describe the crash.
    static let identifyingKeys: Set<String> = [
        "crashReporterKey", "bootSessionUUID", "sleepWakeUUID", "userID", "trialInfo",
        "instructionByteStream", "vmSummary",
    ]

    /// The largest compact report, in characters. A GitHub issue body holds 65,536, and the
    /// rest of the issue form needs some of that.
    static let maximumCompactLength = 50_000

    /// The body key the app adds the JavaScript that was running under (see `JSBreadcrumbs`).
    /// It survives `compactText()`, so the symbolicator can show it too.
    static let javaScriptKey = "hammerspoonJavaScript"

    let header: [String: Any]
    private(set) var body: [String: Any]

    /// Parses an `.ips` crash report.
    /// - Parameters:
    ///   - text: The contents of the `.ips` file
    ///   - homeDirectory: If given, this path is replaced by `~` throughout the report, so the
    ///     user's account name doesn't end up in a public issue
    /// - Throws: `ParseError.notAnIPSFile` if `text` isn't an `.ips` file, or
    ///   `ParseError.notACrash` if it's one that doesn't describe a crash
    init(text: String, redactingHomeDirectory homeDirectory: String? = nil) throws {
        var text = text
        if let homeDirectory, !homeDirectory.isEmpty, homeDirectory != "/" {
            text = Self.redact(homeDirectory, in: text)
        }
        guard let newline = text.firstIndex(of: "\n"),
              let header = Self.jsonObject(text[..<newline]),
              let body = Self.jsonObject(text[text.index(after: newline)...]) else {
            throw ParseError.notAnIPSFile
        }
        guard header["bug_type"] as? String == Self.crashBugType else {
            throw ParseError.notACrash
        }
        self.header = header
        self.body = body.filter { !Self.identifyingKeys.contains($0.key) }
    }

    private static func jsonObject(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// Replaces `home` with `~` wherever it's a whole path component, in both the plain and
    /// the JSON-escaped (`\/`) spellings of the path.
    private static func redact(_ home: String, in text: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        var result = text
        for spelling in [home, home.replacingOccurrences(of: "/", with: "\\/")] {
            let pattern = NSRegularExpression.escapedPattern(for: spelling) + #"(?=[/\\"]|$)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            result = regex.stringByReplacingMatches(in: result,
                                                    range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: "~")
        }
        return result
    }

    // MARK: - What crashed

    /// The report's unique ID.
    var incidentID: String? { header["incident_id"] as? String ?? body["incident"] as? String }

    /// The name of the process that crashed: the app, or one of its helpers.
    var processName: String { body["procName"] as? String ?? header["name"] as? String ?? "Unknown process" }

    /// The code signing identifier of the process that crashed.
    var codeSigningID: String? { body["codeSigningID"] as? String }

    /// The crashed process's `CFBundleShortVersionString`, if it has one. Helper tools don't.
    var appVersion: String? { Self.nonEmpty(header["app_version"]) }

    /// The crashed process's `CFBundleVersion`, if it has one.
    var buildVersion: String? { Self.nonEmpty(header["build_version"]) }

    /// The macOS version, e.g. `macOS 27.0.1 (26A434)`.
    var osVersion: String? { Self.nonEmpty(header["os_version"]) }

    /// When the crash happened, as macOS wrote it.
    var captureTime: String? { body["captureTime"] as? String }

    /// The process ID of the process that crashed.
    var pid: Int32? { (body["pid"] as? NSNumber)?.int32Value }

    /// Whether the crash was in the process with `bundleIdentifier`, or one of its helpers
    /// (whose identifiers start with it).
    func belongs(toBundleIdentifier bundleIdentifier: String) -> Bool {
        guard let codeSigningID else { return false }
        return codeSigningID == bundleIdentifier || codeSigningID.hasPrefix(bundleIdentifier + ".")
    }

    /// The exception, e.g. `EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0`.
    var exceptionDescription: String {
        let exception = body["exception"] as? [String: Any] ?? [:]
        var parts: [String] = []
        if let type = exception["type"] as? String { parts.append(type) }
        if let signal = exception["signal"] as? String { parts.append("(\(signal))") }
        if let subtype = exception["subtype"] as? String { parts.append(subtype) }
        return parts.isEmpty ? "Unknown exception" : parts.joined(separator: " ")
    }

    /// Why the process was terminated, if the system recorded a reason.
    var terminationDescription: String? {
        guard let termination = body["termination"] as? [String: Any] else { return nil }
        let parts = [termination["namespace"], termination["code"], termination["indicator"]]
            .compactMap { $0.map { "\($0)" } }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The "Application Specific Information" lines, such as the message of a Swift
    /// `fatalError` or an uncaught `NSException`'s reason.
    var applicationSpecificInformation: [String] {
        guard let asi = body["asi"] as? [String: Any] else { return [] }
        return asi.keys.sorted().flatMap { library in
            (asi[library] as? [String] ?? []).map { "\(library): \($0)" }
        }
    }

    private var threads: [[String: Any]] { body["threads"] as? [[String: Any]] ?? [] }
    private var usedImages: [[String: Any]] { body["usedImages"] as? [[String: Any]] ?? [] }

    private var faultingThreadIndex: Int? {
        if let index = (body["faultingThread"] as? NSNumber)?.intValue, threads.indices.contains(index) {
            return index
        }
        return threads.firstIndex { ($0["triggered"] as? Bool) == true }
    }

    // MARK: - Frames

    /// One frame of a backtrace.
    struct Frame: Equatable {
        let imageName: String
        let address: UInt64?
        let imageOffset: UInt64
        let symbol: String?
        let symbolOffset: UInt64?

        /// The frame as a line of a backtrace, e.g.
        /// `3   Hammerspoon 2      0x0000000100a1c2d4 Hammerspoon 2 + 115412`.
        func line(index: Int) -> String {
            let addressText = address.map { String(format: "0x%016llx", $0) } ?? "0x????????????????"
            let location: String
            if let symbol {
                location = "\(symbol) + \(symbolOffset ?? 0)"
            } else {
                location = "\(imageName) + \(imageOffset)"
            }
            let paddedIndex = String(index).padding(toLength: 4, withPad: " ", startingAt: 0)
            let paddedImage = imageName.padding(toLength: max(30, imageName.count + 1), withPad: " ", startingAt: 0)
            return "\(paddedIndex)\(paddedImage)\(addressText) \(location)"
        }
    }

    private func frames(_ rawFrames: [[String: Any]]) -> [Frame] {
        let images = usedImages
        return rawFrames.map { frame in
            let imageIndex = (frame["imageIndex"] as? NSNumber)?.intValue
            let image = imageIndex.flatMap { images.indices.contains($0) ? images[$0] : nil } ?? [:]
            let imageOffset = (frame["imageOffset"] as? NSNumber)?.uint64Value ?? 0
            let base = (image["base"] as? NSNumber)?.uint64Value
            return Frame(imageName: Self.imageName(image),
                         address: base.map { $0 &+ imageOffset },
                         imageOffset: imageOffset,
                         symbol: frame["symbol"] as? String,
                         symbolOffset: (frame["symbolLocation"] as? NSNumber)?.uint64Value)
        }
    }

    private static func imageName(_ image: [String: Any]) -> String {
        if let name = nonEmpty(image["name"]) { return name }
        if let path = nonEmpty(image["path"]) { return (path as NSString).lastPathComponent }
        return "???"
    }

    /// The backtrace of the thread that crashed.
    var crashedThreadFrames: [Frame] {
        guard let index = faultingThreadIndex else { return [] }
        return frames(threads[index]["frames"] as? [[String: Any]] ?? [])
    }

    /// Where an uncaught Objective-C exception was thrown, if that's what crashed the process.
    var lastExceptionBacktrace: [Frame] {
        frames(body["lastExceptionBacktrace"] as? [[String: Any]] ?? [])
    }

    // MARK: - JavaScript

    /// The report with what JavaScript the crashed process was running added to it.
    func adding(javaScript snapshot: JSBreadcrumbs.Snapshot) -> CrashReport {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        func entries(_ entries: [JSBreadcrumbs.Entry]) -> [[String: Any]] {
            entries.map { ["time": formatter.string(from: $0.time), "label": $0.label] }
        }

        var javaScript: [String: Any] = ["running": entries(snapshot.running), "recent": entries(snapshot.recent)]
        if snapshot.omittedRunning > 0 { javaScript["omittedRunning"] = snapshot.omittedRunning }
        var report = self
        report.body[Self.javaScriptKey] = javaScript
        return report
    }

    /// Lines describing the JavaScript that was running, and up to `recentLimit` of the
    /// entries before it, if the report has them.
    private func javaScriptLines(recentLimit: Int) -> [String] {
        guard let javaScript = body[Self.javaScriptKey] as? [String: Any] else { return [] }
        func lines(_ key: String) -> [String] {
            (javaScript[key] as? [[String: Any]] ?? []).map {
                "  \($0["time"] as? String ?? "")  \($0["label"] as? String ?? "")"
            }
        }

        var result = [""]
        let running = lines("running")
        if running.isEmpty {
            result.append("JavaScript running: none")
        } else {
            result.append("JavaScript running (innermost last):")
            result.append(contentsOf: running)
            if let omitted = javaScript["omittedRunning"] as? Int, omitted > 0 {
                // Only the outermost entries fit in the file.
                result.append("  ... and \(omitted) more inside those")
            }
        }
        let recent = lines("recent").suffix(recentLimit)
        if !recent.isEmpty {
            result.append("")
            result.append("Recent JavaScript (newest last):")
            result.append(contentsOf: recent)
        }
        return result
    }

    // MARK: - Reporting

    /// A short title for an issue about this crash.
    func issueTitle(version: String?) -> String {
        var title = "Crash: \(exceptionDescription) in \(processName)"
        if let version { title += " \(version)" }
        return String(title.prefix(200))
    }

    /// A human-readable summary of the crash, with the top `frameLimit` frames of the
    /// crashed thread and of any uncaught exception.
    func summary(version: String?, frameLimit: Int = 15) -> String {
        var lines: [String] = []
        lines.append("Process:     \(processName)")
        if let version {
            lines.append("Version:     \(version)" + (buildVersion.map { " (\($0))" } ?? ""))
        }
        if let osVersion { lines.append("macOS:       \(osVersion)") }
        if let model = body["modelCode"] as? String {
            lines.append("Hardware:    \(model)" + ((body["cpuType"] as? String).map { " (\($0))" } ?? ""))
        }
        if let captureTime { lines.append("Time:        \(captureTime)") }
        if let incidentID { lines.append("Incident:    \(incidentID)") }
        lines.append("Exception:   \(exceptionDescription)")
        if let terminationDescription { lines.append("Termination: \(terminationDescription)") }

        let asi = applicationSpecificInformation
        if !asi.isEmpty {
            lines.append("")
            lines.append("Application Specific Information:")
            lines.append(contentsOf: asi.map { String($0.prefix(500)) })
        }
        lines.append(contentsOf: javaScriptLines(recentLimit: min(frameLimit, 10)))

        func append(_ heading: String, _ frames: [Frame]) {
            guard !frames.isEmpty, frameLimit > 0 else { return }
            lines.append("")
            lines.append(heading)
            lines.append(contentsOf: frames.prefix(frameLimit).enumerated().map { $1.line(index: $0) })
            if frames.count > frameLimit {
                lines.append("... \(frames.count - frameLimit) more frames in the crash log")
            }
        }
        append("Last Exception Backtrace:", lastExceptionBacktrace)
        if let index = faultingThreadIndex {
            let thread = threads[index]
            let name = (thread["name"] as? String ?? thread["queue"] as? String).map { " (\($0))" } ?? ""
            append("Crashed Thread \(index)\(name):", crashedThreadFrames)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Compact report

    /// The report as `.ips` text again, cut down to what's needed to symbolicate and
    /// understand it: identifiers are removed, other threads' backtraces are trimmed, and only
    /// the binary images that frames refer to are kept. If it's still longer than
    /// `maximumLength`, other threads are trimmed further and then dropped.
    func compactText(maximumLength: Int = CrashReport.maximumCompactLength) -> String {
        // (frames kept per other thread, frames kept for the crashed thread and exception)
        let levels: [(other: Int?, crashed: Int)] = [(30, 512), (10, 256), (nil, 256), (nil, 64)]
        var text = ""
        for level in levels {
            text = compactText(otherThreadFrames: level.other, crashedFrames: level.crashed)
            if text.count <= maximumLength { break }
        }
        return text
    }

    private func compactText(otherThreadFrames: Int?, crashedFrames: Int) -> String {
        let crashedIndex = faultingThreadIndex
        var images = ImageTable(original: usedImages)
        var compact = body
        compact.removeValue(forKey: "usedImages")

        var keptThreads: [[String: Any]] = []
        for (index, thread) in threads.enumerated() {
            let isCrashed = index == crashedIndex
            guard isCrashed || otherThreadFrames != nil else { continue }
            var kept = thread.filter { ["id", "name", "queue", "triggered"].contains($0.key) }
            if isCrashed, let state = thread["threadState"] { kept["threadState"] = state }
            kept["index"] = index
            let frames = thread["frames"] as? [[String: Any]] ?? []
            let limit = isCrashed ? crashedFrames : (otherThreadFrames ?? 0)
            kept["frames"] = frames.prefix(limit).map { images.remap($0) }
            if frames.count > limit { kept["omittedFrames"] = frames.count - limit }
            keptThreads.append(kept)
        }
        compact["threads"] = keptThreads
        if let crashedIndex, otherThreadFrames == nil {
            // Thread indexes no longer line up with the array, so say where the crash is.
            compact["faultingThread"] = keptThreads.firstIndex { ($0["index"] as? Int) == crashedIndex } ?? 0
        }
        if threads.count != keptThreads.count {
            compact["omittedThreads"] = threads.count - keptThreads.count
        }

        if let backtrace = body["lastExceptionBacktrace"] as? [[String: Any]] {
            compact["lastExceptionBacktrace"] = backtrace.prefix(crashedFrames).map { images.remap($0) }
        }
        compact["usedImages"] = images.kept

        return Self.json(header) + "\n" + Self.json(compact)
    }

    /// Keeps only the images that frames refer to, renumbering the frames to match.
    private struct ImageTable {
        let original: [[String: Any]]
        var kept: [[String: Any]] = []
        var newIndex: [Int: Int] = [:]

        init(original: [[String: Any]]) {
            self.original = original
        }

        mutating func remap(_ frame: [String: Any]) -> [String: Any] {
            guard let index = (frame["imageIndex"] as? NSNumber)?.intValue, original.indices.contains(index) else {
                return frame
            }
            var frame = frame
            if let existing = newIndex[index] {
                frame["imageIndex"] = existing
            } else {
                newIndex[index] = kept.count
                frame["imageIndex"] = kept.count
                kept.append(original[index])
            }
            return frame
        }
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

// MARK: - GitHub issues

/// Builds the URL of a pre-filled "Crash report" issue (`.github/ISSUE_TEMPLATE/crash_report.yml`).
@_documentation(visibility: private)
nonisolated enum CrashReportIssue {
    static let template = "crash_report.yml"

    /// GitHub turns away very long URLs, so the summary is cut down until the URL fits.
    static let maximumURLLength = 7_500

    /// Field IDs in the issue template.
    enum Field {
        static let version = "version"
        static let macOSVersion = "macos-version"
        static let summary = "summary"
        static let crashLog = "crash-log"
    }

    /// The URL of a new crash report issue about `report`.
    /// - Parameters:
    ///   - report: The crash
    ///   - repository: The repository's URL, e.g. `https://github.com/cmsj/Hammerspoon2`
    ///   - version: The version that crashed. Defaults to the report's own, but helper tools
    ///     don't have one, so pass the app's
    ///   - crashLogPlaceholder: What the crash log field starts out as. The crash log itself
    ///     is far too long for a URL, so this tells the user how to add it
    static func url(for report: CrashReport, repository: URL, version: String?, crashLogPlaceholder: String) -> URL? {
        for frameLimit in [15, 10, 5, 0] {
            let fields: [(String, String)] = [
                ("template", template),
                ("title", report.issueTitle(version: version)),
                (Field.version, version ?? ""),
                (Field.macOSVersion, report.osVersion ?? ""),
                (Field.summary, report.summary(version: version, frameLimit: frameLimit)),
                (Field.crashLog, crashLogPlaceholder),
            ]
            let query = fields.map { "\($0)=\(encode($1))" }.joined(separator: "&")
            let string = repository.appending(path: "issues/new").absoluteString + "?" + query
            if string.count <= maximumURLLength || frameLimit == 0 {
                return URL(string: string)
            }
        }
        return nil
    }

    /// Percent-encodes everything but unreserved characters. `URLComponents` leaves `+` alone,
    /// which GitHub would read as a space.
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
