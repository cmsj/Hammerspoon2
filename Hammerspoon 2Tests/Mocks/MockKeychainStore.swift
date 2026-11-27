//
//  MockKeychainStore.swift
//  Hammerspoon 2Tests
//

import Foundation
import Synchronization
@testable import Hammerspoon_2

/// An in-memory KeychainStore, since test builds made without code signing (CI, hs2vm) can't use
/// the real keychain. It records what it was asked, and can be made to fail.
nonisolated final class MockKeychainStore: KeychainStore {
    struct State {
        var items: [String: (write: KeychainWrite, created: Date)] = [:]
        var lastReason: String??
        /// Thrown by every operation while set
        var failure: KeychainError?
    }

    let state = Mutex(State())
    let isAvailable = true

    private static func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    func set(_ item: KeychainWrite) throws(KeychainError) {
        try state.withLock { state throws(KeychainError) in
            if let failure = state.failure { throw failure }
            state.items[Self.key(item.service, item.account)] = (item, Date())
        }
    }

    func secret(service: String, account: String, reason: String?) throws(KeychainError) -> String? {
        try state.withLock { state throws(KeychainError) in
            state.lastReason = .some(reason)
            if let failure = state.failure { throw failure }
            return state.items[Self.key(service, account)]?.write.secret
        }
    }

    func remove(service: String, account: String) throws(KeychainError) -> Bool {
        try state.withLock { state throws(KeychainError) in
            if let failure = state.failure { throw failure }
            return state.items.removeValue(forKey: Self.key(service, account)) != nil
        }
    }

    func items(service: String?) throws(KeychainError) -> [KeychainItemInfo] {
        try state.withLock { state throws(KeychainError) in
            if let failure = state.failure { throw failure }
            return state.items.values
                .filter { service == nil || $0.write.service == service }
                .map {
                    KeychainItemInfo(service: $0.write.service, account: $0.write.account, label: $0.write.label,
                                     comment: $0.write.comment, created: $0.created, modified: $0.created,
                                     synchronizable: $0.write.synchronizable)
                }
                .sorted { ($0.service, $0.account) < ($1.service, $1.account) }
        }
    }

    func write(service: String, account: String) -> KeychainWrite? {
        state.withLock { $0.items[Self.key(service, account)]?.write }
    }
}
