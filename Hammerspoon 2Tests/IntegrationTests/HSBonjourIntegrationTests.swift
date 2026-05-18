//
//  HSBonjourIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Suite 1: hs.bonjour module API structure

@Suite("hs.bonjour module API structure")
struct HSBonjourModuleAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("hs.bonjour is an object")
    func testModuleIsObject() {
        makeHarness().expectTrue("typeof hs.bonjour === 'object'")
    }

    @Test("newSearch is a function")
    func testNewSearchIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch === 'function'")
    }

    @Test("removeSearch is a function")
    func testRemoveSearchIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.removeSearch === 'function'")
    }

    @Test("advertise is a function")
    func testAdvertiseIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.advertise === 'function'")
    }

    @Test("stopAdvertising is a function")
    func testStopAdvertisingIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.stopAdvertising === 'function'")
    }

    @Test("networkServices is a function")
    func testNetworkServicesIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.networkServices === 'function'")
    }
}

// MARK: - Suite 2: serviceTypes

@Suite("hs.bonjour serviceTypes")
struct HSBonjourServiceTypesTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("serviceTypes is an object")
    func testServiceTypesIsObject() {
        makeHarness().expectTrue("typeof hs.bonjour.serviceTypes === 'object'")
    }

    @Test("serviceTypes.http is correct")
    func testServiceTypesHTTP() {
        makeHarness().expectEqual("hs.bonjour.serviceTypes.http", "_http._tcp.")
    }

    @Test("serviceTypes.ssh is correct")
    func testServiceTypesSSH() {
        makeHarness().expectEqual("hs.bonjour.serviceTypes.ssh", "_ssh._tcp.")
    }

    @Test("serviceTypes.vnc is correct")
    func testServiceTypesVNC() {
        makeHarness().expectEqual("hs.bonjour.serviceTypes.vnc", "_rfb._tcp.")
    }

    @Test("serviceTypes.smb is correct")
    func testServiceTypesSMB() {
        makeHarness().expectEqual("hs.bonjour.serviceTypes.smb", "_smb._tcp.")
    }
}

// MARK: - Suite 3: HSBonjourSearch API structure

@Suite("HSBonjourSearch API structure")
struct HSBonjourSearchAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("newSearch() returns an object")
    func testNewSearchReturnsObject() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch() === 'object'")
    }

    @Test("search.typeName is HSBonjourSearch")
    func testSearchTypeName() {
        makeHarness().expectEqual("hs.bonjour.newSearch().typeName", "HSBonjourSearch")
    }

    @Test("search.identifier is a non-empty string")
    func testSearchIdentifierIsString() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.bonjour.newSearch().identifier === 'string'")
        harness.expectTrue("hs.bonjour.newSearch().identifier.length > 0")
        #expect(!harness.hasException)
    }

    @Test("two searches have different identifiers")
    func testSearchesHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.bonjour.newSearch();
                var b = hs.bonjour.newSearch();
                return a.identifier !== b.identifier;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("search has findServices function")
    func testFindServicesIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch().findServices === 'function'")
    }

    @Test("search has findBrowsableDomains function")
    func testFindBrowsableDomainsIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch().findBrowsableDomains === 'function'")
    }

    @Test("search has findRegistrationDomains function")
    func testFindRegistrationDomainsIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch().findRegistrationDomains === 'function'")
    }

    @Test("search has stop function")
    func testStopIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.newSearch().stop === 'function'")
    }

    @Test("search.stop() returns self for chaining")
    func testSearchStopChains() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var s = hs.bonjour.newSearch();
                return s.stop() === s;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("search.includesPeerToPeer is settable and gettable")
    func testIncludesPeerToPeerRoundtrip() {
        let harness = makeHarness()
        harness.eval("var s = hs.bonjour.newSearch(); s.includesPeerToPeer = true;")
        harness.expectTrue("s.includesPeerToPeer === true")
        #expect(!harness.hasException)
    }

    @Test("removeSearch stops and removes a search without error")
    func testRemoveSearch() {
        let harness = makeHarness()
        harness.eval("""
            var s = hs.bonjour.newSearch();
            hs.bonjour.removeSearch(s);
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: advertise / stopAdvertising

@Suite("hs.bonjour advertise API")
struct HSBonjourAdvertiseAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("advertise with name/type/port does not throw")
    func testAdvertiseBasic() {
        let harness = makeHarness()
        harness.eval("hs.bonjour.advertise('TestSvc', '_http._tcp.', 9000)")
        #expect(!harness.hasException)
    }

    @Test("advertise with explicit domain does not throw")
    func testAdvertiseWithDomain() {
        let harness = makeHarness()
        harness.eval("hs.bonjour.advertise('TestSvc2', '_http._tcp.', 9001, 'local.')")
        #expect(!harness.hasException)
    }

    @Test("advertise with callback does not throw")
    func testAdvertiseWithCallback() {
        let harness = makeHarness()
        harness.eval("hs.bonjour.advertise('TestSvc3', '_http._tcp.', 9002, function(ev) {})")
        #expect(!harness.hasException)
    }

    @Test("advertise with domain and callback does not throw")
    func testAdvertiseWithDomainAndCallback() {
        let harness = makeHarness()
        harness.eval("hs.bonjour.advertise('TestSvc4', '_http._tcp.', 9003, 'local.', function(ev) {})")
        #expect(!harness.hasException)
    }

    @Test("stopAdvertising for a non-existent service does not throw")
    func testStopAdvertisingNonExistent() {
        let harness = makeHarness()
        harness.eval("hs.bonjour.stopAdvertising('NoSuch', '_http._tcp.')")
        #expect(!harness.hasException)
    }

    @Test("advertise then stopAdvertising does not throw")
    func testAdvertiseThenStop() {
        let harness = makeHarness()
        harness.eval("""
            hs.bonjour.advertise('StopTest', '_http._tcp.', 9004);
            hs.bonjour.stopAdvertising('StopTest', '_http._tcp.');
        """)
        #expect(!harness.hasException)
    }

    @Test("duplicate advertise does not throw")
    func testDuplicateAdvertise() {
        let harness = makeHarness()
        harness.eval("""
            hs.bonjour.advertise('Dup', '_http._tcp.', 9005);
            hs.bonjour.advertise('Dup', '_http._tcp.', 9005);
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 5: networkServices Promise

@Suite("hs.bonjour networkServices Promise")
struct HSBonjourNetworkServicesTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("networkServices(0.1) returns a Promise")
    func testNetworkServicesReturnsPromise() {
        let harness = makeHarness()
        harness.eval("var p = hs.bonjour.networkServices(0.1)")
        harness.expectTrue("p !== null && typeof p.then === 'function'")
        #expect(!harness.hasException)
    }

    @Test("networkServices() with no argument returns a Promise")
    func testNetworkServicesNoArgReturnsPromise() {
        let harness = makeHarness()
        harness.eval("var p = hs.bonjour.networkServices()")
        harness.expectTrue("p !== null && typeof p.then === 'function'")
        #expect(!harness.hasException)
    }

    @Test("networkServices(0.1) resolves to an array")
    @MainActor
    func testNetworkServicesResolvesToArray() async {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")

        var resolved = false
        harness.eval("""
            hs.bonjour.networkServices(0.1).then(function(types) {
                __test_callback('done');
            });
        """)
        harness.registerCallback("done") { resolved = true }

        let found = await harness.waitForAsync(timeout: 3.0) { resolved }
        #expect(found, "networkServices Promise did not resolve within 3 seconds")
        #expect(!harness.hasException)
    }
}
