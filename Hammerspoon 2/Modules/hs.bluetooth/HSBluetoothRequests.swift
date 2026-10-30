//
//  HSBluetoothRequests.swift
//  Hammerspoon 2
//

import Foundation

/// Pending requests to a Bluetooth stack that answers through delegate callbacks.
///
/// CoreBluetooth and IOBluetooth report results through delegate methods that say what finished
/// (e.g. "a read of characteristic X") but not which request it answers, so each request waits
/// under a key describing what it's waiting for:
///  - `wait(for:timeout:start:)` waits for a key to be settled. Callers waiting for the same key
///    share one request: only the first calls `start`, and one callback settles them all. That
///    suits requests whose answer is the same for everyone (two reads of one characteristic).
///  - `serially(_:_:)` runs operations in a lane one at a time, for requests that mustn't share an
///    answer (each write has its own bytes) or whose effect depends on earlier ones (turning
///    notifications on, then off).
///
/// It knows nothing about Bluetooth, so its behaviour is tested without any hardware.
@MainActor
final class HSBluetoothRequests {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
    }

    private var waiters: [String: [Waiter]] = [:]
    /// The last operation queued in each lane of `serially(_:_:)`
    private var lanes: [String: Task<Void, Never>] = [:]
    /// Set by `close(_:)`, after which every request fails at once
    private var closedError: Error?

    /// The error a request gets when its callback doesn't arrive in time
    static let timeoutError = HSBluetoothError("the device didn't respond in time")

    /// Whether anything is waiting for `key`
    func isWaiting(for key: String) -> Bool {
        waiters[key] != nil
    }

    /// Waits until `key` is settled, calling `start` to make the request if nothing is waiting for
    /// it already. Throws whatever it's settled with, or `timeoutError` if it isn't settled within
    /// `timeout`. A `start` that throws settles everyone waiting with its error.
    func wait(for key: String, timeout: Duration, timeoutError: Error = HSBluetoothRequests.timeoutError,
              start: () throws -> Void) async throws {
        if let closedError { throw closedError }
        let isFirst = waiters[key] == nil
        let id = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.expire(key, id, timeoutError)
            }
            waiters[key, default: []].append(Waiter(id: id, continuation: continuation, timeout: timer))
            if isFirst {
                do {
                    try start()
                } catch {
                    settle(key, error)
                }
            }
        }
    }

    /// Settles everyone waiting for `key`: with `error`, or successfully if it's nil. Does nothing
    /// if nothing is waiting.
    func settle(_ key: String, _ error: Error?) {
        guard let settled = waiters.removeValue(forKey: key) else { return }
        for waiter in settled {
            waiter.timeout.cancel()
            if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume()
            }
        }
    }

    /// Fails everything waiting, e.g. when the device disconnects
    func failAll(_ error: Error) {
        for key in Array(waiters.keys) {
            settle(key, error)
        }
    }

    /// Fails everything waiting, and every later request, with `error`. For when the owner is
    /// being destroyed.
    func close(_ error: Error) {
        closedError = error
        failAll(error)
    }

    /// Runs `body` once every operation queued earlier in `lane` has finished, whether it
    /// succeeded or not, and returns or throws what `body` does.
    func serially(_ lane: String, _ body: @escaping @MainActor () async throws -> Void) async throws {
        let previous = lanes[lane]
        let operation = Task {
            await previous?.value
            if let closedError { throw closedError }
            try await body()
        }
        let finished = Task { _ = await operation.result }
        lanes[lane] = finished
        defer {
            if lanes[lane] == finished { lanes[lane] = nil }
        }
        try await operation.value
    }

    private func expire(_ key: String, _ id: UUID, _ error: Error) {
        guard let index = waiters[key]?.firstIndex(where: { $0.id == id }),
              let waiter = waiters[key]?.remove(at: index) else { return }
        if waiters[key]?.isEmpty ?? false { waiters[key] = nil }
        waiter.continuation.resume(throwing: error)
    }
}
