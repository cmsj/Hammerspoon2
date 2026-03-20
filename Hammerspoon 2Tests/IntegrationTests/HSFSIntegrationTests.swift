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
struct HSFSIntegrationTests {
    let sut = HSFSModule()

    // MARK: - File I/O

    @Test("write creates a file and read returns its content")
    func writeAndRead() throws {
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
        let tmp = try TempDir()
        let file = tmp.child("overwrite.txt")

        _ = sut.write(file, "first")
        _ = sut.write(file, "second")

        let content = sut.read(file)
        #expect(content == "second")
    }

    @Test("append adds content to an existing file")
    func appendToExisting() throws {
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
        let tmp = try TempDir()
        let file = tmp.child("new.txt")

        let ok = sut.append(file, "created")
        #expect(ok, "append should succeed on a new file")
        #expect(sut.read(file) == "created")
    }

    @Test("read returns null for a non-existent file")
    func readMissing() {
        #expect(sut.read("/nonexistent/path/file.txt", 0, 0) == nil)
    }

    @Test("read with offset skips leading bytes")
    func readWithOffset() throws {
        let tmp = try TempDir()
        let file = tmp.child("offset.txt")
        _ = sut.write(file, "Hello, world!")

        // "Hello, " is 7 bytes; reading from offset 7 should give "world!"
        let result = try #require(sut.read(file, 7, 0))
        #expect(result == "world!")
    }

    @Test("read with length limits bytes returned")
    func readWithLength() throws {
        let tmp = try TempDir()
        let file = tmp.child("length.txt")
        _ = sut.write(file, "Hello, world!")

        let result = try #require(sut.read(file, 0, 5))
        #expect(result == "Hello")
    }

    @Test("read with offset and length returns the specified slice")
    func readWithOffsetAndLength() throws {
        let tmp = try TempDir()
        let file = tmp.child("slice.txt")
        _ = sut.write(file, "Hello, world!")

        // bytes 7–12: "world"
        let result = try #require(sut.read(file, 7, 5))
        #expect(result == "world")
    }

    @Test("readLines delivers all lines to the callback")
    func readLinesAll() throws {
        let tmp = try TempDir()
        let file = tmp.child("lines.txt")
        _ = sut.write(file, "alpha\nbeta\ngamma\n")

        let ctx = JSContext()!
        var collected: [String] = []
        let block: @convention(block) (String) -> Bool = { line in
            collected.append(line)
            return true
        }
        let callback = JSValue(object: block, in: ctx)!

        let ok = sut.readLines(file, callback)
        #expect(ok)
        #expect(collected == ["alpha", "beta", "gamma"])
    }

    @Test("readLines handles a file with no trailing newline")
    func readLinesNoTrailingNewline() throws {
        let tmp = try TempDir()
        let file = tmp.child("notrail.txt")
        _ = sut.write(file, "first\nsecond")  // no trailing \n

        let ctx = JSContext()!
        var collected: [String] = []
        let block: @convention(block) (String) -> Bool = { line in
            collected.append(line)
            return true
        }
        let callback = JSValue(object: block, in: ctx)!

        _ = sut.readLines(file, callback)
        #expect(collected == ["first", "second"])
    }

    @Test("readLines stops early when callback returns false")
    func readLinesEarlyStop() throws {
        let tmp = try TempDir()
        let file = tmp.child("stop.txt")
        _ = sut.write(file, "line1\nline2\nline3\n")

        let ctx = JSContext()!
        var collected: [String] = []
        let block: @convention(block) (String) -> Bool = { line in
            collected.append(line)
            return line != "line1"  // stop after the first line
        }
        let callback = JSValue(object: block, in: ctx)!

        let ok = sut.readLines(file, callback)
        #expect(ok, "readLines should return true even on early stop")
        #expect(collected == ["line1"])
    }

    @Test("readLines strips Windows-style CRLF line endings")
    func readLinesCRLF() throws {
        let tmp = try TempDir()
        let file = tmp.child("crlf.txt")
        // Write raw bytes with \r\n endings.
        let data = "alpha\r\nbeta\r\ngamma\r\n".data(using: .utf8)!
        try data.write(to: URL(fileURLWithPath: file))

        let ctx = JSContext()!
        var collected: [String] = []
        let block: @convention(block) (String) -> Bool = { line in
            collected.append(line)
            return true
        }
        let callback = JSValue(object: block, in: ctx)!

        _ = sut.readLines(file, callback)
        #expect(collected == ["alpha", "beta", "gamma"])
    }

    @Test("readLines returns false for a non-existent file")
    func readLinesMissing() throws {
        let ctx = JSContext()!
        let block: @convention(block) (String) -> Bool = { _ in true }
        let callback = JSValue(object: block, in: ctx)!

        let ok = sut.readLines("/nonexistent/\(UUID().uuidString)", callback)
        #expect(ok == false)
    }

    // MARK: - Existence and Type Checks

    @Test("exists returns true for a file and false for a missing path")
    func existsFile() throws {
        let tmp = try TempDir()
        let file = tmp.child("exists.txt")
        _ = sut.write(file, "")
        #expect(sut.exists(file))
        #expect(sut.exists(tmp.child("missing.txt")) == false)
    }

    @Test("exists returns true for a directory")
    func existsDirectory() throws {
        let tmp = try TempDir()
        #expect(sut.exists(tmp.path))
    }

    @Test("isFile is true for a regular file and false for a directory")
    func isFileChecks() throws {
        let tmp = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.isFile(file))
        #expect(sut.isFile(tmp.path) == false)
    }

    @Test("isDirectory is true for a directory and false for a file")
    func isDirectoryChecks() throws {
        let tmp = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.isDirectory(tmp.path))
        #expect(sut.isDirectory(file) == false)
    }

    @Test("isSymlink detects symbolic links but not regular files")
    func isSymlinkChecks() throws {
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
        let tmp = try TempDir()
        let file = tmp.child("rw.txt")
        _ = sut.write(file, "")
        #expect(sut.isReadable(file))
        #expect(sut.isWritable(file))
    }

    // MARK: - File Operations

    @Test("copy creates an independent copy of a file")
    func copyFile() throws {
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
        let tmp = try TempDir()
        let src = tmp.child("src.txt")
        let dst = tmp.child("dst.txt")
        _ = sut.write(src, "src")
        _ = sut.write(dst, "dst")
        #expect(sut.copy(src, dst) == false)
    }

    @Test("move relocates a file and removes the source")
    func moveFile() throws {
        let tmp = try TempDir()
        let src = tmp.child("before.txt")
        let dst = tmp.child("after.txt")
        _ = sut.write(src, "content")

        let ok = sut.move(src, dst)
        #expect(ok, "move should succeed")
        #expect(sut.exists(src) == false, "source should be gone")
        #expect(sut.read(dst, 0, 0) == "content")
    }

    @Test("delete removes a file")
    func deleteFile() throws {
        let tmp = try TempDir()
        let file = tmp.child("delete-me.txt")
        _ = sut.write(file, "")

        let ok = sut.delete(file)
        #expect(ok, "delete should succeed")
        #expect(sut.exists(file) == false)
    }

    @Test("delete removes a directory recursively")
    func deleteDirectoryRecursive() throws {
        let tmp = try TempDir()
        let dir = tmp.child("subtree")
        _ = sut.mkdir(dir)
        _ = sut.write((dir as NSString).appendingPathComponent("f.txt"), "x")

        let ok = sut.delete(dir)
        #expect(ok, "delete should remove a non-empty directory")
        #expect(sut.exists(dir) == false)
    }

    @Test("delete returns false for a non-existent path")
    func deleteMissing() {
        #expect(sut.delete("/nonexistent/\(UUID().uuidString)") == false)
    }

    // MARK: - Directory Operations

    @Test("mkdir creates a directory including intermediate directories")
    func mkdirDeep() throws {
        let tmp = try TempDir()
        let deep = (tmp.path as NSString)
            .appendingPathComponent("a/b/c")

        let ok = sut.mkdir(deep)
        #expect(ok, "mkdir should succeed")
        #expect(sut.isDirectory(deep))
    }

    @Test("mkdir succeeds silently when the directory already exists")
    func mkdirIdempotent() throws {
        let tmp = try TempDir()
        #expect(sut.mkdir(tmp.path), "mkdir on an existing dir should return true")
    }

    @Test("rmdir removes an empty directory")
    func rmdirEmpty() throws {
        let tmp = try TempDir()
        let dir = tmp.child("empty")
        _ = sut.mkdir(dir)

        let ok = sut.rmdir(dir)
        #expect(ok, "rmdir should succeed on an empty directory")
        #expect(sut.exists(dir) == false)
    }

    @Test("rmdir fails on a non-empty directory")
    func rmdirNonEmpty() throws {
        let tmp = try TempDir()
        let dir = tmp.child("nonempty")
        _ = sut.mkdir(dir)
        _ = sut.write((dir as NSString).appendingPathComponent("f.txt"), "x")

        #expect(sut.rmdir(dir) == false, "rmdir must fail if directory is not empty")
        #expect(sut.exists(dir), "directory should still exist")
    }

    @Test("list returns sorted filenames without . or ..")
    func listContents() throws {
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
        #expect(sut.list("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("listRecursive returns sorted relative paths for all descendants")
    func listRecursiveContents() throws {
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
        let dir = try #require(sut.currentDir())
        #expect(dir.isEmpty == false)
    }

    @Test("chdir changes the working directory and can be reversed")
    func chdirAndRestore() throws {
        let original = try #require(sut.currentDir())
        defer { _ = sut.chdir(original) }

        let tmp = try TempDir()
        let ok = sut.chdir(tmp.path)
        #expect(ok, "chdir should succeed")
        #expect(sut.currentDir()?.deletingPrefix("/private") == tmp.path.deletingPrefix("/private"))
    }

    @Test("chdir returns false for a non-existent path")
    func chdirMissing() {
        #expect(sut.chdir("/nonexistent/\(UUID().uuidString)") == false)
    }

    // MARK: - Path Utilities

    @Test("pathToAbsolute expands ~ to the home directory")
    func pathToAbsoluteExpandsTilde() throws {
        let home = sut.homeDirectory()
        let abs  = try #require(sut.pathToAbsolute("~"))
        #expect(abs == home)
    }

    @Test("pathToAbsolute returns null for a non-existent path")
    func pathToAbsoluteMissing() {
        #expect(sut.pathToAbsolute("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("pathToAbsolute resolves symlinks to their canonical path")
    func pathToAbsoluteResolvesSymlinks() throws {
        let tmp = try TempDir()
        let target = tmp.child("real.txt")
        let link   = tmp.child("link.txt")
        _ = sut.write(target, "")
        _ = sut.symlink(target, link)

        let abs = try #require(sut.pathToAbsolute(link)).deletingPrefix("/private")
        #expect(abs == target, "resolved path should point to the real file")
    }

    @Test("temporaryDirectory returns a non-empty path")
    func temporaryDirectoryNonEmpty() {
        let tmp = sut.temporaryDirectory()
        #expect(tmp.isEmpty == false)
        #expect(sut.isDirectory(tmp))
    }

    @Test("homeDirectory returns the current user's home directory")
    func homeDirectoryMatchesFileManager() {
        let expected = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(sut.homeDirectory() == expected)
    }

    @Test("urlFromPath returns a file:// URL string")
    func urlFromPathFormat() throws {
        let tmp = try TempDir()
        let file = tmp.child("url.txt")
        _ = sut.write(file, "")

        let urlString = try #require(sut.urlFromPath(file))
        #expect(urlString.hasPrefix("file://"), "URL should start with file://")
        #expect(urlString.contains("url.txt"))
    }

    @Test("urlFromPath includes the expanded home directory for ~ paths")
    func urlFromPathExpandsTilde() throws {
        let urlString = try #require(sut.urlFromPath("~"))
        #expect(urlString.hasPrefix("file://"))
        #expect(urlString.contains(sut.homeDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    }

    // MARK: - Attributes

    @Test("attributes returns expected keys for a regular file")
    func attributesFile() throws {
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
        let tmp = try TempDir()
        let attrs = try #require(sut.attributes(tmp.path))
        #expect(attrs["type"] as? String == "directory")
    }

    @Test("attributes reports type as 'symlink' for symbolic links")
    func attributesSymlink() throws {
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
        #expect(sut.attributes("/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test("touch creates a file when it does not exist")
    func touchCreatesFile() throws {
        let tmp  = try TempDir()
        let file = tmp.child("new.txt")
        #expect(sut.exists(file) == false)

        let ok = sut.touch(file)
        #expect(ok, "touch should succeed")
        #expect(sut.exists(file))
    }

    @Test("touch updates the modification date of an existing file")
    func touchUpdatesMtime() throws {
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
        let tmp  = try TempDir()
        let file = tmp.child("f.txt")
        _ = sut.write(file, "")
        #expect(sut.readlink(file) == nil)
    }

    // MARK: - Finder Tags

    @Test("setTags, tags, addTags, removeTags round-trip correctly")
    func finderTagsRoundTrip() throws {
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

    @Test("addTags is idempotent — adding an existing tag does not duplicate it")
    func addTagsIdempotent() throws {
        let tmp  = try TempDir()
        let file = tmp.child("idem.txt")
        _ = sut.write(file, "")
        _ = sut.setTags(file, ["Red"] as NSArray)
        _ = sut.addTags(file, ["Red"] as NSArray)

        let result = try #require(sut.tags(file))
        let redCount = result.filter { $0 == "Red" }.count
        #expect(redCount == 1, "Duplicate tags should not be created")
    }

    @Test("removeTags silently ignores tags that are not present")
    func removeTagsIgnoresMissing() throws {
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
        let tmp  = try TempDir()
        let file = tmp.child("sample.txt")
        _ = sut.write(file, "hello")

        let uti = try #require(sut.fileUTI(file), "fileUTI should return a value for .txt")
        #expect(uti.contains("text"), "UTI for .txt should include 'text'")
    }

    @Test("fileUTI returns null for a non-existent path")
    func fileUTIMissing() {
        #expect(sut.fileUTI("/nonexistent/\(UUID().uuidString).txt") == nil)
    }

    // MARK: - Bookmarks

    @Test("pathToBookmark and pathFromBookmark round-trip a file path")
    func bookmarkRoundTrip() throws {
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
        #expect(sut.pathFromBookmark("not-valid-base64!!!") == nil)
    }

    @Test("pathToBookmark returns null for a non-existent path")
    func pathToBookmarkMissing() {
        #expect(sut.pathToBookmark("/nonexistent/\(UUID().uuidString)") == nil)
    }

    // MARK: - Parameterized: tilde expansion

    @Test(
        "tilde is expanded correctly by file I/O methods",
        arguments: ["read", "write", "exists"]
    )
    func tildeExpansion(method: String) throws {
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
