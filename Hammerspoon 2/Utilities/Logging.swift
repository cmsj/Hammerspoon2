//
//  HammerLog.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import HammerspoonSDK

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
        return self.logType.asString
    }
}

@_documentation(visibility: private)
@Observable
@MainActor
final class HammerspoonLog {
    static let shared = HammerspoonLog()

    /// `.Garbage` entries (module lifecycle/GC diagnostics) are extremely high volume
    /// compared to normal user-facing logging, so they get their own small, fixed
    /// capacity rather than sharing `consoleHistoryLength` with everything else.
    private static let garbageBufferCapacity = 200

    /// Per-level ring buffers, so a burst of low-severity entries (e.g. Debug)
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
        level == .Garbage ? Self.garbageBufferCapacity : SettingsManager.shared.consoleHistoryLength
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
