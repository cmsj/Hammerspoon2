//
//  NodeFSIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Test context

// NodeFSTestContext creates an isolated JSContext with the Node builtins registry and
// require() installed (mirroring RequireContext in HSRequireIntegrationTests.swift), plus a
// temporary directory for test files. Each test creates its own instance so there is no shared
// state between tests.
private final class NodeFSTestContext {
    let context: JSContext
    let tempDir: URL
    private(set) var lastException: JSValue?

    init() throws {
        let vm = JSVirtualMachine()
        let ctx = JSContext(virtualMachine: vm)!
        ctx.name = "NodeFSTestContext"
        context = ctx

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs_node_fs_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        ctx.exceptionHandler = { [weak self] _, exc in self?.lastException = exc }
        try NodeBuiltinModulesInstaller().install(in: ctx)
        try RequireInstaller().install(in: ctx)
        ctx.evaluateScript("var fs = require('fs')")
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Absolute path of `name` inside this context's temporary directory.
    func path(_ name: String) -> String {
        tempDir.appendingPathComponent(name).path
    }

    @discardableResult
    func eval(_ script: String) -> Any? {
        lastException = nil
        return context.evaluateScript(script)?.toObject()
    }

    func evalValue(_ script: String) -> JSValue? {
        lastException = nil
        return context.evaluateScript(script)
    }

    func evalString(_ script: String) -> String? { eval(script) as? String }
    func evalBool(_ script: String) -> Bool? { eval(script) as? Bool }
    func evalInt(_ script: String) -> Int? { eval(script) as? Int }

    var hadException: Bool { lastException != nil }

    @discardableResult
    func waitForAsync(timeout: TimeInterval = 2.0, condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if condition() { return true }
        }
        return false
    }
}

// MARK: - Test suites

@Suite("fs tests")
struct NodeFSTests {

    // MARK: Structure

    @Suite("fs API structure tests")
    struct NodeFSStructureTests {
        @Test("fs sync API is fully present")
        func testSyncAPIShape() throws {
            let ctx = try NodeFSTestContext()
            let names = [
                "existsSync", "readFileSync", "writeFileSync", "appendFileSync",
                "mkdirSync", "rmdirSync", "rmSync", "unlinkSync", "readdirSync",
                "statSync", "lstatSync", "renameSync", "copyFileSync", "symlinkSync",
                "readlinkSync", "realpathSync", "linkSync", "accessSync", "truncateSync",
            ]
            for name in names {
                #expect(ctx.evalString("typeof fs.\(name)") == "function", "fs.\(name)")
            }
        }

        @Test("fs.promises API is fully present")
        func testPromisesAPIShape() throws {
            let ctx = try NodeFSTestContext()
            #expect(ctx.evalString("typeof fs.promises") == "object")
            let names = [
                "readFile", "writeFile", "appendFile", "mkdir", "rmdir", "rm", "unlink",
                "readdir", "stat", "lstat", "rename", "copyFile", "symlink", "readlink",
                "realpath", "link", "access", "truncate",
            ]
            for name in names {
                #expect(ctx.evalString("typeof fs.promises.\(name)") == "function", "fs.promises.\(name)")
            }
        }

        @Test("fs.constants exposes POSIX access/copy flags")
        func testConstants() throws {
            let ctx = try NodeFSTestContext()
            #expect(ctx.evalInt("fs.constants.F_OK") == 0)
            #expect(ctx.evalInt("fs.constants.R_OK") == 4)
            #expect(ctx.evalInt("fs.constants.W_OK") == 2)
            #expect(ctx.evalInt("fs.constants.X_OK") == 1)
            #expect(ctx.evalInt("fs.constants.COPYFILE_EXCL") == 1)
        }
    }

    // MARK: File I/O

    @Suite("fs sync file I/O")
    struct NodeFSSyncFileTests {
        @Test("writeFileSync then readFileSync round-trips content")
        func testWriteReadRoundTrip() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("hello.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'Hello, world!\\n')")
            #expect(!ctx.hadException)
            #expect(ctx.evalString("fs.readFileSync('\(p)')") == "Hello, world!\n")
        }

        @Test("appendFileSync appends to existing content")
        func testAppend() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("log.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'a')")
            ctx.eval("fs.appendFileSync('\(p)', 'b')")
            #expect(ctx.evalString("fs.readFileSync('\(p)')") == "ab")
        }

        @Test("writeFileSync with 'a' flag behaves like appendFileSync")
        func testWriteFlagAppend() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("flag.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'a')")
            ctx.eval("fs.writeFileSync('\(p)', 'b', 'a')")
            #expect(ctx.evalString("fs.readFileSync('\(p)')") == "ab")
        }

        @Test("existsSync reflects file presence")
        func testExists() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("maybe.txt")
            #expect(ctx.evalBool("fs.existsSync('\(p)')") == false)
            ctx.eval("fs.writeFileSync('\(p)', 'x')")
            #expect(ctx.evalBool("fs.existsSync('\(p)')") == true)
        }

        @Test("unlinkSync removes a file")
        func testUnlink() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("gone.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'x')")
            ctx.eval("fs.unlinkSync('\(p)')")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.existsSync('\(p)')") == false)
        }
    }

    // MARK: Directories

    @Suite("fs sync directories")
    struct NodeFSSyncDirectoryTests {
        @Test("mkdirSync + readdirSync lists created entries")
        func testMkdirReaddir() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("sub")
            ctx.eval("fs.mkdirSync('\(dir)')")
            ctx.eval("fs.writeFileSync('\(dir)/a.txt', '1')")
            ctx.eval("fs.writeFileSync('\(dir)/b.txt', '2')")
            let names = (ctx.evalValue("fs.readdirSync('\(dir)').sort()")?.toArray() ?? [])
                .compactMap { $0 as? String }
            #expect(names == ["a.txt", "b.txt"])
        }

        @Test("mkdirSync with recursive creates nested directories")
        func testMkdirRecursive() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("a/b/c")
            ctx.eval("fs.mkdirSync('\(dir)', true)")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.existsSync('\(dir)')") == true)
        }

        @Test("readdirSync withFileTypes returns Dirent objects")
        func testReaddirWithFileTypes() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("typed")
            ctx.eval("fs.mkdirSync('\(dir)')")
            ctx.eval("fs.writeFileSync('\(dir)/f.txt', 'x')")
            ctx.eval("fs.mkdirSync('\(dir)/d')")
            ctx.eval("""
                var entries = fs.readdirSync('\(dir)', true);
                var file = entries.find(function(e) { return e.name === 'f.txt'; });
                var subdir = entries.find(function(e) { return e.name === 'd'; });
                var __fileIsFile = file.isFile();
                var __dirIsDir = subdir.isDirectory();
            """)
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("__fileIsFile") == true)
            #expect(ctx.evalBool("__dirIsDir") == true)
        }

        @Test("rmdirSync removes an empty directory but throws ENOTEMPTY for a non-empty one")
        func testRmdir() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("empty")
            ctx.eval("fs.mkdirSync('\(dir)')")
            ctx.eval("fs.rmdirSync('\(dir)')")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.existsSync('\(dir)')") == false)

            let dir2 = ctx.path("nonempty")
            ctx.eval("fs.mkdirSync('\(dir2)')")
            ctx.eval("fs.writeFileSync('\(dir2)/x.txt', 'x')")
            let code = ctx.evalString("""
                (function() {
                    try { fs.rmdirSync('\(dir2)'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "ENOTEMPTY")
        }

        @Test("rmSync with recursive removes non-empty directories")
        func testRmRecursive() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("tree")
            ctx.eval("fs.mkdirSync('\(dir)')")
            ctx.eval("fs.writeFileSync('\(dir)/x.txt', 'x')")
            ctx.eval("fs.rmSync('\(dir)', true, false)")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.existsSync('\(dir)')") == false)
        }

        @Test("rmSync with force does not throw for a missing path")
        func testRmForce() throws {
            let ctx = try NodeFSTestContext()
            ctx.eval("fs.rmSync('\(ctx.path("missing"))', false, true)")
            #expect(!ctx.hadException)
        }
    }

    // MARK: Metadata and links

    @Suite("fs sync metadata and links")
    struct NodeFSSyncMetadataTests {
        @Test("statSync reports size, isFile and isDirectory")
        func testStat() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("stat.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'hello')")
            #expect(ctx.evalInt("fs.statSync('\(p)').size") == 5)
            #expect(ctx.evalBool("fs.statSync('\(p)').isFile()") == true)
            #expect(ctx.evalBool("fs.statSync('\(p)').isDirectory()") == false)
        }

        @Test("statSync with throwIfNoEntry=false returns undefined for a missing path")
        func testStatNoThrow() throws {
            let ctx = try NodeFSTestContext()
            #expect(ctx.evalString("typeof fs.statSync('\(ctx.path("nope"))', false)") == "undefined")
            #expect(!ctx.hadException)
        }

        @Test("symlinkSync + lstatSync/readlinkSync/statSync round-trip")
        func testSymlink() throws {
            let ctx = try NodeFSTestContext()
            let target = ctx.path("target.txt")
            let link = ctx.path("link.txt")
            ctx.eval("fs.writeFileSync('\(target)', 'x')")
            ctx.eval("fs.symlinkSync('\(target)', '\(link)')")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.lstatSync('\(link)').isSymbolicLink()") == true)
            #expect(ctx.evalBool("fs.statSync('\(link)').isFile()") == true)
            #expect(ctx.evalString("fs.readlinkSync('\(link)')") == target)
        }

        @Test("linkSync creates a hard link sharing content")
        func testHardLink() throws {
            let ctx = try NodeFSTestContext()
            let a = ctx.path("a.txt")
            let b = ctx.path("b.txt")
            ctx.eval("fs.writeFileSync('\(a)', 'shared')")
            ctx.eval("fs.linkSync('\(a)', '\(b)')")
            #expect(!ctx.hadException)
            #expect(ctx.evalString("fs.readFileSync('\(b)')") == "shared")
        }

        @Test("renameSync moves a file")
        func testRename() throws {
            let ctx = try NodeFSTestContext()
            let a = ctx.path("old.txt")
            let b = ctx.path("new.txt")
            ctx.eval("fs.writeFileSync('\(a)', 'x')")
            ctx.eval("fs.renameSync('\(a)', '\(b)')")
            #expect(!ctx.hadException)
            #expect(ctx.evalBool("fs.existsSync('\(a)')") == false)
            #expect(ctx.evalBool("fs.existsSync('\(b)')") == true)
        }

        @Test("copyFileSync copies content; COPYFILE_EXCL rejects an existing destination")
        func testCopyFile() throws {
            let ctx = try NodeFSTestContext()
            let a = ctx.path("src.txt")
            let b = ctx.path("dst.txt")
            ctx.eval("fs.writeFileSync('\(a)', 'copied')")
            ctx.eval("fs.copyFileSync('\(a)', '\(b)', 0)")
            #expect(!ctx.hadException)
            #expect(ctx.evalString("fs.readFileSync('\(b)')") == "copied")

            let code = ctx.evalString("""
                (function() {
                    try { fs.copyFileSync('\(a)', '\(b)', fs.constants.COPYFILE_EXCL); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "EEXIST")
        }

        @Test("realpathSync resolves symlinks to a canonical path")
        func testRealpath() throws {
            let ctx = try NodeFSTestContext()
            let target = ctx.path("real.txt")
            let link = ctx.path("alias.txt")
            ctx.eval("fs.writeFileSync('\(target)', 'x')")
            ctx.eval("fs.symlinkSync('\(target)', '\(link)')")
            // Compare against realpath(3) directly, not the raw temp path: macOS's temporary
            // directory is itself reached through a symlink (/var -> /private/var). Foundation's
            // URL.resolvingSymlinksInPath() special-cases /var back to its unresolved form, so
            // it can't be used here - go straight to the same C function realpathSync itself uses.
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            #expect(unsafe realpath(target, &buffer) != nil)
            let canonicalTarget = unsafe String(cString: buffer)
            #expect(ctx.evalString("fs.realpathSync('\(link)')") == canonicalTarget)
        }

        @Test("accessSync succeeds for a writable file and throws ENOENT for a missing one")
        func testAccess() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("access.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'x')")
            ctx.eval("fs.accessSync('\(p)', fs.constants.W_OK)")
            #expect(!ctx.hadException)

            let code = ctx.evalString("""
                (function() {
                    try { fs.accessSync('\(ctx.path("nope"))'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "ENOENT")
        }

        @Test("truncateSync shortens a file")
        func testTruncate() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("trunc.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'Hello, world!')")
            ctx.eval("fs.truncateSync('\(p)', 5)")
            #expect(!ctx.hadException)
            #expect(ctx.evalString("fs.readFileSync('\(p)')") == "Hello")
        }
    }

    // MARK: Error codes

    @Suite("fs sync error codes")
    struct NodeFSSyncErrorTests {
        @Test("readFileSync on a missing file throws ENOENT")
        func testReadMissing() throws {
            let ctx = try NodeFSTestContext()
            let code = ctx.evalString("""
                (function() {
                    try { fs.readFileSync('\(ctx.path("nope.txt"))'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "ENOENT")
        }

        @Test("readFileSync rejects a non-utf8 encoding argument")
        func testReadBadEncoding() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("enc.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'x')")
            let code = ctx.evalString("""
                (function() {
                    try { fs.readFileSync('\(p)', 'latin1'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "ERR_INVALID_ARG_VALUE")
        }

        @Test("mkdirSync without recursive throws EEXIST on an existing directory")
        func testMkdirExisting() throws {
            let ctx = try NodeFSTestContext()
            let dir = ctx.path("dup")
            ctx.eval("fs.mkdirSync('\(dir)')")
            let code = ctx.evalString("""
                (function() {
                    try { fs.mkdirSync('\(dir)'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "EEXIST")
        }

        @Test("writeFileSync with 'wx' flag throws EEXIST if the file already exists")
        func testWriteExclFlag() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("excl.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'x')")
            let code = ctx.evalString("""
                (function() {
                    try { fs.writeFileSync('\(p)', 'y', 'wx'); return null; }
                    catch (e) { return e.code; }
                })()
            """)
            #expect(code == "EEXIST")
        }

        @Test("thrown errors carry syscall, path and errno properties")
        func testErrorShape() throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("missing-shape.txt")
            ctx.eval("""
                var __syscall = null, __path = null, __errno = null;
                try { fs.readFileSync('\(p)'); }
                catch (e) { __syscall = e.syscall; __path = e.path; __errno = e.errno; }
            """)
            #expect(ctx.evalString("__syscall") == "open")
            #expect(ctx.evalString("__path") == p)
            #expect(ctx.evalInt("__errno") == -2)
        }
    }

    // MARK: fs.promises

    @Suite("fs.promises")
    struct NodeFSPromisesTests {
        @Test("promises.writeFile then promises.readFile round-trips content")
        func testPromiseRoundTrip() async throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("async.txt")
            ctx.eval("""
                var __done = false, __result = null;
                fs.promises.writeFile('\(p)', 'async hello').then(function() {
                    return fs.promises.readFile('\(p)');
                }).then(function(text) {
                    __result = text;
                    __done = true;
                });
            """)
            let ok = await ctx.waitForAsync { ctx.evalBool("__done") == true }
            #expect(ok)
            #expect(ctx.evalString("__result") == "async hello")
        }

        @Test("promises.readFile rejects with an ENOENT-coded error for a missing file")
        func testPromiseRejects() async throws {
            let ctx = try NodeFSTestContext()
            ctx.eval("""
                var __done = false, __code = null;
                fs.promises.readFile('\(ctx.path("nope.txt"))').catch(function(e) {
                    __code = e.code;
                    __done = true;
                });
            """)
            let ok = await ctx.waitForAsync { ctx.evalBool("__done") == true }
            #expect(ok)
            #expect(ctx.evalString("__code") == "ENOENT")
        }

        @Test("promises.stat resolves to a Stats object")
        func testPromiseStat() async throws {
            let ctx = try NodeFSTestContext()
            let p = ctx.path("pstat.txt")
            ctx.eval("fs.writeFileSync('\(p)', 'hello')")
            ctx.eval("""
                var __done = false, __size = null, __isFile = null;
                fs.promises.stat('\(p)').then(function(st) {
                    __size = st.size;
                    __isFile = st.isFile();
                    __done = true;
                });
            """)
            let ok = await ctx.waitForAsync { ctx.evalBool("__done") == true }
            #expect(ok)
            #expect(ctx.evalInt("__size") == 5)
            #expect(ctx.evalBool("__isFile") == true)
        }
    }
}
