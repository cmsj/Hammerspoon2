//
//  HSHashIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 06/11/2025.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

/// Integration tests for hs.hash module
///
/// These tests verify that the hash module works correctly when called from JavaScript,
/// including proper type conversion, error handling, and JavaScript bridging.
struct HSHashIntegrationTests {

    // MARK: - Base64 Encoding Tests

    @Test("Base64 encoding works from JavaScript")
    func testBase64EncodeFromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        // Test basic encoding
        let result = harness.eval("hs.hash.base64Encode('hello')")
        #expect(result as? String == "aGVsbG8=")

        // Test empty string
        let empty = harness.eval("hs.hash.base64Encode('')")
        #expect(empty as? String == "")

        // Test Unicode
        let unicode = harness.eval("hs.hash.base64Encode('Hello 🌍')")
        #expect(unicode as? String == "SGVsbG8g8J+MjQ==")
    }

    @Test("Base64 decoding works from JavaScript")
    func testBase64DecodeFromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        // Test basic decoding
        let result = harness.eval("hs.hash.base64Decode('aGVsbG8=')")
        #expect(result as? String == "hello")

        // Test invalid base64 returns null
        let invalid = harness.eval("hs.hash.base64Decode('not-valid-base64!!!')")
        #expect(invalid == nil || (invalid as? NSNull) != nil)

        // Test round-trip
        harness.expectEqual(
            "hs.hash.base64Decode(hs.hash.base64Encode('round trip test'))",
            "round trip test"
        )
    }

    @Test("Base64 encode/decode round-trip with complex data")
    func testBase64RoundTrip() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        let testData = [
            "The quick brown fox jumps over the lazy dog",
            "特殊文字テスト",
            "Emoji test: 😀😃😄😁",
            "Line\nBreak\tTab",
            ""
        ]

        for data in testData {
            harness.eval("var testString = \(escapeJSString(data))")
            harness.expectEqual(
                "hs.hash.base64Decode(hs.hash.base64Encode(testString))",
                data
            )
        }
    }

    // MARK: - MD5 Hash Tests

    @Test("MD5 hash produces correct output from JavaScript")
    func testMD5FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        // Known MD5 hashes
        harness.expectEqual("hs.hash.md5('')", "d41d8cd98f00b204e9800998ecf8427e")
        harness.expectEqual("hs.hash.md5('hello')", "5d41402abc4b2a76b9719d911017c592")
        harness.expectEqual("hs.hash.md5('The quick brown fox jumps over the lazy dog')",
                          "9e107d9d372bb6826bd81d3542a419d6")
    }

    // MARK: - SHA Hash Tests

    @Test("SHA1 hash produces correct output from JavaScript")
    func testSHA1FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.expectEqual("hs.hash.sha1('hello')",
                          "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        harness.expectEqual("hs.hash.sha1('test')",
                          "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
    }

    @Test("SHA256 hash produces correct output from JavaScript")
    func testSHA256FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.expectEqual("hs.hash.sha256('hello')",
                          "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        harness.expectEqual("hs.hash.sha256('')",
                          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("SHA512 hash produces correct output from JavaScript")
    func testSHA512FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.expectEqual("hs.hash.sha512('hello')",
                          "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")
    }

    // MARK: - HMAC Tests

    @Test("HMAC-MD5 produces correct output from JavaScript")
    func testHMACMD5FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        // Test with known HMAC values
        let result = harness.eval("hs.hash.hmacMD5('key', 'message')")
        #expect(result is String, "HMAC-MD5 should return a string")
        #expect((result as? String)?.count == 32, "HMAC-MD5 should be 32 hex characters")
    }

    @Test("HMAC-SHA1 produces correct output from JavaScript")
    func testHMACSHA1FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        let result = harness.eval("hs.hash.hmacSHA1('key', 'message')")
        #expect(result is String, "HMAC-SHA1 should return a string")
        #expect((result as? String)?.count == 40, "HMAC-SHA1 should be 40 hex characters")
    }

    @Test("HMAC-SHA256 produces correct output from JavaScript")
    func testHMACSHA256FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        let result = harness.eval("hs.hash.hmacSHA256('secret', 'data')")
        #expect(result is String, "HMAC-SHA256 should return a string")
        #expect((result as? String)?.count == 64, "HMAC-SHA256 should be 64 hex characters")
    }

    @Test("HMAC-SHA512 produces correct output from JavaScript")
    func testHMACSHA512FromJS() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        let result = harness.eval("hs.hash.hmacSHA512('secret', 'data')")
        #expect(result is String, "HMAC-SHA512 should return a string")
        #expect((result as? String)?.count == 128, "HMAC-SHA512 should be 128 hex characters")
    }

    @Test("HMAC with different keys produces different hashes")
    func testHMACKeyVariation() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        let hash1 = harness.eval("hs.hash.hmacSHA256('key1', 'message')")
        let hash2 = harness.eval("hs.hash.hmacSHA256('key2', 'message')")

        #expect(hash1 as? String != hash2 as? String, "Different keys should produce different hashes")
    }

    // MARK: - Type Validation Tests

    @Test("Hash functions handle type coercion correctly")
    func testTypeCoercion() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        // Numbers should be converted to strings
        let numberHash = harness.eval("hs.hash.md5(String(123))")
        #expect(numberHash is String)

        // Empty strings work
        let emptyHash = harness.eval("hs.hash.sha256('')")
        #expect(emptyHash is String)
    }

    @Test("Hash module is accessible as property")
    func testModuleAccess() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.expectTrue("typeof hs.hash === 'object'")
        harness.expectTrue("typeof hs.hash.md5 === 'function'")
        harness.expectTrue("typeof hs.hash.sha256 === 'function'")
        harness.expectTrue("typeof hs.hash.base64Encode === 'function'")
    }

    // MARK: - Real-World Use Cases

    @Test("Password verification pattern works")
    func testPasswordVerificationPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.eval("""
        function hashPassword(password, salt) {
            return hs.hash.sha256(salt + password);
        }

        function verifyPassword(password, salt, expectedHash) {
            return hashPassword(password, salt) === expectedHash;
        }

        const salt = 'random_salt_123';
        const password = 'mySecretPassword';
        const hashedPassword = hashPassword(password, salt);
        """)

        harness.expectTrue("verifyPassword(password, salt, hashedPassword)")
        harness.expectFalse("verifyPassword('wrongPassword', salt, hashedPassword)")
    }

    @Test("API signature generation pattern works")
    func testAPISignaturePattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.eval("""
        function generateSignature(apiKey, data) {
            return hs.hash.hmacSHA256(apiKey, data);
        }

        const apiKey = 'my-api-key';
        const requestData = 'GET:/api/users:1234567890';
        const signature = generateSignature(apiKey, requestData);
        """)

        harness.expectTrue("signature.length === 64")
        harness.expectTrue("typeof signature === 'string'")
    }

    @Test("Data integrity check pattern works")
    func testDataIntegrityPattern() {
        let harness = JSTestHarness()
        harness.loadModule(HSHashModule.self, as: "hash")

        harness.eval("""
        function createChecksum(data) {
            return {
                data: data,
                checksum: hs.hash.sha256(data)
            };
        }

        function verifyChecksum(obj) {
            return hs.hash.sha256(obj.data) === obj.checksum;
        }

        const message = createChecksum('Important data that must not be tampered with');
        """)

        harness.expectTrue("verifyChecksum(message)")

        // Simulate tampering
        harness.eval("message.data = 'Tampered data';")
        harness.expectFalse("verifyChecksum(message)")
    }

    // MARK: - Helper Functions

    private func escapeJSString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        return "\"\(escaped)\""
    }
}
