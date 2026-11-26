//
//  HSAppInfoIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.appinfo tests")
@MainActor
struct HSAppInfoIntegrationTests {

    /// A harness with hs.appinfo reporting `version` as the running version
    func harness(version: String) -> JSTestHarness {
        var appData = HSAppInfoData()
        appData.version = version
        let harness = JSTestHarness()
        harness.loadModule(HSAppInfoModule(engineID: UUID(), appData: appData), as: "appinfo")
        return harness
    }

    @Test("versionAtLeast() is true for the running version and older ones", arguments: [
        "1.0.0-beta.10", "1.0.0-beta.9", "1.0.0-alpha", "0.9", "0",
    ])
    func atLeastOlder(version: String) {
        harness(version: "1.0.0-beta.10").expectTrue("hs.appinfo.versionAtLeast('\(version)')")
    }

    @Test("versionAtLeast() is false for newer versions", arguments: [
        "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0", "2",
    ])
    func atLeastNewer(version: String) {
        harness(version: "1.0.0-beta.10").expectFalse("hs.appinfo.versionAtLeast('\(version)')")
    }

    @Test("versionAtLeast() throws EINVALIDARG for something that isn't a version")
    func atLeastMalformed() {
        let harness = harness(version: "1.0.0")
        harness.expectEqual(
            "(function () { try { hs.appinfo.versionAtLeast('next week'); return null; } catch (e) { return e.code; } })()",
            "EINVALIDARG"
        )
    }

    @Test("versionAtLeast() is true when the running version can't be compared")
    func atLeastUnparseableRunningVersion() {
        harness(version: "(unknown app version)").expectTrue("hs.appinfo.versionAtLeast('99.0.0')")
    }
}
