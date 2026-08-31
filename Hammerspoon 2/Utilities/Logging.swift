//
//  HammerLog.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import JavaScriptCore
import Synchronization
import os



@_documentation(visibility: private)
struct HammerspoonLogEntry: Identifiable, Equatable, Hashable {
    let id = UUID()
    let date = Date()
    /// Monotonically increasing, assigned by `HammerspoonLog.log(_:_:)`. Used to
    /// merge per-level buffers back into a single chronological stream, since
    /// `Date()` resolution can tie under bursty logging and ties would make
    /// cross-level interleave order ambiguous.
    let sequence: UInt64
    let logType: HammerspoonLogType
    let msg: String

    var levelString: String {
        get {
            return self.logType.asString
        }
    }
}

@_documentation(visibility: private)
extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs for Hammerspoon
    static let Hammerspoon = Logger(subsystem: subsystem, category: "Hammerspoon")
}

@_documentation(visibility: private)
@Observable
@MainActor
final class HammerspoonLog: Sendable {
    static let shared = HammerspoonLog()

    /// `.Debug` entries (module lifecycle/GC diagnostics) are extremely high volume
    /// compared to normal user-facing logging, so they get their own small, fixed
    /// capacity rather than sharing `consoleHistoryLength` with everything else.
    private static let debugBufferCapacity = 200

    /// Per-level ring buffers, so a burst of low-severity entries (e.g. Trace)
    /// can't evict high-severity entries (e.g. Error) before a user filtering
    /// the Console to a higher minimum level ever sees them.
    private var buffers: [HammerspoonLogType: [HammerspoonLogEntry]] = [:]

    @ObservationIgnored
    private var sequenceCounter: UInt64 = 0

    /// Cheap, `@Observable`-tracked change signal for consumers (e.g. hs.ipc's
    /// log-forwarding) that only need to know "did anything change", so they
    /// don't have to pay for a full merge/filter/sort of `entries(minimumLevel:)`
    /// on every single log call.
    private(set) var latestSequence: UInt64 = 0

    private func capacity(for level: HammerspoonLogType) -> Int {
        level == .Debug ? Self.debugBufferCapacity : SettingsManager.shared.consoleHistoryLength
    }

    func log(_ level: HammerspoonLogType, _ msg: String) {
        sequenceCounter += 1
        latestSequence = sequenceCounter

        var levelBuffer = buffers[level] ?? []
        levelBuffer.append(HammerspoonLogEntry(sequence: sequenceCounter, logType: level, msg: msg))

        let cap = capacity(for: level)
        if levelBuffer.count > cap {
            levelBuffer.removeFirst(levelBuffer.count - cap)
        }
        buffers[level] = levelBuffer
    }

    /// The merged, chronological view across every per-level buffer at or above
    /// `minimumLevel`, optionally filtered by `searchString`. This is the single
    /// source of truth for anything that wants to display or forward log history.
    func entries(minimumLevel: HammerspoonLogType, searchString: String = "") -> [HammerspoonLogEntry] {
        HammerspoonLogType.allCases
            .filter { $0.rawValue >= minimumLevel.rawValue }
            .flatMap { buffers[$0] ?? [] }
            .filter { searchString.isEmpty || $0.msg.localizedStandardContains(searchString) }
            .sorted { $0.sequence < $1.sequence }
    }

    func clearLog() {
        buffers.removeAll()
    }
}

@_documentation(visibility: private)
func AKLog(_ level: HammerspoonLogType, _ msg: String) {
    Task { @MainActor in
        HammerspoonLog.shared.log(level, msg)
    }
}

@_documentation(visibility: private)
func AKInfo(_ msg: String) {
    Logger.Hammerspoon.info("\(msg)")
    AKLog(.Info, msg)
}

@_documentation(visibility: private)
func AKWarning(_ msg: String) {
    Logger.Hammerspoon.warning("\(msg)")
    AKLog(.Warning, msg)
}

@_documentation(visibility: private)
func AKError(_ msg: String) {
    Logger.Hammerspoon.error("\(msg)")
    AKLog(.Error, msg)
}

@_documentation(visibility: private)
func AKTrace(_ msg: String) {
    Logger.Hammerspoon.debug("\(msg)")
    AKLog(.Trace, msg)
}

@_documentation(visibility: private)
func AKConsole(_ msg: String) {
    Logger.Hammerspoon.info("JS Console: \(msg)")
    AKLog(.Console, msg)
}

@_documentation(visibility: private)
func AKAutocomplete(_ msg: String) {
    // NOTE: This does not pass into Logger, there's really no need
    AKLog(.Autocomplete, msg)
}

/// Lock-free, thread-agnostic gate for `AKDebug`. `AKDebug` is called from
/// arbitrary threads/actors (including deinits of non-MainActor types) on some
/// hot paths, so checking whether debug logging is enabled must not require
/// hopping to `SettingsManager`'s `@MainActor` isolation or touching UserDefaults.
private let debugLoggingGate = Atomic<Bool>(false)

/// Enables/disables `AKDebug`'s runtime gate. Callable from any thread/actor.
/// `SettingsManager` calls this whenever `debugLoggingEnabled` changes.
func akSetDebugLoggingEnabled(_ enabled: Bool) {
    debugLoggingGate.store(enabled, ordering: .relaxed)
}

@_documentation(visibility: private)
func AKDebug(_ msg: @autoclosure () -> String) {
    guard debugLoggingGate.load(ordering: .relaxed) else { return }
    let message = msg()
    Logger.Hammerspoon.debug("\(message)")
    AKLog(.Debug, message)
}
