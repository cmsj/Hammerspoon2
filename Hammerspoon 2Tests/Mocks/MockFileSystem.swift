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
    var existingDirectories: Set<String> = []
    var fileContents: [URL: String] = [:]

    // Configure behavior
    var shouldThrowOnContentsOf: Bool = false
    var contentsOfError: Error?
    var shouldThrowOnCreateDirectory: Bool = false
    var shouldThrowOnCopyItem: Bool = false
    var shouldThrowOnRemoveItem: Bool = false

    // Call tracking
    var createdDirectories: [URL] = []
    var copiedItems: [(src: URL, dst: URL)] = []
    var removedItems: [URL] = []

    func fileExists(atPath path: String) -> Bool {
        return existingFiles.contains(path) || existingDirectories.contains(path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = existingFiles.contains(path) || existingDirectories.contains(path)
        if exists, let isDirectory = isDirectory {
            isDirectory.pointee = ObjCBool(existingDirectories.contains(path))
        }
        return exists
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

        // Also add parent directories
        let url = URL(fileURLWithPath: path)
        var parentURL = url.deletingLastPathComponent()
        while parentURL.path != "/" {
            existingDirectories.insert(parentURL.path)
            parentURL = parentURL.deletingLastPathComponent()
        }
    }

    func addFile(at url: URL, contents: String = "") {
        existingFiles.insert(url.path)
        fileContents[url] = contents

        // Also add parent directories
        var parentURL = url.deletingLastPathComponent()
        while parentURL.path != "/" {
            existingDirectories.insert(parentURL.path)
            parentURL = parentURL.deletingLastPathComponent()
        }
    }

    func addDirectory(atPath path: String) {
        existingDirectories.insert(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        if shouldThrowOnCreateDirectory {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                NSLocalizedDescriptionKey: "Mock error creating directory"
            ])
        }
        createdDirectories.append(url)
        existingDirectories.insert(url.path)
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if shouldThrowOnCopyItem {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                NSLocalizedDescriptionKey: "Mock error copying file"
            ])
        }
        guard existingFiles.contains(srcURL.path) || existingDirectories.contains(srcURL.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: "File not found: \(srcURL.path)"
            ])
        }
        copiedItems.append((src: srcURL, dst: dstURL))
        addFile(at: dstURL, contents: fileContents[srcURL] ?? "")
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        guard existingDirectories.contains(url.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: "Directory not found: \(url.path)"
            ])
        }
        return existingFiles
            .map { URL(fileURLWithPath: $0) }
            .filter { $0.deletingLastPathComponent().path == url.path }
    }

    func removeItem(at url: URL) throws {
        if shouldThrowOnRemoveItem {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                NSLocalizedDescriptionKey: "Mock error removing item"
            ])
        }
        guard existingFiles.contains(url.path) || existingDirectories.contains(url.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: "File not found: \(url.path)"
            ])
        }
        removedItems.append(url)
        existingFiles.remove(url.path)
        existingDirectories.remove(url.path)
        fileContents.removeValue(forKey: url)
    }

    func reset() {
        existingFiles.removeAll()
        existingDirectories.removeAll()
        fileContents.removeAll()
        shouldThrowOnContentsOf = false
        contentsOfError = nil
        shouldThrowOnCreateDirectory = false
        shouldThrowOnCopyItem = false
        shouldThrowOnRemoveItem = false
        createdDirectories.removeAll()
        copiedItems.removeAll()
        removedItems.removeAll()
    }
}
