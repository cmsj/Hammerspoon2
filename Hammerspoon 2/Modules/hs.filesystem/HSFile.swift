//
//  HSFile.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Darwin

// MARK: - API protocol

/// An open file, created by `hs.fs.open()` or `hs.fs.tempFile()`.
///
/// `HSFile` is the equivalent of a Lua `io` file handle in Hammerspoon v1. It supports
/// reading and writing text (UTF-8) or binary data (`Uint8Array`), seeking, truncating,
/// advisory locking, and operating on the underlying path (rename, duplicate, remove).
///
/// All reads and writes go straight to the file descriptor with no user-space buffering,
/// so `position` is always exact and data written is immediately visible to other
/// processes. Use `flush()` if you also need it forced to stable storage.
///
/// Operations that fail return `null` or `false` and set `lastError` to an object of the
/// form `{code: "ENOENT", message: "No such file or directory"}`. `lastError` is not cleared
/// by successful calls, so only consult it after a call has reported failure.
///
/// Always `close()` files when you are finished with them, or use `hs.fs.withFile()`, which
/// closes the file for you. Any files still open are closed when your configuration is reloaded.
///
/// Example:
/// ```js
/// const f = hs.fs.open("~/notes.txt", "a+")
/// f.writeLine("Remember the milk")
/// f.rewind()
/// let line
/// while ((line = f.readLine()) !== null) console.log(line)
/// f.close()
/// ```
@objc protocol HSFileAPI: HSTypeAPI, JSExport {

    // MARK: - Properties

    /// The absolute path of the file, with symbolic links resolved. Updated by `rename()`.
    /// - Example:
    /// ```js
    /// console.log(f.path)
    /// ```
    @objc var path: String { get }

    /// The mode the file was opened with (e.g. `"r"`, `"w+"`).
    /// - Example:
    /// ```js
    /// console.log(f.mode)
    /// ```
    @objc var mode: String { get }

    /// Whether the file is still open.
    /// - Example:
    /// ```js
    /// if (f.isOpen) f.close()
    /// ```
    @objc var isOpen: Bool { get }

    /// The current byte offset within the file. `0` if the file is closed.
    /// - Example:
    /// ```js
    /// console.log("At byte " + f.position)
    /// ```
    @objc var position: Int { get }

    /// The current size of the file in bytes. `0` if the file is closed.
    /// - Example:
    /// ```js
    /// console.log("File is " + f.size + " bytes")
    /// ```
    @objc var size: Int { get }

    /// Whether the current position is at (or beyond) the end of the file.
    /// - Example:
    /// ```js
    /// while (!f.atEnd) console.log(f.readLine())
    /// ```
    @objc var atEnd: Bool { get }

    /// {{code: string, message: string} | null} The error from the most recent failed operation on this file, or `null` if no operation has failed.
    ///
    /// The object has a `code` (a POSIX error name such as `"ENOENT"`, `"EACCES"`, `"EAGAIN"`, or `"EILSEQ"`
    /// for invalid UTF-8) and a human-readable `message`. It is not cleared by successful operations.
    /// - Example:
    /// ```js
    /// if (!f.lock()) console.log("Lock failed: " + f.lastError.code)
    /// ```
    @objc var lastError: JSValue? { get }

    // MARK: - Reading

    /// Read UTF-8 text from the current position.
    ///
    /// When `byteCount` is given, at most that many bytes are read. If that would split a multi-byte
    /// UTF-8 character, reading stops before the character so it is returned whole by the next read.
    ///
    /// If the data is not valid UTF-8, `null` is returned, the position is left unchanged, and
    /// `lastError.code` is `"EILSEQ"`. Use `readBytes()` for binary data.
    ///
    /// Like Lua's `f:read("a")`, reading to the end of the file never signals end of file: at the end it
    /// returns `""`. Only a read with a `byteCount` returns `null` at end of file, so loop on `read(n)`.
    ///
    /// - Parameter byteCount?: Maximum number of bytes to read. Omit (or pass `0`) to read to the end of the file.
    /// - Returns: {string | null} The text read; `""` when reading to the end of the file from its end; `null` for a `byteCount` read at end of file, or on error.
    /// - Example:
    /// ```js
    /// const everything = f.read()
    /// const first100 = f.read(100)
    /// ```
    @objc func read(_ byteCount: Int) -> JSValue?

    /// Read the next line of UTF-8 text.
    ///
    /// Both `\n` and `\r\n` line endings are recognised. A final line with no trailing newline is still returned.
    ///
    /// - Parameter keepNewline?: Pass `true` to keep the line ending in the returned string. Defaults to `false`.
    /// - Returns: {string | null} The line, or `null` at end of file or on error.
    /// - Example:
    /// ```js
    /// let line
    /// while ((line = f.readLine()) !== null) {
    ///     console.log(line)
    /// }
    /// ```
    @objc func readLine(_ keepNewline: Bool) -> JSValue?

    /// Call a function for each remaining line of the file.
    ///
    /// Line endings are stripped. The callback may return `false` to stop early, leaving the position
    /// immediately after the last line delivered. If the callback throws, iteration stops and the
    /// exception propagates to the caller.
    ///
    /// The callback may use this file: if it moves the position or changes the file's contents, iteration
    /// continues from the current position with the file as it now is. If it closes the file, iteration
    /// stops and `eachLine` returns `false` with `lastError.code === "EBADF"`.
    ///
    /// - Parameter callback: {(line: string) => boolean | void} Called once per line. Return `false` to stop.
    /// - Returns: `true` if iteration completed or was stopped by the callback returning `false`; `false` on error, if the callback threw, or if the file was closed during iteration.
    /// - Example:
    /// ```js
    /// f.eachLine(line => {
    ///     if (line.startsWith("#")) return
    ///     console.log(line)
    /// })
    /// ```
    @objc func eachLine(_ callback: JSFunction) -> Bool

    /// Read all remaining lines of the file into an array.
    ///
    /// Line endings are stripped. On error the position is left unchanged.
    ///
    /// - Returns: {string[] | null} An array of lines (empty at end of file), or `null` on error.
    /// - Example:
    /// ```js
    /// const lines = f.readLines()
    /// console.log(lines.length + " lines")
    /// ```
    @objc func readLines() -> JSValue?

    /// Read raw bytes from the current position.
    ///
    /// As with `read()`, reading to the end of the file returns an empty `Uint8Array` at the end, while a
    /// read with a `byteCount` returns `null` at end of file.
    ///
    /// - Parameter byteCount?: Maximum number of bytes to read. Omit (or pass `0`) to read to the end of the file.
    /// - Returns: {Uint8Array | null} The bytes read; empty when reading to the end of the file from its end; `null` for a `byteCount` read at end of file, or on error.
    /// - Example:
    /// ```js
    /// const magic = f.readBytes(8)
    /// if (magic && magic[0] === 0x89 && magic[1] === 0x50) console.log("PNG file")
    /// ```
    @objc func readBytes(_ byteCount: Int) -> JSValue?

    // MARK: - Writing

    /// Write a string to the file as UTF-8 at the current position (or at the end, for files opened in `"a"`/`"a+"` mode).
    ///
    /// - Parameter text: The text to write.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.write("Hello, ")
    /// f.write("world!\n")
    /// ```
    @objc func write(_ text: String) -> Bool

    /// Write a string followed by a newline (`\n`).
    ///
    /// - Parameter text: The text to write.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.writeLine("one")
    /// f.writeLine("two")
    /// ```
    @objc func writeLine(_ text: String) -> Bool

    /// Write raw bytes to the file.
    ///
    /// - Parameter bytes: {Uint8Array | ArrayBuffer} The bytes to write. Any typed array is accepted; its underlying bytes are written as-is.
    /// - Returns: `true` on success, `false` on failure (including if `bytes` is not a typed array or `ArrayBuffer`).
    /// - Example:
    /// ```js
    /// f.writeBytes(new Uint8Array([0xDE, 0xAD, 0xBE, 0xEF]))
    /// ```
    @objc func writeBytes(_ bytes: JSValue) -> Bool

    /// Force any written data out to stable storage (`fsync`).
    ///
    /// Writes are not buffered by `HSFile`, so other processes see them immediately; `flush()` additionally
    /// guarantees they survive a crash or power loss.
    ///
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.write(importantData)
    /// f.flush()
    /// ```
    @objc func flush() -> Bool

    /// Truncate (or extend with zero bytes) the file to the given length. The position is not changed.
    ///
    /// - Parameter length?: The new length in bytes. Omit (or pass `0`) to empty the file.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.truncate()        // empty the file
    /// f.truncate(1024)    // make it exactly 1KB
    /// ```
    @objc func truncate(_ length: Int) -> Bool

    // MARK: - Positioning

    /// Move the current position.
    ///
    /// Unlike Lua's `f:seek()`, the offset is required: to find the current position or the size of the
    /// file without moving, use the `position` and `size` properties.
    ///
    /// - Parameters:
    ///   - offset: The byte offset (an integer), relative to `whence`. May be negative for `"cur"` and `"end"`.
    ///   - whence?: {"set" | "cur" | "end"} `"set"` (from the start of the file), `"cur"` (from the current position), or `"end"` (from the end of the file). Defaults to `"set"`.
    /// - Returns: {number | null} The new position, or `null` on failure (including `EINVAL` if `offset` is missing or not an integer).
    /// - Example:
    /// ```js
    /// f.seek(0, "end")       // jump to the end
    /// f.seek(-10, "cur")     // back 10 bytes
    /// const pos = f.seek(0, "cur")
    /// ```
    @objc func seek(_ offset: Double, _ whence: String) -> JSValue?

    /// Move the current position back to the start of the file.
    ///
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.write("data")
    /// f.rewind()
    /// console.log(f.read())
    /// ```
    @objc func rewind() -> Bool

    // MARK: - Path operations

    /// Rename (move) the file on disk. The file stays open and `path` is updated.
    ///
    /// Both paths must be on the same volume. By default this fails if `newPath` already exists.
    /// While the file is open, this fails with `"ESTALE"` if `path` no longer refers to it (for example
    /// because another process moved it and put something else in its place), rather than acting on
    /// the wrong file. Once the file is closed, it acts on whatever is at `path`.
    ///
    /// - Parameters:
    ///   - newPath: The new path. `~` is expanded.
    ///   - overwrite?: Pass `true` to atomically replace any existing file at `newPath`. Defaults to `false`.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// // Atomically replace a file with new contents
    /// const tmp = hs.fs.tempFile()
    /// tmp.write(newContents)
    /// tmp.flush()
    /// tmp.rename("~/.myconfig", true)
    /// tmp.close()
    /// ```
    @objc func rename(_ newPath: String, _ overwrite: Bool) -> Bool

    /// Copy the file on disk to a new path, including its metadata. The original stays open.
    ///
    /// Fails if `destination` already exists, if the file has been removed, or (while the file is open)
    /// with `"ESTALE"` if `path` no longer refers to it.
    ///
    /// - Parameter destination: The path for the copy. `~` is expanded.
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.duplicate("~/notes-backup.txt")
    /// ```
    @objc func duplicate(_ destination: String) -> Bool

    /// Remove the file from disk.
    ///
    /// The file stays open: you can keep reading and writing it until `close()`, after which its storage is freed.
    /// While the file is open, this fails with `"ESTALE"` if `path` no longer refers to it, so a file that
    /// has since replaced it is never removed by mistake.
    ///
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// const scratch = hs.fs.tempFile()
    /// scratch.remove()   // invisible to other processes from now on
    /// scratch.write("private data")
    /// ```
    @objc func remove() -> Bool

    /// Get metadata for the open file.
    ///
    /// Returns the same object as `hs.fs.attributes()`, but reads it from the open file itself, so it
    /// remains accurate after the file has been renamed or removed.
    ///
    /// - Returns: {Record<string, any> | null} Attributes object, or `null` on failure.
    /// - Example:
    /// ```js
    /// console.log(f.attributes().modificationDate)
    /// ```
    @objc func attributes() -> JSValue?

    /// Set the POSIX permission bits of the file.
    ///
    /// - Parameter permissions: The permission bits, as an integer between `0` and `0o7777`, e.g. `0o600`. Use an octal literal: decimal `600` is a different (and unusual) mode.
    /// - Returns: `true` on success, `false` on failure (including `EINVAL` if `permissions` is missing or out of range).
    /// - Example:
    /// ```js
    /// f.setPermissions(0o600)
    /// ```
    @objc func setPermissions(_ permissions: Double) -> Bool

    /// Set the access and modification times of the file.
    ///
    /// The argument order matches `hs.fs.touch()` and Hammerspoon v1: access time first.
    ///
    /// - Parameters:
    ///   - accessDate?: Seconds since the Unix epoch (fractions allowed). Defaults to now.
    ///   - modificationDate?: Seconds since the Unix epoch (fractions allowed). Defaults to `accessDate`.
    /// - Returns: `true` on success, `false` on failure (including `EINVAL` for a `NaN`, infinite, or out-of-range timestamp).
    /// - Example:
    /// ```js
    /// f.touch()                          // now
    /// f.touch(Date.now() / 1000 - 3600)  // both times one hour ago
    /// ```
    @objc func touch(_ accessDate: Double, _ modificationDate: Double) -> Bool

    // MARK: - Locking

    /// Take an advisory lock on the file (`flock`).
    ///
    /// Advisory locks only affect other processes that also use locking; they do not prevent reads or writes.
    /// Locks are released by `unlock()` or when the file is closed.
    ///
    /// - Parameters:
    ///   - shared?: Pass `true` for a shared (read) lock, which several processes may hold at once. Defaults to `false` (an exclusive lock).
    ///   - wait?: Pass `true` to wait until the lock is available. **This blocks Hammerspoon until the lock is acquired.** Defaults to `false`, which fails immediately with `lastError.code === "EAGAIN"` if the lock is held elsewhere.
    /// - Returns: `true` if the lock was acquired, `false` otherwise.
    /// - Example:
    /// ```js
    /// const lockFile = hs.fs.open("~/.myscript.lock", "w")
    /// if (!lockFile.lock()) console.log("Another instance is running")
    /// ```
    @objc func lock(_ shared: Bool, _ wait: Bool) -> Bool

    /// Release a lock taken with `lock()`.
    ///
    /// - Returns: `true` on success, `false` on failure.
    /// - Example:
    /// ```js
    /// f.unlock()
    /// ```
    @objc func unlock() -> Bool

    // MARK: - Lifecycle

    /// Close the file. Calling `close()` on a file that is already closed does nothing.
    ///
    /// - Returns: `true` on success (or if the file was already closed), `false` on failure.
    /// - Example:
    /// ```js
    /// f.close()
    /// ```
    @objc func close() -> Bool
}

// MARK: - Implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSFile: NSObject, HSFileAPI {
    @objc var typeName = "HSFile"
    @objc private(set) var path: String
    @objc let mode: String
    /// The `{code, message}` of the most recent failure, exposed to JS as `lastError`.
    private(set) var lastErrorInfo: [String: Any]?

    // A JSValue so that "no error" is a real JS null (JSExport bridges nil to undefined).
    @objc var lastError: JSValue? { HSFSSupport.jsValueOrNull(lastErrorInfo) }

    /// The open file descriptor, or -1 once closed.
    private var fd: Int32

    /// Incremented by every write or truncate through this handle, so `eachLine` can tell that a
    /// callback changed the file even if its size and modification time happen not to.
    private var writeGeneration = 0

    /// Size of each chunk read while scanning for line endings or reading to end of file.
    private static let chunkSize = 65_536

    init(fd: Int32, path: String, mode: String) {
        self.fd = fd
        // Prefer the kernel's view of the path: it is absolute and has symlinks resolved, so it keeps
        // naming this file even if the process's working directory changes.
        self.path = Self.kernelPath(of: fd) ?? path
        self.mode = mode
        super.init()
        AKGarbage("Init of \(typeName): \(path)")
    }

    isolated deinit {
        destroy()
        AKGarbage("Deinit of \(typeName): \(path)")
    }

    /// Release the file descriptor. Called by `close()`, `deinit`, and `HSFSModule.shutdown()`.
    func destroy() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }

    @objc func toString() -> String {
        "<\(typeName): \(path), \(mode), \(isOpen ? "open" : "closed")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Opening

    /// The `open(2)` flags for an fopen-style mode string, or `nil` if the mode is invalid.
    ///
    /// Valid modes are `r`, `w`, or `a`, optionally followed by `+` (read and write), `x` (fail if the
    /// file exists; `w` modes only), and `b` (ignored), in any order, each at most once.
    static func openFlags(forMode mode: String) -> Int32? {
        guard let base = mode.first, "rwa".contains(base) else { return nil }
        let modifiers = mode.dropFirst()
        guard modifiers.allSatisfy({ "+xb".contains($0) }),
              Set(modifiers).count == modifiers.count else { return nil }

        let plus = modifiers.contains("+")
        let exclusive = modifiers.contains("x")
        if exclusive && base != "w" { return nil }

        var flags: Int32 = O_CLOEXEC
        switch base {
        case "r": flags |= plus ? O_RDWR : O_RDONLY
        case "w": flags |= (plus ? O_RDWR : O_WRONLY) | O_CREAT | O_TRUNC
        default:  flags |= (plus ? O_RDWR : O_WRONLY) | O_CREAT | O_APPEND
        }
        if exclusive { flags |= O_EXCL }
        return flags
    }

    // MARK: - Properties

    @objc var isOpen: Bool { fd >= 0 }

    @objc var position: Int {
        guard fd >= 0 else { return 0 }
        return max(0, Int(lseek(fd, 0, SEEK_CUR)))
    }

    @objc var size: Int {
        guard fd >= 0 else { return 0 }
        var st = Darwin.stat()
        guard unsafe fstat(fd, &st) == 0 else { return 0 }
        return Int(st.st_size)
    }

    @objc var atEnd: Bool {
        guard fd >= 0 else { return true }
        return position >= size
    }

    // MARK: - Error helpers

    private func fail(errno code: Int32, _ function: String) {
        lastErrorInfo = HSFSSupport.errorInfo(errno: code)
        AKError("HSFile.\(function): \(path): \(lastErrorInfo?["message"] ?? "")")
    }

    private func fail(code: String, message: String, _ function: String) {
        lastErrorInfo = HSFSSupport.errorInfo(code: code, message: message)
        AKError("HSFile.\(function): \(path): \(message)")
    }

    /// Returns `true` if the file is open, otherwise records an `EBADF` error.
    private func requireOpen(_ function: String) -> Bool {
        guard fd < 0 else { return true }
        fail(code: "EBADF", message: "File is closed", function)
        return false
    }

    // MARK: - Path identity

    /// The path the kernel currently has for an open file descriptor (absolute, symlinks resolved).
    private static func kernelPath(of fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBytes { unsafe fcntl(fd, F_GETPATH, $0.baseAddress!) }
        guard result != -1 else { return nil }
        return buffer.withUnsafeBufferPointer { unsafe String(validatingCString: $0.baseAddress!) }
    }

    /// While the file is open, check that `path` still names this file (same device and inode) before
    /// a path-based operation, so a file that has replaced it at that path is never acted on by mistake.
    /// Closed files skip the check: their path operations act on whatever is at `path`.
    private func requirePathIdentity(_ function: String) -> Bool {
        guard fd >= 0 else { return true }
        var open = Darwin.stat()
        var onDisk = Darwin.stat()
        guard unsafe fstat(fd, &open) == 0 else {
            fail(errno: errno, function)
            return false
        }
        guard unsafe lstat(path, &onDisk) == 0 else {
            fail(errno: errno, function)
            return false
        }
        guard open.st_dev == onDisk.st_dev, open.st_ino == onDisk.st_ino else {
            fail(code: "ESTALE", message: "Path no longer refers to this open file", function)
            return false
        }
        return true
    }

    // MARK: - Low-level I/O

    /// Read up to `count` bytes from the current position (or to end of file if `count` is `nil`).
    /// Returns `nil` on error, with `lastError` set.
    private func readRaw(_ count: Int?, _ function: String) -> [UInt8]? {
        var result: [UInt8] = []
        while count.map({ result.count < $0 }) ?? true {
            let want = min(count.map { $0 - result.count } ?? Self.chunkSize, Self.chunkSize)
            var chunk = [UInt8](repeating: 0, count: want)
            let n = chunk.withUnsafeMutableBytes { unsafe Darwin.read(fd, $0.baseAddress, want) }
            if n < 0 {
                if errno == EINTR { continue }
                fail(errno: errno, function)
                return nil
            }
            if n == 0 { break }
            result.append(contentsOf: chunk[..<n])
        }
        return result
    }

    /// Read up to `count` bytes at `offset` without moving the file position.
    private func preadRaw(_ count: Int, at offset: Int, _ function: String) -> [UInt8]? {
        var chunk = [UInt8](repeating: 0, count: count)
        while true {
            let n = chunk.withUnsafeMutableBytes { unsafe pread(fd, $0.baseAddress, count, off_t(offset)) }
            if n < 0 {
                if errno == EINTR { continue }
                fail(errno: errno, function)
                return nil
            }
            return Array(chunk[..<n])
        }
    }

    private func writeRaw(_ bytes: [UInt8], _ function: String) -> Bool {
        guard requireOpen(function) else { return false }
        writeGeneration += 1
        var written = 0
        while written < bytes.count {
            let n = bytes.withUnsafeBytes { buffer in
                unsafe Darwin.write(fd, buffer.baseAddress?.advanced(by: written), bytes.count - written)
            }
            if n < 0 {
                if errno == EINTR { continue }
                fail(errno: errno, function)
                return false
            }
            written += n
        }
        return true
    }

    @discardableResult
    private func moveTo(_ offset: Int) -> Bool {
        lseek(fd, off_t(offset), SEEK_SET) >= 0
    }

    /// If `bytes` ends part-way through a multi-byte UTF-8 sequence, returns how many trailing bytes
    /// belong to that incomplete sequence and how long the complete sequence would be.
    private static func incompleteUTF8Tail(_ bytes: [UInt8]) -> (present: Int, needed: Int)? {
        for present in 1...min(3, bytes.count) {
            let byte = bytes[bytes.count - present]
            if byte & 0xC0 == 0x80 { continue }   // continuation byte; keep looking for the lead
            guard byte >= 0xC0 else { return nil } // ASCII: the tail is complete
            let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : 2
            return needed > present ? (present, needed) : nil
        }
        return nil
    }

    /// Decode UTF-8, recording an `EILSEQ` error if the bytes are invalid. Callers are responsible
    /// for restoring the file position on failure.
    private func decodeUTF8(_ bytes: some Collection<UInt8>, _ function: String) -> String? {
        if let text = String(validating: bytes, as: UTF8.self) {
            return text
        }
        fail(code: "EILSEQ", message: "Data is not valid UTF-8 text", function)
        return nil
    }

    /// A snapshot used to detect an `eachLine` callback changing the file's contents.
    private struct ContentStamp: Equatable {
        var generation: Int
        var size: off_t
        var modifiedSeconds: Int
        var modifiedNanoseconds: Int
    }

    private func contentStamp() -> ContentStamp? {
        var st = Darwin.stat()
        guard fd >= 0, unsafe fstat(fd, &st) == 0 else { return nil }
        return ContentStamp(generation: writeGeneration, size: st.st_size,
                            modifiedSeconds: st.st_mtimespec.tv_sec,
                            modifiedNanoseconds: st.st_mtimespec.tv_nsec)
    }

    /// Scan lines from the current position, calling `handler` with each line's bytes (including its
    /// `\n`, if any) until it returns `false` or the end of the file is reached. Read-ahead uses `pread`,
    /// so the file position is only ever moved to a line boundary.
    ///
    /// When `runsUserCode` is `true` (for `eachLine`), the handler may use this file: the position is set
    /// to just after each line before the handler runs, and afterwards any read-ahead is discarded if the
    /// handler moved the position or changed the file's contents. If the handler closes the file, the scan
    /// fails with `EBADF`. When `false`, the position is only updated once the scan finishes.
    ///
    /// When the handler returns `false`, the position is left just after the line it was given (callers
    /// may move it afterwards). Returns `false` on a read error or if the file was closed by the handler.
    private func scanLines(_ function: String, runsUserCode: Bool,
                           _ handler: (ArraySlice<UInt8>) -> Bool) -> Bool {
        var base = position     // file offset of buffer[0]
        var buffer: [UInt8] = []
        var start = 0           // index of the first unconsumed byte in buffer
        var searchFrom = 0      // index from which to look for the next newline
        var reachedEOF = false
        var stamp = runsUserCode ? contentStamp() : nil

        while true {
            let newline = buffer[searchFrom...].firstIndex(of: 0x0A)
            if newline == nil && !reachedEOF {
                // Discard consumed bytes, then read the next chunk without moving the file position.
                buffer.removeFirst(start)
                base += start
                start = 0
                searchFrom = buffer.count
                guard let chunk = preadRaw(Self.chunkSize, at: base + buffer.count, function) else {
                    moveTo(base)
                    return false
                }
                if chunk.isEmpty {
                    reachedEOF = true
                } else {
                    buffer.append(contentsOf: chunk)
                }
                continue
            }

            // Either a complete line, or the unterminated remainder of the file.
            let end = newline.map { $0 + 1 } ?? buffer.count
            guard start < end else {
                moveTo(base + start)
                return true
            }
            let line = buffer[start..<end]
            start = end
            searchFrom = end
            let consumed = base + start

            guard runsUserCode else {
                guard handler(line) else {
                    moveTo(consumed)
                    return true
                }
                continue
            }

            moveTo(consumed)
            guard handler(line) else { return true }
            guard fd >= 0 else {
                fail(code: "EBADF", message: "File was closed during \(function)", function)
                return false
            }
            let now = position
            let newStamp = contentStamp()
            if now != consumed || newStamp != stamp {
                // The handler moved the position or changed the file, so the read-ahead may be stale.
                base = now
                buffer = []
                start = 0
                searchFrom = 0
                reachedEOF = false
                stamp = newStamp
            }
        }
    }

    /// Strip a trailing `\n` or `\r\n` from a line.
    private static func strippingNewline(_ line: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var line = line
        if line.last == 0x0A {
            line.removeLast()
            if line.last == 0x0D { line.removeLast() }
        }
        return line
    }

    // MARK: - Reading

    // Methods documented as returning `null` return a JSValue built by HSFSSupport.jsValueOrNull,
    // because JSExport bridges `nil` to `undefined` — which would, for example, make the natural loop
    // `while ((line = f.readLine()) !== null)` spin forever at end of file.

    @objc func read(_ byteCount: Int = 0) -> JSValue? {
        HSFSSupport.jsValueOrNull(readText(byteCount))
    }

    private func readText(_ byteCount: Int) -> String? {
        guard requireOpen("read") else { return nil }
        let start = position
        let limit = byteCount > 0 ? byteCount : nil
        guard var bytes = readRaw(limit, "read") else { return nil }
        // Reading the rest of the file never signals end of file (like Lua's read("a")).
        if bytes.isEmpty { return limit == nil ? "" : nil }

        if limit != nil, let tail = Self.incompleteUTF8Tail(bytes) {
            if tail.present < bytes.count {
                // Stop before the split character; it will be returned by the next read.
                bytes.removeLast(tail.present)
                moveTo(start + bytes.count)
            } else if let rest = readRaw(tail.needed - tail.present, "read") {
                // The request was too small to hold even one whole character, so complete it instead.
                bytes.append(contentsOf: rest)
            }
        }
        guard let text = decodeUTF8(bytes, "read") else {
            moveTo(start)
            return nil
        }
        return text
    }

    @objc func readLine(_ keepNewline: Bool = false) -> JSValue? {
        HSFSSupport.jsValueOrNull(readLineText(keepNewline))
    }

    private func readLineText(_ keepNewline: Bool) -> String? {
        guard requireOpen("readLine") else { return nil }
        let start = position
        var result: String?
        var decoded = true
        let ok = scanLines("readLine", runsUserCode: false) { line in
            result = decodeUTF8(keepNewline ? line : Self.strippingNewline(line), "readLine")
            decoded = result != nil
            return false
        }
        if !decoded { moveTo(start) }
        return ok ? result : nil
    }

    @objc func eachLine(_ callback: JSFunction) -> Bool {
        guard requireOpen("eachLine") else { return false }
        guard let context = JSContext.current() else { return false }
        var succeeded = true
        let ok = scanLines("eachLine", runsUserCode: true) { line in
            guard let text = decodeUTF8(Self.strippingNewline(line), "eachLine") else {
                // Leave the position at the start of the undecodable line.
                moveTo(position - line.count)
                succeeded = false
                return false
            }
            context.exception = nil
            let result = context.callCapturingException { callback.call(withArguments: [text]) }
            if context.exception != nil {
                succeeded = false
                return false
            }
            if let result, result.isBoolean { return result.toBool() }
            return true
        }
        return ok && succeeded
    }

    @objc func readLines() -> JSValue? {
        HSFSSupport.jsValueOrNull(readAllLines())
    }

    private func readAllLines() -> [String]? {
        guard requireOpen("readLines") else { return nil }
        let start = position
        var lines: [String] = []
        var succeeded = true
        let ok = scanLines("readLines", runsUserCode: false) { line in
            guard let text = decodeUTF8(Self.strippingNewline(line), "readLines") else {
                succeeded = false
                return false
            }
            lines.append(text)
            return true
        }
        guard ok, succeeded else {
            moveTo(start)
            return nil
        }
        return lines
    }

    @objc func readBytes(_ byteCount: Int = 0) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let null = JSValue(nullIn: context)
        guard requireOpen("readBytes") else { return null }
        guard let bytes = readRaw(byteCount > 0 ? byteCount : nil, "readBytes") else { return null }
        if bytes.isEmpty && byteCount > 0 { return null }
        guard let array = context.makeUint8Array(bytes) else {
            fail(code: "ENOMEM", message: "Could not allocate a Uint8Array", "readBytes")
            return null
        }
        return array
    }

    // MARK: - Writing

    @objc func write(_ text: String) -> Bool {
        writeRaw(Array(text.utf8), "write")
    }

    @objc func writeLine(_ text: String) -> Bool {
        writeRaw(Array((text + "\n").utf8), "writeLine")
    }

    @objc func writeBytes(_ bytes: JSValue) -> Bool {
        guard let data = bytes.typedArrayBytes else {
            fail(code: "EINVAL", message: "writeBytes() requires a Uint8Array, typed array, or ArrayBuffer", "writeBytes")
            return false
        }
        return writeRaw(data, "writeBytes")
    }

    @objc func flush() -> Bool {
        guard requireOpen("flush") else { return false }
        guard fsync(fd) == 0 else {
            fail(errno: errno, "flush")
            return false
        }
        return true
    }

    @objc func truncate(_ length: Int = 0) -> Bool {
        guard requireOpen("truncate") else { return false }
        guard length >= 0 else {
            fail(code: "EINVAL", message: "Length must not be negative", "truncate")
            return false
        }
        writeGeneration += 1
        guard ftruncate(fd, off_t(length)) == 0 else {
            fail(errno: errno, "truncate")
            return false
        }
        return true
    }

    // MARK: - Positioning

    // `offset` is a Double so that an omitted offset (NaN) is rejected rather than becoming 0. Lua's
    // `f:seek()` and `f:seek("end")` report the position/size; silently rewinding would break ports.
    @objc func seek(_ offset: Double, _ whence: String = "set") -> JSValue? {
        guard requireOpen("seek") else { return HSFSSupport.jsValueOrNull(nil) }
        guard let requested = HSFSSupport.optionalNumberArgument(offset, at: 0),
              let byteOffset = Int(exactly: requested) else {
            fail(code: "EINVAL",
                 message: "seek() requires an integer offset; use the position and size properties to read them",
                 "seek")
            return HSFSSupport.jsValueOrNull(nil)
        }
        return HSFSSupport.jsValueOrNull(seek(to: byteOffset, whence: whence))
    }

    private func seek(to offset: Int, whence: String) -> NSNumber? {
        let origin: Int32
        switch whence {
        case "set", "", "undefined": origin = SEEK_SET
        case "cur":                  origin = SEEK_CUR
        case "end":                  origin = SEEK_END
        default:
            fail(code: "EINVAL", message: "whence must be \"set\", \"cur\", or \"end\" (got \"\(whence)\")", "seek")
            return nil
        }
        let result = lseek(fd, off_t(offset), origin)
        guard result >= 0 else {
            fail(errno: errno, "seek")
            return nil
        }
        return NSNumber(value: Int(result))
    }

    @objc func rewind() -> Bool {
        guard requireOpen("rewind") else { return false }
        return seek(to: 0, whence: "set") != nil
    }

    // MARK: - Path operations

    @objc func rename(_ newPath: String, _ overwrite: Bool = false) -> Bool {
        guard requirePathIdentity("rename") else { return false }
        let destination = (newPath as NSString).expandingTildeInPath
        let flags: UInt32 = overwrite ? 0 : UInt32(RENAME_EXCL)
        guard unsafe renamex_np(path, destination, flags) == 0 else {
            fail(errno: errno, "rename")
            return false
        }
        path = (fd >= 0 ? Self.kernelPath(of: fd) : nil) ?? destination
        return true
    }

    @objc func duplicate(_ destination: String) -> Bool {
        guard requirePathIdentity("duplicate") else { return false }
        let target = (destination as NSString).expandingTildeInPath
        guard unsafe copyfile(path, target, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)) == 0 else {
            fail(errno: errno, "duplicate")
            return false
        }
        return true
    }

    @objc func remove() -> Bool {
        guard requirePathIdentity("remove") else { return false }
        guard unsafe unlink(path) == 0 else {
            fail(errno: errno, "remove")
            return false
        }
        return true
    }

    @objc func attributes() -> JSValue? {
        HSFSSupport.jsValueOrNull(fileAttributes())
    }

    private func fileAttributes() -> [String: Any]? {
        guard requireOpen("attributes") else { return nil }
        var st = Darwin.stat()
        guard unsafe fstat(fd, &st) == 0 else {
            fail(errno: errno, "attributes")
            return nil
        }
        return HSFSSupport.attributes(from: st)
    }

    @objc func setPermissions(_ permissions: Double) -> Bool {
        guard requireOpen("setPermissions") else { return false }
        guard let bits = HSFSSupport.permissionBits(permissions, function: "HSFile.setPermissions") else {
            fail(code: "EINVAL", message: "Permissions must be an integer between 0 and 0o7777", "setPermissions")
            return false
        }
        guard fchmod(fd, bits) == 0 else {
            fail(errno: errno, "setPermissions")
            return false
        }
        return true
    }

    @objc func touch(_ accessDate: Double = .nan, _ modificationDate: Double = .nan) -> Bool {
        guard requireOpen("touch") else { return false }
        guard let times = HSFSSupport.touchTimes(
            accessDate: HSFSSupport.optionalNumberArgument(accessDate, at: 0),
            modificationDate: HSFSSupport.optionalNumberArgument(modificationDate, at: 1)
        ) else {
            fail(code: "EINVAL", message: "Timestamps must be finite numbers of seconds since the Unix epoch", "touch")
            return false
        }
        guard unsafe futimens(fd, times) == 0 else {
            fail(errno: errno, "touch")
            return false
        }
        return true
    }

    // MARK: - Locking

    @objc func lock(_ shared: Bool = false, _ wait: Bool = false) -> Bool {
        guard requireOpen("lock") else { return false }
        let operation = (shared ? LOCK_SH : LOCK_EX) | (wait ? 0 : LOCK_NB)
        while flock(fd, operation) != 0 {
            if errno == EINTR { continue }
            if errno == EWOULDBLOCK {
                // Lock contention is an expected outcome, not an error worth logging.
                lastErrorInfo = HSFSSupport.errorInfo(errno: errno)
                AKDebug("HSFile.lock: \(path) is locked by another process")
            } else {
                fail(errno: errno, "lock")
            }
            return false
        }
        return true
    }

    @objc func unlock() -> Bool {
        guard requireOpen("unlock") else { return false }
        guard flock(fd, LOCK_UN) == 0 else {
            fail(errno: errno, "unlock")
            return false
        }
        return true
    }

    // MARK: - Lifecycle

    @objc func close() -> Bool {
        guard fd >= 0 else { return true }
        let result = Darwin.close(fd)
        fd = -1
        guard result == 0 else {
            fail(errno: errno, "close")
            return false
        }
        return true
    }
}
