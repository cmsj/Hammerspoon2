//
//  HSTaskReaper.swift
//  Hammerspoon 2
//

import Foundation
import Synchronization

/// Ensures processes that have been asked to terminate actually die.
///
/// When an `HSTask` is destroyed (module shutdown, config reload, or garbage collection), its
/// process is sent SIGTERM and handed to the reaper. If the process is still running once its
/// grace period expires, the reaper sends SIGKILL.
///
/// The reaper is process-wide rather than owned by `HSTaskModule`, because pending kills must
/// outlive both the `HSTask` (which may be deallocating) and the module (which is torn down and
/// recreated on every config reload).
///
/// In normal operation each pending process is watched by a detached task. Those tasks can't be
/// relied on while the app is terminating, so `drain(timeout:)` performs the same work
/// synchronously and is called from `applicationWillTerminate(_:)`.
@_documentation(visibility: private)
nonisolated final class HSTaskReaper: Sendable {
    static let shared = HSTaskReaper()

    /// How long a process is given to exit after SIGTERM before it is sent SIGKILL.
    static let defaultGracePeriod: Duration = .seconds(5)

    private static let pollInterval: Duration = .milliseconds(50)

    private struct Entry {
        let process: Process
        var deadline: ContinuousClock.Instant
    }

    /// The result of checking a pending process with `settle(_:at:forceKillAfter:)`.
    private enum Outcome {
        /// Still running and within its grace period, so it remains pending.
        case pending
        /// Exited, or was already resolved elsewhere. No longer pending.
        case exited
        /// Sent SIGKILL. No longer pending.
        case killed(pid_t)
        /// Sending SIGKILL failed. No longer pending, since retrying won't help.
        case killFailed(pid_t, error: String)
    }

    private let pending = Mutex<[ObjectIdentifier: Entry]>([:])

    /// The number of processes currently awaiting exit or SIGKILL.
    var pendingCount: Int {
        pending.withLock { $0.count }
    }

    /// Take responsibility for making sure a process exits.
    ///
    /// The caller should already have sent the process SIGTERM (or whatever signal it expects to
    /// end it). If the process is still running after `gracePeriod`, it is sent SIGKILL.
    ///
    /// Reaping a process that is already pending keeps the earlier of the two deadlines.
    /// - Parameters:
    ///   - process: The process to reap
    ///   - gracePeriod: How long to wait for the process to exit before sending SIGKILL
    func reap(_ process: Process, gracePeriod: Duration = defaultGracePeriod) {
        guard process.isRunning else { return }

        let key = ObjectIdentifier(process)
        let deadline = ContinuousClock.now + gracePeriod

        let isNew = pending.withLock { pending in
            if var existing = pending[key] {
                existing.deadline = min(existing.deadline, deadline)
                pending[key] = existing
                return false
            }
            pending[key] = Entry(process: process, deadline: deadline)
            return true
        }

        guard isNew else { return }

        Task.detached(name: "hs.task reaper (\(process.processIdentifier))") { [self] in
            while true {
                try? await Task.sleep(for: Self.pollInterval)
                switch settle(key, at: .now) {
                case .pending:
                    continue
                case .exited:
                    return
                case .killed(let pid):
                    await AKWarning(Self.killedMessage(pid))
                    return
                case .killFailed(let pid, let error):
                    await AKError(Self.killFailedMessage(pid, error))
                    return
                }
            }
        }
    }

    /// Block the calling thread until every pending process has exited or been sent SIGKILL.
    ///
    /// This is only intended for use while the app is terminating, when the detached watcher tasks
    /// started by `reap(_:gracePeriod:)` may never get to run. Each process is still given until its
    /// own deadline, but anything left running when `timeout` expires is sent SIGKILL regardless.
    /// - Parameter timeout: The maximum time to block for
    /// - Returns: The number of processes that were successfully sent SIGKILL
    @MainActor
    @discardableResult
    func drain(timeout: Duration = defaultGracePeriod) -> Int {
        let drainDeadline = ContinuousClock.now + timeout
        var killed = 0

        while true {
            let now = ContinuousClock.now
            let keys = pending.withLock { Array($0.keys) }
            if keys.isEmpty { break }

            for key in keys {
                switch settle(key, at: now, forceKillAfter: drainDeadline) {
                case .pending, .exited:
                    break
                case .killed(let pid):
                    killed += 1
                    AKWarning(Self.killedMessage(pid))
                case .killFailed(let pid, let error):
                    AKError(Self.killFailedMessage(pid, error))
                }
            }

            Thread.sleep(forTimeInterval: Self.pollInterval.timeInterval)
        }

        return killed
    }

    /// Check a pending process, and SIGKILL it if it has passed its deadline.
    private func settle(_ key: ObjectIdentifier,
                        at now: ContinuousClock.Instant,
                        forceKillAfter forcedDeadline: ContinuousClock.Instant? = nil) -> Outcome {
        pending.withLock { pending in
            guard let entry = pending[key] else { return .exited }

            // Foundation reaps the child itself, after which its PID may be reused. Checking
            // isRunning immediately before kill() means we only signal a PID we still own.
            guard entry.process.isRunning else {
                pending[key] = nil
                return .exited
            }

            let deadline = forcedDeadline.map { min($0, entry.deadline) } ?? entry.deadline
            guard now >= deadline else { return .pending }

            pending[key] = nil
            let pid = entry.process.processIdentifier
            if kill(pid, SIGKILL) == 0 {
                return .killed(pid)
            }
            return .killFailed(pid, error: unsafe String(cString: strerror(errno)))
        }
    }

    private static func killedMessage(_ pid: pid_t) -> String {
        "hs.task: Process \(pid) did not exit after SIGTERM, sent SIGKILL"
    }

    private static func killFailedMessage(_ pid: pid_t, _ error: String) -> String {
        "hs.task: Process \(pid) did not exit after SIGTERM, and SIGKILL failed: \(error)"
    }
}

private extension Duration {
    nonisolated var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
