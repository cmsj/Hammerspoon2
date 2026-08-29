//
//  FileSystemProtocol.swift
//  Hammerspoon 2
//
//  Created by Claude on 05/11/2025.
//

import Foundation

/// Protocol abstraction for file system operations to enable dependency injection and testability
@_documentation(visibility: private)
protocol FileSystemProtocol {
    /// Checks if a file exists at the given path
    /// - Parameter path: The file path to check
    /// - Returns: true if the file exists, false otherwise
    func fileExists(atPath path: String) -> Bool

    /// Checks if a file or directory exists at the given path
    /// - Parameters:
    ///   - path:The file path to check
    ///   - isDirectory: Upon return, will be true if path is a directory
    /// - Returns: true if the file exists, false otherwise
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool

    /// Reads the contents of a file as a string
    /// - Parameter url: The URL of the file to read
    /// - Returns: The contents of the file as a string
    /// - Throws: Error if the file cannot be read
    func contentsOf(url: URL) throws -> String

    /// Creates a directory at the given URL
    /// - Parameters:
    ///   - url: The URL of the directory to create
    ///   - withIntermediateDirectories: Whether to create any missing parent directories
    /// - Throws: Error if the directory cannot be created
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws

    /// Copies a file from one location to another
    /// - Parameters:
    ///   - srcURL: The URL of the file to copy
    ///   - dstURL: The URL to copy the file to
    /// - Throws: Error if the file cannot be copied
    func copyItem(at srcURL: URL, to dstURL: URL) throws

    /// Lists the contents of a directory
    /// - Parameter url: The URL of the directory to list
    /// - Returns: The URLs of the items contained in the directory
    /// - Throws: Error if the directory cannot be read
    func contentsOfDirectory(at url: URL) throws -> [URL]

    /// Removes a file or directory
    /// - Parameter url: The URL of the item to remove
    /// - Throws: Error if the item cannot be removed
    func removeItem(at url: URL) throws
}

/// FileManager extension to conform to FileSystemProtocol
extension FileManager: FileSystemProtocol {
    func contentsOf(url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        return try contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}
