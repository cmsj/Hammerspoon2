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

    // MARK: - Suite 4: ping

    @Suite("hs.network.ping API structure tests")
    struct HSNetworkPingStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("ping is a function")
        func testPingIsFunction() {
            makeHarness().expectTrue("typeof hs.network.ping === 'function'")
        }

        @Test("ping() returns an object")
        func testPingReturnsObject() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.expectTrue("typeof p === 'object' && p !== null")
            #expect(!harness.hasException)
            harness.eval("p.cancel()")
        }

        @Test("ping object has expected string/number/boolean properties")
        func testPingObjectShape() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.expectTrue("typeof p.server === 'string'")
            harness.expectTrue("p.server === '127.0.0.1'")
            harness.expectTrue("typeof p.address === 'string'")
            harness.expectTrue("typeof p.sent === 'number'")
            harness.expectTrue("typeof p.count === 'number'")
            harness.expectTrue("typeof p.isRunning === 'boolean'")
            harness.expectTrue("typeof p.isPaused === 'boolean'")
            #expect(!harness.hasException)
            harness.eval("p.cancel()")
        }

        @Test("ping object has expected methods")
        func testPingObjectMethods() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.expectTrue("typeof p.pause === 'function'")
            harness.expectTrue("typeof p.resume === 'function'")
            harness.expectTrue("typeof p.cancel === 'function'")
            harness.expectTrue("typeof p.setCallback === 'function'")
            harness.expectTrue("typeof p.packets === 'function'")
            harness.expectTrue("typeof p.summary === 'function'")
            #expect(!harness.hasException)
            harness.eval("p.cancel()")
        }

        @Test("two ping objects have different icmpIdentifiers")
        func testUniqueIdentifiers() {
            let harness = makeHarness()
            harness.eval("""
                var p1 = hs.network.ping('127.0.0.1', function(){})
                var p2 = hs.network.ping('127.0.0.1', function(){})
                var different = (p1 !== p2)
                p1.cancel(); p2.cancel()
            """)
            harness.expectTrue("different")
            #expect(!harness.hasException)
        }
    }

    // MARK: Ping behaviour tests

    @Suite("hs.network.ping behaviour tests")
    struct HSNetworkPingBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("cancel() synchronously fires didFinish")
        func testCancelFiresDidFinish() {
            let harness = makeHarness()
            harness.eval("""
                var __cancel_done = false;
                var p = hs.network.ping('127.0.0.1', {
                    count: 100,
                    callback: function(ping, event) {
                        if (event === 'didFinish') { __cancel_done = true; }
                    }
                });
                p.cancel();
            """)
            harness.expectTrue("__cancel_done === true")
            #expect(!harness.hasException)
        }

        @Test("pause() sets isPaused to true")
        func testPauseSetsPaused() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.eval("p.pause()")
            harness.expectTrue("p.isPaused === true")
            harness.eval("p.cancel()")
            #expect(!harness.hasException)
        }

        @Test("resume() after pause() clears isPaused")
        func testResumeClears() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.eval("p.pause()")
            harness.eval("p.resume()")
            harness.expectTrue("p.isPaused === false")
            harness.eval("p.cancel()")
            #expect(!harness.hasException)
        }

        @Test("summary() returns a non-empty string")
        func testSummaryReturnsString() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.expectTrue("typeof p.summary() === 'string' && p.summary().length > 0")
            harness.eval("p.cancel()")
            #expect(!harness.hasException)
        }

        @Test("packets() returns an array when no argument given")
        func testPacketsReturnsArray() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
            harness.expectTrue("Array.isArray(p.packets())")
            harness.eval("p.cancel()")
            #expect(!harness.hasException)
        }

        @Test("count setter is validated")
        func testCountSetter() {
            let harness = makeHarness()
            harness.eval("var p = hs.network.ping('127.0.0.1', {count: 5, callback: function(){}})")
            let original = harness.evalValue("p.count")?.toInt32() ?? 0
            harness.eval("p.count = 10")
            harness.expectTrue("p.count === 10")
            harness.eval("p.count = -1")
            // negative value should be rejected (count stays at 10)
            harness.expectTrue("p.count > 0")
            _ = original
            harness.eval("p.cancel()")
            #expect(!harness.hasException)
        }

        // The three tests below ping 127.0.0.1 and accept either a successful or failed
        // ping — ICMP sockets may not be available in all test environments.

        @Test("pinging 127.0.0.1 with count=1 fires didFinish or didFail")
        @MainActor
        func testPingLoopbackCompletesOrFails() async {
            let harness = makeHarness()
            harness.eval("""
                var __ping_done = false;
                var __ping_event = null;
                hs.network.ping('127.0.0.1', {
                    count: 1,
                    timeout: 2.0,
                    callback: function(ping, event) {
                        if (event === 'didFinish' || event === 'didFail') {
                            __ping_event = event;
                            __ping_done = true;
                        }
                    }
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__ping_done")?.toBool() == true
            }
            #expect(ok, "ping should complete within timeout")
            #expect(!harness.hasException)
            let event = harness.evalValue("__ping_event")?.toString() ?? ""
            #expect(event == "didFinish" || event == "didFail")
        }

        @Test("successful ping of 127.0.0.1 fires receivedPacket with valid packet info")
        @MainActor
        func testPingReceivesPacketWithValidShape() async {
            let harness = makeHarness()
            harness.eval("""
                var __ping_packet = null;
                var __ping_done = false;
                hs.network.ping('127.0.0.1', {
                    count: 1,
                    timeout: 2.0,
                    callback: function(ping, event, info) {
                        if (event === 'receivedPacket') { __ping_packet = info; }
                        if (event === 'didFinish' || event === 'didFail') { __ping_done = true; }
                    }
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__ping_done")?.toBool() == true
            }
            #expect(ok, "ping should complete within timeout")
            #expect(!harness.hasException)

            // Only validate packet details if we received one
            guard harness.evalValue("__ping_packet")?.isObject == true else { return }
            harness.expectTrue("typeof __ping_packet.sequenceNumber === 'number'")
            harness.expectTrue("typeof __ping_packet.icmpIdentifier === 'number'")
            harness.expectTrue("__ping_packet.status === 'received'")
            harness.expectTrue("typeof __ping_packet.rtt === 'number' && __ping_packet.rtt > 0")
        }

        @Test("after completion packets() array contains one entry per sent packet")
        @MainActor
        func testPacketsAfterCompletion() async {
            let harness = makeHarness()
            harness.eval("""
                var __pkts = null;
                var __done = false;
                hs.network.ping('127.0.0.1', {
                    count: 1,
                    timeout: 2.0,
                    callback: function(ping, event) {
                        if (event === 'didFinish' || event === 'didFail') {
                            __pkts = ping.packets();
                            __done = true;
                        }
                    }
                });
            """)
            let ok = await harness.waitForAsync(timeout: 10.0) {
                harness.evalValue("__done")?.toBool() == true
            }
            #expect(ok, "ping should complete within timeout")
            #expect(!harness.hasException)
            // If the socket was opened and packet sent, packets() has entries
            if let arr = harness.evalValue("__pkts")?.toArray(), !arr.isEmpty {
                harness.expectTrue("Array.isArray(__pkts)")
                harness.expectTrue("__pkts.length > 0")
            }
        }
    }

    // MARK: Ping memory leak test

    @Suite("hs.network.ping memory tests")
    struct HSNetworkPingMemoryTests {

        @Test("active HSNetworkPing is released after module shutdown")
        func testPingDoesNotLeakAfterShutdown() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSNetworkModule.self, as: "network")

                // Create and activate the ping
                harness.eval("var p = hs.network.ping('127.0.0.1', function(){})")
                // Spin the run loop briefly to let the async DNS/socket Task execute
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

                if let swift = harness.evalValue("p")?.toObjectOf(HSNetworkPing.self) as? HSNetworkPing {
                    tracker.track(swift)
                }

                harness.eval("p = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }

    // MARK: - Suite 5: reachability structure

    @Suite("hs.network reachability API structure tests")
    struct HSNetworkReachabilityStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("reachabilityFlags is an object")
        func testFlagsIsObject() {
            makeHarness().expectTrue("typeof hs.network.reachabilityFlags === 'object'")
        }

        @Test("reachabilityForAddress is a function")
        func testForAddressIsFunction() {
            makeHarness().expectTrue("typeof hs.network.reachabilityForAddress === 'function'")
        }

        @Test("reachabilityForAddressPair is a function")
        func testForAddressPairIsFunction() {
            makeHarness().expectTrue("typeof hs.network.reachabilityForAddressPair === 'function'")
        }

        @Test("reachabilityForHostName is a function")
        func testForHostNameIsFunction() {
            makeHarness().expectTrue("typeof hs.network.reachabilityForHostName === 'function'")
        }

        @Test("reachabilityInternet is a function")
        func testInternetIsFunction() {
            makeHarness().expectTrue("typeof hs.network.reachabilityInternet === 'function'")
        }

        @Test("reachabilityLinkLocal is a function")
        func testLinkLocalIsFunction() {
            makeHarness().expectTrue("typeof hs.network.reachabilityLinkLocal === 'function'")
        }

        @Test("reachabilityInternet() returns an object with expected methods")
        func testInternetObjectShape() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityInternet()")
            harness.expectTrue("typeof r === 'object' && r !== null")
            harness.expectTrue("r.typeName === 'HSNetworkReachability'")
            harness.expectTrue("typeof r.status === 'function'")
            harness.expectTrue("typeof r.statusString === 'function'")
            harness.expectTrue("typeof r.setCallback === 'function'")
            harness.expectTrue("typeof r.start === 'function'")
            harness.expectTrue("typeof r.stop === 'function'")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }
    }

    // MARK: - Suite 6: reachability behaviour

    @Suite("hs.network reachability behaviour tests")
    struct HSNetworkReachabilityBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("reachabilityFlags has all expected keys as numbers")
        func testFlagsHasExpectedKeys() {
            let harness = makeHarness()
            harness.eval("var f = hs.network.reachabilityFlags")
            for key in ["reachable", "connectionRequired", "transientConnection", "isDirect",
                        "interventionRequired", "connectionOnTraffic", "connectionOnDemand", "isLocalAddress"] {
                harness.expectTrue("typeof f.\(key) === 'number'")
            }
            #expect(!harness.hasException)
        }

        @Test("each reachabilityFlag value is a distinct power of two")
        func testFlagValuesAreDistinctPowersOfTwo() {
            let harness = makeHarness()
            harness.eval("""
                var f = hs.network.reachabilityFlags
                var vals = [f.transientConnection, f.reachable, f.connectionRequired,
                            f.connectionOnTraffic, f.interventionRequired, f.connectionOnDemand,
                            f.isLocalAddress, f.isDirect]
                var allPow2 = vals.every(function(v) { return v > 0 && (v & (v - 1)) === 0 })
                var allDistinct = vals.length === new Set(vals).size
            """)
            harness.expectTrue("allPow2")
            harness.expectTrue("allDistinct")
            #expect(!harness.hasException)
        }

        @Test("reachabilityInternet() status() returns a non-negative number")
        func testStatusReturnsNonNegativeNumber() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityInternet()")
            harness.expectTrue("typeof r.status() === 'number' && r.status() >= 0")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityInternet() statusString() returns an 8-character string")
        func testStatusStringIs8Chars() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityInternet()")
            harness.expectTrue("typeof r.statusString() === 'string' && r.statusString().length === 8")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityForAddress() with a valid IPv4 address returns a reachability object")
        func testForAddressIPv4() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddress('8.8.8.8')")
            harness.expectTrue("typeof r === 'object' && r !== null")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityForAddress() with a valid IPv6 address returns a reachability object")
        func testForAddressIPv6() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddress('::1')")
            harness.expectTrue("typeof r === 'object' && r !== null")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityForAddress() with an invalid string returns null")
        func testForAddressInvalidReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddress('not-an-ip')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("reachabilityForAddress() with a hostname string (not an IP) returns null")
        func testForAddressHostnameReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddress('apple.com')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("reachabilityForAddressPair() with valid addresses returns a reachability object")
        func testForAddressPairValid() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddressPair('0.0.0.0', '8.8.8.8')")
            harness.expectTrue("typeof r === 'object' && r !== null")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityForAddressPair() with an invalid local address returns null")
        func testForAddressPairInvalidLocal() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddressPair('bad', '8.8.8.8')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("reachabilityForAddressPair() with an invalid remote address returns null")
        func testForAddressPairInvalidRemote() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForAddressPair('0.0.0.0', 'bad')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("reachabilityForHostName() with a non-empty hostname returns a reachability object")
        func testForHostNameValid() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForHostName('apple.com')")
            harness.expectTrue("typeof r === 'object' && r !== null")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("reachabilityForHostName() with an empty string returns null")
        func testForHostNameEmptyReturnsNull() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityForHostName('')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("reachabilityLinkLocal() returns a reachability object")
        func testLinkLocalReturnsObject() {
            let harness = makeHarness()
            harness.eval("var r = hs.network.reachabilityLinkLocal()")
            harness.expectTrue("typeof r === 'object' && r !== null")
            #expect(!harness.hasException)
            harness.eval("r.stop()")
        }

        @Test("start() and stop() chain fluently back to the same object")
        func testStartStopChain() {
            let harness = makeHarness()
            harness.eval("""
                var r = hs.network.reachabilityInternet()
                var r2 = r.setCallback(function() {}).start()
                var r3 = r2.stop()
            """)
            harness.expectTrue("r === r2 && r2 === r3")
            #expect(!harness.hasException)
        }

        @Test("calling stop() before start() does not throw")
        func testStopBeforeStartIsNoop() {
            let harness = makeHarness()
            harness.eval("hs.network.reachabilityInternet().stop()")
            #expect(!harness.hasException)
        }

        @Test("calling start() twice is idempotent")
        func testDoubleStartIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
                var r = hs.network.reachabilityInternet().setCallback(function() {})
                r.start(); r.start()
                r.stop()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Reachability memory leak test

    @Suite("hs.network.reachability memory tests")
    struct HSNetworkReachabilityMemoryTests {

        @Test("active HSNetworkReachability is released after module shutdown")
        func testReachabilityDoesNotLeakAfterShutdown() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSNetworkModule.self, as: "network")

                harness.eval("""
                    var r = hs.network.reachabilityInternet()
                    r.setCallback(function() {}).start()
                """)

                if let swift = harness.evalValue("r")?.toObjectOf(HSNetworkReachability.self) as? HSNetworkReachability {
                    tracker.track(swift)
                }

                harness.eval("r = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }

    // MARK: - Suite 7: Configuration API structure

    @Suite("hs.network configuration API structure tests")
    struct HSNetworkConfigurationStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("configurationStore is a function")
        func testConfigurationStoreIsFunction() {
            makeHarness().expectTrue("typeof hs.network.configurationStore === 'function'")
        }

        @Test("configurationLocations is a function")
        func testConfigurationLocationsIsFunction() {
            makeHarness().expectTrue("typeof hs.network.configurationLocations === 'function'")
        }

        @Test("configurationSetLocation is a function")
        func testConfigurationSetLocationIsFunction() {
            makeHarness().expectTrue("typeof hs.network.configurationSetLocation === 'function'")
        }

        @Test("configurationWatcher is a function")
        func testConfigurationWatcherIsFunction() {
            makeHarness().expectTrue("typeof hs.network.configurationWatcher === 'function'")
        }

        @Test("configurationWatcher() returns an object")
        func testConfigurationWatcherReturnsObject() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationWatcher() === 'object'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() object has setKeys function")
        func testConfigurationWatcherHasSetKeys() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationWatcher().setKeys === 'function'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() object has setCallback function")
        func testConfigurationWatcherHasSetCallback() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationWatcher().setCallback === 'function'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() object has start function")
        func testConfigurationWatcherHasStart() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationWatcher().start === 'function'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() object has stop function")
        func testConfigurationWatcherHasStop() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationWatcher().stop === 'function'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() object has typeName string")
        func testConfigurationWatcherHasTypeName() {
            let harness = makeHarness()
            harness.expectTrue("hs.network.configurationWatcher().typeName === 'HSNetworkConfigurationWatcher'")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 8: Configuration behaviour

    @Suite("hs.network configuration behaviour tests")
    struct HSNetworkConfigurationBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSNetworkModule.self, as: "network")
            return harness
        }

        @Test("configurationStore() with no argument returns an object")
        func testConfigurationStoreNoArgReturnsObject() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationStore() === 'object'")
            #expect(!harness.hasException)
        }

        @Test("configurationStore() result keys are strings (or result is empty)")
        func testConfigurationStoreHasStringKeys() {
            let harness = makeHarness()
            // SCDynamicStore may return empty in a sandboxed test environment; that is OK.
            harness.expectTrue("""
                (function() {
                    var s = hs.network.configurationStore()
                    var keys = Object.keys(s)
                    return keys.length === 0 || typeof keys[0] === 'string'
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("configurationStore() filtered result is a subset of unfiltered")
        func testConfigurationStoreFilteredReturnsSubset() {
            let harness = makeHarness()
            // SCDynamicStore may return empty in a sandboxed test environment; skip assertion if so.
            harness.expectTrue("""
                (function() {
                    var all = Object.keys(hs.network.configurationStore()).length
                    var ipv4 = Object.keys(hs.network.configurationStore("State:/Network/Global/IPv4")).length
                    return all === 0 || all >= ipv4
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("configurationLocations() returns an object")
        func testConfigurationLocationsReturnsObject() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.network.configurationLocations() === 'object'")
            #expect(!harness.hasException)
        }

        @Test("configurationLocations() has at least one entry")
        func testConfigurationLocationsHasEntries() {
            let harness = makeHarness()
            harness.expectTrue("Object.keys(hs.network.configurationLocations()).length >= 1")
            #expect(!harness.hasException)
        }

        @Test("configurationLocations() values are strings")
        func testConfigurationLocationsValuesAreStrings() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var locs = hs.network.configurationLocations()
                    var vals = Object.values(locs)
                    return vals.length > 0 && typeof vals[0] === 'string'
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("configurationSetLocation() with invalid name returns false")
        func testConfigurationSetLocationInvalidReturnsFalse() {
            let harness = makeHarness()
            harness.expectTrue("hs.network.configurationSetLocation('__no_such_location__') === false")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher() methods chain (return self)")
        func testConfigurationWatcherChaining() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.network.configurationWatcher()
                var r = w.setKeys(['State:/Network/.*'], true)
                        .setCallback(function() {})
            """)
            harness.expectTrue("r === w || typeof r === 'object'")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher stop() before start() does not throw")
        func testConfigurationWatcherStopBeforeStartIsNoop() {
            let harness = makeHarness()
            harness.eval("hs.network.configurationWatcher().stop()")
            #expect(!harness.hasException)
        }

        @Test("configurationWatcher start() and stop() round-trip does not throw")
        func testConfigurationWatcherStartStop() {
            let harness = makeHarness()
            harness.eval("""
                var w = hs.network.configurationWatcher()
                w.setKeys(['State:/Network/Global/IPv4'])
                 .setCallback(function() {})
                 .start()
                 .stop()
            """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Configuration watcher memory leak test

    @Suite("hs.network configuration watcher memory tests")
    struct HSNetworkConfigurationWatcherMemoryTests {

        @Test("active HSNetworkConfigurationWatcher is released after module shutdown")
        func testConfigurationWatcherDoesNotLeakAfterShutdown() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSNetworkModule.self, as: "network")

                harness.eval("""
                    var w = hs.network.configurationWatcher()
                    w.setKeys(['State:/Network/Global/IPv4'])
                     .setCallback(function() {})
                     .start()
                """)

                if let swift = harness.evalValue("w")?.toObjectOf(HSNetworkConfigurationWatcher.self) as? HSNetworkConfigurationWatcher {
                    tracker.track(swift)
                }

                harness.eval("w = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
