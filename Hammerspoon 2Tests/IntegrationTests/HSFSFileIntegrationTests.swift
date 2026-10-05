//
//  HSFSFileIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Helpers

/// `realpath()` for test path comparisons.
private func resolvedPath(_ path: String) -> String {
    guard let resolved = unsafe realpath(path, nil) else { return path }
    defer { unsafe free(resolved) }
    return unsafe String(cString: resolved)
}

/// A unique temporary directory for one test, deleted when the object is deallocated.
private final class FileTestDir {
    let path: String

    init() throws {
        let created = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hs.fs-file-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
        // HSFile.path reports the kernel's resolved path (e.g. /private/var/... rather than
        // /var/...), so resolve ours the same way to compare paths directly.
        path = resolvedPath(created)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    func child(_ name: String) -> String {
        (path as NSString).appendingPathComponent(name)
    }

    /// Create a file containing `bytes` and return its path.
    @discardableResult
    func makeFile(_ name: String, bytes: [UInt8]) throws -> String {
        let file = child(name)
        try Data(bytes).write(to: URL(fileURLWithPath: file))
        return file
    }

    @discardableResult
    func makeFile(_ name: String, _ text: String) throws -> String {
        try makeFile(name, bytes: Array(text.utf8))
    }

    func contents(_ name: String) -> [UInt8]? {
        FileManager.default.contents(atPath: child(name)).map { Array($0) }
    }

    func text(_ name: String) -> String? {
        contents(name).flatMap { String(bytes: $0, encoding: .utf8) }
    }
}

@MainActor
private func makeHarness() -> JSTestHarness {
    let harness = JSTestHarness()
    harness.loadModule(HSFSModule.self, as: "fs")
    return harness
}

// MARK: - Test suite

@MainActor
@Suite("hs.fs file handle tests")
struct HSFSFileTests {

    // MARK: - API structure

    @Suite("hs.fs file handle API structure")
    struct StructureTests {
        @Test("module-level file functions exist", arguments: ["open", "tempFile", "withFile", "chmod", "touch"])
        func moduleFunctions(name: String) {
            #expect(makeHarness().evalTypeOf("hs.fs.\(name)") == "function")
        }

        @Test("hs.fs.lastError is null before any failure")
        func lastErrorInitiallyNull() {
            let harness = makeHarness()
            harness.expectTrue("hs.fs.lastError == null")
        }

        @Test("HSFile exposes its methods", arguments: [
            "read", "readLine", "eachLine", "readLines", "readBytes",
            "write", "writeLine", "writeBytes", "flush", "truncate",
            "seek", "rewind", "rename", "duplicate", "remove", "attributes",
            "setPermissions", "touch", "lock", "unlock", "close", "toString",
        ])
        func fileMethods(name: String) {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile()")
            #expect(harness.evalTypeOf("f.\(name)") == "function")
            harness.eval("f.remove(); f.close()")
        }

        @Test("HSFile properties have the expected types")
        func fileProperties() {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile()")
            #expect(harness.evalTypeOf("f.path") == "string")
            #expect(harness.evalString("f.mode") == "w+")
            #expect(harness.evalBool("f.isOpen") == true)
            #expect(harness.evalInt("f.position") == 0)
            #expect(harness.evalInt("f.size") == 0)
            #expect(harness.evalBool("f.atEnd") == true)
            harness.expectTrue("f.lastError == null")
            #expect(harness.evalString("f.typeName") == "HSFile")
            harness.eval("f.remove(); f.close()")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Opening

    @Suite("hs.fs.open")
    struct OpenTests {
        @Test("defaults to read-only mode")
        func defaultMode() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "hello")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.mode") == "r")
            #expect(harness.evalString("f.read()") == "hello")
            #expect(harness.evalBool("f.write('x')") == false)
            #expect(harness.evalString("f.lastError.code") == "EBADF")
            harness.eval("f.close()")
        }

        @Test("missing file returns null and sets lastError to ENOENT")
        func missingFile() {
            let harness = makeHarness()
            harness.expectTrue("hs.fs.open('/nonexistent/\(UUID().uuidString)') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
            #expect(harness.evalTypeOf("hs.fs.lastError.message") == "string")
        }

        @Test("invalid modes are rejected with EINVAL", arguments: ["q", "rw", "r++", "rx", "ax", ""])
        func invalidModes(mode: String) throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "x")
            let harness = makeHarness()
            // "" is treated as an omitted mode (i.e. "r"), so it should succeed.
            if mode.isEmpty {
                harness.expectTrue("hs.fs.open('\(file)', '') != null")
                return
            }
            harness.expectTrue("hs.fs.open('\(file)', '\(mode)') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
        }

        @Test("valid modes with b and x modifiers are accepted", arguments: ["rb", "r+b", "wb", "w+x", "wxb", "a+"])
        func validModes(mode: String) throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(dir.child("new.txt"))', '\(mode)')")
            if mode.hasPrefix("r") {
                // r modes need an existing file
                harness.expectTrue("f == null")
            } else {
                harness.expectTrue("f != null")
                harness.eval("f.close()")
            }
        }

        @Test("directories cannot be opened")
        func directory() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.expectTrue("hs.fs.open('\(dir.path)') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EISDIR")
        }

        @Test("w truncates and wx refuses an existing file")
        func writeModes() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "old contents")
            let harness = makeHarness()
            harness.expectTrue("hs.fs.open('\(file)', 'wx') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EEXIST")
            harness.eval("var f = hs.fs.open('\(file)', 'w'); f.write('new'); f.close()")
            #expect(dir.text("a.txt") == "new")
        }

        @Test("a always appends, even after seeking")
        func appendMode() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "one\n")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'a'); f.seek(0); f.write('two\\n'); f.close()")
            #expect(dir.text("a.txt") == "one\ntwo\n")
        }

        @Test("a+ reads from the start and appends writes")
        func appendPlusMode() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "one\n")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'a+')")
            #expect(harness.evalString("f.readLine()") == "one")
            harness.eval("f.writeLine('two'); f.close()")
            #expect(dir.text("a.txt") == "one\ntwo\n")
        }

        @Test("r+ reads and overwrites in place")
        func readPlusMode() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "hello world")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'r+'); f.seek(6); f.write('there'); f.close()")
            #expect(dir.text("a.txt") == "hello there")
        }

        @Test("permissions apply to newly created files")
        func createPermissions() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.eval("hs.fs.open('\(dir.child("secret"))', 'w', 0o600).close()")
            let attrs = try FileManager.default.attributesOfItem(atPath: dir.child("secret"))
            #expect((attrs[.posixPermissions] as? Int) == 0o600)
        }

        @Test("an explicit permissions value of 0 is honoured, not replaced by the default")
        func zeroPermissions() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.eval("hs.fs.open('\(dir.child("none"))', 'w', 0).close()")
            let attrs = try FileManager.default.attributesOfItem(atPath: dir.child("none"))
            #expect((attrs[.posixPermissions] as? Int) == 0)
        }

        @Test("invalid permissions are rejected with EINVAL", arguments: ["-1", "0o10000", "1.5", "Infinity", "NaN", "0 / 0"])
        func invalidPermissions(value: String) throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.expectTrue("hs.fs.open('\(dir.child("x"))', 'w', \(value)) == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
            #expect(!FileManager.default.fileExists(atPath: dir.child("x")))
        }

        @Test("an omitted or undefined permissions argument uses the 0o644 default")
        func defaultPermissions() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            // Create a reference file with 0o644 to learn what the process umask turns that into,
            // without touching process-wide state (there is no side-effect-free umask getter).
            let reference = dir.child("reference")
            let fd = unsafe open(reference, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            try #require(fd >= 0)
            close(fd)
            let expected = try #require(
                try FileManager.default.attributesOfItem(atPath: reference)[.posixPermissions] as? Int)
            harness.eval("""
                hs.fs.open('\(dir.child("omitted"))', 'w').close();
                hs.fs.open('\(dir.child("undef"))', 'w', undefined).close();
                hs.fs.withFile('\(dir.child("withfile"))', 'w', f => {});
            """)
            #expect(!harness.hasException)
            for name in ["omitted", "undef", "withfile"] {
                let attrs = try FileManager.default.attributesOfItem(atPath: dir.child(name))
                #expect((attrs[.posixPermissions] as? Int) == expected, "\(name)")
            }
        }

        @Test("path is absolute even when opened with a relative path")
        func relativePath() throws {
            let dir = try FileTestDir()
            try dir.makeFile("rel.txt", "x")
            let harness = makeHarness()
            // Build a path relative to the current working directory rather than changing it,
            // since the working directory is process-wide state shared with parallel tests.
            let cwdDepth = resolvedPath(FileManager.default.currentDirectoryPath)
                .split(separator: "/").count
            let relative = String(repeating: "../", count: cwdDepth) + dir.child("rel.txt").dropFirst()
            #expect(!relative.hasPrefix("/"))
            harness.eval("var f = hs.fs.open('\(relative)')")
            #expect(harness.evalString("f.path") == dir.child("rel.txt"))
            harness.eval("f.close()")
        }

        @Test("~ is expanded and path is absolute")
        func tildeExpansion() {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile()")
            harness.expectTrue("f.path.startsWith('/')")
            harness.eval("f.remove(); f.close()")
            // Opening ~ itself fails because it is a directory — proving it was expanded.
            harness.expectTrue("hs.fs.open('~') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EISDIR")
        }
    }

    // MARK: - Reading text

    @Suite("HSFile text reading")
    struct ReadTests {
        @Test("read() returns the rest of the file, then null at EOF")
        func readAll() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "Hello, world!")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.read(7)") == "Hello, ")
            #expect(harness.evalInt("f.position") == 7)
            #expect(harness.evalString("f.read()") == "world!")
            harness.expectTrue("f.read() === null")
            harness.expectTrue("f.read(5) === null")
            #expect(harness.evalBool("f.atEnd") == true)
            harness.eval("f.close()")
        }

        @Test("read(n) does not split a multi-byte character")
        func readUTF8Boundary() throws {
            let dir = try FileTestDir()
            // "a" (1 byte) + "é" (2 bytes) + "€" (3 bytes)
            let file = try dir.makeFile("a.txt", "aé€")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.read(2)") == "a")
            #expect(harness.evalInt("f.position") == 1)
            #expect(harness.evalString("f.read(4)") == "é")
            #expect(harness.evalInt("f.position") == 3)
            // A request too small for one whole character returns the whole character.
            #expect(harness.evalString("f.read(1)") == "€")
            #expect(harness.evalInt("f.position") == 6)
            harness.eval("f.close()")
        }

        @Test("invalid UTF-8 returns null with EILSEQ and does not move the position")
        func readInvalidUTF8() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("bin", bytes: [0x41, 0xFF, 0xFE, 0x42])
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            harness.expectTrue("f.read() === null")
            #expect(harness.evalString("f.lastError.code") == "EILSEQ")
            #expect(harness.evalInt("f.position") == 0)
            #expect(harness.evalInt("f.readBytes().length") == 4)
            harness.eval("f.close()")
        }

        @Test("readLine handles LF, CRLF, empty lines, and a final unterminated line")
        func readLine() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "one\r\ntwo\n\nthree")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.readLine()") == "one")
            #expect(harness.evalInt("f.position") == 5)
            #expect(harness.evalString("f.readLine()") == "two")
            #expect(harness.evalString("f.readLine()") == "")
            #expect(harness.evalString("f.readLine()") == "three")
            harness.expectTrue("f.readLine() === null")
            harness.eval("f.close()")
        }

        @Test("the documented `!== null` read loop terminates at end of file")
        func readLoopTerminates() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)'), lines = [], line, iterations = 0;
                while ((line = f.readLine()) !== null && iterations++ < 10) lines.push(line);
                var chunks = 0; f.rewind();
                while (f.read(1) !== null && chunks < 10) chunks++;
                var byteChunks = 0; f.rewind();
                while (f.readBytes(1) !== null && byteChunks < 10) byteChunks++;
                f.close();
            """)
            #expect(harness.evalString("lines.join(',')") == "a,b")
            #expect(harness.evalInt("chunks") == 4)
            #expect(harness.evalInt("byteChunks") == 4)
        }

        @Test("readLine(true) keeps line endings")
        func readLineKeepNewline() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "one\r\ntwo\nthree")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.readLine(true)") == "one\r\n")
            #expect(harness.evalString("f.readLine(true)") == "two\n")
            #expect(harness.evalString("f.readLine(true)") == "three")
            harness.eval("f.close()")
        }

        @Test("readLine handles lines longer than the internal read chunk")
        func readLongLine() throws {
            let dir = try FileTestDir()
            let long = String(repeating: "x", count: 200_000)
            let file = try dir.makeFile("a.txt", "\(long)\nshort\n")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalInt("f.readLine().length") == 200_000)
            #expect(harness.evalString("f.readLine()") == "short")
            harness.eval("f.close()")
        }

        @Test("readLine interleaves correctly with read()")
        func readLineThenRead() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "header\nbody text")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.readLine()") == "header")
            #expect(harness.evalString("f.read()") == "body text")
            harness.eval("f.close()")
        }

        @Test("readLines returns all remaining lines")
        func readLines() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "skip\na\r\nb\nc")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)'); f.readLine()")
            #expect(harness.evalString("JSON.stringify(f.readLines())") == #"["a","b","c"]"#)
            #expect(harness.evalString("JSON.stringify(f.readLines())") == "[]")
            harness.eval("f.close()")
        }

        @Test("eachLine visits every line and can stop early")
        func eachLine() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\nc\nd\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)');
                var seen = [];
                var ok = f.eachLine(line => { seen.push(line); if (line === 'b') return false; });
            """)
            #expect(harness.evalBool("ok") == true)
            #expect(harness.evalString("seen.join(',')") == "a,b")
            // Position is immediately after the last delivered line.
            #expect(harness.evalString("f.readLine()") == "c")
            harness.eval("seen = []; f.eachLine(line => { seen.push(line) })")
            #expect(harness.evalString("seen.join(',')") == "d")
            harness.eval("f.close()")
            #expect(!harness.hasException)
        }

        @Test("eachLine callback can use the file, and an exception propagates")
        func eachLineReentrancyAndThrow() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\nc\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)');
                var seen = [];
                f.eachLine(line => { seen.push(line + '@' + f.position); if (line === 'a') f.seek(4); });
            """)
            // After 'a' the callback jumps to byte 4 ("c"), skipping "b".
            #expect(harness.evalString("seen.join(',')") == "a@2,c@6")

            harness.eval("""
                f.rewind();
                var caught = null;
                try { f.eachLine(line => { throw new Error('boom ' + line) }) } catch (e) { caught = e.message }
            """)
            #expect(harness.evalString("caught") == "boom a")
            #expect(harness.evalString("f.readLine()") == "b")
            harness.eval("f.close()")
        }
    }

    @Suite("HSFile eachLine callbacks that modify the file", .serialized)
    struct EachLineMutationTests {
        @Test("truncating the file in a callback stops delivering stale lines")
        func truncateDuringEachLine() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\nc\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)', 'r+'), seen = [];
                var ok = f.eachLine(line => { seen.push(line); if (line === 'a') f.truncate(2); });
                f.close();
            """)
            #expect(harness.evalBool("ok") == true)
            #expect(harness.evalString("seen.join(',')") == "a")
        }

        @Test("overwriting later lines in a callback delivers the new contents")
        func overwriteDuringEachLine() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\nc\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)', 'r+'), seen = [];
                f.eachLine(line => {
                    seen.push(line);
                    if (line === 'a') { var p = f.position; f.write('X\\nY\\n'); f.seek(p); }
                });
                f.close();
            """)
            #expect(harness.evalString("seen.join(',')") == "a,X,Y")
        }

        @Test("closing the file in a callback makes eachLine return false with EBADF")
        func closeDuringEachLine() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "a\nb\nc\n")
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(file)'), seen = [];
                var ok = f.eachLine(line => { seen.push(line); f.close(); });
            """)
            #expect(harness.evalBool("ok") == false)
            #expect(harness.evalString("seen.join(',')") == "a")
            #expect(harness.evalString("f.lastError.code") == "EBADF")
        }
    }

    // MARK: - Binary data

    @Suite("HSFile binary data")
    struct BinaryTests {
        @Test("readBytes returns a Uint8Array with the file's bytes")
        func readBytes() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("bin", bytes: [0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)'); var b = f.readBytes(4)")
            harness.expectTrue("b instanceof Uint8Array")
            #expect(harness.evalString("Array.from(b).join(',')") == "137,80,78,71")
            #expect(harness.evalString("Array.from(f.readBytes()).join(',')") == "0,255")
            harness.expectTrue("f.readBytes() === null")
            harness.eval("f.close()")
        }

        @Test("writeBytes writes typed arrays, views, and ArrayBuffers")
        func writeBytes() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.open('\(dir.child("bin"))', 'w');
                var r1 = f.writeBytes(new Uint8Array([1, 2, 3]));
                var r2 = f.writeBytes(new Uint8Array([9, 9, 4, 5, 9]).subarray(2, 4));
                var r3 = f.writeBytes(new Uint8Array([6, 7]).buffer);
                var r4 = f.writeBytes(new Uint16Array([0x0908]));
                var r5 = f.writeBytes(new Uint8Array(new Uint8Array([0, 0, 0, 0, 0, 0, 10, 11]).buffer, 6, 2));
                f.close();
            """)
            #expect(harness.evalBool("r1 && r2 && r3 && r4 && r5") == true)
            #expect(dir.contents("bin") == [1, 2, 3, 4, 5, 6, 7, 0x08, 0x09, 10, 11])
        }

        @Test("writeBytes rejects non-binary values with EINVAL", arguments: ["'text'", "[1, 2]", "null", "42", "new DataView(new ArrayBuffer(2))"])
        func writeBytesInvalid(value: String) throws {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile(); var r = f.writeBytes(\(value))")
            #expect(harness.evalBool("r") == false)
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            #expect(harness.evalInt("f.size") == 0)
            harness.eval("f.remove(); f.close()")
        }

        @Test("binary data round-trips through write and read")
        func roundTrip() throws {
            let harness = makeHarness()
            harness.eval("""
                var f = hs.fs.tempFile();
                var src = new Uint8Array(256); for (var i = 0; i < 256; i++) src[i] = i;
                f.writeBytes(src); f.rewind();
                var back = f.readBytes();
                var same = back.length === 256 && back.every((v, i) => v === i);
                f.remove(); f.close();
            """)
            #expect(harness.evalBool("same") == true)
        }

        @Test("empty typed arrays write nothing and succeed")
        func emptyWrite() {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile(); var r = f.writeBytes(new Uint8Array(0))")
            #expect(harness.evalBool("r") == true)
            #expect(harness.evalInt("f.size") == 0)
            harness.eval("f.remove(); f.close()")
        }
    }

    // MARK: - Writing and positioning

    @Suite("HSFile writing and positioning")
    struct WriteTests {
        @Test("write and writeLine encode UTF-8")
        func writeText() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(dir.child("a.txt"))', 'w'); f.write('héllo '); f.writeLine('wörld'); f.close()")
            #expect(dir.text("a.txt") == "héllo wörld\n")
        }

        @Test("seek supports set, cur, and end, and rejects bad whence")
        func seek() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "0123456789")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalInt("f.seek(3)") == 3)
            #expect(harness.evalInt("f.seek(2, 'cur')") == 5)
            #expect(harness.evalInt("f.seek(-1, 'end')") == 9)
            #expect(harness.evalString("f.read()") == "9")
            harness.expectTrue("f.seek(0, 'sideways') == null")
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            harness.expectTrue("f.seek(-100) == null")
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            // Lua idioms for reading the position / size must not silently rewind.
            harness.eval("f.seek(4)")
            for call in ["f.seek()", "f.seek('end')", "f.seek(undefined, 'end')", "f.seek(1.5)", "f.seek(NaN)"] {
                harness.expectTrue("\(call) == null")
                #expect(harness.evalString("f.lastError.code") == "EINVAL", "\(call)")
                #expect(harness.evalInt("f.position") == 4, "\(call) must not move the position")
            }
            #expect(harness.evalBool("f.rewind()") == true)
            #expect(harness.evalInt("f.position") == 0)
            harness.eval("f.close()")
        }

        @Test("truncate shrinks, extends, and empties without moving the position")
        func truncate() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "0123456789")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'r+'); f.seek(8)")
            #expect(harness.evalBool("f.truncate(4)") == true)
            #expect(harness.evalInt("f.size") == 4)
            #expect(harness.evalInt("f.position") == 8)
            #expect(harness.evalBool("f.truncate(6)") == true)
            #expect(dir.contents("a.txt") == Array("0123".utf8) + [0, 0])
            #expect(harness.evalBool("f.truncate()") == true)
            #expect(harness.evalInt("f.size") == 0)
            #expect(harness.evalBool("f.truncate(-1)") == false)
            harness.eval("f.close()")
        }

        @Test("size and atEnd track writes")
        func sizeTracksWrites() {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile(); f.write('abc')")
            #expect(harness.evalInt("f.size") == 3)
            #expect(harness.evalBool("f.atEnd") == true)
            harness.eval("f.rewind()")
            #expect(harness.evalBool("f.atEnd") == false)
            #expect(harness.evalBool("f.flush()") == true)
            harness.eval("f.remove(); f.close()")
        }
    }

    // MARK: - Path operations

    @Suite("HSFile path operations")
    struct PathTests {
        @Test("rename moves the file, updates path, and keeps the handle usable")
        func rename() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "data")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'r+')")
            #expect(harness.evalBool("f.rename('\(dir.child("b.txt"))')") == true)
            #expect(harness.evalString("f.path") == dir.child("b.txt"))
            #expect(harness.evalString("f.read()") == "data")
            harness.eval("f.write('more'); f.close()")
            #expect(!FileManager.default.fileExists(atPath: file))
            #expect(dir.text("b.txt") == "datamore")
        }

        @Test("rename refuses to overwrite unless asked")
        func renameOverwrite() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "new")
            try dir.makeFile("b.txt", "old")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalBool("f.rename('\(dir.child("b.txt"))')") == false)
            #expect(harness.evalString("f.lastError.code") == "EEXIST")
            #expect(harness.evalString("f.path") == file)
            #expect(harness.evalBool("f.rename('\(dir.child("b.txt"))', true)") == true)
            harness.eval("f.close()")
            #expect(dir.text("b.txt") == "new")
        }

        @Test("duplicate copies the file and refuses to overwrite")
        func duplicate() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "data")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalBool("f.duplicate('\(dir.child("copy.txt"))')") == true)
            #expect(dir.text("copy.txt") == "data")
            #expect(harness.evalBool("f.duplicate('\(dir.child("copy.txt"))')") == false)
            #expect(harness.evalString("f.lastError.code") == "EEXIST")
            harness.eval("f.close()")
        }

        @Test("remove unlinks the path but the handle keeps working")
        func remove() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "data")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)', 'r+')")
            #expect(harness.evalBool("f.remove()") == true)
            #expect(!FileManager.default.fileExists(atPath: file))
            #expect(harness.evalString("f.read()") == "data")
            #expect(harness.evalBool("f.write('!')") == true)
            #expect(harness.evalInt("f.attributes().size") == 5)
            #expect(harness.evalBool("f.remove()") == false)
            #expect(harness.evalString("f.lastError.code") == "ENOENT")
            harness.eval("f.close()")
        }

        @Test("path operations refuse to act on a file that has replaced the open one")
        func replacedPath() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "original")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            // Another process moves the file away and puts a different file at the same path.
            try FileManager.default.moveItem(atPath: file, toPath: dir.child("moved.txt"))
            try dir.makeFile("a.txt", "impostor")

            #expect(harness.evalBool("f.remove()") == false)
            #expect(harness.evalString("f.lastError.code") == "ESTALE")
            #expect(harness.evalBool("f.rename('\(dir.child("b.txt"))')") == false)
            #expect(harness.evalString("f.lastError.code") == "ESTALE")
            #expect(harness.evalBool("f.duplicate('\(dir.child("c.txt"))')") == false)
            #expect(harness.evalString("f.lastError.code") == "ESTALE")
            #expect(dir.text("a.txt") == "impostor")
            #expect(!FileManager.default.fileExists(atPath: dir.child("b.txt")))
            #expect(!FileManager.default.fileExists(atPath: dir.child("c.txt")))
            #expect(harness.evalString("f.read()") == "original")
            harness.eval("f.close()")
        }

        @Test("attributes, setPermissions, and touch act on the open file")
        func metadata() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "data")
            let harness = makeHarness()
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalString("f.attributes().type") == "file")
            #expect(harness.evalInt("f.attributes().size") == 4)
            #expect(harness.evalBool("f.setPermissions(0o640)") == true)
            #expect(harness.evalInt("f.attributes().permissions") == 0o640)
            #expect(harness.evalBool("f.touch(1000000000)") == true)
            #expect(harness.evalDouble("f.attributes().modificationDate") == 1_000_000_000)
            #expect(harness.evalBool("f.touch(0)") == true)
            #expect(harness.evalDouble("f.attributes().modificationDate") == 0)
            #expect(harness.evalBool("f.touch(1e100)") == false)
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            #expect(harness.evalBool("f.touch(Infinity)") == false)
            #expect(harness.evalBool("f.touch(NaN)") == false)
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            #expect(harness.evalBool("f.touch(1000, NaN)") == false)
            #expect(harness.evalBool("f.touch(undefined)") == true)
            #expect(harness.evalBool("f.touch()") == true)
            harness.expectTrue("Math.abs(f.attributes().modificationDate - Date.now() / 1000) < 60")
            harness.eval("f.close()")
        }
    }

    // MARK: - Locking

    @Suite("HSFile locking")
    struct LockTests {
        @Test("exclusive locks conflict; shared locks coexist")
        func locking() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("lock", "")
            let harness = makeHarness()
            harness.eval("var a = hs.fs.open('\(file)'); var b = hs.fs.open('\(file)')")
            #expect(harness.evalBool("a.lock()") == true)
            #expect(harness.evalBool("b.lock()") == false)
            #expect(harness.evalString("b.lastError.code") == "EAGAIN")
            #expect(harness.evalBool("b.lock(true)") == false)
            #expect(harness.evalBool("a.unlock()") == true)
            #expect(harness.evalBool("b.lock()") == true)
            #expect(harness.evalBool("b.unlock()") == true)
            #expect(harness.evalBool("a.lock(true)") == true)
            #expect(harness.evalBool("b.lock(true)") == true)
            // Closing releases the lock.
            harness.eval("a.close(); b.close(); a = hs.fs.open('\(file)'); b = hs.fs.open('\(file)')")
            #expect(harness.evalBool("a.lock()") == true)
            harness.eval("a.close()")
            #expect(harness.evalBool("b.lock()") == true)
            harness.eval("b.close()")
        }
    }

    // MARK: - Lifecycle

    @Suite("HSFile lifecycle")
    struct LifecycleTests {
        @Test("close is idempotent and later operations fail with EBADF")
        func close() throws {
            let harness = makeHarness()
            harness.eval("var f = hs.fs.tempFile(); var p = f.path; f.remove()")
            #expect(harness.evalBool("f.close()") == true)
            #expect(harness.evalBool("f.close()") == true)
            #expect(harness.evalBool("f.isOpen") == false)
            #expect(harness.evalInt("f.position") == 0)
            harness.expectTrue("f.read() === null")
            #expect(harness.evalString("f.lastError.code") == "EBADF")
            #expect(harness.evalBool("f.write('x')") == false)
            harness.expectTrue("f.attributes() == null")
            harness.expectTrue(#"String(f).endsWith(", w+, closed>")"#)
            #expect(!harness.hasException)
        }

        @Test("tempFile creates a unique private file with the given prefix")
        func tempFile() throws {
            let harness = makeHarness()
            harness.eval("var a = hs.fs.tempFile('myspoon'); var b = hs.fs.tempFile('myspoon')")
            harness.expectTrue("a.path !== b.path")
            let path = try #require(harness.evalString("a.path"))
            #expect((path as NSString).lastPathComponent.hasPrefix("myspoon."))
            #expect(path.hasPrefix(resolvedPath(NSTemporaryDirectory())))
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attrs[.posixPermissions] as? Int) == 0o600)
            harness.eval("a.remove(); a.close(); b.remove(); b.close()")
            harness.expectTrue("hs.fs.tempFile('a/b') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
        }

        @Test("withFile returns the callback's result and closes the file")
        func withFile() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "first\nsecond\n")
            let harness = makeHarness()
            harness.eval("var kept = null; var r = hs.fs.withFile('\(file)', 'r', f => { kept = f; return f.readLine() })")
            #expect(harness.evalString("r") == "first")
            #expect(harness.evalBool("kept.isOpen") == false)
            #expect(!harness.hasException)
        }

        @Test("withFile closes the file and propagates exceptions")
        func withFileThrows() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "x")
            let harness = makeHarness()
            harness.eval("""
                var kept = null, caught = null;
                try { hs.fs.withFile('\(file)', 'r', f => { kept = f; throw new Error('nope') }) }
                catch (e) { caught = e.message }
            """)
            #expect(harness.evalString("caught") == "nope")
            #expect(harness.evalBool("kept.isOpen") == false)
        }

        @Test("withFile returns null and sets lastError when the file cannot be opened")
        func withFileMissing() {
            let harness = makeHarness()
            harness.eval("var called = false; var r = hs.fs.withFile('/nonexistent/\(UUID().uuidString)', 'r', f => { called = true })")
            harness.expectTrue("r == null && called === false")
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
        }

        @Test("module shutdown closes open files")
        func shutdownClosesFiles() throws {
            let module = HSFSModule(engineID: UUID())
            let file = try #require(module.tempFile("shutdown"))
            _ = file.remove()
            #expect(file.isOpen)
            module.shutdown()
            #expect(!file.isOpen)
        }

        @Test("HSFile is released after shutdown")
        func testFileDoesNotLeakAfterReload() throws {
            let dir = try FileTestDir()
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSFSModule.self, as: "fs")
                harness.eval("""
                    var f = hs.fs.open('\(dir.child("leak.txt"))', 'w+');
                    f.writeLine('hello'); f.lock(); f.rewind();
                    f.eachLine(line => {});
                    f.readBytes();
                """)
                if let swift = harness.evalValue("f")?.toObjectOf(HSFile.self) as? HSFile {
                    tracker.track(swift)
                }
                harness.eval("f = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }

    // MARK: - Module-level additions

    @Suite("hs.fs chmod, touch, and lastError")
    struct ModuleTests {
        @Test("chmod and setPermissions reject missing or out-of-range permissions",
              arguments: ["", ", -1", ", 0o10000", ", 1.5", ", NaN", ", 'abc'"])
        func invalidPermissionArguments(argument: String) throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "x")
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file)
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.chmod('\(file)'\(argument))") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
            harness.eval("var f = hs.fs.open('\(file)')")
            #expect(harness.evalBool("f.setPermissions(\(argument.dropFirst(2)))") == false)
            #expect(harness.evalString("f.lastError.code") == "EINVAL")
            harness.eval("f.close()")
            let attrs = try FileManager.default.attributesOfItem(atPath: file)
            #expect((attrs[.posixPermissions] as? Int) == 0o640, "mode must be unchanged")
        }

        @Test("chmod sets permissions")
        func chmod() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.sh", "#!/bin/sh\n")
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.chmod('\(file)', 0o755)") == true)
            #expect(harness.evalInt("hs.fs.attributes('\(file)').permissions") == 0o755)
            #expect(harness.evalBool("hs.fs.chmod('\(dir.child("missing"))', 0o755)") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
        }

        @Test("touch accepts explicit modification and access dates")
        func touchDates() throws {
            let dir = try FileTestDir()
            let file = dir.child("t.txt")
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.touch('\(file)', 1000000000)") == true)
            #expect(harness.evalDouble("hs.fs.attributes('\(file)').modificationDate") == 1_000_000_000)
            #expect(harness.evalBool("hs.fs.touch('\(file)', 1000000000, 1100000000)") == true)
            let attrs = try FileManager.default.attributesOfItem(atPath: file)
            #expect((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 == 1_000_000_000)
            var st = stat()
            #expect(unsafe stat(file, &st) == 0)
            #expect(st.st_atimespec.tv_sec == 1_100_000_000)
        }

        @Test("touch treats 0 as the epoch and rejects out-of-range timestamps without creating the file")
        func touchEdgeCases() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.touch('\(dir.child("epoch"))', 0)") == true)
            #expect(harness.evalDouble("hs.fs.attributes('\(dir.child("epoch"))').modificationDate") == 0)
            #expect(harness.evalBool("hs.fs.touch('\(dir.child("huge"))', 1e100)") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
            #expect(harness.evalBool("hs.fs.touch('\(dir.child("huge"))', 1000, -Infinity)") == false)
            #expect(harness.evalBool("hs.fs.touch('\(dir.child("huge"))', NaN)") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "EINVAL")
            #expect(!FileManager.default.fileExists(atPath: dir.child("huge")))
        }

        @Test("touch does not truncate an existing file and works on directories")
        func touchExisting() throws {
            let dir = try FileTestDir()
            let file = try dir.makeFile("a.txt", "keep me")
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.touch('\(file)')") == true)
            #expect(dir.text("a.txt") == "keep me")
            #expect(harness.evalBool("hs.fs.touch('\(dir.path)', 1000000000)") == true)
            #expect(harness.evalDouble("hs.fs.attributes('\(dir.path)').modificationDate") == 1_000_000_000)
        }

        @Test("existing path functions record lastError")
        func existingFunctionsSetLastError() throws {
            let dir = try FileTestDir()
            let harness = makeHarness()
            #expect(harness.evalBool("hs.fs.copy('\(dir.child("missing"))', '\(dir.child("b"))')") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
            try dir.makeFile("x", "")
            #expect(harness.evalBool("hs.fs.mkdir('\(dir.child("x"))')") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "EEXIST")
            #expect(harness.evalBool("hs.fs.rmdir('\(dir.path)')") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOTEMPTY")

            // Both chdir calls are expected to fail, so the process-wide working directory is unchanged.
            #expect(harness.evalBool("hs.fs.chdir('\(dir.child("missing"))')") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
            #expect(harness.evalBool("hs.fs.chdir('\(dir.child("x"))')") == false)
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOTDIR")
            harness.expectTrue("hs.fs.pathToAbsolute('\(dir.child("missing2"))') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
            harness.expectTrue("hs.fs.displayName('\(dir.child("x"))') != null")
            harness.expectTrue("hs.fs.displayName('\(dir.child("missing3"))') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOENT")
            harness.expectTrue("hs.fs.xattrGet('\(dir.child("x"))', 'com.example.absent') == null")
            #expect(harness.evalString("hs.fs.lastError.code") == "ENOATTR")
        }

        @Test("errno values map to their symbolic names")
        func errnoNames() {
            #expect(HSFSSupport.errnoName(ENOENT) == "ENOENT")
            #expect(HSFSSupport.errnoName(EAGAIN) == "EAGAIN")
            #expect(HSFSSupport.errnoName(EISDIR) == "EISDIR")
            #expect(HSFSSupport.errnoName(99_999) == "UNKNOWN")
        }
    }
}
