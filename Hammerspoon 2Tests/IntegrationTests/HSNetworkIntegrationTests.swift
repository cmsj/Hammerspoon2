//
//  HSNetworkIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.network tests")
struct HSNetworkTests {

    // MARK: - Suite 1: API structure

    @Suite("hs.network API structure tests")
    struct HSNetworkStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("interfaces is a function")
        func testInterfacesIsFunction() {
            makeHarness().expectTrue("typeof hs.network.interfaces === 'function'")
        }

        @Test("primaryInterface is a function")
        func testPrimaryInterfaceIsFunction() {
            makeHarness().expectTrue("typeof hs.network.primaryInterface === 'function'")
        }

        @Test("addresses is a function")
        func testAddressesIsFunction() {
            makeHarness().expectTrue("typeof hs.network.addresses === 'function'")
        }
    }

    // MARK: - Suite 2: Behaviour

    @Suite("hs.network behaviour tests")
    struct HSNetworkBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("interfaces() returns an array")
        func testInterfacesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.network.interfaces())")
            #expect(!harness.hasException)
        }

        @Test("interfaces() contains lo0")
        func testInterfacesContainsLoopback() {
            let harness = makeHarness()
            harness.expectTrue("hs.network.interfaces().some(function(i) { return i.name === 'lo0'; })")
            #expect(!harness.hasException)
        }

        @Test("interfaces() marks lo0 as loopback")
        func testLoopbackFlagIsSet() {
            let harness = makeHarness()
            harness.eval("var lo = hs.network.interfaces().find(function(i) { return i.name === 'lo0'; })")
            harness.expectTrue("lo.isLoopback === true")
            #expect(!harness.hasException)
        }

        @Test("each interface has required fields with correct types")
        func testInterfaceShape() {
            let harness = makeHarness()
            harness.eval("""
                var ifaces = hs.network.interfaces();
                var allValid = ifaces.every(function(i) {
                    return typeof i.name === 'string' &&
                           i.name.length > 0 &&
                           typeof i.isLoopback === 'boolean' &&
                           typeof i.isUp === 'boolean' &&
                           typeof i.isRunning === 'boolean';
                });
            """)
            harness.expectTrue("allValid")
            #expect(!harness.hasException)
        }

        @Test("displayName is a string when present")
        func testDisplayNameIsString() {
            let harness = makeHarness()
            harness.eval("""
                var ifaces = hs.network.interfaces();
                var displayNamesValid = ifaces.every(function(i) {
                    return i.displayName === undefined || typeof i.displayName === 'string';
                });
            """)
            harness.expectTrue("displayNamesValid")
            #expect(!harness.hasException)
        }

        @Test("addresses() returns an array")
        func testAddressesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.network.addresses())")
            #expect(!harness.hasException)
        }

        @Test("addresses() contains IPv4 loopback 127.0.0.1")
        func testAddressesContainsIPv4Loopback() {
            let harness = makeHarness()
            harness.expectTrue("hs.network.addresses().some(function(a) { return a.address === '127.0.0.1'; })")
            #expect(!harness.hasException)
        }

        @Test("addresses() contains IPv6 loopback ::1")
        func testAddressesContainsIPv6Loopback() {
            let harness = makeHarness()
            harness.expectTrue("hs.network.addresses().some(function(a) { return a.address === '::1'; })")
            #expect(!harness.hasException)
        }

        @Test("each address has interface, address, and family fields")
        func testAddressShape() {
            let harness = makeHarness()
            harness.eval("""
                var addrs = hs.network.addresses();
                var allValid = addrs.every(function(a) {
                    return typeof a.interface === 'string' &&
                           a.interface.length > 0 &&
                           typeof a.address === 'string' &&
                           a.address.length > 0 &&
                           (a.family === 'ipv4' || a.family === 'ipv6');
                });
            """)
            harness.expectTrue("allValid")
            #expect(!harness.hasException)
        }

        @Test("addresses() lo0 entries reference interface 'lo0'")
        func testLoopbackAddressesHaveCorrectInterface() {
            let harness = makeHarness()
            harness.eval("""
                var loAddrs = hs.network.addresses().filter(function(a) { return a.address === '127.0.0.1'; });
                var allLo0 = loAddrs.length > 0 && loAddrs.every(function(a) { return a.interface === 'lo0'; });
            """)
            harness.expectTrue("allLo0")
            #expect(!harness.hasException)
        }

        @Test("primaryInterface() returns a non-empty string or null")
        func testPrimaryInterfaceType() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.primaryInterface()")
            harness.expectTrue("p === null || (typeof p === 'string' && p.length > 0)")
            #expect(!harness.hasException)
        }

        @Test("primaryInterface() names an interface in interfaces()")
        func testPrimaryInterfaceIsInInterfaceList() {
            let harness = makeHarness()
            harness.eval("""
                var primary = hs.network.primaryInterface();
                var names = hs.network.interfaces().map(function(i) { return i.name; });
                var valid = primary === null || names.indexOf(primary) !== -1;
            """)
            harness.expectTrue("valid")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 3: DNS resolution

    @Suite("hs.network DNS resolution tests")
    struct HSNetworkDNSTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        // resolve() uses Task { @MainActor in } to call back into JSC after getaddrinfo completes.
        // Async tests with @MainActor + waitForAsync() cooperatively yield the main actor
        // (via Task.sleep), allowing the Task continuation to run. The evalValue() call in
        // the condition then flushes JSC's microtask queue so the .then handler fires.

        @Test("resolve is a function")
        func testResolveIsFunction() {
            makeHarness().expectTrue("typeof hs.network.resolve === 'function'")
        }

        @Test("resolve returns a Promise")
        func testResolveReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.resolve('localhost')")
            harness.expectTrue("p !== null && p !== undefined && typeof p.then === 'function'")
            #expect(!harness.hasException)
        }

        // localhost is resolved via /etc/hosts — no real DNS query, safe for all environments.

        @Test("resolve('localhost','ipv4') includes 127.0.0.1")
        @MainActor
        func testResolveLocalhostIPv4() async {
            let harness = makeHarness()
            harness.eval("""
                var __dns4_done = false;
                var __dns4_addrs = null;
                hs.network.resolve('localhost', 'ipv4').then(function(addrs) {
                    __dns4_addrs = addrs;
                    __dns4_done = true;
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__dns4_done")?.toBool() == true
            }
            #expect(ok, "resolve('localhost','ipv4') did not resolve within timeout")
            #expect(!harness.hasException)
            let addrs = harness.evalValue("__dns4_addrs")?.toArray()?.compactMap { $0 as? String } ?? []
            #expect(addrs.contains("127.0.0.1"))
        }

        @Test("resolve('localhost','ipv6') includes ::1")
        @MainActor
        func testResolveLocalhostIPv6() async {
            let harness = makeHarness()
            harness.eval("""
                var __dns6_done = false;
                var __dns6_addrs = null;
                hs.network.resolve('localhost', 'ipv6').then(function(addrs) {
                    __dns6_addrs = addrs;
                    __dns6_done = true;
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__dns6_done")?.toBool() == true
            }
            #expect(ok, "resolve('localhost','ipv6') did not resolve within timeout")
            #expect(!harness.hasException)
            let addrs = harness.evalValue("__dns6_addrs")?.toArray()?.compactMap { $0 as? String } ?? []
            #expect(addrs.contains("::1"))
        }

        @Test("resolve('localhost') with omitted family resolves to a non-empty array")
        @MainActor
        func testResolveLocalhostBoth() async {
            let harness = makeHarness()
            harness.eval("""
                var __dnsB_done = false;
                var __dnsB_count = 0;
                hs.network.resolve('localhost').then(function(addrs) {
                    __dnsB_count = addrs.length;
                    __dnsB_done = true;
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__dnsB_done")?.toBool() == true
            }
            #expect(ok, "resolve('localhost') (omitted family) did not resolve within timeout")
            #expect(!harness.hasException)
            let count = harness.evalValue("__dnsB_count")?.toInt32() ?? 0
            #expect(count > 0)
        }

        @Test("resolve rejects on unknown family string")
        @MainActor
        func testResolveRejectsUnknownFamily() async {
            let harness = makeHarness()
            harness.eval("""
                var __dnsR_rejected = false;
                hs.network.resolve('localhost', 'invalid').catch(function() {
                    __dnsR_rejected = true;
                });
            """)
            let ok = await harness.waitForAsync(timeout: 1.0) {
                harness.evalValue("__dnsR_rejected")?.toBool() == true
            }
            #expect(ok, "Invalid family should cause Promise rejection")
            #expect(!harness.hasException)
        }
    }
}
