//
//  CrashReportManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 20/10/2026.
//

import AppKit

/// Offers, at launch, to report the last crash of Hammerspoon 2 (or one of its helpers) as a
/// GitHub issue.
///
/// Nothing is sent anywhere by the app: it opens a pre-filled issue in the user's browser, puts
/// the redacted crash log on the clipboard and shows it in Finder, and the user decides what to
/// submit.
@_documentation(visibility: private)
@MainActor
final class CrashReportManager {
    static let shared = CrashReportManager()

    static let repository = URL(string: "https://github.com/cmsj/Hammerspoon2")!

    /// The UserDefaults key of the last time we looked for crash reports.
    static let lastCheckedKey = "crashReportsLastChecked"

    let reportsDirectory: URL
    let defaults: UserDefaults

    init(reportsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory),
         defaults: UserDefaults = .standard) {
        self.reportsDirectory = reportsDirectory
        self.defaults = defaults
    }

    /// Looks for crashes since the app last launched, and offers to report the newest one.
    func offerToReportNewCrashes() {
        guard SettingsManager.shared.offerCrashReports else { return }
        // The test host is the app itself, and a modal alert would stall the tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let crashes = newCrashReports(bundleIdentifier: bundleIdentifier)
        guard let newest = crashes.last else { return }
        AKInfo("Found \(crashes.count) new crash report(s), the newest at \(newest.file.path)")
        offerToReport(newest.report, otherCrashes: crashes.count - 1)
    }

    /// Crash reports of the app or its helpers written since the last call, oldest first.
    ///
    /// The first call only records when it happened, so crashes from before crash reporting
    /// existed (and whose dSYMs may not be published) aren't offered.
    func newCrashReports(bundleIdentifier: String, now: Date = Date()) -> [(file: URL, report: CrashReport)] {
        let lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        defaults.set(now, forKey: Self.lastCheckedKey)
        guard let lastChecked else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Reports macOS has already sent to Apple may have been moved into Retired.
        let directories = [reportsDirectory, reportsDirectory.appending(path: "Retired", directoryHint: .isDirectory)]
        var seenIncidents = Set<String>()
        var found: [(file: URL, report: CrashReport, date: Date)] = []
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension == "ips" {
                guard let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      created > lastChecked,
                      let text = try? String(contentsOf: file, encoding: .utf8),
                      let report = try? CrashReport(text: text, redactingHomeDirectory: home),
                      report.belongs(toBundleIdentifier: bundleIdentifier) else { continue }
                if let incident = report.incidentID, !seenIncidents.insert(incident).inserted { continue }
                found.append((file, report, created))
            }
        }
        return found.sorted { $0.date < $1.date }.map { ($0.file, $0.report) }
    }

    private func offerToReport(_ report: CrashReport, otherCrashes: Int) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(report.processName) Quit Unexpectedly"
        var information = """
            Would you like to report the crash on GitHub? This opens a new issue in your browser, \
            filled in with details of the crash, for you to review before you submit it. Nothing is \
            sent unless you do.
            """
        if otherCrashes > 0 {
            information += "\n\nThere \(otherCrashes == 1 ? "was 1 other crash" : "were \(otherCrashes) other crashes") since Hammerspoon 2 last started; this is the most recent."
        }
        alert.informativeText = information
        alert.addButton(withTitle: "Report on GitHub…")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't offer to report crashes"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            SettingsManager.shared.offerCrashReports = false
        }
        guard response == .alertFirstButtonReturn else { return }
        openIssue(for: report)
    }

    private func openIssue(for report: CrashReport) {
        let compact = report.compactText()
        let file = saveCompactReport(compact, for: report)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(compact, forType: .string)

        let fileName = file?.lastPathComponent ?? "the crash log"
        let placeholder = """
            The crash log is on your clipboard: select all of this text and paste over it. \
            If your clipboard has changed since, drag in \(fileName), which Hammerspoon 2 has \
            shown you in Finder.
            """
        let version = report.appVersion ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let url = CrashReportIssue.url(for: report, repository: Self.repository,
                                             version: version, crashLogPlaceholder: placeholder) else {
            AKError("Couldn't build a crash report issue URL")
            return
        }

        if let file {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        NSWorkspace.shared.open(url)
    }

    /// Writes the compact report where the user can find it to attach to the issue. It's a
    /// `.txt` file because GitHub doesn't accept `.ips` attachments.
    private func saveCompactReport(_ text: String, for report: CrashReport) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Hammerspoon 2 Crash Reports", directoryHint: .isDirectory)
        let name = "\(report.processName)-\(report.incidentID ?? UUID().uuidString).txt"
            .replacingOccurrences(of: "/", with: "-")
        let file = directory.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            AKError("Couldn't save the crash report to \(file.path): \(error.localizedDescription)")
            return nil
        }
    }
}
