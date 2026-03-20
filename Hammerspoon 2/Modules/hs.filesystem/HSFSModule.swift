//
//  HSFSModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit          // NSWorkspace (fileUTI)
import Darwin          // POSIX stat/lstat/rmdir

// MARK: - JavaScript API

/// Module for filesystem operations.
///
/// `hs.fs` provides a comprehensive set of filesystem operations covering file
/// I/O, directory management, path manipulation, metadata access, symbolic
/// links, Finder tags, and macOS-specific features like file bookmarks and
/// Uniform Type Identifiers.
///
/// It replaces both Hammerspoon v1's `hs.fs` module and the functionality that
/// was previously available through Lua's built-in `io` and `file` modules.
///
/// ## Reading and writing files
///
/// ```javascript
/// const contents = hs.fs.read("/etc/hosts");           // entire file
/// const chunk    = hs.fs.read("/etc/hosts", 100, 50);  // 50 bytes from offset 100
///
/// hs.fs.readLines("/etc/hosts", function(line) {
///     console.log(line);
///     return true; // return false to stop early
/// });
///
/// hs.fs.write("/tmp/hello.txt", "Hello, world!\n");
/// hs.fs.append("/tmp/hello.txt", "More content\n");
/// ```
///
/// ## Directory operations
///
/// ```javascript
/// hs.fs.mkdir("~/Projects/new-thing");
///
/// const files = hs.fs.list("~/Documents");
/// const all   = hs.fs.listRecursive("~/Documents");
/// ```
///
/// ## Path utilities
///
/// ```javascript
/// const abs  = hs.fs.pathToAbsolute("~/Library");
/// const tmp  = hs.fs.temporaryDirectory();
/// const home = hs.fs.homeDirectory();
/// ```
///
/// ## Metadata
///
/// ```javascript
/// const info = hs.fs.attributes("/etc/hosts");
/// // { size: 1234, type: "file", permissions: 420,
/// //   ownerID: 0, groupID: 0,
/// //   creationDate: 1700000000.0, modificationDate: 1700001000.0 }
/// ```
@objc protocol HSFSModuleAPI: JSExport {

    // MARK: - File I/O

    /// Read part or all of a file as a UTF-8 string.
    ///
    /// ```javascript
    /// const all   = hs.fs.read("/etc/hosts");          // entire file
    /// const chunk = hs.fs.read("/etc/hosts", 100, 50); // 50 bytes starting at byte 100
    /// ```
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - offset: Byte offset to start reading from. Pass `0` (or omit) to read from the beginning.
    ///   - length: Maximum number of bytes to read. Pass `0` (or omit) to read to the end of the file.
    /// - Returns: The file contents as a UTF-8 string, or `null` if the file cannot be read.
    @objc func read(_ path: String, _ offset: Int, _ length: Int) -> String?

    /// Read a file line-by-line, invoking a callback for each line.
    ///
    /// Lines are delivered with newline characters stripped. Both `\n` and `\r\n`
    /// line endings are handled. The file is read in chunks so it is never fully
    /// loaded into memory, making this safe for arbitrarily large files.
    ///
    /// ```javascript
    /// hs.fs.readLines("/etc/hosts", function(line) {
    ///     if (line.startsWith("#")) return true; // skip comment lines, keep going
    ///     console.log(line);
    ///     return true; // return false to stop early
    /// });
    /// ```
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - callback: Called once per line with the line text. Return `true` to continue
    ///     reading, or `false` to stop early.
    /// - Returns: `true` if the file was read successfully (including early stops requested
    ///   by the callback), or `false` if the file could not be opened.
    @objc func readLines(_ path: String, _ callback: JSValue) -> Bool

    /// Write a UTF-8 string to a file, creating it or overwriting any existing content.
    ///
    /// Intermediate directories are not created automatically; use `mkdir` first if needed.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - content: String to write.
    ///   - atomically: Whether to write the file in-place or atomically
    /// - Returns: `true` on success, `false` on failure.
    @objc func write(_ path: String, _ content: String, _ atomically: Bool) -> Bool

    /// Append a UTF-8 string to a file, creating it if it does not exist.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - content: String to append.
    /// - Returns: `true` on success, `false` on failure.
    @objc func append(_ path: String, _ content: String) -> Bool

    // MARK: - Existence and Type Checks

    /// Determine if a filesystem object exists at the given path
    /// Unlike `isFile` and `isDirectory`, this follows symlinks.
    /// 
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if any filesystem entry (file, directory, symlink, etc.) exists at the path.
    @objc func exists(_ path: String) -> Bool

    /// Determine if a file exists at the given path
    /// This does **not** follow symlinks; a symlink pointing at a file returns `false`.
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if a regular file (not a directory or symlink) exists at the path.
    @objc func isFile(_ path: String) -> Bool

    /// Determine if a directory exists at the given path
    /// This does **not** follow symlinks; a symlink pointing at a directory returns `false`.
    /// 
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if a directory exists at the path.
    @objc func isDirectory(_ path: String) -> Bool

    /// Determine if a symlink exists at the given path
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the path is a symbolic link.
    @objc func isSymlink(_ path: String) -> Bool

    /// Determine if a given filesystem path is readable
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the current process can read the file or directory at the path.
    @objc func isReadable(_ path: String) -> Bool

    /// Determine if a given filesystem path is writable
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the current process can write to the file or directory at the path.
    @objc func isWritable(_ path: String) -> Bool

    // MARK: - File Operations

    /// Copy a file or directory to a new location.
    ///
    /// The destination must not already exist. If `source` is a directory, its
    /// entire contents are copied recursively.
    ///
    /// - Parameters:
    ///   - source: Path to the existing file or directory. `~` is expanded.
    ///   - destination: Path for the copy. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func copy(_ source: String, _ destination: String) -> Bool

    /// Move (rename) a file or directory.
    ///
    /// The destination must not already exist.
    ///
    /// - Parameters:
    ///   - source: Path to the existing file or directory. `~` is expanded.
    ///   - destination: New path. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func move(_ source: String, _ destination: String) -> Bool

    /// Delete a file or directory.
    ///
    /// Directories are removed recursively. To remove only an empty directory,
    /// use `rmdir` instead.
    ///
    /// - Parameter path: Path to delete. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func delete(_ path: String) -> Bool

    // MARK: - Directory Operations

    /// List the immediate contents of a directory.
    ///
    /// Returns bare filenames (not full paths), sorted alphabetically.
    /// The `.` and `..` entries are never included.
    ///
    /// - Parameter path: Path to the directory. `~` is expanded.
    /// - Returns: Sorted array of filenames, or `null` if the path cannot be read.
    @objc func list(_ path: String) -> [String]?

    /// Recursively list all entries under a directory.
    ///
    /// Returns paths relative to `path`, sorted alphabetically.
    ///
    /// - Parameter path: Path to the root directory. `~` is expanded.
    /// - Returns: Sorted array of relative paths, or `null` if the path cannot be read.
    @objc func listRecursive(_ path: String) -> [String]?

    /// Create a directory, including all necessary intermediate directories.
    ///
    /// Succeeds silently if the directory already exists.
    ///
    /// - Parameter path: Path of the directory to create. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func mkdir(_ path: String) -> Bool

    /// Remove an empty directory.
    ///
    /// Fails if the directory is not empty. Use `delete` to remove a non-empty
    /// directory recursively.
    ///
    /// - Parameter path: Path of the directory to remove. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func rmdir(_ path: String) -> Bool

    // MARK: - Working Directory

    /// Returns the current working directory of the process.
    ///
    /// - Returns: Current directory path, or `null` on error.
    @objc func currentDir() -> String?

    /// Change the current working directory of the process.
    ///
    /// - Parameter path: New working directory path. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func chdir(_ path: String) -> Bool

    // MARK: - Path Utilities

    /// Resolve a path to its absolute, canonical form.
    ///
    /// Expands `~`, resolves `.` and `..`, and follows all symbolic links.
    /// Returns `null` if any component of the path does not exist.
    ///
    /// - Parameter path: Path to resolve.
    /// - Returns: Absolute canonical path, or `null` if it cannot be resolved.
    @objc func pathToAbsolute(_ path: String) -> String?

    /// Return the localised display name for a file or directory as shown by Finder.
    ///
    /// For example, `/Library` appears as `"Library"` in Finder even though its
    /// on-disk name is the same.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Display name string, or `null` if the path does not exist.
    @objc func displayName(_ path: String) -> String?

    /// Returns the temporary directory for the current user.
    ///
    /// - Returns: Temporary directory path (always ends with `/`).
    @objc func temporaryDirectory() -> String

    /// Returns the home directory for the current user.
    ///
    /// - Returns: Home directory path string.
    @objc func homeDirectory() -> String

    /// Returns a `file://` URL string for the given path.
    ///
    /// ```javascript
    /// hs.fs.urlFromPath("/tmp/foo.txt")
    /// // → "file:///tmp/foo.txt"
    /// ```
    ///
    /// - Parameter path: Filesystem path. `~` is expanded.
    /// - Returns: URL string, or `null` on failure.
    @objc func urlFromPath(_ path: String) -> String?

    // MARK: - File Attributes

    /// Get metadata attributes for a file or directory.
    ///
    /// Does not follow symbolic links. Use `isSymlink` to detect links before calling this if needed.
    ///
    /// Returns an object with:
    /// - `size` — Size in bytes (`number`).
    /// - `type` — One of `"file"`, `"directory"`, `"symlink"`, `"socket"`, `"characterSpecial"`, `"blockSpecial"`, or `"unknown"`.
    /// - `permissions` — POSIX permission bits as an integer (e.g. `0o644` = `420`).
    /// - `ownerID` — Owner UID.
    /// - `groupID` — Owner GID.
    /// - `inode` — Inode number.
    /// - `creationDate` — Creation date as seconds since the Unix epoch.
    /// - `modificationDate` — Last modification date as seconds since the Unix epoch.
    ///
    /// - Parameter path: Path to inspect. `~` is expanded.
    /// - Returns: Attributes object, or `null` if the path cannot be accessed.
    @objc func attributes(_ path: String) -> NSDictionary?

    /// Update the modification timestamp of a file to the current time.
    ///
    /// Creates the file if it does not exist (equivalent to the POSIX `touch` command).
    ///
    /// - Parameter path: Path to the file. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    @objc func touch(_ path: String) -> Bool

    // MARK: - Links

    /// Create a hard link at `destination` pointing at `source`.
    ///
    /// Both paths must be on the same filesystem volume.
    ///
    /// - Parameters:
    ///   - source: Path of the existing file.
    ///   - destination: Path for the new hard link.
    /// - Returns: `true` on success, `false` on failure.
    @objc func link(_ source: String, _ destination: String) -> Bool

    /// Create a symbolic link at `destination` pointing at `source`.
    ///
    /// Unlike hard links, symlinks may cross filesystem boundaries and may
    /// point to paths that do not yet exist.
    ///
    /// - Parameters:
    ///   - source: The path the symlink will point to.
    ///   - destination: The path where the symlink will be created.
    /// - Returns: `true` on success, `false` on failure.
    @objc func symlink(_ source: String, _ destination: String) -> Bool

    /// Read the target of a symbolic link without resolving it.
    ///
    /// - Parameter path: Path to the symbolic link.
    /// - Returns: The raw path the link points to, or `null` if the path is not a symlink.
    @objc func readlink(_ path: String) -> String?

    // MARK: - Finder Tags

    /// Get the Finder tags assigned to a file or directory.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Array of tag name strings, or `null` if no tags are set.
    @objc func tags(_ path: String) -> [String]?

    /// Replace all Finder tags on a file or directory.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - newTags: Array of tag name strings.
    /// - Returns: `true` on success, `false` on failure.
    @objc func setTags(_ path: String, _ newTags: NSArray) -> Bool

    /// Add Finder tags to a file or directory (union with existing tags).
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - newTags: Array of tag name strings to add.
    /// - Returns: `true` on success, `false` on failure.
    @objc func addTags(_ path: String, _ newTags: NSArray) -> Bool

    /// Remove specific Finder tags from a file or directory.
    ///
    /// Tags not currently present are silently ignored.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - tagsToRemove: Array of tag name strings to remove.
    /// - Returns: `true` on success, `false` on failure.
    @objc func removeTags(_ path: String, _ tagsToRemove: NSArray) -> Bool

    // MARK: - Uniform Type Identifiers

    /// Return the Uniform Type Identifier for the file at the given path.
    ///
    /// ```javascript
    /// hs.fs.fileUTI("/etc/hosts")   // → "public.plain-text"
    /// hs.fs.fileUTI("/tmp/foo.png") // → "public.png"
    /// ```
    ///
    /// - Parameter path: Path to the file.
    /// - Returns: UTI string, or `null` on failure.
    @objc func fileUTI(_ path: String) -> String?

    // MARK: - Bookmarks

    /// Encode a file path as a persistent bookmark that survives file moves and renames.
    ///
    /// The returned string is base64-encoded bookmark data that can be stored and
    /// later resolved with `pathFromBookmark`.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Base64-encoded bookmark string, or `null` on failure.
    @objc func pathToBookmark(_ path: String) -> String?

    /// Resolve a base64-encoded bookmark back to a file path.
    ///
    /// - Parameter data: Base64-encoded bookmark string produced by `pathToBookmark`.
    /// - Returns: The current file path, or `null` if the bookmark cannot be resolved.
    @objc func pathFromBookmark(_ data: String) -> String?
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSFSModule: NSObject, HSModuleAPI, HSFSModuleAPI {
    var name = "hs.fs"

    override required init() { super.init() }
    func shutdown() {}

    // MARK: - Private helpers

    private let fm = FileManager.default

    /// Expand `~` and return the expanded path string.
    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// `lstat` a path and return the raw mode bits (does **not** follow symlinks).
    private func lstatMode(at path: String) -> mode_t? {
        var st = Darwin.stat()
        guard unsafe Darwin.lstat(expand(path), &st) == 0 else { return nil }
        return st.st_mode
    }

    private func modeToType(_ mode: mode_t) -> String {
        switch mode & S_IFMT {
        case S_IFREG:  return "file"
        case S_IFDIR:  return "directory"
        case S_IFLNK:  return "symlink"
        case S_IFSOCK: return "socket"
        case S_IFCHR:  return "characterSpecial"
        case S_IFBLK:  return "blockSpecial"
        default:       return "unknown"
        }
    }

    // MARK: - File I/O

    @objc func read(_ path: String, _ offset: Int = 0, _ length: Int = 0) -> String? {
        guard let handle = FileHandle(forReadingAtPath: expand(path)) else {
            AKError("hs.fs.read: could not open \(path)")
            return nil
        }
        defer { handle.closeFile() }

        if offset > 0 { handle.seek(toFileOffset: UInt64(offset)) }
        let data = length > 0 ? handle.readData(ofLength: length) : handle.readDataToEndOfFile()

        guard let result = String(data: data, encoding: .utf8) else {
            AKError("hs.fs.read: \(path) is not valid UTF-8")
            return nil
        }
        return result
    }

    @objc func readLines(_ path: String, _ callback: JSValue) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: expand(path)) else {
            AKError("hs.fs.readLines: could not open \(path)")
            return false
        }
        defer { handle.closeFile() }

        var pending = Data()
        let bufferSize = 65_536

        while true {
            let chunk = handle.readData(ofLength: bufferSize)
            let isEOF = chunk.isEmpty
            if !isEOF { pending.append(chunk) }

            // Flush all complete lines from the pending buffer.
            while let nlIdx = pending.firstIndex(of: 0x0A) {
                // Strip a preceding \r for Windows-style line endings.
                let lineEnd = nlIdx > 0 && pending[nlIdx - 1] == 0x0D ? nlIdx - 1 : nlIdx
                let line = String(data: pending[..<lineEnd], encoding: .utf8) ?? ""
                let keepGoing = callback.call(withArguments: [line])?.toBool() ?? false
                pending = Data(pending[(nlIdx + 1)...])
                if !keepGoing { return true }
            }

            if isEOF { break }
        }

        // Deliver any final line that has no trailing newline.
        if !pending.isEmpty {
            let line = String(data: pending, encoding: .utf8) ?? ""
            _ = callback.call(withArguments: [line])
        }

        return true
    }

    @objc func write(_ path: String, _ content: String, _ atomically: Bool = true) -> Bool {
        do {
            try content.write(toFile: expand(path), atomically: atomically, encoding: .utf8)
            return true
        } catch {
            AKError("hs.fs.write: \(error.localizedDescription)")
            return false
        }
    }

    @objc func append(_ path: String, _ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else {
            AKError("hs.fs.append: could not encode content as UTF-8")
            return false
        }
        let expandedPath = expand(path)
        do {
            if fm.fileExists(atPath: expandedPath) {
                let handle = try FileHandle(forWritingAtPath: expandedPath)
                    .require(label: "hs.fs.append: could not open file for writing")
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try data.write(to: URL(fileURLWithPath: expandedPath), options: .atomic)
            }
            return true
        } catch {
            AKError("hs.fs.append: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Existence and Type Checks

    @objc func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: expand(path))
    }

    @objc func isFile(_ path: String) -> Bool {
        guard let mode = lstatMode(at: path) else { return false }
        return (mode & S_IFMT) == S_IFREG
    }

    @objc func isDirectory(_ path: String) -> Bool {
        guard let mode = lstatMode(at: path) else { return false }
        return (mode & S_IFMT) == S_IFDIR
    }

    @objc func isSymlink(_ path: String) -> Bool {
        guard let mode = lstatMode(at: path) else { return false }
        return (mode & S_IFMT) == S_IFLNK
    }

    @objc func isReadable(_ path: String) -> Bool {
        fm.isReadableFile(atPath: expand(path))
    }

    @objc func isWritable(_ path: String) -> Bool {
        fm.isWritableFile(atPath: expand(path))
    }

    // MARK: - File Operations

    @objc func copy(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.copyItem(atPath: expand(source), toPath: expand(destination))
            return true
        } catch {
            AKError("hs.fs.copy: \(error.localizedDescription)")
            return false
        }
    }

    @objc func move(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.moveItem(atPath: expand(source), toPath: expand(destination))
            return true
        } catch {
            AKError("hs.fs.move: \(error.localizedDescription)")
            return false
        }
    }

    @objc func delete(_ path: String) -> Bool {
        do {
            try fm.removeItem(atPath: expand(path))
            return true
        } catch {
            AKError("hs.fs.delete: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Directory Operations

    @objc func list(_ path: String) -> [String]? {
        do {
            return try fm.contentsOfDirectory(atPath: expand(path)).sorted()
        } catch {
            AKError("hs.fs.list: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func listRecursive(_ path: String) -> [String]? {
        do {
            return try fm.subpathsOfDirectory(atPath: expand(path)).sorted()
        } catch {
            AKError("hs.fs.listRecursive: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func mkdir(_ path: String) -> Bool {
        do {
            try fm.createDirectory(atPath: expand(path),
                                   withIntermediateDirectories: true,
                                   attributes: nil)
            return true
        } catch {
            AKError("hs.fs.mkdir: \(error.localizedDescription)")
            return false
        }
    }

    @objc func rmdir(_ path: String) -> Bool {
        // Use POSIX rmdir() so it correctly rejects non-empty directories.
        let expandedPath = expand(path)
        guard unsafe Darwin.rmdir(expandedPath) == 0 else {
            AKError(unsafe "hs.fs.rmdir: \(String(cString: strerror(errno)))")
            return false
        }
        return true
    }

    // MARK: - Working Directory

    @objc func currentDir() -> String? {
        fm.currentDirectoryPath
    }

    @objc func chdir(_ path: String) -> Bool {
        fm.changeCurrentDirectoryPath(expand(path))
    }

    // MARK: - Path Utilities

    @objc func pathToAbsolute(_ path: String) -> String? {
        let expandedPath = expand(path)
        var resolved = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard unsafe realpath(expandedPath, &resolved) != nil else { return nil }
        return String(cString: resolved)
    }

    @objc func displayName(_ path: String) -> String? {
        let expandedPath = expand(path)
        guard fm.fileExists(atPath: expandedPath) else { return nil }
        return fm.displayName(atPath: expandedPath)
    }

    @objc func temporaryDirectory() -> String {
        NSTemporaryDirectory()
    }

    @objc func homeDirectory() -> String {
        fm.homeDirectoryForCurrentUser.path
    }

    @objc func urlFromPath(_ path: String) -> String? {
        URL(fileURLWithPath: expand(path)).absoluteString
    }

    // MARK: - File Attributes

    @objc func attributes(_ path: String) -> NSDictionary? {
        let expandedPath = expand(path)
        var st = Darwin.stat()
        // Use lstat so the type field correctly reports symlinks.
        guard unsafe Darwin.lstat(expandedPath, &st) == 0 else {
            AKError(unsafe "hs.fs.attributes: \(String(cString: strerror(errno)))")
            return nil
        }

        let creationDate = Double(st.st_birthtimespec.tv_sec)
                         + Double(st.st_birthtimespec.tv_nsec) / 1_000_000_000
        let modDate = Double(st.st_mtimespec.tv_sec)
                    + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000

        return [
            "size":             Int(st.st_size),
            "type":             modeToType(st.st_mode),
            "permissions":      Int(st.st_mode & 0o7777),
            "ownerID":          Int(st.st_uid),
            "groupID":          Int(st.st_gid),
            "inode":            Int(st.st_ino),
            "creationDate":     creationDate,
            "modificationDate": modDate,
        ] as NSDictionary
    }

    @objc func touch(_ path: String) -> Bool {
        let expandedPath = expand(path)
        if fm.fileExists(atPath: expandedPath) {
            do {
                try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: expandedPath)
                return true
            } catch {
                AKError("hs.fs.touch: \(error.localizedDescription)")
                return false
            }
        } else {
            return fm.createFile(atPath: expandedPath, contents: nil)
        }
    }

    // MARK: - Links

    @objc func link(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.linkItem(atPath: expand(source), toPath: expand(destination))
            return true
        } catch {
            AKError("hs.fs.link: \(error.localizedDescription)")
            return false
        }
    }

    @objc func symlink(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.createSymbolicLink(atPath: expand(destination),
                                      withDestinationPath: expand(source))
            return true
        } catch {
            AKError("hs.fs.symlink: \(error.localizedDescription)")
            return false
        }
    }

    @objc func readlink(_ path: String) -> String? {
        do {
            return try fm.destinationOfSymbolicLink(atPath: expand(path))
        } catch {
            AKError("hs.fs.readlink: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Finder Tags

    @objc func tags(_ path: String) -> [String]? {
        do {
            let values = try URL(fileURLWithPath: expand(path))
                .resourceValues(forKeys: [.tagNamesKey])
            guard let tagNames = values.tagNames, !tagNames.isEmpty else { return nil }
            return tagNames
        } catch {
            AKError("hs.fs.tags: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func setTags(_ path: String, _ newTags: NSArray) -> Bool {
        let tagList = newTags.compactMap { $0 as? String }
        do {
            var values = URLResourceValues()
            values.tagNames = tagList
            var fileURL = URL(fileURLWithPath: expand(path))
            try fileURL.setResourceValues(values)
            return true
        } catch {
            AKError("hs.fs.setTags: \(error.localizedDescription)")
            return false
        }
    }

    @objc func addTags(_ path: String, _ newTags: NSArray) -> Bool {
        let existing = Set(tags(path) ?? [])
        let toAdd    = Set(newTags.compactMap { $0 as? String })
        return setTags(path, Array(existing.union(toAdd)).sorted() as NSArray)
    }

    @objc func removeTags(_ path: String, _ tagsToRemove: NSArray) -> Bool {
        let existing = Set(tags(path) ?? [])
        let toRemove = Set(tagsToRemove.compactMap { $0 as? String })
        return setTags(path, Array(existing.subtracting(toRemove)).sorted() as NSArray)
    }

    // MARK: - Uniform Type Identifiers

    @objc func fileUTI(_ path: String) -> String? {
        // NSWorkspace is @MainActor; JS always runs on the main thread.
        MainActor.assumeIsolated {
            do {
                return try NSWorkspace.shared.type(ofFile: expand(path))
            } catch {
                AKError("hs.fs.fileUTI: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Bookmarks

    @objc func pathToBookmark(_ path: String) -> String? {
        do {
            let data = try URL(fileURLWithPath: expand(path))
                .bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return data.base64EncodedString()
        } catch {
            AKError("hs.fs.pathToBookmark: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func pathFromBookmark(_ data: String) -> String? {
        guard let bookmarkData = Data(base64Encoded: data) else {
            AKError("hs.fs.pathFromBookmark: invalid base64 data")
            return nil
        }
        do {
            var isStale = false
            let resolved = try URL(resolvingBookmarkData: bookmarkData,
                                   options: .withoutMounting,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
            if isStale { AKTrace("hs.fs.pathFromBookmark: bookmark data is stale") }
            return resolved.path
        } catch {
            AKError("hs.fs.pathFromBookmark: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Private extension

private extension Optional where Wrapped == FileHandle {
    /// Unwrap a `FileHandle?`, throwing a descriptive error if nil.
    func require(label: String) throws -> FileHandle {
        guard let handle = self else {
            throw CocoaError(.fileReadUnknown,
                             userInfo: [NSLocalizedDescriptionKey: label])
        }
        return handle
    }
}
