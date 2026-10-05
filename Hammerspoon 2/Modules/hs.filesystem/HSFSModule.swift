//
//  HSFSModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit          // NSWorkspace (volumes, eject, fileUTI)
import Darwin          // POSIX stat/lstat/rmdir
import UniformTypeIdentifiers

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
/// hs.fs.eachLine("/etc/hosts", function(line) {
///     console.log(line);
///     // return false to stop early
/// });
///
/// hs.fs.write("/tmp/hello.txt", "Hello, world!\n");
/// hs.fs.append("/tmp/hello.txt", "More content\n");
/// ```
///
/// ## Working with open files
///
/// For incremental, positioned, binary, or locked access, open the file to get an
/// `HSFile` object (the equivalent of a Lua `io` file handle):
///
/// ```javascript
/// const f = hs.fs.open("~/notes.txt", "r+");
/// const firstLine = f.readLine();
/// f.seek(0, "end");
/// f.writeLine("appended");
/// f.close();
///
/// // Or let hs.fs.withFile() close it for you:
/// const header = hs.fs.withFile("~/image.png", "r", f => f.readBytes(8));
/// ```
///
/// ## Errors
///
/// Functions that fail return `null` or `false` and set `hs.fs.lastError` to an object like
/// `{code: "ENOENT", message: "No such file or directory"}`. Most failures are also logged to the
/// Console; failures that are often expected (such as `hs.fs.open()` on a missing file) are not.
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

    // MARK: - Errors

    /// {{code: string, message: string} | null} The error from the most recent failed `hs.fs` function, or `null` if none has failed.
    ///
    /// The object has a `code` (a POSIX error name such as `"ENOENT"`, `"EEXIST"`, or `"EACCES"`, or
    /// `"EINVAL"` for invalid arguments) and a human-readable `message`. Like C's `errno`, it is not
    /// cleared by successful calls, so only consult it after a function has reported failure.
    /// Errors from methods on an open file are recorded on that file's own `lastError` instead.
    /// - Example:
    /// ```js
    /// const f = hs.fs.open("/does/not/exist")
    /// if (!f) console.log("Open failed: " + hs.fs.lastError.code)
    /// ```
    @objc var lastError: JSValue? { get }

    // MARK: - Open files

    /// Open a file, returning an `HSFile` object for reading and/or writing it.
    ///
    /// Modes follow C's `fopen()` (and Lua's `io.open()`):
    ///
    /// | Mode | Read | Write | Creates | Truncates | Notes |
    /// |------|------|-------|---------|-----------|-------|
    /// | `"r"`  | ✓ | | | | The default |
    /// | `"r+"` | ✓ | ✓ | | | |
    /// | `"w"`  | | ✓ | ✓ | ✓ | |
    /// | `"w+"` | ✓ | ✓ | ✓ | ✓ | |
    /// | `"a"`  | | ✓ | ✓ | | Every write goes to the end of the file |
    /// | `"a+"` | ✓ | ✓ | ✓ | | Reads start at the beginning; every write goes to the end |
    ///
    /// Add `x` to a `w` mode (`"wx"`, `"w+x"`) to fail if the file already exists. A `b` is accepted and
    /// ignored, since all files can be read as text or bytes.
    ///
    /// Directories cannot be opened. A file that can't be opened (for example because it doesn't exist) is
    /// not logged to the Console, since that is often an expected outcome; check `hs.fs.lastError` instead.
    /// Invalid arguments, such as an unknown mode, are logged.
    ///
    /// Close the file with `close()` when you are finished with it; any files still open are closed
    /// automatically when your configuration is reloaded.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - mode?: The open mode. Defaults to `"r"`.
    ///   - permissions?: POSIX permission bits applied if the file is created, e.g. `0o600` (`0` creates a file with no permissions). Defaults to `0o644` when omitted; any other non-integer value, including `NaN`, fails with `EINVAL`. The process umask is applied in either case.
    /// - Returns: {HSFile | null} An `HSFile`, or `null` on failure (see `hs.fs.lastError`).
    /// - Example:
    /// ```js
    /// const f = hs.fs.open("~/notes.txt", "a")
    /// if (f) {
    ///     f.writeLine("Another note")
    ///     f.close()
    /// }
    /// ```
    @objc func open(_ path: String, _ mode: String, _ permissions: Double) -> JSValue?

    /// Create and open a new, uniquely named temporary file.
    ///
    /// The file is created in `hs.fs.temporaryDirectory()` with permissions `0o600` and opened in `"w+"` mode.
    /// It is not deleted automatically; call `remove()` on it when you no longer need it on disk.
    ///
    /// - Parameter prefix?: A prefix for the file name. Must not contain `/`. Defaults to `"hs"`.
    /// - Returns: {HSFile | null} An `HSFile`, or `null` on failure (see `hs.fs.lastError`).
    /// - Example:
    /// ```js
    /// const tmp = hs.fs.tempFile("myspoon")
    /// tmp.write("scratch data")
    /// console.log("Wrote " + tmp.path)
    /// ```
    @objc func tempFile(_ prefix: String) -> JSValue?

    /// Open a file, pass it to a function, and close it again afterwards.
    ///
    /// The file is closed when the function returns, even if it throws (in which case the exception
    /// propagates to you). The function must do all its work synchronously: an `async` function would
    /// find the file already closed after its first `await`.
    ///
    /// The mode may be omitted, in which case the file is opened for reading (`"r"`):
    /// `hs.fs.withFile(path, f => ...)`.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - mode?: {string | ((file: HSFile) => any)} The open mode, as for `hs.fs.open()`. Defaults to `"r"`; if you omit it, pass the callback in its place.
    ///   - callback?: {(file: HSFile) => any} Called with the open file. Required unless it was passed in place of `mode`.
    /// - Returns: {any} Whatever `callback` returns, or `null` if the file could not be opened or no callback was given (see `hs.fs.lastError`).
    /// - Example:
    /// ```js
    /// const header = hs.fs.withFile("/etc/hosts", f => f.readLine())
    ///
    /// hs.fs.withFile("~/counter.txt", "r+", f => {
    ///     const n = (parseInt(f.read()) || 0) + 1
    ///     f.truncate()
    ///     f.rewind()
    ///     f.write(String(n))
    /// })
    /// ```
    @objc func withFile(_ path: String, _ mode: String, _ callback: JSFunction) -> JSValue?

    // MARK: - File I/O

    /// Read part or all of a file as a UTF-8 string.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - offset: Byte offset to start reading from. Pass `0` (or omit) to read from the beginning.
    ///   - length: Maximum number of bytes to read. Pass `0` (or omit) to read to the end of the file.
    /// - Returns: The file contents as a UTF-8 string, or `null` if the file cannot be read.
    /// - Example:
    /// ```js
    /// const all   = hs.fs.read("/etc/hosts")            // entire file
    /// const chunk = hs.fs.read("/etc/hosts", 100, 50)   // 50 bytes starting at byte 100
    /// ```
    @objc func read(_ path: String, _ offset: Int, _ length: Int) -> String?

    /// Call a function for each line of a file.
    ///
    /// This behaves exactly like opening the file and calling `HSFile.eachLine()`: line endings (`\n` or
    /// `\r\n`) are stripped; the callback may return `false` (and only `false`) to stop early; if the
    /// callback throws, iteration stops and the exception propagates to you; and invalid UTF-8 stops
    /// iteration with `hs.fs.lastError.code === "EILSEQ"`.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - callback: {(line: string) => boolean | void} Called once per line. Return `false` to stop.
    /// - Returns: `true` if iteration completed or was stopped by the callback returning `false`; `false` if the file could not be opened or read (see `hs.fs.lastError`), or if the callback threw.
    /// - Example:
    /// ```js
    /// hs.fs.eachLine("/etc/hosts", (line) => {
    ///     if (line.startsWith("#")) return
    ///     console.log(line)
    /// })
    /// ```
    @objc func eachLine(_ path: String, _ callback: JSFunction) -> Bool

    /// Write a UTF-8 string to a file, creating it or overwriting any existing content.
    ///
    /// Intermediate directories are not created automatically; use `mkdir` first if needed.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - content: String to write.
    ///   - inPlace?: Whether to write the file in-place or atomically. Defaults to atomically (false).
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.write("/tmp/hello.txt", "Hello, world!\n")
    /// ```
    @objc func write(_ path: String, _ content: String, _ inPlace: Bool) -> Bool

    /// Append a UTF-8 string to a file, creating it if it does not exist.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - content: String to append.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.append("/tmp/log.txt", "another line\n")
    /// ```
    @objc func append(_ path: String, _ content: String) -> Bool

    // MARK: - Existence and Type Checks

    /// Determine if a filesystem object exists at the given path
    /// Unlike `isFile` and `isDirectory`, this follows symlinks.
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if any filesystem entry (file, directory, symlink, etc.) exists at the path.
    /// - Example:
    /// ```js
    /// if (hs.fs.exists("/tmp/file.txt")) console.log("exists")
    /// ```
    @objc func exists(_ path: String) -> Bool

    /// Determine if a file exists at the given path
    /// This does **not** follow symlinks; a symlink pointing at a file returns `false`.
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if a regular file (not a directory or symlink) exists at the path.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.isFile("/etc/hosts"))
    /// ```
    @objc func isFile(_ path: String) -> Bool

    /// Determine if a directory exists at the given path
    /// This does **not** follow symlinks; a symlink pointing at a directory returns `false`.
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if a directory exists at the path.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.isDirectory("/tmp"))
    /// ```
    @objc func isDirectory(_ path: String) -> Bool

    /// Determine if a symlink exists at the given path
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the path is a symbolic link.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.isSymlink("/var"))
    /// ```
    @objc func isSymlink(_ path: String) -> Bool

    /// Determine if a given filesystem path is readable
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the current process can read the file or directory at the path.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.isReadable("/etc/hosts"))
    /// ```
    @objc func isReadable(_ path: String) -> Bool

    /// Determine if a given filesystem path is writable
    ///
    /// - Parameter path: Path to check. `~` is expanded.
    /// - Returns: `true` if the current process can write to the file or directory at the path.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.isWritable("/tmp"))
    /// ```
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
    /// - Example:
    /// ```js
    /// hs.fs.copy("/tmp/a.txt", "/tmp/b.txt")
    /// ```
    @objc func copy(_ source: String, _ destination: String) -> Bool

    /// Move (rename) a file or directory.
    ///
    /// The destination must not already exist.
    ///
    /// - Parameters:
    ///   - source: Path to the existing file or directory. `~` is expanded.
    ///   - destination: New path. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.move("/tmp/old.txt", "/tmp/new.txt")
    /// ```
    @objc func move(_ source: String, _ destination: String) -> Bool

    /// Delete a file or directory at the given path.
    ///
    /// Directories are removed recursively. To remove only an empty directory,
    /// use `rmdir` instead.
    ///
    /// - Parameter path: Path to delete. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.deletePath("/tmp/old.txt")
    /// ```
    @objc func deletePath(_ path: String) -> Bool

    // MARK: - Directory Operations

    /// List the immediate contents of a directory.
    ///
    /// Returns bare filenames (not full paths), sorted alphabetically.
    /// The `.` and `..` entries are never included.
    ///
    /// - Parameter path: Path to the directory. `~` is expanded.
    /// - Returns: Sorted array of filenames, or `null` if the path cannot be read.
    /// - Example:
    /// ```js
    /// const files = hs.fs.list("~/Documents")
    /// ```
    @objc func list(_ path: String) -> [String]?

    /// Recursively list all entries under a directory.
    ///
    /// Returns paths relative to `path`, sorted alphabetically.
    ///
    /// - Parameter path: Path to the root directory. `~` is expanded.
    /// - Returns: Sorted array of relative paths, or `null` if the path cannot be read.
    /// - Example:
    /// ```js
    /// const all = hs.fs.listRecursive("~/Documents")
    /// ```
    @objc func listRecursive(_ path: String) -> [String]?

    /// Create a directory, including all necessary intermediate directories.
    ///
    /// Succeeds silently if the directory already exists.
    ///
    /// - Parameter path: Path of the directory to create. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.mkdir("~/Projects/new-thing")
    /// ```
    @objc func mkdir(_ path: String) -> Bool

    /// Remove an empty directory.
    ///
    /// Fails if the directory is not empty. Use `deletePath` to remove a non-empty
    /// directory recursively.
    ///
    /// - Parameter path: Path of the directory to remove. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.rmdir("/tmp/empty-dir")
    /// ```
    @objc func rmdir(_ path: String) -> Bool

    // MARK: - Working Directory

    /// Returns the current working directory of the process.
    ///
    /// - Returns: Current directory path, or `null` on error.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.currentDir())
    /// ```
    @objc func currentDir() -> String?

    /// Change the current working directory of the process.
    ///
    /// - Parameter path: New working directory path. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.chdir("~/Projects")
    /// ```
    @objc func chdir(_ path: String) -> Bool

    // MARK: - Path Utilities

    /// Resolve a path to its absolute, canonical form.
    ///
    /// Expands `~`, resolves `.` and `..`, and follows all symbolic links.
    /// Returns `null` if any component of the path does not exist.
    ///
    /// - Parameter path: Path to resolve.
    /// - Returns: Absolute canonical path, or `null` if it cannot be resolved.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.pathToAbsolute("~/Library"))
    /// ```
    @objc func pathToAbsolute(_ path: String) -> String?

    /// Return the localised display name for a file or directory as shown by Finder.
    ///
    /// For example, `/Library` appears as `"Library"` in Finder even though its
    /// on-disk name is the same.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Display name string, or `null` if the path does not exist.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.displayName("/Library"))
    /// ```
    @objc func displayName(_ path: String) -> String?

    /// Returns the temporary directory for the current user.
    ///
    /// - Returns: Temporary directory path (always ends with `/`).
    /// - Example:
    /// ```js
    /// console.log(hs.fs.temporaryDirectory())
    /// ```
    @objc func temporaryDirectory() -> String

    /// Returns the home directory for the current user.
    ///
    /// - Returns: Home directory path string.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.homeDirectory())
    /// ```
    @objc func homeDirectory() -> String

    /// Returns a `file://` URL string for the given path.
    ///
    /// - Parameter path: Filesystem path. `~` is expanded.
    /// - Returns: URL string
    /// - Example:
    /// ```js
    /// console.log(hs.fs.urlFromPath("/tmp/foo.txt"))
    /// // → "file:///tmp/foo.txt"
    /// ```
    @objc func urlFromPath(_ path: String) -> String

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
    /// - Example:
    /// ```js
    /// const info = hs.fs.attributes("/etc/hosts")
    /// console.log(info.size, info.type)
    /// ```
    @objc func attributes(_ path: String) -> [String: Any]?

    /// Set the access and modification times of a file, creating it if it does not exist
    /// (equivalent to the POSIX `touch` command).
    ///
    /// The argument order matches Hammerspoon v1 (LuaFileSystem) and Node's `fs.utimes`: access time first.
    ///
    /// - Parameters:
    ///   - path: Path to the file. `~` is expanded.
    ///   - accessDate?: Seconds since the Unix epoch (fractions allowed). Defaults to now.
    ///   - modificationDate?: Seconds since the Unix epoch (fractions allowed). Defaults to `accessDate`.
    /// - Returns: `true` on success, `false` on failure (including `EINVAL` for a `NaN`, infinite, or out-of-range timestamp).
    /// - Example:
    /// ```js
    /// hs.fs.touch("/tmp/marker.txt")                             // now
    /// hs.fs.touch("/tmp/marker.txt", Date.now() / 1000 - 86400)  // both times one day ago
    /// ```
    @objc func touch(_ path: String, _ accessDate: Double, _ modificationDate: Double) -> Bool

    /// Set the POSIX permission bits of a file or directory.
    ///
    /// Follows symbolic links.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - permissions: The permission bits, as an integer between `0` and `0o7777`, e.g. `0o644`. Use an octal literal: decimal `755` is a different (and unusual) mode.
    /// - Returns: `true` on success, `false` on failure (including `EINVAL` if `permissions` is missing or out of range).
    /// - Example:
    /// ```js
    /// hs.fs.setPermissions("~/bin/myscript.sh", 0o755)
    /// ```
    @objc func setPermissions(_ path: String, _ permissions: Double) -> Bool

    // MARK: - Links

    /// Create a hard link at `destination` pointing at `source`.
    ///
    /// Both paths must be on the same filesystem volume.
    ///
    /// - Parameters:
    ///   - source: Path of the existing file.
    ///   - destination: Path for the new hard link.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.link("/tmp/a.txt", "/tmp/b.txt")
    /// ```
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
    /// - Example:
    /// ```js
    /// hs.fs.symlink("/usr/local/bin", "/tmp/bin-link")
    /// ```
    @objc func symlink(_ source: String, _ destination: String) -> Bool

    /// Read the target of a symbolic link without resolving it.
    ///
    /// - Parameter path: Path to the symbolic link.
    /// - Returns: The raw path the link points to, or `null` if the path is not a symlink.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.readlink("/var"))
    /// ```
    @objc func readlink(_ path: String) -> String?

    // MARK: - Finder Tags

    /// Get the Finder tags assigned to a file or directory.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Array of tag name strings, or `null` if no tags are set.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.tags("~/Documents/report.pdf"))
    /// ```
    @objc func tags(_ path: String) -> [String]?

    /// Replace all Finder tags on a file or directory.
    /// This function is only available on macOS Tahoe (26) or later.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - newTags: Array of tag name strings.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.setTags("~/Documents/report.pdf", ["Important", "Work"])
    /// ```
    @objc @available(macOS 26.0, *) func setTags(_ path: String, _ newTags: NSArray) -> Bool

    /// Add Finder tags to a file or directory (union with existing tags).
    /// This function is only available on macOS Tahoe (26) or later.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - newTags: Array of tag name strings to add.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.addTags("~/Documents/report.pdf", ["Reviewed"])
    /// ```
    @objc @available(macOS 26.0, *) func addTags(_ path: String, _ newTags: NSArray) -> Bool

    /// Remove specific Finder tags from a file or directory.
    /// This function is only available on macOS Tahoe (26) or later.
    ///
    /// Tags not currently present are silently ignored.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - tagsToRemove: Array of tag name strings to remove.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.removeTags("~/Documents/report.pdf", ["Draft"])
    /// ```
    @objc @available(macOS 26.0, *) func removeTags(_ path: String, _ tagsToRemove: NSArray) -> Bool

    // MARK: - Uniform Type Identifiers

    /// Return the Uniform Type Identifier for the file at the given path.
    ///
    /// - Parameter path: Path to the file.
    /// - Returns: UTI string, or `null` on failure.
    /// - Example:
    /// ```js
    /// console.log(hs.fs.fileUTI("/etc/hosts"))    // → "public.plain-text"
    /// console.log(hs.fs.fileUTI("/tmp/foo.png"))  // → "public.png"
    /// ```
    @objc func fileUTI(_ path: String) -> String?

    // MARK: - Bookmarks

    /// Encode a file path as a persistent bookmark that survives file moves and renames.
    ///
    /// The returned string is base64-encoded bookmark data that can be stored and
    /// later resolved with `pathFromBookmark`.
    ///
    /// - Parameter path: Path to the file or directory. `~` is expanded.
    /// - Returns: Base64-encoded bookmark string, or `null` on failure.
    /// - Example:
    /// ```js
    /// const data = hs.fs.pathToBookmark("/tmp/foo.txt")
    /// ```
    @objc func pathToBookmark(_ path: String) -> String?

    /// Resolve a base64-encoded bookmark back to a file path.
    ///
    /// - Parameter data: Base64-encoded bookmark string produced by `pathToBookmark`.
    /// - Returns: The current file path, or `null` if the bookmark cannot be resolved.
    /// - Example:
    /// ```js
    /// const path = hs.fs.pathFromBookmark(savedData)
    /// ```
    @objc func pathFromBookmark(_ data: String) -> String?

    // MARK: - Volume operations

    /// Return information about all currently mounted filesystem volumes.
    ///
    /// Returns an object keyed by the volume mount path. Each value contains:
    /// - `name` — Localised display name of the volume.
    /// - `isLocal` — `true` if the volume is locally connected.
    /// - `isInternal` — `true` if the volume resides on internal storage.
    /// - `isEjectable` — `true` if the volume can be ejected.
    /// - `isRemovable` — `true` if the volume resides on removable media.
    /// - `isBrowsable` — `true` if the volume can be browsed by the user.
    /// - `isReadOnly` — `true` if the volume is mounted read-only.
    /// - `isRootFileSystem` — `true` if this is the root filesystem (`/`).
    /// - `totalCapacity` — Total size in bytes.
    /// - `availableCapacity` — Available space in bytes.
    /// - `uuid` — Volume UUID string (if available).
    ///
    /// - Parameter showHidden: Pass `true` to include hidden volumes. Defaults to `false`.
    /// - Returns: Object keyed by mount path, or `null` on failure.
    /// - Example:
    /// ```js
    /// const vols = hs.fs.volumes()
    /// for (const [path, info] of Object.entries(vols)) {
    ///     console.log(path + " — " + info.name)
    /// }
    /// ```
    @objc func volumes(_ showHidden: Bool) -> [String: Any]?

    /// Unmount and eject the volume at the given path.
    ///
    /// - Parameter path: The mount path of the volume to eject. `~` is expanded.
    /// - Returns: `true` if the volume was ejected successfully, `false` otherwise.
    /// - Example:
    /// ```js
    /// const ok = hs.fs.ejectVolume("/Volumes/MyDisk")
    /// ```
    @objc func ejectVolume(_ path: String) -> Bool

    /// Create a new volume event watcher.
    ///
    /// Call `setCallback()` and `start()` on the returned object to begin receiving
    /// volume mount/unmount/rename events.
    ///
    /// - Returns: An `HSVolumeWatcher` object.
    /// - Example:
    /// ```js
    /// const w = hs.fs.addVolumeWatcher()
    /// w.setCallback((event, info) => {
    ///     console.log(event + ": " + info.path)
    /// }).start()
    /// ```
    @objc func addVolumeWatcher() -> HSVolumeWatcher

    /// Stop and destroy a volume watcher previously created with `addVolumeWatcher`.
    ///
    /// - Parameter watcher: The watcher to remove.
    /// - Example:
    /// ```js
    /// const w = hs.fs.addVolumeWatcher()
    /// // ... later ...
    /// hs.fs.removeVolumeWatcher(w)
    /// ```
    @objc func removeVolumeWatcher(_ watcher: HSVolumeWatcher)

    // MARK: - Path watchers

    /// Create a watcher for filesystem events at a given path.
    ///
    /// Events are batched and delivered with a latency of approximately one second.
    /// Call `setCallback()` and `start()` on the returned object to begin receiving events.
    ///
    /// - Parameter path: The path to watch. `~` is expanded.
    /// - Returns: An `HSPathWatcher` object.
    /// - Example:
    /// ```js
    /// const w = hs.fs.createPathWatcher("/Users/me/Documents")
    /// w.setCallback((paths, flags) => {
    ///     paths.forEach((p, i) => console.log(flags[i].join(",") + ": " + p))
    /// }).start()
    /// ```
    @objc func createPathWatcher(_ path: String) -> HSPathWatcher

    // MARK: - Extended attributes

    /// Get the value of an extended attribute for a file or directory.
    ///
    /// Attribute values are returned as ISO Latin-1 encoded strings so that arbitrary byte
    /// sequences are represented without loss. ASCII text attribute values appear readable as-is.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - attribute: Name of the extended attribute.
    ///   - options?: {string[]} Array of option strings: `"noFollow"` (do not follow symlinks), `"hfsCompression"`, `"createOnly"`, `"replaceOnly"`, `"noSecurity"`, `"noDefault"`. Pass an empty array or omit to use no options.
    ///   - position?: Byte offset within the attribute data. Defaults to `0`. Non-zero values are only valid for `"com.apple.ResourceFork"`.
    /// - Returns: The attribute value as a string, `""` if the attribute exists but contains no data, or `null` if the attribute does not exist or an error occurs.
    /// - Example:
    /// ```js
    /// const quarantine = hs.fs.xattrGet("/path/to/file.dmg", "com.apple.quarantine")
    /// if (quarantine !== null) console.log("quarantine: " + quarantine)
    /// ```
    @objc func xattrGet(_ path: String, _ attribute: String, _ options: NSArray?, _ position: Int) -> String?

    /// List all extended attributes defined for a file or directory.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - options?: {string[]} Array of option strings. Pass an empty array or omit to use no options.
    /// - Returns: Array of attribute name strings (may be empty), or `null` on error.
    /// - Example:
    /// ```js
    /// const attrs = hs.fs.xattrList("/path/to/file.dmg")
    /// if (attrs) attrs.forEach(a => console.log(a))
    /// ```
    @objc func xattrList(_ path: String, _ options: NSArray?) -> [String]?

    /// Set the value of an extended attribute for a file or directory.
    ///
    /// The value is written as ISO Latin-1 bytes, providing a lossless round-trip with
    /// `xattrGet`. Plain ASCII strings work directly without any encoding.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - attribute: Name of the extended attribute.
    ///   - value: The value to write.
    ///   - options?: {string[]} Array of option strings: `"noFollow"`, `"hfsCompression"`, `"createOnly"`, `"replaceOnly"`, `"noSecurity"`, `"noDefault"`. Pass an empty array or omit to use no options.
    ///   - position?: Byte offset within the attribute data. Defaults to `0`. Non-zero values are only valid for `"com.apple.ResourceFork"`.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// hs.fs.xattrSet("/path/to/file.txt", "com.example.origin", "https://example.com")
    /// ```
    @objc func xattrSet(_ path: String, _ attribute: String, _ value: String, _ options: NSArray?, _ position: Int) -> Bool

    /// Remove an extended attribute from a file or directory.
    ///
    /// - Parameters:
    ///   - path: Path to the file or directory. `~` is expanded.
    ///   - attribute: Name of the extended attribute to remove.
    ///   - options?: {string[]} Array of option strings: `"noFollow"`, `"hfsCompression"`. Pass an empty array or omit to use no options.
    /// - Returns: `true` on success, `false` on failure (including if the attribute does not exist).
    /// - Example:
    /// ```js
    /// hs.fs.xattrRemove("/path/to/file.dmg", "com.apple.quarantine")
    /// ```
    @objc func xattrRemove(_ path: String, _ attribute: String, _ options: NSArray?) -> Bool
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSFSModule: NSObject, HSModuleAPI, HSFSModuleAPI {
    var moduleName = "hs.fs"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    private var volumeWatchers = HSWeakObjectSet<HSVolumeWatcher>()
    private var pathWatchers = HSWeakObjectSet<HSPathWatcher>()
    private var openFiles = HSWeakObjectSet<HSFile>()

    /// The `{code, message}` of the most recent failure, exposed to JS as `lastError`.
    private(set) var lastErrorInfo: [String: Any]?

    // A JSValue so that "no error" is a real JS null (JSExport bridges nil to undefined).
    @objc var lastError: JSValue? { HSFSSupport.jsValueOrNull(lastErrorInfo) }

    func shutdown() {
        for watcher in volumeWatchers.allObjects { watcher.destroy() }
        volumeWatchers.removeAllObjects()
        for watcher in pathWatchers.allObjects { watcher.destroy() }
        pathWatchers.removeAllObjects()
        for file in openFiles.allObjects { file.destroy() }
        openFiles.removeAllObjects()
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let v = volumeWatchers.allObjects.count
        let p = pathWatchers.allObjects.count
        let f = openFiles.allObjects.filter(\.isOpen).count
        return "<\(moduleName): \(v) volume watcher\(v == 1 ? "" : "s"), \(p) path watcher\(p == 1 ? "" : "s"), \(f) open file\(f == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Private helpers

    private let fm = FileManager.default

    /// Record a Foundation error in `lastError` and log it.
    private func fail(_ function: String, _ error: Error) {
        lastErrorInfo = HSFSSupport.errorInfo(from: error)
        AKError("\(function): \(error.localizedDescription)")
    }

    /// Record a POSIX errno in `lastError` and log it, optionally naming the path involved.
    private func fail(_ function: String, errno code: Int32, path: String? = nil) {
        let info = HSFSSupport.errorInfo(errno: code)
        lastErrorInfo = info
        let message = info["message"] as? String ?? ""
        AKError("\(function): \(path.map { "\($0): " } ?? "")\(message)")
    }

    /// Record a POSIX errno in `lastError` without logging, for functions whose `null` result is an
    /// expected outcome (e.g. `pathToAbsolute` on a path that doesn't exist).
    private func record(errno code: Int32) {
        lastErrorInfo = HSFSSupport.errorInfo(errno: code)
    }

    /// Record an error with an explicit code in `lastError` without logging.
    private func record(code: String, message: String) {
        lastErrorInfo = HSFSSupport.errorInfo(code: code, message: message)
    }

    /// Record an error with an explicit code in `lastError` and log it.
    private func fail(_ function: String, code: String, message: String) {
        lastErrorInfo = HSFSSupport.errorInfo(code: code, message: message)
        AKError("\(function): \(message)")
    }

    /// JSExport passes omitted string arguments as the literal string "undefined".
    private func isOmitted(_ argument: String) -> Bool {
        argument.isEmpty || argument == "undefined"
    }

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

    private func parseXattrOptions(_ options: NSArray?) -> Int32? {
        guard let options = options else { return 0 }
        var flags: Int32 = 0
        for case let opt as String in options {
            switch opt {
            case "noFollow":       flags |= XATTR_NOFOLLOW
            case "hfsCompression": flags |= XATTR_SHOWCOMPRESSION
            case "createOnly":     flags |= XATTR_CREATE
            case "replaceOnly":    flags |= XATTR_REPLACE
            case "noSecurity":     flags |= XATTR_NOSECURITY
            case "noDefault":      flags |= XATTR_NODEFAULT
            default:
                fail("hs.fs xattr", code: "EINVAL", message: "unrecognized option '\(opt)'")
                return nil
            }
        }
        return flags
    }

    // MARK: - Open files

    // `permissions` is a Double so that an explicit 0 is distinguishable from an omitted argument.
    // Returns a JSValue so failure is a real JS null rather than undefined.
    @objc func open(_ path: String, _ mode: String = "r", _ permissions: Double = .nan) -> JSValue? {
        // Only a genuinely omitted (or undefined) argument selects the default. An explicit NaN is
        // rejected rather than silently creating a file with the more permissive 0o644.
        HSFSSupport.jsValueOrNull(
            openFile(path, mode, permissions: HSFSSupport.optionalNumberArgument(permissions, at: 2)))
    }

    /// Open a file. `permissions` is `nil` to use the default `0o644` for newly created files.
    func openFile(_ path: String, _ mode: String, permissions: Double?) -> HSFile? {
        let fileMode = isOmitted(mode) ? "r" : mode
        guard let flags = HSFile.openFlags(forMode: fileMode) else {
            fail("hs.fs.open", code: "EINVAL", message: "invalid mode \"\(mode)\"")
            return nil
        }
        let createMode: mode_t
        if let permissions {
            guard let bits = HSFSSupport.permissionBits(permissions, function: "hs.fs.open") else {
                fail("hs.fs.open", code: "EINVAL", message: "permissions must be an integer between 0 and 0o7777")
                return nil
            }
            createMode = bits
        } else {
            createMode = 0o644
        }
        let expandedPath = expand(path)
        let fd = unsafe Darwin.open(expandedPath, flags, createMode)
        guard fd >= 0 else {
            // Not logged: "try to open, fall back if it's missing" is a normal pattern, and the
            // caller gets null plus lastError. Invalid arguments (above) are still logged.
            record(errno: errno)
            return nil
        }

        var st = Darwin.stat()
        if unsafe fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR {
            Darwin.close(fd)
            record(errno: EISDIR)
            return nil
        }

        let file = HSFile(fd: fd, path: expandedPath, mode: fileMode)
        openFiles.add(file)
        return file
    }

    @objc func tempFile(_ prefix: String = "hs") -> JSValue? {
        HSFSSupport.jsValueOrNull(makeTempFile(prefix))
    }

    /// Create and open a unique temporary file (see `tempFile`).
    func makeTempFile(_ prefix: String) -> HSFile? {
        let namePrefix = isOmitted(prefix) ? "hs" : prefix
        guard !namePrefix.contains("/") else {
            fail("hs.fs.tempFile", code: "EINVAL", message: "prefix must not contain \"/\"")
            return nil
        }
        var template = Array(((NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(namePrefix).XXXXXX")).utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { unsafe mkostemp($0.baseAddress, O_CLOEXEC) }
        guard fd >= 0 else {
            fail("hs.fs.tempFile", errno: errno)
            return nil
        }
        let path = template.withUnsafeBufferPointer { unsafe String(cString: $0.baseAddress!) }
        let file = HSFile(fd: fd, path: path, mode: "w+")
        openFiles.add(file)
        return file
    }

    @objc func withFile(_ path: String, _ mode: String, _ callback: JSFunction) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        // Support withFile(path, fn): the mode was omitted and the callback is the second argument.
        var fileMode = mode
        var function = callback
        if let arguments = JSContext.currentArguments() as? [JSValue], arguments.count >= 2,
           HSFSSupport.isFunction(arguments[1]) {
            fileMode = "r"
            function = arguments[1]
        }
        guard HSFSSupport.isFunction(function) else {
            fail("hs.fs.withFile", code: "EINVAL", message: "a callback function is required")
            return JSValue(nullIn: context)
        }
        guard let file = openFile(path, fileMode, permissions: nil) else { return JSValue(nullIn: context) }
        defer { _ = file.close() }
        // callCapturingException ensures a throw inside the callback reaches the JS caller.
        return context.callCapturingException { function.call(withArguments: [file]) }
    }

    // MARK: - File I/O

    @objc func read(_ path: String, _ offset: Int = 0, _ length: Int = 0) -> String? {
        guard let handle = FileHandle(forReadingAtPath: expand(path)) else {
            fail("hs.fs.read", errno: errno, path: path)
            return nil
        }
        defer { handle.closeFile() }

        if offset > 0 { handle.seek(toFileOffset: UInt64(offset)) }
        let data = length > 0 ? handle.readData(ofLength: length) : handle.readDataToEndOfFile()

        guard let result = String(data: data, encoding: .utf8) else {
            fail("hs.fs.read", code: "EILSEQ", message: "\(path) is not valid UTF-8")
            return nil
        }
        return result
    }

    @objc func eachLine(_ path: String, _ callback: JSFunction) -> Bool {
        // Delegate to HSFile so the module and handle forms behave identically.
        guard let file = openFile(path, "r", permissions: nil) else { return false }
        defer { _ = file.close() }
        let completed = file.eachLine(callback)
        if !completed, let error = file.lastErrorInfo {
            lastErrorInfo = error
        }
        return completed
    }

    @objc func write(_ path: String, _ content: String, _ inPlace: Bool = false) -> Bool {
        do {
            try content.write(toFile: expand(path), atomically: !inPlace, encoding: .utf8)
            return true
        } catch {
            fail("hs.fs.write", error)
            return false
        }
    }

    @objc func append(_ path: String, _ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else {
            fail("hs.fs.append", code: "EILSEQ", message: "could not encode content as UTF-8")
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
            fail("hs.fs.append", error)
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
            fail("hs.fs.copy", error)
            return false
        }
    }

    @objc func move(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.moveItem(atPath: expand(source), toPath: expand(destination))
            return true
        } catch {
            fail("hs.fs.move", error)
            return false
        }
    }

    @objc func deletePath(_ path: String) -> Bool {
        do {
            try fm.removeItem(atPath: expand(path))
            return true
        } catch {
            fail("hs.fs.deletePath", error)
            return false
        }
    }

    // MARK: - Directory Operations

    @objc func list(_ path: String) -> [String]? {
        do {
            return try fm.contentsOfDirectory(atPath: expand(path)).sorted()
        } catch {
            fail("hs.fs.list", error)
            return nil
        }
    }

    @objc func listRecursive(_ path: String) -> [String]? {
        do {
            return try fm.subpathsOfDirectory(atPath: expand(path)).sorted()
        } catch {
            fail("hs.fs.listRecursive", error)
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
            fail("hs.fs.mkdir", error)
            return false
        }
    }

    @objc func rmdir(_ path: String) -> Bool {
        // Use POSIX rmdir() so it correctly rejects non-empty directories.
        let expandedPath = expand(path)
        guard unsafe Darwin.rmdir(expandedPath) == 0 else {
            fail("hs.fs.rmdir", errno: errno)
            return false
        }
        return true
    }

    // MARK: - Working Directory

    @objc func currentDir() -> String? {
        fm.currentDirectoryPath
    }

    @objc func chdir(_ path: String) -> Bool {
        guard unsafe Darwin.chdir(expand(path)) == 0 else {
            fail("hs.fs.chdir", errno: errno, path: path)
            return false
        }
        return true
    }

    // MARK: - Path Utilities

    @objc func pathToAbsolute(_ path: String) -> String? {
        let expandedPath = expand(path)

        // realpath() allocates memory for us when we pass it a nil second parameter.
        // We must free() that memory later.
        guard let resolved = unsafe realpath(expandedPath, nil) else {
            record(errno: errno)
            return nil
        }
        defer { unsafe free(resolved) }

        return unsafe String(validatingCString: resolved)
    }

    @objc func displayName(_ path: String) -> String? {
        let expandedPath = expand(path)
        guard fm.fileExists(atPath: expandedPath) else {
            record(errno: ENOENT)
            return nil
        }
        return fm.displayName(atPath: expandedPath)
    }

    @objc func temporaryDirectory() -> String {
        NSTemporaryDirectory()
    }

    @objc func homeDirectory() -> String {
        fm.homeDirectoryForCurrentUser.path
    }

    @objc func urlFromPath(_ path: String) -> String {
        URL(filePath: expand(path), directoryHint: .checkFileSystem).absoluteString
    }

    // MARK: - File Attributes

    @objc func attributes(_ path: String) -> [String: Any]? {
        var st = Darwin.stat()
        // Use lstat so the type field correctly reports symlinks.
        guard unsafe Darwin.lstat(expand(path), &st) == 0 else {
            fail("hs.fs.attributes", errno: errno)
            return nil
        }
        return HSFSSupport.attributes(from: st)
    }

    @objc func touch(_ path: String, _ accessDate: Double = .nan, _ modificationDate: Double = .nan) -> Bool {
        // Validate before creating anything, so a bad timestamp doesn't leave a new empty file behind.
        guard let times = HSFSSupport.touchTimes(
            accessDate: HSFSSupport.optionalNumberArgument(accessDate, at: 1),
            modificationDate: HSFSSupport.optionalNumberArgument(modificationDate, at: 2)
        ) else {
            fail("hs.fs.touch", code: "EINVAL", message: "timestamps must be finite numbers of seconds since the Unix epoch")
            return false
        }
        let expandedPath = expand(path)
        // O_CREAT without O_TRUNC: creates a missing file but leaves an existing one's contents alone.
        let fd = unsafe Darwin.open(expandedPath, O_WRONLY | O_CREAT | O_CLOEXEC, 0o644)
        if fd >= 0 {
            Darwin.close(fd)
        } else if errno != EISDIR {
            fail("hs.fs.touch", errno: errno, path: path)
            return false
        }
        guard unsafe utimensat(AT_FDCWD, expandedPath, times, 0) == 0 else {
            fail("hs.fs.touch", errno: errno, path: path)
            return false
        }
        return true
    }

    @objc func setPermissions(_ path: String, _ permissions: Double) -> Bool {
        guard let bits = HSFSSupport.permissionBits(permissions, function: "hs.fs.setPermissions") else {
            fail("hs.fs.setPermissions", code: "EINVAL", message: "permissions must be an integer between 0 and 0o7777")
            return false
        }
        guard unsafe Darwin.chmod(expand(path), bits) == 0 else {
            fail("hs.fs.setPermissions", errno: errno, path: path)
            return false
        }
        return true
    }

    // MARK: - Links

    @objc func link(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.linkItem(atPath: expand(source), toPath: expand(destination))
            return true
        } catch {
            fail("hs.fs.link", error)
            return false
        }
    }

    @objc func symlink(_ source: String, _ destination: String) -> Bool {
        do {
            try fm.createSymbolicLink(atPath: expand(destination),
                                      withDestinationPath: expand(source))
            return true
        } catch {
            fail("hs.fs.symlink", error)
            return false
        }
    }

    @objc func readlink(_ path: String) -> String? {
        do {
            return try fm.destinationOfSymbolicLink(atPath: expand(path))
        } catch {
            fail("hs.fs.readlink", error)
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
            fail("hs.fs.tags", error)
            return nil
        }
    }

    @objc @available(macOS 26.0, *)
    func setTags(_ path: String, _ newTags: NSArray) -> Bool {
        let tagList = newTags.compactMap { $0 as? String }
        do {
            var values = URLResourceValues()
            values.tagNames = tagList
            var fileURL = URL(fileURLWithPath: expand(path))
            try fileURL.setResourceValues(values)
            return true
        } catch {
            fail("hs.fs.setTags", error)
            return false
        }
    }

    @objc @available(macOS 26.0, *) func addTags(_ path: String, _ newTags: NSArray) -> Bool {
        let existing = Set(tags(path) ?? [])
        let toAdd    = Set(newTags.compactMap { $0 as? String })
        return setTags(path, Array(existing.union(toAdd)).sorted() as NSArray)
    }

    @objc @available(macOS 26.0, *) func removeTags(_ path: String, _ tagsToRemove: NSArray) -> Bool {
        let existing = Set(tags(path) ?? [])
        let toRemove = Set(tagsToRemove.compactMap { $0 as? String })
        return setTags(path, Array(existing.subtracting(toRemove)).sorted() as NSArray)
    }

    // MARK: - Uniform Type Identifiers

    @objc func fileUTI(_ path: String) -> String? {
        let url = NSURL(fileURLWithPath: expand(path))
        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey])
            guard let utType = values[.contentTypeKey] as? UTType else {
                record(code: "UNKNOWN", message: "No type identifier is available for \(path)")
                return nil
            }
            return utType.identifier
        } catch {
            lastErrorInfo = HSFSSupport.errorInfo(from: error)
            return nil
        }
    }

    // MARK: - Bookmarks

    @objc func pathToBookmark(_ path: String) -> String? {
        do {
            let data = try URL(fileURLWithPath: expand(path))
                .bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return data.base64EncodedString()
        } catch {
            fail("hs.fs.pathToBookmark", error)
            return nil
        }
    }

    @objc func pathFromBookmark(_ data: String) -> String? {
        guard let bookmarkData = Data(base64Encoded: data) else {
            fail("hs.fs.pathFromBookmark", code: "EINVAL", message: "invalid base64 data")
            return nil
        }
        do {
            var isStale = false
            let resolved = try URL(resolvingBookmarkData: bookmarkData,
                                   options: .withoutMounting,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
            if isStale { AKDebug("hs.fs.pathFromBookmark: bookmark data is stale") }
            return resolved.path
        } catch {
            fail("hs.fs.pathFromBookmark", error)
            return nil
        }
    }

    // MARK: - Volume operations

    @objc func volumes(_ showHidden: Bool) -> [String: Any]? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey,
            .volumeIsReadOnlyKey,
            .volumeIsRootFileSystemKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeUUIDStringKey,
        ]
        var options: FileManager.VolumeEnumerationOptions = []
        if !showHidden { options.insert(.skipHiddenVolumes) }

        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                              options: options) else {
            fail("hs.fs.volumes", code: "UNKNOWN", message: "could not enumerate mounted volumes")
            return nil
        }

        var result: [String: Any] = [:]
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            var info: [String: Any] = [:]
            if let v = values.volumeLocalizedName    { info["name"]              = v }
            if let v = values.volumeIsLocal          { info["isLocal"]           = v }
            if let v = values.volumeIsInternal       { info["isInternal"]        = v }
            if let v = values.volumeIsEjectable      { info["isEjectable"]       = v }
            if let v = values.volumeIsRemovable      { info["isRemovable"]       = v }
            if let v = values.volumeIsBrowsable      { info["isBrowsable"]       = v }
            if let v = values.volumeIsReadOnly       { info["isReadOnly"]        = v }
            if let v = values.volumeIsRootFileSystem { info["isRootFileSystem"]  = v }
            if let v = values.volumeTotalCapacity    { info["totalCapacity"]     = v }
            if let v = values.volumeAvailableCapacity { info["availableCapacity"] = v }
            if let v = values.volumeUUIDString       { info["uuid"]              = v }
            result[url.path] = info
        }
        return result
    }

    @objc func ejectVolume(_ path: String) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: expand(path)))
            return true
        } catch {
            fail("hs.fs.ejectVolume", error)
            return false
        }
    }

    @objc func addVolumeWatcher() -> HSVolumeWatcher {
        let watcher = HSVolumeWatcher()
        volumeWatchers.add(watcher)
        return watcher
    }

    @objc func removeVolumeWatcher(_ watcher: HSVolumeWatcher) {
        watcher.destroy()
        volumeWatchers.remove(watcher)
    }

    // MARK: - Path watchers

    @objc func createPathWatcher(_ path: String) -> HSPathWatcher {
        let watcher = HSPathWatcher(path: expand(path))
        pathWatchers.add(watcher)
        return watcher
    }

    // MARK: - Extended attributes

    @objc func xattrGet(_ path: String, _ attribute: String, _ options: NSArray?, _ position: Int) -> String? {
        let p = expand(path)
        guard let flags = parseXattrOptions(options) else { return nil }
        let pos = UInt32(max(0, position))

        let size = unsafe Darwin.getxattr(p, attribute, nil, 0, pos, flags)
        if size < 0 {
            if errno == ENOATTR {
                // A missing attribute is an expected outcome, so record it without logging.
                record(errno: ENOATTR)
            } else {
                fail("hs.fs.xattrGet", errno: errno)
            }
            return nil
        }
        guard size > 0 else { return "" }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { ptr in
            unsafe Darwin.getxattr(p, attribute, ptr.baseAddress, size, pos, flags)
        }
        if read < 0 {
            fail("hs.fs.xattrGet", errno: errno)
            return nil
        }
        return String(bytes: buffer[..<read], encoding: .isoLatin1)
    }

    @objc func xattrList(_ path: String, _ options: NSArray?) -> [String]? {
        let p = expand(path)
        guard let flags = parseXattrOptions(options) else { return nil }

        let size = unsafe Darwin.listxattr(p, nil, 0, flags)
        if size < 0 {
            fail("hs.fs.xattrList", errno: errno)
            return nil
        }
        guard size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { ptr in
            let cBuf: UnsafeMutablePointer<CChar>? = unsafe ptr.baseAddress?.assumingMemoryBound(to: CChar.self)
            return unsafe Darwin.listxattr(p, cBuf, size, flags)
        }
        if read < 0 {
            fail("hs.fs.xattrList", errno: errno)
            return nil
        }

        // The buffer is a sequence of NUL-terminated attribute name strings concatenated together.
        var result: [String] = []
        var remaining = Data(buffer[..<read])
        while !remaining.isEmpty {
            guard let nullIdx = remaining.firstIndex(of: 0) else { break }
            if let name = String(data: remaining[..<nullIdx], encoding: .utf8), !name.isEmpty {
                result.append(name)
            }
            remaining = remaining[(nullIdx + 1)...]
        }
        return result
    }

    @objc func xattrSet(_ path: String, _ attribute: String, _ value: String, _ options: NSArray?, _ position: Int) -> Bool {
        let p = expand(path)
        guard let flags = parseXattrOptions(options) else { return false }
        let pos = UInt32(max(0, position))

        guard let data = value.data(using: .isoLatin1) else {
            fail("hs.fs.xattrSet", code: "EINVAL", message: "value contains characters outside the Latin-1 range")
            return false
        }
        let result = unsafe data.withUnsafeBytes { ptr in
            unsafe Darwin.setxattr(p, attribute, ptr.baseAddress, data.count, pos, flags)
        }
        if result < 0 {
            fail("hs.fs.xattrSet", errno: errno)
            return false
        }
        return true
    }

    @objc func xattrRemove(_ path: String, _ attribute: String, _ options: NSArray?) -> Bool {
        let p = expand(path)
        guard let flags = parseXattrOptions(options) else { return false }
        if unsafe Darwin.removexattr(p, attribute, flags) < 0 {
            fail("hs.fs.xattrRemove", errno: errno)
            return false
        }
        return true
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
