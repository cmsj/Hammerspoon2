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

    @Test("createBrowser is a function")
    func testCreateBrowserIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser === 'function'")
    }

    @Test("removeBrowser is a function")
    func testRemoveBrowserIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.removeBrowser === 'function'")
    }

    @Test("createService is a function")
    func testCreateServiceIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createService === 'function'")
    }

    @Test("removeService is a function")
    func testRemoveServiceIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.removeService === 'function'")
    }

    @Test("networkServices is a function")
    func testNetworkServicesIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.networkServices === 'function'")
    }
}

// MARK: - Suite 2: JS enhancement (serviceTypes and default parameters)

@Suite("hs.bonjour JS enhancement")
struct HSBonjourJSEnhancementTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("serviceTypes is a frozen object")
    func testServiceTypesIsFrozenObject() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.bonjour.serviceTypes === 'object'")
        harness.expectTrue("Object.isFrozen(hs.bonjour.serviceTypes)")
        #expect(!harness.hasException)
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

    @Test("createService domain defaults to local.")
    func testCreateServiceDefaultDomain() {
        let harness = makeHarness()
        harness.eval("var svc = hs.bonjour.createService('Test', '_http._tcp.', 9000)")
        harness.expectEqual("svc.domain", "local.")
        #expect(!harness.hasException)
    }

    @Test("createService accepts explicit domain")
    func testCreateServiceExplicitDomain() {
        let harness = makeHarness()
        harness.eval("var svc = hs.bonjour.createService('Test', '_http._tcp.', 9000, 'local.')")
        harness.expectEqual("svc.domain", "local.")
        #expect(!harness.hasException)
    }

    @Test("networkServices returns a Promise without timeout argument")
    func testNetworkServicesPromiseNoArg() {
        let harness = makeHarness()
        harness.eval("var p = hs.bonjour.networkServices()")
        harness.expectTrue("p !== null && typeof p.then === 'function'")
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 3: HSBonjourBrowser API structure

@Suite("HSBonjourBrowser API structure")
struct HSBonjourBrowserAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    @Test("createBrowser() returns an object")
    func testCreateBrowserReturnsObject() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser() === 'object'")
    }

    @Test("browser.typeName is HSBonjourBrowser")
    func testBrowserTypeName() {
        makeHarness().expectEqual("hs.bonjour.createBrowser().typeName", "HSBonjourBrowser")
    }

    @Test("browser.identifier is a non-empty string")
    func testBrowserIdentifierIsString() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.bonjour.createBrowser().identifier === 'string'")
        harness.expectTrue("hs.bonjour.createBrowser().identifier.length > 0")
        #expect(!harness.hasException)
    }

    @Test("two browsers have different identifiers")
    func testBrowsersHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.bonjour.createBrowser();
                var b = hs.bonjour.createBrowser();
                return a.identifier !== b.identifier;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("browser has searchForServices function")
    func testSearchForServicesIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser().searchForServices === 'function'")
    }

    @Test("browser has searchForBrowsableDomains function")
    func testSearchForBrowsableDomainsIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser().searchForBrowsableDomains === 'function'")
    }

    @Test("browser has searchForRegistrationDomains function")
    func testSearchForRegistrationDomainsIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser().searchForRegistrationDomains === 'function'")
    }

    @Test("browser has stop function")
    func testStopIsFunction() {
        makeHarness().expectTrue("typeof hs.bonjour.createBrowser().stop === 'function'")
    }

    @Test("browser.stop() returns self for chaining")
    func testBrowserStopChains() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var b = hs.bonjour.createBrowser();
                return b.stop() === b;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("browser.includesPeerToPeer is settable and gettable")
    func testIncludesPeerToPeerRoundtrip() {
        let harness = makeHarness()
        harness.eval("var b = hs.bonjour.createBrowser(); b.includesPeerToPeer = true;")
        harness.expectTrue("b.includesPeerToPeer === true")
        #expect(!harness.hasException)
    }

    @Test("removeBrowser stops and removes a browser without error")
    func testRemoveBrowser() {
        let harness = makeHarness()
        harness.eval("""
            var b = hs.bonjour.createBrowser();
            hs.bonjour.removeBrowser(b);
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: HSBonjourService API structure

@Suite("HSBonjourService API structure")
struct HSBonjourServiceAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSBonjourModule.self, as: "bonjour")
        return harness
    }

    private func makeServiceHarness() -> JSTestHarness {
        let harness = makeHarness()
        harness.eval("var svc = hs.bonjour.createService('TestSvc', '_http._tcp.', 8888, 'local.');")
        return harness
    }

    @Test("createService() returns an object")
    func testCreateServiceReturnsObject() {
        makeHarness().expectTrue("""
            typeof hs.bonjour.createService('T', '_http._tcp.', 80, 'local.') === 'object'
        """)
    }

    @Test("service.typeName is HSBonjourService")
    func testServiceTypeName() {
        makeServiceHarness().expectEqual("svc.typeName", "HSBonjourService")
    }

    @Test("service.identifier is a non-empty string")
    func testServiceIdentifier() {
        let harness = makeServiceHarness()
        harness.expectTrue("typeof svc.identifier === 'string' && svc.identifier.length > 0")
        #expect(!harness.hasException)
    }

    @Test("service.name matches the creation name")
    func testServiceName() {
        makeServiceHarness().expectEqual("svc.name", "TestSvc")
    }

    @Test("service.type matches the creation type")
    func testServiceType() {
        makeServiceHarness().expectEqual("svc.type", "_http._tcp.")
    }

    @Test("service.port matches the creation port")
    func testServicePort() {
        makeServiceHarness().expectEqual("svc.port", 8888)
    }

    @Test("service.domain is local.")
    func testServiceDomain() {
        makeServiceHarness().expectEqual("svc.domain", "local.")
    }

    @Test("service.isLocal is true for a created service")
    func testServiceIsLocal() {
        makeServiceHarness().expectTrue("svc.isLocal === true")
    }

    @Test("service.hostname is null before publishing")
    func testServiceHostnameNullBeforePublish() {
        let harness = makeServiceHarness()
        harness.expectTrue("svc.hostname === null || svc.hostname === undefined")
        #expect(!harness.hasException)
    }

    @Test("service.addresses is an empty array before publishing")
    func testServiceAddressesEmptyBeforePublish() {
        let harness = makeServiceHarness()
        harness.expectTrue("Array.isArray(svc.addresses) && svc.addresses.length === 0")
        #expect(!harness.hasException)
    }

    @Test("service.txtRecord is null when none is set")
    func testServiceTxtRecordNullInitially() {
        let harness = makeServiceHarness()
        harness.expectTrue("svc.txtRecord === null || svc.txtRecord === undefined")
        #expect(!harness.hasException)
    }

    @Test("publish is a function")
    func testPublishIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.publish === 'function'")
    }

    @Test("resolve is a function")
    func testResolveIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.resolve === 'function'")
    }

    @Test("monitor is a function")
    func testMonitorIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.monitor === 'function'")
    }

    @Test("stop is a function")
    func testStopIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.stop === 'function'")
    }

    @Test("stopMonitoring is a function")
    func testStopMonitoringIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.stopMonitoring === 'function'")
    }

    @Test("setTXTRecord is a function")
    func testSetTXTRecordIsFunction() {
        makeServiceHarness().expectTrue("typeof svc.setTXTRecord === 'function'")
    }

    @Test("stop() returns self for chaining")
    func testStopChains() {
        let harness = makeServiceHarness()
        harness.expectTrue("svc.stop() === svc")
        #expect(!harness.hasException)
    }

    @Test("stopMonitoring() returns self for chaining")
    func testStopMonitoringChains() {
        let harness = makeServiceHarness()
        harness.expectTrue("svc.stopMonitoring() === svc")
        #expect(!harness.hasException)
    }

    @Test("two services have different identifiers")
    func testServicesHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.bonjour.createService('A', '_http._tcp.', 80, 'local.');
                var b = hs.bonjour.createService('B', '_http._tcp.', 81, 'local.');
                return a.identifier !== b.identifier;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("removeService stops and removes a service without error")
    func testRemoveService() {
        let harness = makeHarness()
        harness.eval("""
            var svc = hs.bonjour.createService('X', '_http._tcp.', 9999, 'local.');
            hs.bonjour.removeService(svc);
        """)
        #expect(!harness.hasException)
    }

    @Test("service.includesPeerToPeer is settable")
    func testIncludesPeerToPeer() {
        let harness = makeServiceHarness()
        harness.eval("svc.includesPeerToPeer = true;")
        harness.expectTrue("svc.includesPeerToPeer === true")
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
