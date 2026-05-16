//
//  HSLocationIntegrationTests.swift
//  Hammerspoon 2Tests
//
//  Created by Chris Jones on 13/05/2026.
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Suite 1: hs.location API structure

/// Tests that all expected functions and properties exist on hs.location.
/// No actual Location Services calls are made — the test runner has no
/// Location Services permission.
@Suite("hs.location API structure")
struct HSLocationStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSLocationModule.self, as: "location")
        return harness
    }

    @Test("hs.location is accessible as an object")
    func testModuleAccess() {
        makeHarness().expectTrue("typeof hs.location === 'object'")
    }

    @Test("servicesEnabled is a function")
    func testServicesEnabledIsFunction() {
        makeHarness().expectTrue("typeof hs.location.servicesEnabled === 'function'")
    }

    @Test("authorizationStatus is a function")
    func testAuthorizationStatusIsFunction() {
        makeHarness().expectTrue("typeof hs.location.authorizationStatus === 'function'")
    }

    @Test("get is a function")
    func testGetIsFunction() {
        makeHarness().expectTrue("typeof hs.location.get === 'function'")
    }

    @Test("distance is a function")
    func testDistanceIsFunction() {
        makeHarness().expectTrue("typeof hs.location.distance === 'function'")
    }

    @Test("sunrise is a function")
    func testSunriseIsFunction() {
        makeHarness().expectTrue("typeof hs.location.sunrise === 'function'")
    }

    @Test("sunset is a function")
    func testSunsetIsFunction() {
        makeHarness().expectTrue("typeof hs.location.sunset === 'function'")
    }

    @Test("addWatcher is a function")
    func testAddWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.location.addWatcher === 'function'")
    }

    @Test("removeWatcher is a function")
    func testRemoveWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.location.removeWatcher === 'function'")
    }

    @Test("geocoder is an object")
    func testGeocoderIsObject() {
        makeHarness().expectTrue("typeof hs.location.geocoder === 'object'")
    }

    @Test("servicesEnabled returns a boolean")
    func testServicesEnabledReturnsBool() {
        let harness = makeHarness()
        harness.expectTrue("typeof hs.location.servicesEnabled() === 'boolean'")
        #expect(!harness.hasException)
    }

    @Test("authorizationStatus returns one of the documented strings")
    func testAuthorizationStatusReturnsString() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var s = hs.location.authorizationStatus();
                return s === 'authorized' || s === 'denied' || s === 'restricted' || s === 'notDetermined';
            })()
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 2: hs.location pure calculations

/// Tests for functions that don't require Location Services or network access.
@Suite("hs.location pure calculations")
struct HSLocationCalculationTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSLocationModule.self, as: "location")
        return harness
    }

    @Test("distance() between London and Paris is approximately 341km")
    func testDistanceLondonParis() {
        let harness = makeHarness()
        harness.eval("""
            var d = hs.location.distance(
                { latitude: 51.5074, longitude: -0.1278 },
                { latitude: 48.8566, longitude:  2.3522 }
            );
        """)
        harness.expectTrue("typeof d === 'number'")
        harness.expectTrue("Math.abs(d - 341402) < 5000")
        #expect(!harness.hasException)
    }

    @Test("distance() to same point is zero")
    func testDistanceToSelf() {
        let harness = makeHarness()
        harness.eval("""
            var d = hs.location.distance(
                { latitude: 40.0, longitude: -74.0 },
                { latitude: 40.0, longitude: -74.0 }
            );
        """)
        harness.expectTrue("d === 0")
        #expect(!harness.hasException)
    }

    @Test("distance() returns -1 for invalid 'from' input")
    func testDistanceInvalidFrom() {
        let harness = makeHarness()
        harness.eval("""
            var d = hs.location.distance({}, { latitude: 40.0, longitude: -74.0 });
        """)
        harness.expectTrue("d === -1")
        #expect(!harness.hasException)
    }

    @Test("distance() returns -1 for invalid 'to' input")
    func testDistanceInvalidTo() {
        let harness = makeHarness()
        harness.eval("""
            var d = hs.location.distance({ latitude: 40.0, longitude: -74.0 }, {});
        """)
        harness.expectTrue("d === -1")
        #expect(!harness.hasException)
    }

    @Test("sunrise() returns a number for London on 2024-01-01")
    func testSunriseLondon() {
        let harness = makeHarness()
        harness.eval("""
            var rise = hs.location.sunrise(51.5074, -0.1278, new Date('2024-01-01T12:00:00Z'));
        """)
        harness.expectTrue("typeof rise === 'number'")
        // Known: 1 Jan 2024 sunrise London ≈ 08:06 UTC → unix ≈ 1704096360
        harness.expectTrue("Math.abs(rise - 1704096360) < 300")
        #expect(!harness.hasException)
    }

    @Test("sunset() returns a number for London on 2024-01-01")
    func testSunsetLondon() {
        let harness = makeHarness()
        harness.eval("""
            var set = hs.location.sunset(51.5074, -0.1278, new Date('2024-01-01T12:00:00Z'));
        """)
        harness.expectTrue("typeof set === 'number'")
        // 1 Jan 2024 sunset London ≈ 16:01 UTC → unix ≈ 1704124800 (accept wider band)
        harness.expectTrue("Math.abs(set - 1704124800) < 600")
        #expect(!harness.hasException)
    }

    @Test("sunrise() returns null for polar night (North Pole in December)")
    func testSunrisePolarNight() {
        let harness = makeHarness()
        harness.eval("""
            var rise = hs.location.sunrise(89.0, 0.0, new Date('2024-12-21T12:00:00Z'));
        """)
        harness.expectTrue("rise === null || rise === undefined")
        #expect(!harness.hasException)
    }

    @Test("sunset() returns null for midnight sun (North Pole in June)")
    func testSunsetMidnightSun() {
        let harness = makeHarness()
        harness.eval("""
            var set = hs.location.sunset(89.0, 0.0, new Date('2024-06-21T12:00:00Z'));
        """)
        harness.expectTrue("set === null || set === undefined")
        #expect(!harness.hasException)
    }

    @Test("sunrise() with omitted date defaults to today")
    func testSunriseDefaultDate() {
        let harness = makeHarness()
        harness.eval("""
            var rise = hs.location.sunrise(51.5074, -0.1278);
        """)
        // Should still return a number for London (sun rises every day)
        harness.expectTrue("typeof rise === 'number'")
        #expect(!harness.hasException)
    }

    @Test("sunrise() with null date defaults to today")
    func testSunriseNullDate() {
        let harness = makeHarness()
        harness.eval("""
            var rise = hs.location.sunrise(51.5074, -0.1278, null);
        """)
        harness.expectTrue("typeof rise === 'number'")
        #expect(!harness.hasException)
    }

    @Test("sunrise is before sunset on a typical day in London")
    func testSunriseBeforeSunset() {
        let harness = makeHarness()
        harness.eval("""
            var d = new Date('2024-06-15T12:00:00Z');
            var rise = hs.location.sunrise(51.5074, -0.1278, d);
            var set  = hs.location.sunset(51.5074, -0.1278, d);
        """)
        harness.expectTrue("rise < set")
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 3: hs.location.geocoder API structure

@Suite("hs.location.geocoder API structure")
struct HSLocationGeocoderTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSLocationModule.self, as: "location")
        return harness
    }

    @Test("geocoder exists on hs.location")
    func testGeocoderExists() {
        makeHarness().expectTrue("hs.location.geocoder !== null && hs.location.geocoder !== undefined")
    }

    @Test("lookupAddress is a function")
    func testLookupAddressIsFunction() {
        makeHarness().expectTrue("typeof hs.location.geocoder.lookupAddress === 'function'")
    }

    @Test("lookupLocation is a function")
    func testLookupLocationIsFunction() {
        makeHarness().expectTrue("typeof hs.location.geocoder.lookupLocation === 'function'")
    }

    @Test("lookupLocation returns null for an invalid locationTable")
    func testLookupLocationInvalid() {
        let harness = makeHarness()
        harness.eval("""
            var p = hs.location.geocoder.lookupLocation({});
        """)
        harness.expectTrue("p === null || p === undefined")
        #expect(!harness.hasException)
    }

    @Test("lookupLocation returns a Promise-like object for a valid locationTable")
    func testLookupLocationReturnsPromise() {
        let harness = makeHarness()
        harness.eval("""
            var p = hs.location.geocoder.lookupLocation({ latitude: 37.3349, longitude: -122.0090 });
        console.log("typeof p: " + typeof p);
        console.log("typeof p.then: " + typeof p.then);
        """)
        // A Promise has a 'then' method
        harness.expectTrue("p !== null && typeof p.then === 'function'")
        #expect(!harness.hasException)
    }

    @Test("lookupAddress returns a Promise-like object")
    func testLookupAddressReturnsPromise() {
        let harness = makeHarness()
        harness.eval("""
            var p = hs.location.geocoder.lookupAddress('Apple Park');
        """)
        harness.expectTrue("p !== null && typeof p.then === 'function'")
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: HSLocationWatcher API structure

@Suite("HSLocationWatcher API structure")
struct HSLocationWatcherTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSLocationModule.self, as: "location")
        return harness
    }

    @Test("addWatcher() returns a watcher object")
    func testAddWatcherReturnsObject() {
        makeHarness().expectTrue("typeof hs.location.addWatcher() === 'object'")
    }

    @Test("watcher has an identifier string")
    func testWatcherHasIdentifier() {
        makeHarness().expectTrue("typeof hs.location.addWatcher().identifier === 'string'")
    }

    @Test("watcher identifier is a non-empty string")
    func testWatcherIdentifierNonEmpty() {
        makeHarness().expectTrue("hs.location.addWatcher().identifier.length > 0")
    }

    @Test("two watchers have different identifiers")
    func testWatchersHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.location.addWatcher();
                var b = hs.location.addWatcher();
                return a.identifier !== b.identifier;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("watcher has typeName HSLocationWatcher")
    func testWatcherTypeName() {
        makeHarness().expectTrue("hs.location.addWatcher().typeName === 'HSLocationWatcher'")
    }

    @Test("start is a function")
    func testStartIsFunction() {
        makeHarness().expectTrue("typeof hs.location.addWatcher().start === 'function'")
    }

    @Test("stop is a function")
    func testStopIsFunction() {
        makeHarness().expectTrue("typeof hs.location.addWatcher().stop === 'function'")
    }

    @Test("setCallback is a function")
    func testSetCallbackIsFunction() {
        makeHarness().expectTrue("typeof hs.location.addWatcher().setCallback === 'function'")
    }

    @Test("location is a function")
    func testLocationIsFunction() {
        makeHarness().expectTrue("typeof hs.location.addWatcher().location === 'function'")
    }

    @Test("watcher.location() returns null when no location yet")
    func testWatcherLocationInitiallyNull() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var w = hs.location.addWatcher();
                var l = w.location();
                return l === null || l === undefined;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("setCallback returns the watcher for chaining")
    func testSetCallbackChainable() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var w = hs.location.addWatcher();
                return w.setCallback(function() {}) === w;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("stop returns the watcher for chaining")
    func testStopChainable() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var w = hs.location.addWatcher();
                return w.stop() === w;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("removeWatcher stops and removes a watcher without error")
    func testRemoveWatcher() {
        let harness = makeHarness()
        harness.eval("""
            var w = hs.location.addWatcher();
            hs.location.removeWatcher(w);
        """)
        #expect(!harness.hasException)
    }

    @Test("distanceFilter is settable and gettable")
    func testDistanceFilterRoundtrip() {
        let harness = makeHarness()
        harness.eval("""
            var w = hs.location.addWatcher();
            w.distanceFilter = 100;
        """)
        harness.expectTrue("w.distanceFilter === 100")
        #expect(!harness.hasException)
    }
}
