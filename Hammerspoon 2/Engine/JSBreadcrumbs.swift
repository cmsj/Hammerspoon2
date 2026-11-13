//
//  JSBreadcrumbs.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 13/11/2026.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras
import ObjectiveC

/// Records what JavaScript the app is running, so a crash report can say which part of the
/// user's config was running when the app crashed.
///
/// A crash report's backtrace shows the app's own frames: which event (a hotkey, a timer, ...)
/// called into JavaScript, and which API crashed. JavaScript frames are just JavaScriptCore's
/// interpreter, so it can't say which of the user's functions was running. This fills that gap.
///
/// Every time native code calls into JavaScript (`JSValue.call(withArguments:)`,
/// `invokeMethod(_:withArguments:)`, `construct(withArguments:)` and
/// `JSContext.evaluateScript(_:withSourceURL:)`, all hooked here), and every time an
/// `EventEmitter` calls a listener (engine.js), an entry is recorded. Two lists are kept:
/// what's running now, innermost last, and a ring of the most recent entries.
///
/// They're kept in a small memory-mapped file, one per process, rather than in memory. The
/// kernel writes a shared mapping's pages back to its file even when the process crashes, so
/// `CrashReportManager` can read them at the next launch and add them to the crash report.
///
/// Labels are function names, emitter and event names and script paths (with the home folder
/// replaced by `~`), never arguments or source code, since they end up in a public issue.
///
/// Only the main thread is recorded, since that's where JavaScript runs.
@safe @_documentation(visibility: private)
@MainActor
final class JSBreadcrumbs {
    struct Entry: Equatable, Sendable {
        var time: Date
        var label: String
    }

    /// The entries in a breadcrumbs file.
    struct Snapshot: Equatable, Sendable {
        /// What was running, outermost first.
        var running: [Entry]
        /// How many entries were running beyond those in `running`, which has a limited size.
        var omittedRunning: Int
        /// The most recent entries, oldest first.
        var recent: [Entry]
    }

    nonisolated static let runningCapacity = 16
    nonisolated static let recentCapacity = 32
    /// The longest label, in UTF-8 bytes. Longer ones are cut short.
    nonisolated static let labelCapacity = 118

    // The file is a header followed by `runningCapacity` records for the running entries and
    // then `recentCapacity` for the ring of recent ones.
    //
    // Header: magic (UInt32), format version (UInt32), running depth (Int32), index of the next
    // recent record (Int32), number of recent records in use (Int32).
    // Record: time since 1970 (Double), label length (UInt16), label (UTF-8).
    private nonisolated static let magic: UInt32 = 0x4853_4243 // "HSBC"
    private nonisolated static let formatVersion: UInt32 = 1
    private nonisolated static let headerSize = 32
    private nonisolated static let recordSize = 8 + 2 + labelCapacity
    nonisolated static let fileSize = headerSize + (runningCapacity + recentCapacity) * recordSize

    private nonisolated enum HeaderOffset {
        static let magic = 0
        static let version = 4
        static let depth = 8
        static let nextRecent = 12
        static let recentCount = 16
    }

    /// The recorder the hooks write to, if any.
    static var current: JSBreadcrumbs?

    /// Where each process's breadcrumbs go.
    nonisolated static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appending(path: Bundle.main.bundleIdentifier ?? "Hammerspoon 2", directoryHint: .isDirectory)
            .appending(path: "JavaScript Breadcrumbs", directoryHint: .isDirectory)
    }

    /// The breadcrumbs file of the process `pid`.
    nonisolated static func file(forProcess pid: Int32, in directory: URL) -> URL {
        directory.appending(path: "\(pid).breadcrumbs")
    }

    let file: URL
    private let buffer: UnsafeMutableRawPointer
    private var depth = 0
    private var nextRecent = 0
    private var recentCount = 0

    /// Creates (or empties) `file` and maps it into memory.
    init(file: URL) throws {
        let descriptor = open(file.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(Self.fileSize)) == 0 else { throw Self.posixError() }
        let mapping = unsafe mmap(nil, Self.fileSize, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
        guard let mapping = unsafe mapping, unsafe mapping != MAP_FAILED else { throw Self.posixError() }

        self.file = file
        unsafe self.buffer = mapping
        unsafe buffer.storeBytes(of: Self.magic, toByteOffset: HeaderOffset.magic, as: UInt32.self)
        unsafe buffer.storeBytes(of: Self.formatVersion, toByteOffset: HeaderOffset.version, as: UInt32.self)
    }

    isolated deinit {
        unsafe munmap(buffer, Self.fileSize)
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    // MARK: - Recording

    /// Starts recording for this process in `directory`, deleting all but the newest few
    /// files of earlier processes.
    static func start(in directory: URL = defaultDirectory, keeping: Int = 5) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            removeOldFiles(in: directory, keeping: keeping - 1)
            current = try JSBreadcrumbs(file: file(forProcess: getpid(), in: directory))
            installHooks()
        } catch {
            AKError("Couldn't start recording JavaScript breadcrumbs in \(directory.path): \(error.localizedDescription)")
        }
    }

    private static func removeOldFiles(in directory: URL, keeping: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let dated = files
            .filter { $0.pathExtension == "breadcrumbs" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (file, _) in dated.dropFirst(max(keeping, 0)) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Records `label` as running, until the matching `pop()`.
    func push(_ label: String) {
        let time = Date().timeIntervalSince1970
        if depth < Self.runningCapacity {
            write(label, time: time, toRecord: depth)
        }
        depth += 1
        storeHeader(depth, at: HeaderOffset.depth)

        write(label, time: time, toRecord: Self.runningCapacity + nextRecent)
        nextRecent = (nextRecent + 1) % Self.recentCapacity
        recentCount = min(recentCount + 1, Self.recentCapacity)
        storeHeader(nextRecent, at: HeaderOffset.nextRecent)
        storeHeader(recentCount, at: HeaderOffset.recentCount)
    }

    /// Records that the innermost running entry has finished.
    func pop() {
        depth = max(depth - 1, 0)
        storeHeader(depth, at: HeaderOffset.depth)
    }

    private func storeHeader(_ value: Int, at offset: Int) {
        unsafe buffer.storeBytes(of: Int32(clamping: value), toByteOffset: offset, as: Int32.self)
    }

    private func write(_ label: String, time: Double, toRecord index: Int) {
        let record = unsafe buffer + Self.headerSize + index * Self.recordSize
        // The length goes last, so a record cut short by a crash is at worst half-written.
        unsafe record.storeBytes(of: 0, toByteOffset: 8, as: UInt16.self)
        unsafe record.storeBytes(of: time, as: Double.self)
        var length = 0
        for byte in label.utf8.prefix(Self.labelCapacity) {
            unsafe record.storeBytes(of: byte, toByteOffset: 10 + length, as: UInt8.self)
            length += 1
        }
        unsafe record.storeBytes(of: UInt16(length), toByteOffset: 8, as: UInt16.self)
    }

    // MARK: - Reading

    /// The entries recorded by process `pid`, if it left a breadcrumbs file in `directory`.
    nonisolated static func snapshot(forProcess pid: Int32, in directory: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(forProcess: pid, in: directory)) else { return nil }
        return snapshot(of: data)
    }

    /// The entries in the contents of a breadcrumbs file.
    nonisolated static func snapshot(of data: Data) -> Snapshot? {
        guard data.count == fileSize else { return nil }
        return unsafe data.withUnsafeBytes { bytes -> Snapshot? in
            func load<T>(_ offset: Int, as type: T.Type) -> T {
                unsafe bytes.loadUnaligned(fromByteOffset: offset, as: type)
            }
            guard load(HeaderOffset.magic, as: UInt32.self) == magic,
                  load(HeaderOffset.version, as: UInt32.self) == formatVersion else { return nil }

            func entry(_ index: Int) -> Entry? {
                let offset = headerSize + index * recordSize
                let length = min(Int(load(offset + 8, as: UInt16.self)), labelCapacity)
                guard length > 0 else { return nil }
                let start = offset + 10
                let label = String(decoding: unsafe bytes[start..<start + length], as: UTF8.self)
                return Entry(time: Date(timeIntervalSince1970: load(offset, as: Double.self)), label: label)
            }

            let depth = max(Int(load(HeaderOffset.depth, as: Int32.self)), 0)
            let running = (0..<min(depth, runningCapacity)).compactMap { entry($0) }

            let nextRecent = Int(load(HeaderOffset.nextRecent, as: Int32.self))
            let recentCount = Int(load(HeaderOffset.recentCount, as: Int32.self))
            guard (0..<recentCapacity).contains(nextRecent), (0...recentCapacity).contains(recentCount) else { return nil }
            let recent = (0..<recentCount).compactMap { offset in
                entry(runningCapacity + (nextRecent - recentCount + offset + recentCapacity) % recentCapacity)
            }
            return Snapshot(running: running, omittedRunning: max(depth - runningCapacity, 0), recent: recent)
        }
    }

    // MARK: - Hooks

    /// Records `label()` as running, if this is the main thread and a recorder is running.
    /// - Returns: Whether it was recorded, in which case call `exit()` when it's finished
    nonisolated static func enter(_ label: () -> String) -> Bool {
        guard pthread_main_np() != 0, MainActor.assumeIsolated({ current != nil }) else { return false }
        let text = label()
        return MainActor.assumeIsolated {
            guard let current else { return false }
            current.push(text)
            return true
        }
    }

    /// Records that the innermost running entry has finished.
    nonisolated static func exit() {
        guard pthread_main_np() != 0 else { return }
        MainActor.assumeIsolated { current?.pop() }
    }

    /// Hooks the methods native code calls JavaScript with. Safe to call more than once.
    static func installHooks() {
        _ = hooksInstalled
    }

    private static let hooksInstalled: Void = {
        exchange(JSValue.self, #selector(JSValue.call(withArguments:)),
                 #selector(JSValue.breadcrumbCall(withArguments:)))
        exchange(JSValue.self, #selector(JSValue.construct(withArguments:)),
                 #selector(JSValue.breadcrumbConstruct(withArguments:)))
        exchange(JSValue.self, #selector(JSValue.invokeMethod(_:withArguments:)),
                 #selector(JSValue.breadcrumbInvokeMethod(_:withArguments:)))
        // evaluateScript(_:) calls this too.
        exchange(JSContext.self, #selector(JSContext.evaluateScript(_:withSourceURL:)),
                 #selector(JSContext.breadcrumbEvaluateScript(_:withSourceURL:)))
    }()

    private static func exchange(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else {
            AKError("Couldn't hook -[\(type) \(original)] for JavaScript breadcrumbs")
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    /// How a script is named in a label: bundled scripts by file name, others by path.
    nonisolated static func scriptName(_ url: URL?) -> String {
        guard let url else { return "script" }
        if let resources = Bundle.main.resourceURL?.path, url.path.hasPrefix(resources + "/") {
            return url.lastPathComponent
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.isFileURL ? url.path : url.absoluteString
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Hooked methods

// After `JSBreadcrumbs.installHooks()`, these and the methods they're named after have swapped
// implementations, so each calls the original by calling itself.
extension JSValue {
    /// A function's name, for labels.
    nonisolated var breadcrumbName: String {
        guard isObject, let name = forProperty("name"), name.isString,
              let string = name.toString(), !string.isEmpty else {
            return "anonymous function"
        }
        return string
    }

    @objc(hs_breadcrumbCallWithArguments:)
    nonisolated dynamic func breadcrumbCall(withArguments arguments: [Any]!) -> JSValue! {
        let entered = JSBreadcrumbs.enter { "call \(breadcrumbName)" }
        defer { if entered { JSBreadcrumbs.exit() } }
        return breadcrumbCall(withArguments: arguments)
    }

    @objc(hs_breadcrumbConstructWithArguments:)
    nonisolated dynamic func breadcrumbConstruct(withArguments arguments: [Any]!) -> JSValue! {
        let entered = JSBreadcrumbs.enter { "new \(breadcrumbName)" }
        defer { if entered { JSBreadcrumbs.exit() } }
        return breadcrumbConstruct(withArguments: arguments)
    }

    @objc(hs_breadcrumbInvokeMethod:withArguments:)
    nonisolated dynamic func breadcrumbInvokeMethod(_ method: String!, withArguments arguments: [Any]!) -> JSValue! {
        let entered = JSBreadcrumbs.enter { "call .\(method ?? "?")" }
        defer { if entered { JSBreadcrumbs.exit() } }
        return breadcrumbInvokeMethod(method, withArguments: arguments)
    }
}

extension JSContext {
    @objc(hs_breadcrumbEvaluateScript:withSourceURL:)
    nonisolated dynamic func breadcrumbEvaluateScript(_ script: String!, withSourceURL sourceURL: URL!) -> JSValue! {
        let entered = JSBreadcrumbs.enter { "evaluate \(JSBreadcrumbs.scriptName(sourceURL))" }
        defer { if entered { JSBreadcrumbs.exit() } }
        return breadcrumbEvaluateScript(script, withSourceURL: sourceURL)
    }
}

// MARK: - Event listeners

/// Gives engine.js the functions it records event listeners with. engine.js removes them from
/// the global scope once it has them.
struct JSBreadcrumbsInstaller: JSContextInstallable {
    func install(in context: JSContext) throws {
        let enter: @convention(block) (JSValue, JSValue, JSValue) -> Bool = { emitter, event, listener in
            JSBreadcrumbs.enter {
                let emitterName = emitter.isString ? emitter.toString() ?? "" : "EventEmitter"
                let eventName = event.isString ? event.toString() ?? "" : "event"
                return "\(emitterName) \"\(eventName)\" listener \(listener.breadcrumbName)"
            }
        }
        let exit: @convention(block) () -> Void = {
            JSBreadcrumbs.exit()
        }
        context.setObject(enter, forKeyedSubscript: "_hs_breadcrumbEnter" as NSString)
        context.setObject(exit, forKeyedSubscript: "_hs_breadcrumbExit" as NSString)
    }
}
