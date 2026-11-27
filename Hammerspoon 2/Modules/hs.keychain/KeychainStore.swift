//
//  KeychainStore.swift
//  Hammerspoon 2
//

import Foundation
import Security
import LocalAuthentication

// MARK: - Errors

/// Why a keychain operation failed. `code` becomes the `code` property of the JS Error.
nonisolated struct KeychainError: Error, Sendable, Equatable {
    let code: String
    let message: String
    /// The Security framework `OSStatus`, when the failure came from it
    let status: OSStatus?

    static func invalidArgument(_ message: String) -> KeychainError {
        KeychainError(code: "EINVALIDARG", message: message, status: nil)
    }

    static let missingEntitlement = KeychainError(
        code: "ENOENTITLEMENT",
        message: "this copy of Hammerspoon 2 isn't signed with a keychain access group, so it can't use the keychain "
            + "(builds made without code signing, such as CI and VM test builds, can't)",
        status: errSecMissingEntitlement
    )

    /// Maps a failing `OSStatus` from the Security framework to an error
    init(status: OSStatus) {
        if status == errSecMissingEntitlement {
            self = .missingEntitlement
            return
        }
        self.status = status
        let description = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        switch status {
        case errSecUserCanceled:
            code = "ECANCELED"
        case errSecAuthFailed:
            code = "EAUTH"
        case errSecInteractionNotAllowed:
            code = "EINTERACTION"
        case errSecNotAvailable, errSecNoSuchKeychain:
            code = "EUNAVAILABLE"
        default:
            code = "EKEYCHAIN"
        }
        message = "\(description) (OSStatus \(status))"
    }

    init(code: String, message: String, status: OSStatus?) {
        self.code = code
        self.message = message
        self.status = status
    }
}

// MARK: - Values

/// A secret to store, and how to protect it
nonisolated struct KeychainWrite: Sendable, Equatable {
    var service: String
    var account: String
    var secret: String
    var label: String?
    var comment: String?
    /// Sync the item to the user's other devices through iCloud Keychain
    var synchronizable = false
    /// Require Touch ID, an Apple Watch or the user's password each time the secret is read
    var requireUserPresence = false
}

/// What can be known about a stored item without reading its secret
nonisolated struct KeychainItemInfo: Sendable, Equatable {
    var service: String
    var account: String
    var label: String?
    var comment: String?
    var created: Date?
    var modified: Date?
    var synchronizable: Bool

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "service": service,
            "account": account,
            "synchronizable": synchronizable,
        ]
        result["label"] = label
        result["comment"] = comment
        result["created"] = created
        result["modified"] = modified
        return result
    }
}

// MARK: - Store

/// The keychain operations hs.keychain needs, so tests can stand in a fake: builds without code
/// signing (CI, the hs2vm VMs) have no keychain access group, so the real keychain refuses them.
///
/// Every method may be called from any thread. `secret` can block while macOS asks the user to
/// authenticate, so it must not be called on the main thread.
nonisolated protocol KeychainStore: Sendable {
    /// Whether this process can use the keychain at all
    var isAvailable: Bool { get }
    /// Adds the item, replacing any item with the same service and account
    func set(_ item: KeychainWrite) throws(KeychainError)
    /// The item's secret, or nil if there's no such item
    func secret(service: String, account: String, reason: String?) throws(KeychainError) -> String?
    /// Removes the item. Returns false if there was no such item.
    func remove(service: String, account: String) throws(KeychainError) -> Bool
    /// Every item, or every item for one service, without their secrets
    func items(service: String?) throws(KeychainError) -> [KeychainItemInfo]
}

/// The data protection keychain (the iOS-style one), restricted to Hammerspoon 2's own keychain
/// access group. Unlike the legacy file-based keychain, nothing outside that access group can
/// read, list, or even see these items, and items can require user presence or sync via iCloud.
nonisolated struct SecurityKeychainStore: KeychainStore {
    /// The access group items are stored in: the first `keychain-access-groups` entitlement,
    /// with its team ID prefix already expanded (e.g. "ABCDE12345.net.tenshu.Hammerspoon-2.keychainGroup").
    /// Nil when the process isn't signed with one.
    let accessGroup: String?

    init(accessGroup: String? = SecurityKeychainStore.entitledAccessGroup()) {
        self.accessGroup = accessGroup
    }

    var isAvailable: Bool { accessGroup != nil }

    /// Reads this process's own `keychain-access-groups` entitlement
    static func entitledAccessGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil),
              let groups = value as? [String] else {
            return nil
        }
        return groups.first
    }

    private func baseQuery(service: String?, account: String?) throws(KeychainError) -> [CFString: Any] {
        guard let accessGroup else { throw .missingEntitlement }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessGroup: accessGroup,
            // Without this, queries only match items that don't sync
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
        ]
        query[kSecAttrService] = service
        query[kSecAttrAccount] = account
        return query
    }

    func set(_ item: KeychainWrite) throws(KeychainError) {
        guard let accessGroup else { throw .missingEntitlement }
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecAttrSynchronizable: item.synchronizable,
            kSecValueData: Data(item.secret.utf8),
        ]
        attributes[kSecAttrLabel] = item.label
        attributes[kSecAttrComment] = item.comment

        // After first unlock, rather than while unlocked, so a config can still read its secrets
        // while the screen is locked (e.g. a timer making an authenticated HTTP request).
        // Items that sync can't be limited to this device.
        let accessible = item.synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if item.requireUserPresence {
            var error: Unmanaged<CFError>?
            guard let access = unsafe SecAccessControlCreateWithFlags(nil, accessible, .userPresence, &error) else {
                let message = unsafe error?.takeRetainedValue().localizedDescription ?? "unknown error"
                throw KeychainError(code: "EKEYCHAIN", message: "couldn't create access control: \(message)", status: nil)
            }
            attributes[kSecAttrAccessControl] = access
        } else {
            attributes[kSecAttrAccessible] = accessible
        }

        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Replace it outright, rather than SecItemUpdate, so the new protection and
            // attributes all apply. The add just failed only because the item exists, so
            // it won't fail again for another reason after the old one is gone.
            var existing = try baseQuery(service: item.service, account: item.account)
            existing[kSecAttrSynchronizable] = item.synchronizable
            status = SecItemDelete(existing as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }

        // Whether an item syncs is part of its identity, so an item with the same service and
        // account that does the opposite is a separate item. Remove it, or there'd be two.
        var other = try baseQuery(service: item.service, account: item.account)
        other[kSecAttrSynchronizable] = !item.synchronizable
        status = SecItemDelete(other as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    func secret(service: String, account: String, reason: String?) throws(KeychainError) -> String? {
        var query = try baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let context = LAContext()
        if let reason {
            context.localizedReason = reason
        }
        query[kSecUseAuthenticationContext] = context

        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError(code: "EKEYCHAIN", message: "the stored secret isn't text", status: nil)
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func remove(service: String, account: String) throws(KeychainError) -> Bool {
        let status = SecItemDelete(try baseQuery(service: service, account: account) as CFDictionary)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError(status: status)
        }
    }

    func items(service: String?) throws(KeychainError) -> [KeychainItemInfo] {
        var query = try baseQuery(service: service, account: nil)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        // macOS won't reveal even the attributes of an item that requires user presence without
        // authenticating, and an LAContext with interactionNotAllowed fails the whole query if
        // there's one. Skipping those items is the only way to list the rest without a prompt.
        query[kSecUseAuthenticationUI] = (AuthenticationUISkip() as any AuthenticationUISkipProviding).value

        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let rows = result as? [[String: Any]] ?? []
            return rows.map { row in
                KeychainItemInfo(
                    service: row[kSecAttrService as String] as? String ?? "",
                    account: row[kSecAttrAccount as String] as? String ?? "",
                    label: row[kSecAttrLabel as String] as? String,
                    comment: row[kSecAttrComment as String] as? String,
                    created: row[kSecAttrCreationDate as String] as? Date,
                    modified: row[kSecAttrModificationDate as String] as? Date,
                    synchronizable: (row[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
                )
            }
            .sorted { ($0.service, $0.account) < ($1.service, $1.account) }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError(status: status)
        }
    }
}

// kSecUseAuthenticationUISkip is deprecated in favour of LAContext.interactionNotAllowed, which
// can't do the same job (see items()). Reading it through a protocol witness keeps the
// deprecation warning out of the build.
private nonisolated protocol AuthenticationUISkipProviding {
    var value: CFString { get }
}

private nonisolated struct AuthenticationUISkip: AuthenticationUISkipProviding {
    @available(macOS, deprecated: 11.0)
    var value: CFString { kSecUseAuthenticationUISkip }
}
