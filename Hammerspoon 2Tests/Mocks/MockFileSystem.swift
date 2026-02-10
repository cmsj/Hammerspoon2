//
//  MockFileSystem.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 05/11/2025.
//

import Foundation
@testable import Hammerspoon_2

/// Mock implementation of FileSystemProtocol for testing
class MockFileSystem: FileSystemProtocol {
    var existingFiles: Set<String> = []
    var fileContents: [URL: String] = [:]

    // Configure behavior
    var shouldThrowOnContentsOf: Bool = false
    var contentsOfError: Error?

    func fileExists(atPath path: String) -> Bool {
        return existingFiles.contains(path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        return existingFiles.contains(path)
    }

    func contentsOf(url: URL) throws -> String {
        if shouldThrowOnContentsOf {
            throw contentsOfError ?? NSError(domain: "MockFileSystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error reading file"])
        }

        if let contents = fileContents[url] {
            return contents
        }

        // Default behavior: return empty string if file "exists" in our mock
        if existingFiles.contains(url.path) {
            return ""
        }

        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [
            NSLocalizedDescriptionKey: "File not found: \(url.path)"
        ])
    }

    // Helper methods for testing
    func addFile(atPath path: String, contents: String = "") {
        existingFiles.insert(path)
        fileContents[URL(fileURLWithPath: path)] = contents
    }

    func addFile(at url: URL, contents: String = "") {
        existingFiles.insert(url.path)
        fileContents[url] = contents
    }

    func reset() {
        existingFiles.removeAll()
        fileContents.removeAll()
        shouldThrowOnContentsOf = false
        contentsOfError = nil
    }
}
