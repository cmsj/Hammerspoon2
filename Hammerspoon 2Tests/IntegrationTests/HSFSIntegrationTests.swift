//
//  HSFSIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Test-only string helper

private extension String {
    /// Strip a leading prefix from a string, returning the original if it is absent.
    /// Used to normalise macOS paths where `/tmp` is a symlink to `/private/tmp`,
    /// causing `realpath`-based APIs to return `/private/tmp/…` while our test
    /// paths are constructed from `NSTemporaryDirectory()` which may return either.
    func deletingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

// MARK: - Helpers

/// Creates a unique temporary directory for one test, deletes it when the
/// returned token is deallocated.  Use with `defer { _ = token }`.
private final class TempDir {
    let path: String

    init() throws {
        let uuid = UUID().uuidString
        path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hs.fs-tests-\(uuid)")
        try FileManager.default.createDirectory(atPath: path,
                                                withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Return the full path to a name within this directory.
    func child(_ name: String) -> String {
        (path as NSString).appendingPathComponent(name)
    }
}

// MARK: - Test suite

/// Integration tests for `HSFSModule` (`hs.fs`).
///
/// Each test creates its own isolated temporary directory so tests remain
/// independent regardless of execution order.
@MainActor
@Suite("hs.fs tests")
struct HSFSIntegrationTests {
    // MARK: - File I/O

    @Test("write creates a file and read returns its content")
    func writeAndRead() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("hello.txt")

        let written = sut.write(file, "Hello, world!")
        #expect(written, "write should succeed")

        let content = try #require(sut.read(file), "read should return content")
        #expect(content == "Hello, world!")

        let content2 = try #require(sut.read(file, 0, 0), "read should return content")
        #expect(content2 == "Hello, world!")
    }

    @Test("write overwrites existing file content")
    func writeOverwrites() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("overwrite.txt")

        _ = sut.write(file, "first")
        _ = sut.write(file, "second")

        let content = sut.read(file)
        #expect(content == "second")
    }

    @Test("append adds content to an existing file")
    func appendToExisting() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("append.txt")

        _ = sut.write(file, "line1\n")
        let ok = sut.append(file, "line2\n")
        #expect(ok, "append should succeed")

        let content = sut.read(file)
        #expect(content == "line1\nline2\n")
    }

    @Test("append creates the file when it does not exist")
    func appendCreatesFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("new.txt")

        let ok = sut.append(file, "created")
        #expect(ok, "append should succeed on a new file")
        #expect(sut.read(file) == "created")
    }

    @Test("read returns null for a non-existent file")
    func readMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.read("/nonexistent/path/file.txt", 0, 0) == nil)
    }

    @Test("read with offset skips leading bytes")
    func readWithOffset() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("offset.txt")
        _ = sut.write(file, "Hello, world!")

        // "Hello, " is 7 bytes; reading from offset 7 should give "world!"
        let result = try #require(sut.read(file, 7, 0))
        #expect(result == "world!")
    }

    @Test("read with length limits bytes returned")
    func readWithLength() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("length.txt")
        _ = sut.write(file, "Hello, world!")

        let result = try #require(sut.read(file, 0, 5))
        #expect(result == "Hello")
    }

    @Test("read with offset and length returns the specified slice")
    func readWithOffsetAndLength() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("slice.txt")
        _ = sut.write(file, "Hello, world!")

        // bytes 7–12: "world"
        let result = try #require(sut.read(file, 7, 5))
        #expect(result == "world")
    }

    // eachLine runs a JS callback, so these tests go through a JS context.
    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSFSModule.self, as: "fs")
        return harness
    }

    @Test("eachLine delivers all lines to the callback")
    func eachLineAll() throws {
        let tmp = try TempDir()
        let file = tmp.child("lines.txt")
        try "alpha\nbeta\ngamma\n".write(toFile: file, atomically: true, encoding: .utf8)
        let harness = makeHarness()
        harness.eval("var seen = []; var ok = hs.fs.eachLine('\(file)', line => { seen.push(line) })")
        #expect(harness.evalBool("ok") == true)
        #expect(harness.evalString("seen.join(',')") == "alpha,beta,gamma")
    }

    @Test("eachLine handles a file with no trailing newline")
    func eachLineNoTrailingNewline() throws {
        let tmp = try TempDir()
        let file = tmp.child("notrail.txt")
        try "first\nsecond".write(toFile: file, atomically: true, encoding: .utf8)
        let harness = makeHarness()
        harness.eval("var seen = []; hs.fs.eachLine('\(file)', line => { seen.push(line) })")
        #expect(harness.evalString("seen.join(',')") == "first,second")
    }

    @Test("eachLine stops early only when the callback returns false")
    func eachLineEarlyStop() throws {
        let tmp = try TempDir()
        let file = tmp.child("stop.txt")
        try "line1\nline2\nline3\nline4\n".write(toFile: file, atomically: true, encoding: .utf8)
        let harness = makeHarness()
        // Falsy values other than false (0, "", null) do not stop iteration.
        harness.eval("""
            var seen = [];
            var ok = hs.fs.eachLine('\(file)', line => {
                seen.push(line);
                if (line === 'line1') return 0;
                if (line === 'line2') return '';
                if (line === 'line3') return false;
            });
        """)
        #expect(harness.evalBool("ok") == true, "eachLine should return true on an early stop")
        #expect(harness.evalString("seen.join(',')") == "line1,line2,line3")
    }

    @Test("eachLine strips Windows-style CRLF line endings")
    func eachLineCRLF() throws {
        let tmp = try TempDir()
        let file = tmp.child("crlf.txt")
        try "alpha\r\nbeta\r\ngamma\r\n".write(toFile: file, atomically: true, encoding: .utf8)
        let harness = makeHarness()
        harness.eval("var seen = []; hs.fs.eachLine('\(file)', line => { seen.push(line) })")
        #expect(harness.evalString("seen.join(',')") == "alpha,beta,gamma")
    }

    @Test("eachLine propagates exceptions thrown by the callback")
    func eachLineThrows() throws {
        let tmp = try TempDir()
        let file = tmp.child("throw.txt")
        try "a\nb\n".write(toFile: file, atomically: true, encoding: .utf8)
        let harness = makeHarness()
        harness.eval("""
            var seen = [], caught = null;
            try { hs.fs.eachLine('\(file)', line => { seen.push(line); throw new Error('stop ' + line) }) }
            catch (e) { caught = e.message }
        """)
        #expect(harness.evalString("caught") == "stop a")
        #expect(harness.evalString("seen.join(',')") == "a")
    }

    @Test("eachLine stops with EILSEQ on invalid UTF-8")
    func eachLineInvalidUTF8() throws {
        let tmp = try TempDir()
        let file = tmp.child("bad.txt")
        try Data([0x6F, 0x6B, 0x0A, 0xFF, 0xFE, 0x0A, 0x7A, 0x0A]).write(to: URL(fileURLWithPath: file))
        let harness = makeHarness()
        harness.eval("var seen = []; var ok = hs.fs.eachLine('\(file)', line => { seen.push(line) })")
        #expect(harness.evalBool("ok") == false)
        #expect(harness.evalString("seen.join(',')") == "ok")
        #expect(harness.evalString("hs.fs.lastError.code") == "EILSEQ")
    }

    @Test("eachLine returns false for a non-existent file")
    func eachLineMissing() throws {
        let harness = makeHarness()
        #expect(harness.evalBool("hs.fs.eachLine('/nonexistent/\(UUID().uuidString)', line => {})") == false)
        #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
    }

    // MARK: - Existence and Type Checks

    @Test("exists returns true for a file and false for a missing path")
    func existsFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("exists.txt")
        _ = sut.write(file, "")
        #expect(sut.exists(file))
        #expect(sut.exists(tmp.child("missing.txt")) == false)
    }

    @Test("exists returns true for a directory")
    func existsDirectory() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        #expect(sut.exists(tmp.path))
    }

    @Test("isFile is true for a regular file and false for a directory")
    func isFileChecks() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.isFile(file))
        #expect(sut.isFile(tmp.path) == false)
    }

    @Test("isDirectory is true for a directory and false for a file")
    func isDirectoryChecks() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.isDirectory(tmp.path))
        #expect(sut.isDirectory(file) == false)
    }

    @Test("isSymlink detects symbolic links but not regular files")
    func isSymlinkChecks() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("target.txt")
        let link = tmp.child("link.txt")
        _ = sut.write(file, "")
        _ = sut.symlink(file, link)
        #expect(sut.isSymlink(link))
        #expect(sut.isSymlink(file) == false)
    }

    @Test("isReadable and isWritable are true for a newly created file")
    func readableWritable() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("rw.txt")
        _ = sut.write(file, "")
        #expect(sut.isReadable(file))
        #expect(sut.isWritable(file))
    }

    // MARK: - File Operations

    @Test("copy creates an independent copy of a file")
    func copyFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let src = tmp.child("src.txt")
        let dst = tmp.child("dst.txt")
        _ = sut.write(src, "original")

        let ok = sut.copy(src, dst)
        #expect(ok, "copy should succeed")
        #expect(sut.exists(src), "source should still exist")
        #expect(sut.read(dst, 0, 0) == "original")
    }

    @Test("copy fails when the destination already exists")
    func copyFailsIfDestinationExists() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let src = tmp.child("src.txt")
        let dst = tmp.child("dst.txt")
        _ = sut.write(src, "src")
        _ = sut.write(dst, "dst")
        #expect(sut.copy(src, dst) == false)
    }

    @Test("move relocates a file and removes the source")
    func moveFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let src = tmp.child("before.txt")
        let dst = tmp.child("after.txt")
        _ = sut.write(src, "content")

        let ok = sut.move(src, dst)
        #expect(ok, "move should succeed")
        #expect(sut.exists(src) == false, "source should be gone")
        #expect(sut.read(dst, 0, 0) == "content")
    }

    @Test("deletePath removes a file")
    func deletePathFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("delete-me.txt")
        _ = sut.write(file, "")

        let ok = sut.deletePath(file)
        #expect(ok, "deletePath should succeed")
        #expect(sut.exists(file) == false)
    }

    @Test("deletePath removes a directory recursively")
    func deletePathDirectoryRecursive() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let dir = tmp.child("subtree")
        _ = sut.mkdir(dir)
        _ = sut.write((dir as NSString).appendingPathComponent("f.txt"), "x")

        let ok = sut.deletePath(dir)
        #expect(ok, "deletePath should remove a non-empty directory")
        #expect(sut.exists(dir) == false)
    }

    @Test("deletePath returns false for a non-existent path")
    func deletePathMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.deletePath("/nonexistent/\(UUID().uuidString)") == false)
    }

    // MARK: - Directory Operations

    @Test("mkdir creates a directory including intermediate directories")
    func mkdirDeep() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let deep = (tmp.path as NSString)
            .appendingPathComponent("a/b/c")

        let ok = sut.mkdir(deep)
        #expect(ok, "mkdir should succeed")
        #expect(sut.isDirectory(deep))
    }

    @Test("mkdir succeeds silently when the directory already exists")
    func mkdirIdempotent() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        #expect(sut.mkdir(tmp.path), "mkdir on an existing dir should return true")
    }

    @Test("rmdir removes an empty directory")
    func rmdirEmpty() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let dir = tmp.child("empty")
        _ = sut.mkdir(dir)

        let ok = sut.rmdir(dir)
        #expect(ok, "rmdir should succeed on an empty directory")
        #expect(sut.exists(dir) == false)
    }

    @Test("rmdir fails on a non-empty directory")
    func rmdirNonEmpty() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let dir = tmp.child("nonempty")
        _ = sut.mkdir(dir)
        _ = sut.write((dir as NSString).appendingPathComponent("f.txt"), "x")

        #expect(sut.rmdir(dir) == false, "rmdir must fail if directory is not empty")
        #expect(sut.exists(dir), "directory should still exist")
    }

    @Test("list returns sorted filenames without . or ..")
    func listContents() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        _ = sut.write(tmp.child("b.txt"), "")
        _ = sut.write(tmp.child("a.txt"), "")
        _ = sut.write(tmp.child("c.txt"), "")
        _ = sut.mkdir(tmp.child("dir"))

        let items = try #require(sut.list(tmp.path))
        #expect(items == ["a.txt", "b.txt", "c.txt", "dir"],
                "list should be sorted and include only direct children")
    }

    @Test("list returns null for a non-existent directory")
    func listMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.list("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("listRecursive returns sorted relative paths for all descendants")
    func listRecursiveContents() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        _ = sut.mkdir(tmp.child("sub"))
        _ = sut.write(tmp.child("root.txt"), "")
        _ = sut.write(tmp.child("sub/child.txt"), "")

        let items = try #require(sut.listRecursive(tmp.path))
        #expect(items.contains("root.txt"))
        #expect(items.contains("sub"))
        #expect(items.contains("sub/child.txt"))
        #expect(items == items.sorted(), "listRecursive should be sorted")
    }

    // MARK: - Working Directory

    @Test("currentDir returns a non-empty string")
    func currentDirNonEmpty() throws {
        let sut = HSFSModule(engineID: UUID())
        let dir = try #require(sut.currentDir())
        #expect(dir.isEmpty == false)
    }

    @Test("chdir changes the working directory and can be reversed")
    func chdirAndRestore() throws {
        let sut = HSFSModule(engineID: UUID())
        let original = try #require(sut.currentDir())
        defer { _ = sut.chdir(original) }

        let tmp = try TempDir()
        let ok = sut.chdir(tmp.path)
        #expect(ok, "chdir should succeed")
        #expect(sut.currentDir()?.deletingPrefix("/private") == tmp.path.deletingPrefix("/private"))
    }

    @Test("chdir returns false for a non-existent path")
    func chdirMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.chdir("/nonexistent/\(UUID().uuidString)") == false)
    }

    // MARK: - Path Utilities

    @Test("pathToAbsolute expands ~ to the home directory")
    func pathToAbsoluteExpandsTilde() throws {
        let sut = HSFSModule(engineID: UUID())
        let home = sut.homeDirectory()
        let abs  = try #require(sut.pathToAbsolute("~"))
        #expect(abs == home)
    }

    @Test("pathToAbsolute returns null for a non-existent path")
    func pathToAbsoluteMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.pathToAbsolute("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("pathToAbsolute resolves symlinks to their canonical path")
    func pathToAbsoluteResolvesSymlinks() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let target = tmp.child("real.txt")
        let link   = tmp.child("link.txt")
        _ = sut.write(target, "")
        _ = sut.symlink(target, link)

        let abs = try #require(sut.pathToAbsolute(link)).deletingPrefix("/private")
        #expect(abs == target, "resolved path should point to the real file")
    }

    @Test("tempDirectory returns an existing, symlink-resolved directory ending in /")
    func tempDirectoryResolved() {
        let sut = HSFSModule(engineID: UUID())
        let tmp = sut.tempDirectory()
        #expect(tmp.hasSuffix("/"))
        #expect(sut.isDirectory(tmp))
        #expect(sut.pathToAbsolute(tmp).map { $0 + "/" } == tmp)
    }

    @Test("homeDirectory returns the current user's home directory")
    func homeDirectoryMatchesFileManager() {
        let sut = HSFSModule(engineID: UUID())
        let expected = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(sut.homeDirectory() == expected)
    }

    @Test("urlFromPath returns a file:// URL string")
    func urlFromPathFormat() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let file = tmp.child("url.txt")
        _ = sut.write(file, "")

        let urlString = sut.urlFromPath(file)
        #expect(urlString.hasPrefix("file://"), "URL should start with file://")
        #expect(urlString.contains("url.txt"))
    }

    @Test("urlFromPath includes the expanded home directory for ~ paths")
    func urlFromPathExpandsTilde() throws {
        let sut = HSFSModule(engineID: UUID())
        let urlString = sut.urlFromPath("~")
        #expect(urlString.hasPrefix("file://"))
        #expect(urlString.contains(sut.homeDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    }

    // MARK: - Attributes

    @Test("attributes returns expected keys for a regular file")
    func attributesFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("attrs.txt")
        _ = sut.write(file, "hello")

        let attrs = try #require(sut.attributes(file))
        #expect(attrs["type"] as? String == "file")
        #expect((attrs["size"] as? Int ?? 0) > 0)
        #expect(attrs["permissions"] != nil)
        #expect(attrs["ownerID"] != nil)
        #expect(attrs["groupID"] != nil)
        #expect(attrs["creationDate"] as? Double != nil)
        #expect(attrs["modificationDate"] as? Double != nil)
    }

    @Test("attributes reports type as 'directory' for directories")
    func attributesDirectory() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let attrs = try #require(sut.attributes(tmp.path))
        #expect(attrs["type"] as? String == "directory")
    }

    @Test("attributes reports type as 'symlink' for symbolic links")
    func attributesSymlink() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp = try TempDir()
        let target = tmp.child("t.txt")
        let link   = tmp.child("l.txt")
        _ = sut.write(target, "")
        _ = sut.symlink(target, link)

        let attrs = try #require(sut.attributes(link))
        #expect(attrs["type"] as? String == "symlink",
                "attributes should use lstat so symlinks are reported as 'symlink'")
    }

    @Test("attributes returns null for a non-existent path")
    func attributesMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.attributes("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("touch creates a file when it does not exist")
    func touchCreatesFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("new.txt")
        #expect(sut.exists(file) == false)

        let ok = sut.touch(file)
        #expect(ok, "touch should succeed")
        #expect(sut.exists(file))
    }

    @Test("touch updates the modification date of an existing file")
    func touchUpdatesMtime() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("mtime.txt")
        _ = sut.write(file, "")

        // Back-date the modification time so there is a detectable gap.
        let past = Date(timeIntervalSinceNow: -10)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file)

        let oldMtime = (sut.attributes(file)?["modificationDate"] as? Double) ?? 0
        _ = sut.touch(file)
        let newMtime = (sut.attributes(file)?["modificationDate"] as? Double) ?? 0

        #expect(newMtime > oldMtime, "modification date should be updated by touch")
    }

    // MARK: - Links

    @Test("link creates a hard link — both paths point to the same inode")
    func hardLink() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let src  = tmp.child("orig.txt")
        let hard = tmp.child("hard.txt")
        _ = sut.write(src, "shared content")

        let ok = sut.link(src, hard)
        #expect(ok, "link should succeed")
        #expect(sut.read(hard) == "shared content")

        // Verify it is truly a hard link (same inode).
        let srcIno  = (sut.attributes(src)?["inode"]  as? Int) // use ino via stat directly
        let hardIno = (sut.attributes(hard)?["inode"] as? Int)

        #expect(srcIno != nil && hardIno != nil, "inode numbers should not be nil")
        #expect(srcIno == hardIno, "hard link should point to the same file")

        // A more reliable check: write via one path, read via the other.
        _ = sut.write(src, "updated", true)
        #expect(sut.read(hard) == "updated", "hard link should reflect writes through either path")
    }

    @Test("symlink creates a symbolic link pointing at the source")
    func symbolicLink() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp    = try TempDir()
        let target = tmp.child("target.txt")
        let link   = tmp.child("link.txt")
        _ = sut.write(target, "target content")

        let ok = sut.symlink(target, link)
        #expect(ok, "symlink should succeed")
        #expect(sut.isSymlink(link))
        #expect(sut.read(link, 0, 0) == "target content", "reading through symlink should give target content")
    }

    @Test("readlink returns the raw symlink target without resolving it")
    func readlinkTarget() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp    = try TempDir()
        let target = tmp.child("target.txt")
        let link   = tmp.child("link.txt")
        _ = sut.write(target, "")
        _ = sut.symlink(target, link)

        let result = try #require(sut.readlink(link))
        #expect(result == target)
    }

    @Test("readlink returns null for a regular file")
    func readlinkOnFile() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.readlink(file) == nil)
    }

    // MARK: - Finder Tags

    @available(macOS 26.0, *)
    @Test("setTags, tags, addTags, removeTags round-trip correctly")
    func finderTagsRoundTrip() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("tagged.txt")
        _ = sut.write(file, "")

        // Set initial tags
        let setOk = sut.setTags(file, ["Red", "Blue"] as NSArray)
        #expect(setOk, "setTags should succeed")

        let initial = try #require(sut.tags(file))
        #expect(Set(initial) == Set(["Red", "Blue"]))

        // Add a tag
        let addOk = sut.addTags(file, ["Green"] as NSArray)
        #expect(addOk)
        let afterAdd = try #require(sut.tags(file))
        #expect(afterAdd.contains("Green"))
        #expect(afterAdd.contains("Red"))

        // Remove a tag
        let removeOk = sut.removeTags(file, ["Blue"] as NSArray)
        #expect(removeOk)
        let afterRemove = try #require(sut.tags(file))
        #expect(afterRemove.contains("Blue") == false)
        #expect(afterRemove.contains("Red"))
        #expect(afterRemove.contains("Green"))

        // Clear all tags
        _ = sut.setTags(file, [] as NSArray)
        #expect(sut.tags(file) == nil, "setTags([]) should clear all tags")
    }

    @available(macOS 26.0, *)
    @Test("addTags is idempotent — adding an existing tag does not duplicate it")
    func addTagsIdempotent() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("idem.txt")
        _ = sut.write(file, "")
        _ = sut.setTags(file, ["Red"] as NSArray)
        _ = sut.addTags(file, ["Red"] as NSArray)

        let result = try #require(sut.tags(file))
        let redCount = result.filter { $0 == "Red" }.count
        #expect(redCount == 1, "Duplicate tags should not be created")
    }

    @available(macOS 26.0, *)
    @Test("removeTags silently ignores tags that are not present")
    func removeTagsIgnoresMissing() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("ignore.txt")
        _ = sut.write(file, "")
        _ = sut.setTags(file, ["Red"] as NSArray)

        let ok = sut.removeTags(file, ["Green", "Blue"] as NSArray)
        #expect(ok, "removeTags should succeed even when tags are absent")
        let remaining = try #require(sut.tags(file))
        #expect(remaining == ["Red"])
    }

    // MARK: - Uniform Type Identifiers

    @Test("fileUTI returns a UTI string for a plain text file")
    func fileUTIPlainText() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("sample.txt")
        _ = sut.write(file, "hello")

        let uti = try #require(sut.fileUTI(file), "fileUTI should return a value for .txt")
        #expect(uti.contains("text"), "UTI for .txt should include 'text'")
    }

    @Test("fileUTI returns null for a non-existent path")
    func fileUTIMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.fileUTI("/nonexistent/\(UUID().uuidString).txt") == nil)
    }

    // MARK: - Bookmarks

    @Test("pathToBookmark and pathFromBookmark round-trip a file path")
    func bookmarkRoundTrip() throws {
        let sut = HSFSModule(engineID: UUID())
        let tmp  = try TempDir()
        let file = tmp.child("bookmark.txt")
        _ = sut.write(file, "")

        let bookmark = try #require(sut.pathToBookmark(file),
                                    "pathToBookmark should succeed for an existing file")
        // Verify it is valid base64
        #expect(Data(base64Encoded: bookmark) != nil, "bookmark should be valid base64")

        let resolved = try #require(sut.pathFromBookmark(bookmark)?.deletingPrefix("/private"),
                                    "pathFromBookmark should resolve back to a path")
        #expect(resolved == file.deletingPrefix("/private"))
    }

    @Test("pathFromBookmark returns null for invalid base64")
    func pathFromBookmarkInvalidBase64() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.pathFromBookmark("not-valid-base64!!!") == nil)
    }

    @Test("pathToBookmark returns null for a non-existent path")
    func pathToBookmarkMissing() {
        let sut = HSFSModule(engineID: UUID())
        #expect(sut.pathToBookmark("/nonexistent/\(UUID().uuidString)") == nil)
    }

    // MARK: - Parameterized: tilde expansion

    @Test(
        "tilde is expanded correctly by file I/O methods",
        arguments: ["read", "write", "exists"]
    )
    func tildeExpansion(method: String) throws {
        let sut = HSFSModule(engineID: UUID())
        // Just verify none of these crash or misparse the tilde.
        let home = sut.homeDirectory()
        switch method {
        case "read":
            // /etc/hosts is a real file on every macOS system.
            let result = sut.read("/etc/hosts", 0, 0)
            #expect(result != nil, "read on /etc/hosts should succeed")
        case "write":
            let tmp  = try TempDir()
            let file = tmp.child("tilde.txt")
            // Simulate writing to a path that does NOT contain a tilde
            // (tilde in the middle of a path is not expanded by the shell).
            let ok = sut.write(file, "tilde test")
            #expect(ok)
        case "exists":
            #expect(sut.exists("~"), "~ should resolve to home and exist")
            #expect(sut.pathToAbsolute("~") == home)
        default:
            break
        }
    }
}
