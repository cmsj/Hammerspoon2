//
//  HSNPMIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Mock configuration files

/// Two organisation scopes on GitHub Packages sharing one token, a third scope on an internal
/// registry whose token comes from the environment, basic auth for the public registry, and
/// both comment styles.
private let mockNPMRC = """
# GitHub Packages serves both of our organisations
@NAMESPACE1:registry=https://npm.pkg.github.com
@NAMESPACE2:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=ghp_mock_token

; Internal registry, token from the environment
@internal:registry=https://npm.example.com/registry/
//npm.example.com/registry/:_authToken=${HS_TEST_NPM_TOKEN}

//registry.npmjs.org/:_auth="dXNlcjpwYXNz"
"""

private let mockPackageJSON = """
{
  "name": "my-hammerspoon-config",
  "dependencies": {
    "@NAMESPACE1/logger": "^1.2.0",
    "@NAMESPACE2/utils": "~0.3.1",
    "dayjs": "1.11.x"
  }
}
"""

private let mockEnvironment = ["HS_TEST_NPM_TOKEN": "internal-secret"]

@Suite("hs.npm tests")
struct HSNPMTests {

    // MARK: - .npmrc parsing and routing

    @Suite(".npmrc parsing")
    struct NPMRCTests {
        private let rc = NPMRC.parse(mockNPMRC, environment: mockEnvironment)

        @Test("Both scopes map to GitHub Packages, with a normalised trailing slash")
        func testScopedRegistries() {
            #expect(rc.scopedRegistries["@NAMESPACE1"] == URL(string: "https://npm.pkg.github.com/"))
            #expect(rc.scopedRegistries["@NAMESPACE2"] == URL(string: "https://npm.pkg.github.com/"))
            #expect(rc.scopedRegistries["@internal"] == URL(string: "https://npm.example.com/registry/"))
        }

        @Test("Unscoped and unknown-scope packages fall back to the public registry")
        func testDefaultRegistry() {
            #expect(rc.defaultRegistry == NPMRC.publicRegistry)
            #expect(rc.registry(for: "dayjs") == NPMRC.publicRegistry)
            #expect(rc.registry(for: "@unknown/thing") == NPMRC.publicRegistry)
            #expect(rc.registry(for: "@NAMESPACE1/logger") == URL(string: "https://npm.pkg.github.com/"))
        }

        @Test("A registry= line overrides the default")
        func testRegistryOverride() {
            let rc = NPMRC.parse("registry=https://mirror.example.com/npm")
            #expect(rc.defaultRegistry == URL(string: "https://mirror.example.com/npm/"))
        }

        @Test("Comments and blank lines are ignored")
        func testComments() {
            let rc = NPMRC.parse("# @a:registry=https://a.example.com\n; @b:registry=https://b.example.com\n\n")
            #expect(rc.scopedRegistries.isEmpty)
            #expect(rc.credentials.isEmpty)
        }

        @Test("Scoped package names are percent-encoded in the metadata path")
        func testMetadataURL() {
            #expect(rc.metadataURL(for: "@NAMESPACE1/logger")?.absoluteString == "https://npm.pkg.github.com/@NAMESPACE1%2Flogger")
            #expect(rc.metadataURL(for: "dayjs")?.absoluteString == "https://registry.npmjs.org/dayjs")
        }

        @Test("_authToken becomes a Bearer header for the registry and its tarballs")
        func testBearerToken() throws {
            let metadata = try #require(rc.metadataURL(for: "@NAMESPACE2/utils"))
            #expect(rc.authorization(for: metadata) == "Bearer ghp_mock_token")
            let tarball = try #require(URL(string: "https://npm.pkg.github.com/download/@NAMESPACE1/logger/1.2.3/abcdef"))
            #expect(rc.authorization(for: tarball) == "Bearer ghp_mock_token")
        }

        @Test("${VAR} in a token expands from the environment, and only matches under its path")
        func testEnvironmentToken() throws {
            #expect(rc.authorization(for: try #require(URL(string: "https://npm.example.com/registry/@internal%2Ftool"))) == "Bearer internal-secret")
            #expect(rc.authorization(for: try #require(URL(string: "https://npm.example.com/other/thing"))) == nil)
        }

        @Test("_auth becomes a Basic header, quotes stripped")
        func testBasicAuth() throws {
            #expect(rc.authorization(for: try #require(URL(string: "https://registry.npmjs.org/dayjs"))) == "Basic dXNlcjpwYXNz")
        }

        @Test("No credential is sent to a host .npmrc doesn't name")
        func testUnknownHost() throws {
            #expect(rc.authorization(for: try #require(URL(string: "https://cdn.example.net/x.tgz"))) == nil)
        }
    }

    // MARK: - package.json

    @Suite("package.json dependencies")
    struct PackageJSONTests {
        @Test("dependencies are read as name/range pairs in name order")
        func testDependencies() throws {
            let json = try #require(JSONSerialization.jsonObject(with: Data(mockPackageJSON.utf8)) as? [String: Any])
            let deps = NPMInstaller.dependencies(of: json)
            #expect(deps.map(\.name) == ["@NAMESPACE1/logger", "@NAMESPACE2/utils", "dayjs"])
            #expect(deps.map(\.range) == ["^1.2.0", "~0.3.1", "1.11.x"])
        }
    }

    // MARK: - Semver

    @Suite("semver")
    struct SemVerTests {
        @Test("Versions parse and order correctly")
        func testParseAndOrder() throws {
            #expect(SemVer("v1.2.3") == SemVer(1, 2, 3))
            #expect(SemVer("1.2") == nil)
            #expect(SemVer("1.2.3-beta.1")?.prerelease == "beta.1")
            #expect(try #require(SemVer("1.2.3-beta.1")) < #require(SemVer("1.2.3")))
            #expect(try #require(SemVer("1.10.0")) > #require(SemVer("1.9.9")))
        }

        @Test("Ranges match like npm", arguments: [
            ("1.2.3", "^1.2.0", true), ("2.0.0", "^1.2.0", false), ("1.1.0", "^1.2.0", false),
            ("0.3.9", "~0.3.1", true), ("0.4.0", "~0.3.1", false),
            ("0.0.3", "^0.0.3", true), ("0.0.4", "^0.0.3", false), ("0.2.9", "^0.2.3", true), ("0.3.0", "^0.2.3", false),
            ("1.11.5", "1.11.x", true), ("1.12.0", "1.11.x", false), ("1.5.0", "1", true), ("2.0.0", "1", false),
            ("1.5.0", ">=1.2.0 <2.0.0", true), ("2.0.0", ">=1.2.0 <2.0.0", false),
            ("1.5.0", ">= 1.2.3 < 2", true), ("2.0.0", ">= 1.2.3 < 2", false), ("1.2.2", ">= 1.2.3 < 2", false), ("1.5.0", "^ 1.2", true), ("1.3.0", ">1.2", true), ("1.2.9", ">1.2", false),
            ("3.0.0", "1 || 3", true), ("2.0.0", "1 || 3", false),
            ("1.5.0", "1.2.3 - 1.8.0", true), ("1.8.1", "1.2.3 - 1.8.0", false), ("1.8.9", "1.2.3 - 1.8", true),
            ("2.1.0", "*", true), ("2.1.0", "", true), ("1.2.3", "1.2.3", true), ("1.2.3", "=1.2.3", true), ("1.2.4", "1.2.3", false),
            ("1.0.0-beta.1", "^1.0.0", false), ("1.0.0-beta.1", "1.0.0-beta.1", true),
            ("1.2.3", "^1.2.3-beta.1", true), ("1.9.0", "^1.2.3-beta.1", true), ("2.0.0", "^1.2.3-beta.1", false), ("1.2.2", "^1.2.3-beta.1", false),
            ("2.0.0", "^1.2.3.4", false), ("2.0.0", "latest", false), ("2.0.0", "git+https://example.com/x.git", false),
        ])
        func testSatisfies(version: String, range: String, expected: Bool) throws {
            #expect(try #require(SemVer(version)).satisfies(range) == expected, "\(version) satisfies '\(range)'")
        }

        @Test("selectVersion prefers dist-tags, then the highest matching release")
        func testSelectVersion() {
            let versions = ["1.0.0", "1.2.3", "1.3.0-beta.1", "2.0.0"]
            let tags = ["latest": "2.0.0", "next": "1.3.0-beta.1"]
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "^1.2.0") == "1.2.3")
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "^1") == "1.2.3")
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "latest") == "2.0.0")
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "next") == "1.3.0-beta.1")
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "") == "2.0.0")
            #expect(NPMInstaller.selectVersion(from: versions, tags: tags, range: "^3") == nil)
        }
    }

    // MARK: - Integrity

    @Suite("tarball integrity")
    struct IntegrityTests {
        private let data = Data("hello".utf8)

        @Test("A matching sha512 SRI passes, a wrong one throws")
        func testSRI() throws {
            let good = "sha512-m3HSJL1i83hdltRq0+o9czGb+8KJDKra4t/3JRlnPKcjI8PZm6XBHXx6zG4UuMXaDEZjR1wuXDre9G9zvN7AQw=="
            try NPMInstaller.verify(data, integrity: good, shasum: nil)
            #expect(throws: NPMError.self) { try NPMInstaller.verify(Data("hellp".utf8), integrity: good, shasum: nil) }
        }

        @Test("Legacy shasum is checked when no integrity is given")
        func testShasum() throws {
            try NPMInstaller.verify(data, integrity: nil, shasum: "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
            #expect(throws: NPMError.self) { try NPMInstaller.verify(data, integrity: nil, shasum: "0000") }
            try NPMInstaller.verify(data, integrity: nil, shasum: nil)
        }
    }

    // MARK: - require() of installed packages

    @Suite("require() from node_modules")
    struct RequireNodeModulesTests {
        @Test("A scoped package resolves through its package.json main")
        func testScopedPackageMain() throws {
            let ctx = try RequireContext()
            try ctx.write("node_modules/@NAMESPACE1/logger/package.json", #"{ "name": "@NAMESPACE1/logger", "main": "lib/logger" }"#)
            try ctx.write("node_modules/@NAMESPACE1/logger/lib/logger.js", "module.exports = { name: 'logger', fmt: require('./format') }")
            try ctx.write("node_modules/@NAMESPACE1/logger/lib/format.js", "module.exports = (s) => '[' + s + ']'")
            let main = try ctx.write("main.js", "module.exports = require('@NAMESPACE1/logger').fmt('ok')")
            #expect(ctx.eval("require('\(main)')")?.toString() == "[ok]")
            #expect(!ctx.hadException)
        }

        @Test("A package without main falls back to index.js, found by walking up the tree")
        func testWalkUpToIndex() throws {
            let ctx = try RequireContext()
            try ctx.write("node_modules/dayjs/index.js", "module.exports = 'dayjs-root'")
            try ctx.write("node_modules/dayjs/plugin/utc.js", "module.exports = 'utc'")
            let deep = try ctx.write("src/deep/er/mod.js", "module.exports = require('dayjs') + '+' + require('dayjs/plugin/utc')")
            #expect(ctx.eval("require('\(deep)')")?.toString() == "dayjs-root+utc")
            #expect(!ctx.hadException)
        }

        @Test("Each package is evaluated once, so the same exports object is shared")
        func testCached() throws {
            let ctx = try RequireContext()
            try ctx.write("node_modules/counter/index.js", "module.exports = { n: 0 }")
            let a = try ctx.write("a.js", "module.exports = require('counter')")
            let b = try ctx.write("b.js", "module.exports = require('counter')")
            #expect(ctx.eval("require('\(a)') === require('\(b)')")?.toBool() == true)
        }

        @Test("A bare specifier with no package installed throws")
        func testMissingPackage() throws {
            let ctx = try RequireContext()
            let main = try ctx.write("main.js", "require('not-installed')")
            ctx.eval("require('\(main)')")
            #expect(ctx.hadException)
            #expect(ctx.eval("require('util') !== undefined")?.toBool() == true)
        }
    }

    // MARK: - JS API

    @Suite("hs.npm API")
    struct HSNPMAPITests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNPMModule.self, as: "npm")
            return harness
        }

        @Test("install is a function returning a Promise")
        func testInstallShape() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.npm.install") == "function")
            harness.eval("var p = hs.npm.install(); p.catch(() => {})")
            #expect(harness.evalTypeOf("p.then") == "function")
            #expect(!harness.hasException)
        }

        @Test("install() rejects when the config directory has no package.json")
        func testInstallRejectsWithoutPackageJSON() async {
            let harness = makeHarness()
            var rejected = false
            harness.registerCallback("rejected") { rejected = true }
            harness.eval("hs.npm.install().catch(() => __test_callback('rejected'))")
            #expect(await harness.waitForAsync(timeout: 2.0) { rejected })
        }
    }
}
