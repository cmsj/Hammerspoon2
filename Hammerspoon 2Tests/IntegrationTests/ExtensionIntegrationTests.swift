//
//  ExtensionIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
@testable import Hammerspoon_2
import HammerspoonSDK

// MARK: - Fixtures

/// The test extension (Helpers/TestExtension), which the test target's "Build Test Extension"
/// phase builds next to the app.
///
/// Its code can only be loaded into the test process once, from one place: a second copy at
/// another path defines the same classes. So tests that load it use the built bundle where it
/// is, and tests that need a broken or changed bundle use a copy that never gets as far as
/// loading code.
private enum TestExtensionFixture {
    static let name = "hs2.testextension"

    static var directory: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("TestExtensions")
    }

    /// Copies the extension into a new extensions directory.
    /// - Parameters:
    ///   - newName: The name to give the copy, in its file name and Info.plist
    ///   - editInfo: Changes to make to its Info.plist
    ///   - resign: Whether to sign the copy again after changing it
    /// - Returns: The new extensions directory
    static func copy(as newName: String = name,
                     editInfo: (inout [String: Any]) -> Void = { _ in },
                     resign: Bool = true) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hs2-extensions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = ExtensionManifest.bundleURL(forName: newName, in: directory)
        try FileManager.default.copyItem(at: ExtensionManifest.bundleURL(forName: name, in: Self.directory), to: bundle)

        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        var info = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any])
        info["HSModuleName"] = newName
        editInfo(&info)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plistURL)
        if newName != name {
            let scripts = bundle.appendingPathComponent("Contents/Resources")
            try FileManager.default.moveItem(at: scripts.appendingPathComponent("\(name).js"),
                                             to: scripts.appendingPathComponent("\(newName).js"))
        }
        if resign {
            try codesign(["--force", "--sign", "-", bundle.path])
        }
        return directory
    }

    static func codesign(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "codesign \(arguments.joined(separator: " ")) failed")
    }
}

/// Answers approval requests with a fixed answer, recording each one
private final class RecordingApprover: ExtensionApprover {
    var answer: Bool
    private(set) var requests: [String] = []

    init(answer: Bool) {
        self.answer = answer
    }

    func approve(_ manifest: ExtensionManifest, signature: ExtensionSignature) -> Bool {
        requests.append(manifest.name)
        return answer
    }
}

/// A loader with its own approvals, which are removed when it's released
private final class LoaderSetup {
    let approver: RecordingApprover
    let defaults: UserDefaults
    let loader: ExtensionLoader
    private let suiteName = "net.tenshu.Hammerspoon-2Tests.extensions.\(UUID().uuidString)"

    init(directory: URL = TestExtensionFixture.directory,
         enabled: Bool = true,
         approve: Bool = true,
         hostSDKVersion: HSSDKVersion = HSSDK.version) {
        approver = RecordingApprover(answer: approve)
        defaults = UserDefaults(suiteName: suiteName)!
        loader = ExtensionLoader(directory: { directory },
                                 isEnabled: { enabled },
                                 approver: approver,
                                 approvals: ExtensionApprovals(defaults: defaults),
                                 hostSDKVersion: hostSDKVersion)
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// A JSExport protocol in the retained-result method family, which an extension must not have
@objc private protocol RetainedResultTestAPI: JSExport {
    @objc func copyThing() -> NSObject
    @objc func thing() -> NSObject
}

@objc private final class RetainedResultTestObject: NSObject, RetainedResultTestAPI {
    func copyThing() -> NSObject { NSObject() }
    func thing() -> NSObject { NSObject() }
}

// MARK: - Tests

@Suite("Extension tests")
struct ExtensionTests {

    @Suite("SDK versions")
    struct SDKVersionTests {
        @Test("Versions parse from major.minor strings", arguments: [
            ("1.0", HSSDKVersion(major: 1, minor: 0)),
            ("2.13", HSSDKVersion(major: 2, minor: 13)),
        ])
        func parse(string: String, expected: HSSDKVersion) {
            #expect(HSSDKVersion(string) == expected)
        }

        @Test("Malformed versions don't parse", arguments: ["", "1", "1.", ".1", "1.2.3", "a.b", "-1.0"])
        func parseInvalid(string: String) {
            #expect(HSSDKVersion(string) == nil)
        }

        @Test("A host supports extensions built for its major version and an equal or older minor")
        func supports() {
            let host = HSSDKVersion(major: 1, minor: 2)
            #expect(host.supports(HSSDKVersion(major: 1, minor: 0)))
            #expect(host.supports(HSSDKVersion(major: 1, minor: 2)))
            #expect(!host.supports(HSSDKVersion(major: 1, minor: 3)))
            #expect(!host.supports(HSSDKVersion(major: 0, minor: 9)))
            #expect(!host.supports(HSSDKVersion(major: 2, minor: 0)))
        }
    }

    @Suite("The SDK in the app bundle")
    struct EmbeddedSDKTests {
        @Test("The app's copy of the SDK has its public interface, and nothing that exposes host-only API")
        func publicInterfaceOnly() throws {
            let module = try #require(Bundle.main.privateFrameworksURL)
                .appendingPathComponent("HammerspoonSDK.framework/Modules/HammerspoonSDK.swiftmodule")
            let files = try FileManager.default.contentsOfDirectory(atPath: module.path)
            let isPrivate: (String) -> Bool = { $0.hasSuffix(".private.swiftinterface") || $0.hasSuffix(".package.swiftinterface") }
            #expect(files.contains { $0.hasSuffix(".swiftinterface") && !isPrivate($0) }, "Extension authors need the public interface to build against: \(files)")
            #expect(!files.contains { isPrivate($0) || $0.hasSuffix(".swiftmodule") || $0 == "Project" }, "Only the public interface should ship: \(files)")
        }
    }

    @Suite("Refusing extensions before loading their code")
    struct RefusalTests {
        @Test("Nothing loads while extensions are turned off, and nobody is asked")
        func disabled() {
            let setup = LoaderSetup(enabled: false)
            #expect(throws: ExtensionError.disabled) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            #expect(setup.approver.requests.isEmpty)
        }

        @Test("Names that aren't plain file names are refused", arguments: ["", "../escape", "a/b", ".hidden", "with space", "-dash"])
        func invalidName(name: String) {
            let setup = LoaderSetup()
            #expect(throws: ExtensionError.invalidName(name)) {
                try setup.loader.load(named: name)
            }
        }

        @Test("A missing extension says where it was looked for")
        func notFound() {
            let setup = LoaderSetup()
            let expected = ExtensionManifest.bundleURL(forName: "hs2.missing", in: TestExtensionFixture.directory)
            #expect(throws: ExtensionError.notFound(name: "hs2.missing", expectedAt: expected)) {
                try setup.loader.load(named: "hs2.missing")
            }
        }

        @Test("An extension whose Info.plist names another extension is refused")
        func nameMismatch() throws {
            let directory = try TestExtensionFixture.copy(editInfo: { $0["HSModuleName"] = "hs2.other" })
            let setup = LoaderSetup(directory: directory)
            let error = #expect(throws: ExtensionError.self) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            guard case .invalidBundle = error else {
                Issue.record("Expected invalidBundle, got \(String(describing: error))")
                return
            }
        }

        @Test("An extension built for another major SDK version is refused")
        func incompatibleSDK() {
            let setup = LoaderSetup(hostSDKVersion: HSSDKVersion(major: 2, minor: 0))
            #expect(throws: ExtensionError.incompatibleSDK(name: TestExtensionFixture.name,
                                                           required: HSSDKVersion(major: 1, minor: 0),
                                                           available: HSSDKVersion(major: 2, minor: 0))) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            #expect(setup.approver.requests.isEmpty)
        }

        @Test("An unsigned extension is refused without asking")
        func unsigned() throws {
            let directory = try TestExtensionFixture.copy(resign: false)
            let bundle = ExtensionManifest.bundleURL(forName: TestExtensionFixture.name, in: directory)
            try TestExtensionFixture.codesign(["--remove-signature", bundle.path])
            let setup = LoaderSetup(directory: directory)
            let error = #expect(throws: ExtensionError.self) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            guard case .invalidSignature = error else {
                Issue.record("Expected invalidSignature, got \(String(describing: error))")
                return
            }
            #expect(setup.approver.requests.isEmpty)
        }

        @Test("An extension changed after it was signed is refused without asking")
        func tampered() throws {
            let directory = try TestExtensionFixture.copy()
            let script = ExtensionManifest.bundleURL(forName: TestExtensionFixture.name, in: directory)
                .appendingPathComponent("Contents/Resources/\(TestExtensionFixture.name).js")
            try "ext.greet = () => 'tampered';".write(to: script, atomically: true, encoding: .utf8)
            let setup = LoaderSetup(directory: directory)
            let error = #expect(throws: ExtensionError.self) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            guard case .invalidSignature = error else {
                Issue.record("Expected invalidSignature, got \(String(describing: error))")
                return
            }
            #expect(setup.approver.requests.isEmpty)
        }

        @Test("An extension the user doesn't allow isn't loaded, and they're asked again next time")
        func notApproved() {
            let setup = LoaderSetup(approve: false)
            #expect(throws: ExtensionError.notApproved(name: TestExtensionFixture.name)) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            #expect(throws: ExtensionError.notApproved(name: TestExtensionFixture.name)) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }
            #expect(setup.approver.requests == [TestExtensionFixture.name, TestExtensionFixture.name])
            #expect(!setup.loader.isLoaded(TestExtensionFixture.name))
        }

        @Test("Approval is for one build: a changed extension is asked about again")
        func approvalIsPerBuild() throws {
            let setup = LoaderSetup(approve: false)
            let original = try ExtensionSignature.verify(bundleAt: ExtensionManifest.bundleURL(forName: TestExtensionFixture.name, in: TestExtensionFixture.directory),
                                                         name: TestExtensionFixture.name)
            ExtensionApprovals(defaults: setup.defaults).approve(TestExtensionFixture.name, signature: original)

            // Same name, different contents, so a different cdhash
            let directory = try TestExtensionFixture.copy(editInfo: { $0["CFBundleVersion"] = "2" })
            let changed = try ExtensionSignature.verify(bundleAt: ExtensionManifest.bundleURL(forName: TestExtensionFixture.name, in: directory),
                                                        name: TestExtensionFixture.name)
            #expect(changed.cdHash != original.cdHash)
            #expect(!ExtensionApprovals(defaults: setup.defaults).isApproved(TestExtensionFixture.name, signature: changed))

            let changedSetupLoader = ExtensionLoader(directory: { directory }, isEnabled: { true },
                                                     approver: setup.approver,
                                                     approvals: ExtensionApprovals(defaults: setup.defaults))
            #expect(throws: ExtensionError.notApproved(name: TestExtensionFixture.name)) {
                try changedSetupLoader.load(named: TestExtensionFixture.name)
            }
            #expect(setup.approver.requests == [TestExtensionFixture.name])
        }
    }

    @Suite("Loading extensions")
    struct LoadingTests {
        @Test("An approved extension loads, and isn't asked about again")
        func loadsOnce() throws {
            let setup = LoaderSetup()
            let loaded = try setup.loader.load(named: TestExtensionFixture.name)
            #expect(loaded.manifest.name == TestExtensionFixture.name)
            #expect(loaded.signature.isAdHoc)
            #expect(NSStringFromClass(loaded.moduleType) == "HS2TestExtensionModule")

            // A second loader with the same approvals doesn't ask either
            let second = ExtensionLoader(directory: { TestExtensionFixture.directory }, isEnabled: { true },
                                         approver: setup.approver,
                                         approvals: ExtensionApprovals(defaults: setup.defaults))
            _ = try second.load(named: TestExtensionFixture.name)
            _ = try setup.loader.load(named: TestExtensionFixture.name)
            #expect(setup.approver.requests == [TestExtensionFixture.name])
        }

        @Test("Approvals record who signed the build, and can be removed")
        func approvalRecords() throws {
            let setup = LoaderSetup()
            let approvals = ExtensionApprovals(defaults: setup.defaults)
            let adHoc = ExtensionSignature(cdHash: "aa", teamIdentifier: nil, signerName: nil)
            let signed = ExtensionSignature(cdHash: "bb", teamIdentifier: "ABCDE12345", signerName: "Developer ID Application: Example Ltd (ABCDE12345)")
            approvals.approve("com.example.zed", signature: adHoc)
            approvals.approve("com.example.alpha", signature: signed)

            #expect(approvals.all.map(\.name) == ["com.example.alpha", "com.example.zed"])
            #expect(approvals.all.first?.signerName == signed.signerName)
            #expect(approvals.all.last?.signerName == nil)

            approvals.revoke("com.example.alpha")
            #expect(approvals.all.map(\.name) == ["com.example.zed"])
            #expect(!approvals.isApproved("com.example.alpha", signature: signed))

            approvals.revokeAll()
            #expect(approvals.all.isEmpty)
        }

        @Test("Removing the approval of a loaded extension means the user is asked again before it's used")
        func revokedAfterLoading() throws {
            let setup = LoaderSetup()
            _ = try setup.loader.load(named: TestExtensionFixture.name)
            #expect(setup.approver.requests == [TestExtensionFixture.name])

            ExtensionApprovals(defaults: setup.defaults).revoke(TestExtensionFixture.name)
            setup.approver.answer = false
            #expect(throws: ExtensionError.notApproved(name: TestExtensionFixture.name)) {
                try setup.loader.load(named: TestExtensionFixture.name)
            }

            setup.approver.answer = true
            _ = try setup.loader.load(named: TestExtensionFixture.name)
            #expect(setup.approver.requests == Array(repeating: TestExtensionFixture.name, count: 3))
        }

        @Test("An extension whose classes clash with loaded ones is unusable")
        func classCollision() throws {
            // Load the original first, so its classes are the ones the runtime knows by name
            _ = try LoaderSetup().loader.load(named: TestExtensionFixture.name)

            let copyName = "hs2.testextension-copy"
            let directory = try TestExtensionFixture.copy(as: copyName)
            let setup = LoaderSetup(directory: directory)
            let error = #expect(throws: ExtensionError.self) {
                try setup.loader.load(named: copyName)
            }
            guard case .classCollision(_, let classes) = error else {
                Issue.record("Expected classCollision, got \(String(describing: error))")
                return
            }
            #expect(classes.contains("HS2TestExtensionModule"))

            // The code can't be unloaded, so it stays unusable, without asking again
            #expect(throws: ExtensionError.self) {
                try setup.loader.load(named: copyName)
            }
            #expect(setup.approver.requests == [copyName])
        }

        @Test("Selectors in the retained-result method families are detected")
        func retainedFamilies() {
            #expect(ExtensionLoader.isInRetainedFamily("copyThing"))
            #expect(ExtensionLoader.isInRetainedFamily("new"))
            #expect(ExtensionLoader.isInRetainedFamily("_allocFoo:"))
            #expect(ExtensionLoader.isInRetainedFamily("mutableCopy"))
            #expect(!ExtensionLoader.isInRetainedFamily("copyright"))
            #expect(!ExtensionLoader.isInRetainedFamily("newline"))
            #expect(!ExtensionLoader.isInRetainedFamily("thing"))
            #expect(ExtensionLoader.retainedResultSelectors(of: [RetainedResultTestObject.self]) == ["copyThing"])
        }
    }

    @Suite("require('ext:...')")
    struct RequireTests {
        /// A harness with `require()` set up to load extensions through `setup`
        private func makeHarness(_ setup: LoaderSetup = LoaderSetup()) throws -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModuleRoot(extensionLoader: setup.loader)
            try harness.installRequire()
            return harness
        }

        @Test("require() returns the extension's module")
        func returnsModule() throws {
            let harness = try makeHarness()
            harness.eval("var ext = require('ext:hs2.testextension')")
            #expect(!harness.hasException)
            #expect(harness.evalString("String(ext)") == "<hs2.testextension>")
            #expect(harness.evalDouble("ext.add(2, 3)") == 5)
        }

        @Test("Requiring an extension twice gives the same module")
        func sameModule() throws {
            let harness = try makeHarness()
            #expect(harness.evalBool("require('ext:hs2.testextension') === require('ext:hs2.testextension')") == true)
        }

        @Test("The extension's enhancement script runs with the module as ext")
        func enhancementScript() throws {
            let harness = try makeHarness()
            #expect(harness.evalString("require('ext:hs2.testextension').greet('World')") == "Hello, World, from <hs2.testextension>")
        }

        @Test("nil returned by an extension reaches JavaScript as null")
        func nilIsNull() throws {
            let harness = try makeHarness()
            #expect(harness.evalBool("require('ext:hs2.testextension').nothing() === null") == true)
        }

        @Test("An extension can return the SDK's shared types")
        func sharedTypes() throws {
            let harness = try makeHarness()
            harness.eval("var red = require('ext:hs2.testextension').red()")
            #expect(harness.evalString("red.typeName") == "HSColor")
            #expect(harness.evalBool("red instanceof HSColor") == true)
        }

        @Test("A failure throws a JavaScript Error with a code")
        func errors() throws {
            let harness = try makeHarness(LoaderSetup(enabled: false))
            #expect(harness.evalString("""
                (function () {
                    try { require('ext:hs2.testextension'); return 'no error'; }
                    catch (e) { return (e instanceof Error) + ' ' + e.code; }
                })()
                """) == "true ERR_EXTENSIONS_DISABLED")

            let enabled = try makeHarness()
            #expect(enabled.evalString("""
                (function () {
                    try { require('ext:hs2.missing'); return 'no error'; }
                    catch (e) { return e.code; }
                })()
                """) == "ERR_EXTENSION_NOT_FOUND")
        }
    }

    @Suite("Extension object lifetimes")
    struct LifetimeTests {
        private func makeHarness(_ setup: LoaderSetup) throws -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModuleRoot(extensionLoader: setup.loader)
            try harness.installRequire()
            return harness
        }

        @Test("A running ticker the script didn't keep still calls back after garbage collection")
        func activeUnreferencedSurvivesGC() throws {
            let setup = LoaderSetup()
            let harness = try makeHarness(setup)
            var ticks = 0
            harness.registerCallback("onTick") { ticks += 1 }

            autoreleasepool {
                _ = harness.eval("void require('ext:hs2.testextension').makeTicker(0.02, function () { __test_callback('onTick'); }).start()")
            }
            harness.collectGarbage()

            #expect(harness.waitFor(timeout: 0.5) { ticks >= 2 })
            #expect(harness.evalString("hs.activeObjects().map(String).join()") == "<HS2TestTicker running>")
        }

        @Test("A stopped ticker the script didn't keep is garbage collected")
        func inactiveUnreferencedIsCollected() throws {
            let setup = LoaderSetup()
            let harness = try makeHarness(setup)
            weak var ticker: NSObject?
            autoreleasepool {
                harness.eval("var t = require('ext:hs2.testextension').makeTicker(60, function () {}).start()")
                ticker = harness.evalValue("t")?.toObject() as? NSObject
                harness.eval("t.stop(); t = null")
            }
            #expect(ticker != nil)
            harness.collectGarbage()
            #expect(ticker == nil)
        }

        @Test("A running ticker is released after shutdown")
        func noLeakAfterReload() throws {
            let setup = LoaderSetup()
            let tracker = WeakLeakTracker()
            try autoreleasepool {
                let harness = try makeHarness(setup)
                harness.eval("var t = require('ext:hs2.testextension').makeTicker(0.02, function () {}).start()")
                #expect(!harness.hasException)
                if let ticker = harness.evalValue("t")?.toObject() as? NSObject {
                    tracker.track(ticker)
                }
                harness.eval("t = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
