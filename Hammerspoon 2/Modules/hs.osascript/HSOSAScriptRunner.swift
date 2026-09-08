//
//  HSOSAScriptRunner.swift
//  Hammerspoon 2
//

import Foundation
import Synchronization

/// Executes OSA scripts via the `HammerspoonOSAScriptHelper` XPC service.
///
/// A single `XPCSession` is cached and reused across calls, since standing up
/// a fresh XPC connection for every script execution is expensive. `XPCSession`
/// is torn down (not silently reconnected) when its peer disappears, but it
/// reports this via a cancellation handler, so the cached session is cleared
/// there and lazily recreated - relaunching the helper process - on next use.
final class HSOSAScriptRunner: Sendable {

    private let cachedSession = Mutex<XPCSession?>(nil)

    // MARK: - Public API

    /// Execute an OSA script in the helper process.
    ///
    /// - Parameters:
    ///   - source: Script source code.
    ///   - language: OSA language name (`"AppleScript"` or `"JavaScript"`).
    /// - Returns: A tuple where:
    ///   - `success` mirrors the helper's success flag.
    ///   - `resultJSON` is a JSON string of the parsed result (nil on failure).
    ///   - `raw` is `result.stringValue` on success, or the error message on failure.
    /// - Throws: Only for XPC infrastructure failures (connection refused, helper crash
    ///   before reply, etc.).  Script-level errors are returned as `(false, nil, message)`.
    func run(source: String, language: String) async throws -> (Bool, String?, String) {
        let session = try session()

        return try await withCheckedThrowingContinuation { continuation in
            let message = HSOSARequest(language: language, source: source)

            do {
                try session.send(message) { result in
                    var success = false
                    var resultJSON: String? = ""
                    var raw = ""

                    switch result {
                    case let .success(result):
                        if let response = try? result.decode(as: HSOSAResponse.self) {
                            success = response.success
                            resultJSON = response.jsonMessage
                            raw = response.rawMessage
                        } else {
                            raw = "Unable to decode response"
                        }
                    case let .failure(error):
                        raw = error.localizedDescription
                    }

                    continuation.resume(returning: (success, resultJSON, raw))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Execute an OSA script in the helper process synchronously.
    ///
    /// Blocks the calling thread until the helper responds.  Use only when an
    /// async context is not available; prefer `run(source:language:)` otherwise.
    ///
    /// - Parameters:
    ///   - source: Script source code.
    ///   - language: OSA language name (`"AppleScript"` or `"JavaScript"`).
    /// - Returns: A tuple where:
    ///   - `success` mirrors the helper's success flag.
    ///   - `resultJSON` is a JSON string of the parsed result (nil on failure).
    ///   - `raw` is `result.stringValue` on success, or the error message on failure.
    /// - Throws: Only for XPC infrastructure failures (connection refused, helper crash, etc.).
    ///   Script-level errors are returned as `(false, nil, message)`.
    func runSync(source: String, language: String) throws -> (Bool, String?, String) {
        let session = try session()

        let message = HSOSARequest(language: language, source: source)
        let received = try session.sendSync(message)

        if let response = try? received.decode(as: HSOSAResponse.self) {
            return (response.success, response.jsonMessage, response.rawMessage)
        } else {
            return (false, nil, "Unable to decode response")
        }
    }

    /// Tears down the cached session, if any.
    func shutdown() {
        teardownCachedSession(reason: "HSOSAScriptRunner shutdown")
    }

    /// An `XPCSession` that is still active when its last reference is
    /// released triggers a fatal `_xpc_api_misuse` trap - it must be
    /// cancelled first. `shutdown()` isn't guaranteed to run before this
    /// object deallocates (e.g. in tests), so cancel here too as a backstop.
    isolated deinit {
        teardownCachedSession(reason: "HSOSAScriptRunner deinit")
    }

    // MARK: - Private helpers

    private func teardownCachedSession(reason: String) {
        let session = cachedSession.withLock { cached -> XPCSession? in
            defer { cached = nil }
            return cached
        }
        session?.cancel(reason: reason)
    }

    /// Returns the cached `XPCSession`, creating and activating a new one if
    /// none is cached - e.g. on first use, or after the helper process
    /// crashed/exited and the previous session's cancellation handler cleared it.
    ///
    /// `session()` only ever runs on the main actor, so there's no need to
    /// guard against two calls racing to create a session here. The cache
    /// still needs a lock because a session's cancellation handler can fire
    /// on an arbitrary queue, off the main actor.
    private func session() throws -> XPCSession {
        if let cached = cachedSession.withLock({ $0 }) {
            return cached
        }

        let session = try makeSession()
        cachedSession.withLock { $0 = session }
        return session
    }

    private func makeSession() throws -> XPCSession {
        let session = try XPCSession(xpcService: HSOSAScriptServiceName, options: .inactive)
#if DEBUG
        AKWarning("OSASCRIPT XPC SERVICE RUNNING WITHOUT PEER REQUIREMENTS. This is a serious security risk, do not use this build for production.")
#else
        AKDebug("Enforcing peer requirement for XPC connections.")
        session.setPeerRequirement(.isFromSameTeam())
#endif
        // Weakly capture `session` itself (not just `self`) so a cancellation
        // that arrives after this particular session has already been
        // replaced in the cache doesn't clear out its (unrelated) successor.
        session.setCancellationHandler { [weak self, weak session] error in
            AKDebug("hs.osascript XPC session was cancelled (\(error)); a new session will be created on next use")
            guard let self, let session else { return }
            self.cachedSession.withLock { cached in
                if cached === session {
                    cached = nil
                }
            }
        }

        try session.activate()
        return session
    }
}
