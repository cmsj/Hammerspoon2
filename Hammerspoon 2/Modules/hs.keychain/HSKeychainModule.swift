//
//  HSKeychainModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Store small secrets, such as passwords, API tokens and TOTP seeds, in the macOS keychain,
/// so they don't have to live in your config files.
///
/// Each secret is identified by a `service` and an `account`, both strings of your choosing.
/// A good convention is to use a host name or a Spoon's name as the service, and a user name
/// as the account.
///
/// Secrets are kept in Hammerspoon 2's own part of the keychain (its keychain access group).
/// Other apps can't read, list or even see them, and Hammerspoon 2 can't see any other app's
/// items, such as the passwords saved in the Passwords app. Bear in mind that any code running
/// in Hammerspoon 2, including every Spoon you load, can read every secret stored here, unless
/// it's stored with `requireUserPresence`.
///
/// Secrets can be read while the screen is locked, once you've logged in, so timers and
/// watchers can use them. Reading a secret is asynchronous, because macOS may need to ask you
/// to authenticate first.
///
/// Errors are thrown (or rejected, for `get()`) as `Error`s with a `code` property:
///
/// | Code | Meaning |
/// |------|---------|
/// | `EINVALIDARG` | An argument or option is missing or malformed |
/// | `ENOENTITLEMENT` | This copy of Hammerspoon 2 can't use the keychain, see `isAvailable` |
/// | `ECANCELED` | You cancelled the authentication prompt |
/// | `EAUTH` | Authentication failed |
/// | `EINTERACTION` | The keychain needed to ask you something, but couldn't |
/// | `EUNAVAILABLE` | The keychain isn't available, e.g. before you've logged in |
/// | `EKEYCHAIN` | Any other keychain error. The message includes its `OSStatus`, which is also in the `status` property |
///
/// ## Quick start
///
/// Store a secret once, from the Console:
///
/// ```js
/// hs.keychain.set("api.example.com", "me", "my-api-token")
/// ```
///
/// Then use it in your config:
///
/// ```js
/// hs.keychain.get("api.example.com", "me").then(token => {
///     return fetch("https://api.example.com/things", {
///         headers: { Authorization: `Bearer ${token}` }
///     })
/// }).then(response => response.json())
///   .then(things => console.log(`${things.length} things`))
///   .catch(err => console.error(err.message))
/// ```
///
/// ## HTTP basic authentication
///
/// ```js
/// const user = "me"
/// hs.keychain.get("intranet.example.com", user).then(password => {
///     return fetch("https://intranet.example.com/status", {
///         headers: { Authorization: "Basic " + hs.hashing.base64Encode(`${user}:${password}`) }
///     })
/// }).then(response => console.log(`Status: ${response.status}`))
///   .catch(err => console.error(err.message))
/// ```
@objc protocol HSKeychainModuleAPI: JSExport {
    /// Whether this copy of Hammerspoon 2 can use the keychain. Copies built without code
    /// signing (such as development builds made with signing turned off) can't, and every
    /// other function then throws an `ENOENTITLEMENT` error.
    /// - Example:
    /// ```js
    /// if (!hs.keychain.isAvailable) {
    ///     console.error("The keychain isn't available")
    /// }
    /// ```
    @objc var isAvailable: Bool { get }

    /// Store a secret, replacing any secret already stored for the same service and account.
    /// - Parameter service: What the secret is for, such as a host name or a Spoon's name. Can't be empty.
    /// - Parameter account: Whose secret it is, such as a user name. Can't be empty.
    /// - Parameter secret: The secret itself
    /// - Parameter options?: How to store the secret
    ///   - label?: {string} A name for the secret, shown by `items()`
    ///   - comment?: {string} A note about the secret, shown by `items()`
    ///   - requireUserPresence?: {boolean} Ask you to authenticate (with Touch ID, an Apple
    ///     Watch, or your password) each time the secret is read. Such secrets aren't listed by
    ///     `items()`, but can be replaced and removed without authenticating. Defaults to false.
    ///   - synchronizable?: {boolean} Sync the secret to your other Macs through iCloud
    ///     Keychain. Defaults to false. Can't be combined with `requireUserPresence`.
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     hs.keychain.set("TOTP", "github", "JBSWY3DPEHPK3PXP", { label: "GitHub 2FA seed" })
    ///     hs.keychain.set("bank.example.com", "me", "hunter2", { requireUserPresence: true })
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func set(_ service: String, _ account: String, _ secret: String, _ options: [String: Any]?)

    /// Read a secret. If it was stored with `requireUserPresence`, macOS asks you to
    /// authenticate first, and the Promise settles once you have.
    /// - Parameter service: The service the secret was stored with
    /// - Parameter account: The account the secret was stored with
    /// - Parameter reason?: Why the secret is needed, shown in the authentication prompt, as in
    ///   "Hammerspoon 2 is trying to *reason*"
    /// - Returns: {Promise<string|null>} A Promise that resolves to the secret, or null if
    ///   there's no secret for that service and account, and rejects with an `Error` if it
    ///   can't be read (e.g. with code `ECANCELED` if you cancel the authentication prompt)
    /// - Example:
    /// ```js
    /// hs.keychain.get("TOTP", "github", "show your GitHub code")
    ///     .then(seed => {
    ///         if (seed === null) console.log("No seed stored")
    ///         else console.log(`The seed is ${seed.length} characters long`)
    ///     })
    ///     .catch(err => console.error(err.message))
    /// ```
    @objc func get(_ service: String, _ account: String, _ reason: String?) -> JSPromise?

    /// Remove a secret
    /// - Parameter service: The service the secret was stored with
    /// - Parameter account: The account the secret was stored with
    /// - Returns: true if the secret was removed, false if there was no such secret
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     if (!hs.keychain.remove("TOTP", "github")) console.log("There was no such secret")
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func remove(_ service: String, _ account: String) -> Bool

    /// List the stored secrets, without the secrets themselves. Secrets stored with
    /// `requireUserPresence` aren't listed, because macOS won't reveal anything about them,
    /// not even that they exist, until you authenticate, and listing never asks you to.
    /// - Parameter service?: Only list the secrets for this service. Lists every secret if omitted.
    /// - Returns: {Array<{service: string, account: string, label?: string, comment?: string, created?: Date, modified?: Date, synchronizable: boolean}>}
    ///   The stored secrets, sorted by service and then account
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const accounts = hs.keychain.items("TOTP").map(item => item.account)
    ///     console.log(`TOTP seeds are stored for: ${accounts.join(", ")}`)
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    /// ```
    @objc func items(_ service: String?) -> [[String: Any]]
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSKeychainModule: NSObject, HSModuleAPI, HSKeychainModuleAPI {
    var moduleName = "hs.keychain"
    let engineID: UUID
    private let store: any KeychainStore

    /// Tests use this to stand in a fake store
    init(engineID: UUID, store: any KeychainStore) {
        self.engineID = engineID
        self.store = store
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    required convenience init(engineID: UUID) {
        self.init(engineID: engineID, store: SecurityKeychainStore())
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName)\(store.isAvailable ? "" : " (unavailable)")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    func shutdown() {}

    // MARK: - HSKeychainModuleAPI

    @objc var isAvailable: Bool {
        store.isAvailable
    }

    @objc func set(_ service: String, _ account: String, _ secret: String, _ options: [String: Any]?) {
        do throws(KeychainError) {
            let write = try Self.makeWrite(service: service, account: account, secret: secret, options: options)
            try store.set(write)
        } catch {
            fail("set", error)
        }
    }

    @objc func get(_ service: String, _ account: String, _ reason: String?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let reason = Self.optionalString(reason)
        let store = store

        return wrapAsyncInJSPromise(in: context) { holder in
            do throws(KeychainError) {
                try Self.validate(service: service, account: account)
            } catch {
                Self.reject(holder, "get", error)
                return
            }
            Task {
                switch await Self.readSecret(store, service: service, account: account, reason: reason) {
                case .success(let secret):
                    holder.resolveWith(secret ?? NSNull())
                case .failure(let error):
                    Self.reject(holder, "get", error)
                }
            }
        }
    }

    @objc func remove(_ service: String, _ account: String) -> Bool {
        do throws(KeychainError) {
            try Self.validate(service: service, account: account)
            return try store.remove(service: service, account: account)
        } catch {
            fail("remove", error)
            return false
        }
    }

    @objc func items(_ service: String?) -> [[String: Any]] {
        do throws(KeychainError) {
            let service = Self.optionalString(service)
            if service?.isEmpty == true {
                throw .invalidArgument("service can't be empty")
            }
            return try store.items(service: service).map(\.dictionary)
        } catch {
            fail("items", error)
            return []
        }
    }

    // MARK: - Private

    /// Reads off the main thread, since macOS may block the read while it asks the user to authenticate
    @concurrent
    private nonisolated static func readSecret(_ store: any KeychainStore, service: String, account: String,
                                               reason: String?) async -> Result<String?, KeychainError> {
        Result { () throws(KeychainError) in try store.secret(service: service, account: account, reason: reason) }
    }

    /// An omitted trailing String? argument arrives from JSExport as the literal "undefined"
    private static func optionalString(_ value: String?) -> String? {
        switch value {
        case nil, "undefined", "null": nil
        default: value
        }
    }

    private static func validate(service: String, account: String) throws(KeychainError) {
        // An omitted String argument arrives as the literal "undefined"
        guard !service.isEmpty, service != "undefined" else { throw .invalidArgument("a service is required") }
        guard !account.isEmpty, account != "undefined" else { throw .invalidArgument("an account is required") }
    }

    private static let optionNames: Set<String> = ["label", "comment", "requireUserPresence", "synchronizable"]

    static func makeWrite(service: String, account: String, secret: String,
                          options: [String: Any]?) throws(KeychainError) -> KeychainWrite {
        try validate(service: service, account: account)
        var write = KeychainWrite(service: service, account: account, secret: secret)
        guard let options else { return write }

        if let unknown = options.keys.first(where: { !optionNames.contains($0) }) {
            throw .invalidArgument("unknown option '\(unknown)'")
        }
        func string(_ key: String) throws(KeychainError) -> String? {
            guard let value = options[key], !(value is NSNull) else { return nil }
            guard let string = value as? String else { throw .invalidArgument("option '\(key)' must be a string") }
            return string
        }
        func bool(_ key: String) throws(KeychainError) -> Bool {
            guard let value = options[key], !(value is NSNull) else { return false }
            // JS booleans arrive as NSNumber, but so do numbers, which aren't accepted
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw .invalidArgument("option '\(key)' must be a boolean")
            }
            return number.boolValue
        }
        write.label = try string("label")
        write.comment = try string("comment")
        write.requireUserPresence = try bool("requireUserPresence")
        write.synchronizable = try bool("synchronizable")
        if write.requireUserPresence && write.synchronizable {
            // Access control is tied to this Mac, so an item that has it can't sync
            throw .invalidArgument("requireUserPresence and synchronizable can't be combined")
        }
        return write
    }

    private func fail(_ function: String, _ error: KeychainError) {
        guard let context = JSContext.current() else { return }
        context.exception = Self.makeError(function, error, in: context)
    }

    private static func reject(_ holder: JSPromiseHolder, _ function: String, _ error: KeychainError) {
        holder.rejectWith(code: error.code, message: "hs.keychain.\(function)(): \(error.message)",
                          properties: error.status.map { ["status": Int($0)] } ?? [:])
    }

    private static func makeError(_ function: String, _ error: KeychainError, in context: JSContext) -> JSValue? {
        let value = JSValue(newErrorFromMessage: "hs.keychain.\(function)(): \(error.message)", in: context)
        value?.setValue(error.code, forProperty: "code")
        if let status = error.status {
            value?.setValue(Int(status), forProperty: "status")
        }
        return value
    }
}
