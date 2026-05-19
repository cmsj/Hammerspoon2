//
//  HashModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore
import CryptoKit

// MARK: - Declare our JavaScript API

/// Module for hashing and encoding operations
@objc protocol HSHashModuleAPI: JSExport {
    // Base64 encoding
    /// Encode a string to base64
    /// - Parameter data: The string to encode
    /// - Returns: Base64 encoded string
    /// - Example:
    /// ```js
    /// console.log(hs.hash.base64Encode("Hello"))
    /// ```
    @objc func base64Encode(_ data: String) -> String

    /// Decode a base64 string
    /// - Parameter data: The base64 string to decode
    /// - Returns: Decoded string, or nil if the input is invalid
    /// - Example:
    /// ```js
    /// console.log(hs.hash.base64Decode("SGVsbG8="))
    /// ```
    @objc func base64Decode(_ data: String) -> String?

    // Hash functions
    /// Generate MD5 hash of a string
    /// - Parameter data: The string to hash
    /// - Returns: Hexadecimal MD5 hash
    /// - Example:
    /// ```js
    /// console.log(hs.hash.md5("hello"))
    /// ```
    @objc func md5(_ data: String) -> String

    /// Generate SHA1 hash of a string
    /// - Parameter data: The string to hash
    /// - Returns: Hexadecimal SHA1 hash
    /// - Example:
    /// ```js
    /// console.log(hs.hash.sha1("hello"))
    /// ```
    @objc func sha1(_ data: String) -> String

    /// Generate SHA256 hash of a string
    /// - Parameter data: The string to hash
    /// - Returns: Hexadecimal SHA256 hash
    /// - Example:
    /// ```js
    /// console.log(hs.hash.sha256("hello"))
    /// ```
    @objc func sha256(_ data: String) -> String

    /// Generate SHA512 hash of a string
    /// - Parameter data: The string to hash
    /// - Returns: Hexadecimal SHA512 hash
    /// - Example:
    /// ```js
    /// console.log(hs.hash.sha512("hello"))
    /// ```
    @objc func sha512(_ data: String) -> String

    // HMAC functions
    /// Generate HMAC-MD5 of a string with a key
    /// - Parameters:
    ///   - key: The secret key
    ///   - data: The data to authenticate
    /// - Returns: Hexadecimal HMAC-MD5
    /// - Example:
    /// ```js
    /// console.log(hs.hash.hmacMD5("secret", "hello"))
    /// ```
    @objc func hmacMD5(_ key: String, _ data: String) -> String

    /// Generate HMAC-SHA1 of a string with a key
    /// - Parameters:
    ///   - key: The secret key
    ///   - data: The data to authenticate
    /// - Returns: Hexadecimal HMAC-SHA1
    /// - Example:
    /// ```js
    /// console.log(hs.hash.hmacSHA1("secret", "hello"))
    /// ```
    @objc func hmacSHA1(_ key: String, _ data: String) -> String

    /// Generate HMAC-SHA256 of a string with a key
    /// - Parameters:
    ///   - key: The secret key
    ///   - data: The data to authenticate
    /// - Returns: Hexadecimal HMAC-SHA256
    /// - Example:
    /// ```js
    /// console.log(hs.hash.hmacSHA256("secret", "hello"))
    /// ```
    @objc func hmacSHA256(_ key: String, _ data: String) -> String

    /// Generate HMAC-SHA512 of a string with a key
    /// - Parameters:
    ///   - key: The secret key
    ///   - data: The data to authenticate
    /// - Returns: Hexadecimal HMAC-SHA512
    /// - Example:
    /// ```js
    /// console.log(hs.hash.hmacSHA512("secret", "hello"))
    /// ```
    @objc func hmacSHA512(_ key: String, _ data: String) -> String
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHashModule: NSObject, HSModuleAPI, HSHashModuleAPI {
    var name = "hs.hash"
    let engineID: UUID

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - Base64 encoding

    @objc func base64Encode(_ data: String) -> String {
        return Data(data.utf8).base64EncodedString()
    }

    @objc func base64Decode(_ data: String) -> String? {
        guard let dataObject = Data(base64Encoded: data) else {
            return nil
        }
        return String(data: dataObject, encoding: .utf8)
    }

    // MARK: - Hash functions

    @objc func md5(_ data: String) -> String {
        let inputData = Data(data.utf8)
        let hashed = Insecure.MD5.hash(data: inputData)
        return hashed.map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func sha1(_ data: String) -> String {
        let inputData = Data(data.utf8)
        let hashed = Insecure.SHA1.hash(data: inputData)
        return hashed.map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func sha256(_ data: String) -> String {
        let inputData = Data(data.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func sha512(_ data: String) -> String {
        let inputData = Data(data.utf8)
        let hashed = SHA512.hash(data: inputData)
        return hashed.map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - HMAC functions

    @objc func hmacMD5(_ key: String, _ data: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let inputData = Data(data.utf8)
        let authCode = HMAC<Insecure.MD5>.authenticationCode(for: inputData, using: keyData)
        return Data(authCode).map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func hmacSHA1(_ key: String, _ data: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let inputData = Data(data.utf8)
        let authCode = HMAC<Insecure.SHA1>.authenticationCode(for: inputData, using: keyData)
        return Data(authCode).map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func hmacSHA256(_ key: String, _ data: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let inputData = Data(data.utf8)
        let authCode = HMAC<SHA256>.authenticationCode(for: inputData, using: keyData)
        return Data(authCode).map { unsafe String(format: "%02hhx", $0) }.joined()
    }

    @objc func hmacSHA512(_ key: String, _ data: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let inputData = Data(data.utf8)
        let authCode = HMAC<SHA512>.authenticationCode(for: inputData, using: keyData)
        return Data(authCode).map { unsafe String(format: "%02hhx", $0) }.joined()
    }
}
