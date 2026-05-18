//
//  HSPowerIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Suite 1: Module API structure

@Suite("hs.power module API structure")
struct HSPowerModuleAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    @Test("hs.power is an object")
    func testModuleIsObject() {
        makeHarness().expectTrue("typeof hs.power === 'object'")
    }

    // MARK: Functions

    @Test("preventSleep is a function")
    func testPreventSleepIsFunction() {
        makeHarness().expectTrue("typeof hs.power.preventSleep === 'function'")
    }

    @Test("allowSleep is a function")
    func testAllowSleepIsFunction() {
        makeHarness().expectTrue("typeof hs.power.allowSleep === 'function'")
    }

    @Test("isSleepPrevented is a function")
    func testIsSleepPreventedIsFunction() {
        makeHarness().expectTrue("typeof hs.power.isSleepPrevented === 'function'")
    }

    @Test("declareActivity is a function")
    func testDeclareActivityIsFunction() {
        makeHarness().expectTrue("typeof hs.power.declareActivity === 'function'")
    }

    @Test("currentAssertions is a function")
    func testCurrentAssertionsIsFunction() {
        makeHarness().expectTrue("typeof hs.power.currentAssertions === 'function'")
    }

    @Test("systemSleep is a function")
    func testSystemSleepIsFunction() {
        makeHarness().expectTrue("typeof hs.power.systemSleep === 'function'")
    }

    @Test("lockScreen is a function")
    func testLockScreenIsFunction() {
        makeHarness().expectTrue("typeof hs.power.lockScreen === 'function'")
    }

    @Test("startScreensaver is a function")
    func testStartScreensaverIsFunction() {
        makeHarness().expectTrue("typeof hs.power.startScreensaver === 'function'")
    }

    @Test("batteryInfo is a function")
    func testBatteryInfoIsFunction() {
        makeHarness().expectTrue("typeof hs.power.batteryInfo === 'function'")
    }

    @Test("addEventWatcher is a function")
    func testAddEventWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.power.addEventWatcher === 'function'")
    }

    @Test("removeEventWatcher is a function")
    func testRemoveEventWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.power.removeEventWatcher === 'function'")
    }

    @Test("addBatteryWatcher is a function")
    func testAddBatteryWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.power.addBatteryWatcher === 'function'")
    }

    @Test("removeBatteryWatcher is a function")
    func testRemoveBatteryWatcherIsFunction() {
        makeHarness().expectTrue("typeof hs.power.removeBatteryWatcher === 'function'")
    }

    // MARK: Properties (not functions)

    @Test("percentage is a number property")
    func testPercentageIsProperty() {
        makeHarness().expectTrue("typeof hs.power.percentage === 'number'")
    }

    @Test("isCharging is a boolean property")
    func testIsChargingIsProperty() {
        makeHarness().expectTrue("typeof hs.power.isCharging === 'boolean'")
    }

    @Test("powerSource is a string property")
    func testPowerSourceIsProperty() {
        makeHarness().expectTrue("typeof hs.power.powerSource === 'string'")
    }

    @Test("isLowPowerMode is a boolean property")
    func testIsLowPowerModeIsProperty() {
        makeHarness().expectTrue("typeof hs.power.isLowPowerMode === 'boolean'")
    }

    @Test("thermalState is a string property")
    func testThermalStateIsProperty() {
        makeHarness().expectTrue("typeof hs.power.thermalState === 'string'")
    }

    // MARK: JS layer internals

    @Test("_eventWatcherEmitter is populated after module load")
    func testEventWatcherEmitterExists() {
        makeHarness().expectTrue(
            "typeof hs.power._eventWatcherEmitter === 'object' && hs.power._eventWatcherEmitter !== null"
        )
    }

    @Test("_batteryWatcherEmitter is populated after module load")
    func testBatteryWatcherEmitterExists() {
        makeHarness().expectTrue(
            "typeof hs.power._batteryWatcherEmitter === 'object' && hs.power._batteryWatcherEmitter !== null"
        )
    }
}

// MARK: - Suite 2: Sleep prevention

@Suite("hs.power sleep prevention")
struct HSPowerSleepPreventionTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    // MARK: Round-trip for each type

    @Test("preventSleep('display') returns true")
    func testPreventDisplaySleepReturnsTrue() {
        let harness = makeHarness()
        harness.expectTrue("hs.power.preventSleep('display') === true")
        harness.eval("hs.power.allowSleep('display')")
        #expect(!harness.hasException)
    }

    @Test("preventSleep('systemIdle') returns true")
    func testPreventSystemIdleSleepReturnsTrue() {
        let harness = makeHarness()
        harness.expectTrue("hs.power.preventSleep('systemIdle') === true")
        harness.eval("hs.power.allowSleep('systemIdle')")
        #expect(!harness.hasException)
    }

    @Test("preventSleep('system') returns true")
    func testPreventSystemSleepReturnsTrue() {
        let harness = makeHarness()
        harness.expectTrue("hs.power.preventSleep('system') === true")
        harness.eval("hs.power.allowSleep('system')")
        #expect(!harness.hasException)
    }

    // MARK: Invalid input

    @Test("preventSleep with invalid type returns false")
    func testPreventSleepInvalidTypeReturnsFalse() {
        makeHarness().expectFalse("hs.power.preventSleep('invalid')")
    }

    @Test("allowSleep with invalid type returns false")
    func testAllowSleepInvalidTypeReturnsFalse() {
        makeHarness().expectFalse("hs.power.allowSleep('invalid')")
    }

    @Test("isSleepPrevented with invalid type returns false")
    func testIsSleepPreventedInvalidTypeReturnsFalse() {
        makeHarness().expectFalse("hs.power.isSleepPrevented('invalid')")
    }

    // MARK: isSleepPrevented state transitions

    @Test("isSleepPrevented returns false before prevention")
    func testIsSleepPreventedFalseInitially() {
        makeHarness().expectFalse("hs.power.isSleepPrevented('display')")
    }

    @Test("isSleepPrevented('display') returns true after preventSleep")
    func testIsSleepPreventedDisplayTrueAfterPrevention() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.expectTrue("hs.power.isSleepPrevented('display')")
        harness.eval("hs.power.allowSleep('display')")
        #expect(!harness.hasException)
    }

    @Test("isSleepPrevented('systemIdle') returns true after preventSleep")
    func testIsSleepPreventedSystemIdleTrueAfterPrevention() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('systemIdle')")
        harness.expectTrue("hs.power.isSleepPrevented('systemIdle')")
        harness.eval("hs.power.allowSleep('systemIdle')")
        #expect(!harness.hasException)
    }

    @Test("isSleepPrevented('system') returns true after preventSleep")
    func testIsSleepPreventedSystemTrueAfterPrevention() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('system')")
        harness.expectTrue("hs.power.isSleepPrevented('system')")
        harness.eval("hs.power.allowSleep('system')")
        #expect(!harness.hasException)
    }

    @Test("allowSleep restores isSleepPrevented to false")
    func testAllowSleepRestoresFalse() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.eval("hs.power.allowSleep('display')")
        harness.expectFalse("hs.power.isSleepPrevented('display')")
        #expect(!harness.hasException)
    }

    @Test("allowSleep when not preventing returns false")
    func testAllowSleepWhenNotPreventingReturnsFalse() {
        makeHarness().expectFalse("hs.power.allowSleep('display')")
    }

    // MARK: Idempotency and independence

    @Test("preventSleep with the same type twice is idempotent")
    func testDoublePrevention() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var first = hs.power.preventSleep('display');
                var second = hs.power.preventSleep('display');
                hs.power.allowSleep('display');
                return first === true && second === true;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("sleep prevention types are independent of each other")
    func testPreventionTypesAreIndependent() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                hs.power.preventSleep('display');
                var ok = hs.power.isSleepPrevented('display') === true &&
                         hs.power.isSleepPrevented('systemIdle') === false &&
                         hs.power.isSleepPrevented('system') === false;
                hs.power.allowSleep('display');
                return ok;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("all three types can be active simultaneously")
    func testAllThreeTypesSimultaneous() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                hs.power.preventSleep('display');
                hs.power.preventSleep('systemIdle');
                hs.power.preventSleep('system');
                var ok = hs.power.isSleepPrevented('display') &&
                         hs.power.isSleepPrevented('systemIdle') &&
                         hs.power.isSleepPrevented('system');
                hs.power.allowSleep('display');
                hs.power.allowSleep('systemIdle');
                hs.power.allowSleep('system');
                return ok;
            })()
        """)
        #expect(!harness.hasException)
    }

    // MARK: declareActivity

    @Test("declareActivity does not throw")
    func testDeclareActivityDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.power.declareActivity()")
        #expect(!harness.hasException)
    }

    @Test("declareActivity can be called multiple times without throwing")
    func testDeclareActivityMultipleCalls() {
        let harness = makeHarness()
        harness.eval("hs.power.declareActivity(); hs.power.declareActivity(); hs.power.declareActivity()")
        #expect(!harness.hasException)
    }

    // MARK: currentAssertions

    @Test("currentAssertions returns an array")
    func testCurrentAssertionsReturnsArray() {
        makeHarness().expectTrue("Array.isArray(hs.power.currentAssertions())")
    }

    @Test("currentAssertions is non-empty while an assertion is active")
    func testCurrentAssertionsNonEmptyWhileActive() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.expectTrue("""
            (function() {
                var a = hs.power.currentAssertions();
                hs.power.allowSleep('display');
                return a.length > 0;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("currentAssertions entries have pid property")
    func testCurrentAssertionsEntriesHavePid() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.expectTrue("""
            (function() {
                var a = hs.power.currentAssertions();
                hs.power.allowSleep('display');
                return a.every(function(e) { return typeof e.pid === 'number'; });
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("currentAssertions entries have name property")
    func testCurrentAssertionsEntriesHaveName() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.expectTrue("""
            (function() {
                var a = hs.power.currentAssertions();
                hs.power.allowSleep('display');
                return a.every(function(e) { return typeof e.name === 'string'; });
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("currentAssertions entries have type property")
    func testCurrentAssertionsEntriesHaveType() {
        let harness = makeHarness()
        harness.eval("hs.power.preventSleep('display')")
        harness.expectTrue("""
            (function() {
                var a = hs.power.currentAssertions();
                hs.power.allowSleep('display');
                return a.every(function(e) { return typeof e.type === 'string'; });
            })()
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 3: System state

@Suite("hs.power system state")
struct HSPowerSystemStateTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    @Test("isLowPowerMode is a boolean")
    func testIsLowPowerModeIsBoolean() {
        makeHarness().expectTrue("typeof hs.power.isLowPowerMode === 'boolean'")
    }

    @Test("thermalState is a recognised string")
    func testThermalStateIsKnownString() {
        makeHarness().expectTrue(
            "['nominal','fair','serious','critical'].includes(hs.power.thermalState)"
        )
    }

    @Test("powerSource is a recognised string")
    func testPowerSourceIsKnownString() {
        makeHarness().expectTrue(
            "['ac','battery','ups','unknown'].includes(hs.power.powerSource)"
        )
    }

    @Test("percentage is a number")
    func testPercentageIsNumber() {
        makeHarness().expectTrue("typeof hs.power.percentage === 'number'")
    }

    @Test("isCharging is a boolean")
    func testIsChargingIsBoolean() {
        makeHarness().expectTrue("typeof hs.power.isCharging === 'boolean'")
    }

    @Test("percentage is -1 or in range 0–100")
    func testPercentageRange() {
        makeHarness().expectTrue("""
            (function() {
                var p = hs.power.percentage;
                return p === -1 || (p >= 0 && p <= 100);
            })()
        """)
    }

    @Test("isCharging is false when no battery is present")
    func testIsChargingFalseWhenNoBattery() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                if (hs.power.percentage !== -1) return true; // has battery — skip
                return hs.power.isCharging === false;
            })()
        """)
    }

    @Test("percentage is -1 when batteryInfo is null")
    func testPercentageNegativeOneWhenNoBattery() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info !== null) return true; // has battery — skip
                return hs.power.percentage === -1;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("powerSource is consistent with batteryInfo source")
    func testPowerSourceConsistencyWithBatteryInfo() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.source === hs.power.powerSource;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("isCharging is consistent with batteryInfo isCharging")
    func testIsChargingConsistencyWithBatteryInfo() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.isCharging === hs.power.isCharging;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("percentage is consistent with batteryInfo percentage")
    func testPercentageConsistencyWithBatteryInfo() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.percentage === hs.power.percentage;
            })()
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: Battery info

@Suite("hs.power battery info")
struct HSPowerBatteryInfoTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    // MARK: Return type

    @Test("batteryInfo returns null or an object")
    func testBatteryInfoReturnsNullOrObject() {
        makeHarness().expectTrue(
            "(function() { var i = hs.power.batteryInfo(); return i === null || typeof i === 'object'; })()"
        )
    }

    @Test("batteryInfo returns a new object on each call")
    func testBatteryInfoReturnsNewObject() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.power.batteryInfo();
                var b = hs.power.batteryInfo();
                if (a === null && b === null) return true;
                return a !== b;
            })()
        """)
        #expect(!harness.hasException)
    }

    // MARK: Key presence

    @Test("batteryInfo object has all expected keys when present")
    func testBatteryInfoHasExpectedKeys() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                var required = ['percentage','isCharging','isCharged','source',
                                'health','healthCondition','cycleCount','capacity',
                                'maxCapacity','designCapacity','voltage','amperage',
                                'watts','temperature','timeRemaining','timeToFullCharge','serial'];
                return required.every(function(k) { return k in info; });
            })()
        """)
        #expect(!harness.hasException)
    }

    // MARK: Per-field type validation

    @Test("batteryInfo percentage is a number in range 0–100")
    func testBatteryInfoPercentageRange() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return typeof info.percentage === 'number' && info.percentage >= 0 && info.percentage <= 100;
            })()
        """)
    }

    @Test("batteryInfo isCharging is a boolean")
    func testBatteryInfoIsChargingIsBoolean() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return typeof info.isCharging === 'boolean';
            })()
        """)
    }

    @Test("batteryInfo isCharged is a boolean")
    func testBatteryInfoIsChargedIsBoolean() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return typeof info.isCharged === 'boolean';
            })()
        """)
    }

    @Test("batteryInfo source is a recognised string")
    func testBatteryInfoSourceIsKnownString() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return ['ac','battery','ups','unknown'].includes(info.source);
            })()
        """)
    }

    @Test("batteryInfo source matches top-level powerSource")
    func testBatteryInfoSourceMatchesPowerSource() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.source === hs.power.powerSource;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("batteryInfo health is a string")
    func testBatteryInfoHealthIsString() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return typeof info.health === 'string';
            })()
        """)
    }

    @Test("batteryInfo healthCondition is null or a string")
    func testBatteryInfoHealthConditionIsNullOrString() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.healthCondition === null || typeof info.healthCondition === 'string';
            })()
        """)
    }

    @Test("batteryInfo cycleCount is null or a non-negative integer")
    func testBatteryInfoCycleCountIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.cycleCount === null ||
                       (typeof info.cycleCount === 'number' && info.cycleCount >= 0);
            })()
        """)
    }

    @Test("batteryInfo capacity is null or a non-negative number")
    func testBatteryInfoCapacityIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.capacity === null ||
                       (typeof info.capacity === 'number' && info.capacity >= 0);
            })()
        """)
    }

    @Test("batteryInfo maxCapacity is null or a non-negative number")
    func testBatteryInfoMaxCapacityIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.maxCapacity === null ||
                       (typeof info.maxCapacity === 'number' && info.maxCapacity >= 0);
            })()
        """)
    }

    @Test("batteryInfo designCapacity is null or a non-negative number")
    func testBatteryInfoDesignCapacityIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.designCapacity === null ||
                       (typeof info.designCapacity === 'number' && info.designCapacity >= 0);
            })()
        """)
    }

    @Test("batteryInfo voltage is null or a positive number")
    func testBatteryInfoVoltageIsNullOrPositiveNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.voltage === null ||
                       (typeof info.voltage === 'number' && info.voltage > 0);
            })()
        """)
    }

    @Test("batteryInfo amperage is null or a number (may be negative when discharging)")
    func testBatteryInfoAmperageIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.amperage === null || typeof info.amperage === 'number';
            })()
        """)
    }

    @Test("batteryInfo watts is null or a number (may be negative when discharging)")
    func testBatteryInfoWattsIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.watts === null || typeof info.watts === 'number';
            })()
        """)
    }

    @Test("batteryInfo amperage and watts are both null or both numbers")
    func testBatteryInfoAmperageWattsConsistency() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                var aNull = info.amperage === null;
                var wNull = info.watts === null;
                return aNull === wNull;
            })()
        """)
    }

    @Test("batteryInfo temperature is null or a non-negative number")
    func testBatteryInfoTemperatureIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.temperature === null ||
                       (typeof info.temperature === 'number' && info.temperature >= 0);
            })()
        """)
    }

    @Test("batteryInfo timeRemaining is null or a positive number")
    func testBatteryInfoTimeRemainingIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.timeRemaining === null ||
                       (typeof info.timeRemaining === 'number' && info.timeRemaining > 0);
            })()
        """)
    }

    @Test("batteryInfo timeToFullCharge is null or a positive number")
    func testBatteryInfoTimeToFullChargeIsNullOrNumber() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.timeToFullCharge === null ||
                       (typeof info.timeToFullCharge === 'number' && info.timeToFullCharge > 0);
            })()
        """)
    }

    @Test("batteryInfo serial is null or a string")
    func testBatteryInfoSerialIsNullOrString() {
        makeHarness().expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.serial === null || typeof info.serial === 'string';
            })()
        """)
    }

    // MARK: Consistency with top-level properties

    @Test("batteryInfo percentage matches top-level percentage property")
    func testBatteryInfoPercentageMatchesProperty() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.percentage === hs.power.percentage;
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("batteryInfo isCharging matches top-level isCharging property")
    func testBatteryInfoIsChargingMatchesProperty() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var info = hs.power.batteryInfo();
                if (info === null) return true;
                return info.isCharging === hs.power.isCharging;
            })()
        """)
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 5: System actions

/// These tests verify that the system-action calls do not raise JavaScript exceptions.
/// The actual side effects (sleep, lock, screensaver) depend on OS permissions and
/// may not occur in a sandboxed test environment.
@Suite("hs.power system actions")
struct HSPowerSystemActionTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    @Test("systemSleep does not throw a JavaScript exception")
    func testSystemSleepNoThrow() {
        let harness = makeHarness()
        harness.eval("hs.power.systemSleep()")
        #expect(!harness.hasException)
    }

    @Test("lockScreen does not throw a JavaScript exception")
    func testLockScreenNoThrow() {
        let harness = makeHarness()
        harness.eval("hs.power.lockScreen()")
        #expect(!harness.hasException)
    }

    @Test("startScreensaver does not throw a JavaScript exception")
    func testStartScreensaverNoThrow() {
        let harness = makeHarness()
        harness.eval("hs.power.startScreensaver()")
        #expect(!harness.hasException)
    }

    @Test("systemSleep returns undefined")
    func testSystemSleepReturnsUndefined() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.power.systemSleep()")
        #expect(result?.isUndefined == true)
    }

    @Test("lockScreen returns undefined")
    func testLockScreenReturnsUndefined() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.power.lockScreen()")
        #expect(result?.isUndefined == true)
    }

    @Test("startScreensaver returns undefined")
    func testStartScreensaverReturnsUndefined() {
        let harness = makeHarness()
        let result = harness.evalValue("hs.power.startScreensaver()")
        #expect(result?.isUndefined == true)
    }
}

// MARK: - Suite 6: Watcher API

@Suite("hs.power watcher API")
struct HSPowerWatcherAPITests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSPowerModule.self, as: "power")
        return harness
    }

    // MARK: Event watcher — valid usage

    @Test("addEventWatcher and removeEventWatcher with the same function do not throw")
    func testAddThenRemoveEventWatcher() {
        let harness = makeHarness()
        harness.eval("""
            var _evtHandler = function(e) {};
            hs.power.addEventWatcher(_evtHandler);
            hs.power.removeEventWatcher(_evtHandler);
        """)
        #expect(!harness.hasException)
    }

    @Test("removeEventWatcher with an unregistered function does not throw")
    func testRemoveEventWatcherUnregistered() {
        let harness = makeHarness()
        harness.eval("hs.power.removeEventWatcher(function(e) {})")
        #expect(!harness.hasException)
    }

    @Test("multiple event watcher listeners can be added and removed")
    func testMultipleEventWatchersCanBeAdded() {
        let harness = makeHarness()
        harness.eval("""
            var _fn1 = function(e) {};
            var _fn2 = function(e) {};
            hs.power.addEventWatcher(_fn1);
            hs.power.addEventWatcher(_fn2);
            hs.power.removeEventWatcher(_fn1);
            hs.power.removeEventWatcher(_fn2);
        """)
        #expect(!harness.hasException)
    }

    @Test("duplicate addEventWatcher registration is idempotent and does not throw")
    func testDuplicateEventWatcherIsIdempotent() {
        let harness = makeHarness()
        harness.eval("""
            var _dupEvtFn = function(e) {};
            hs.power.addEventWatcher(_dupEvtFn);
            hs.power.addEventWatcher(_dupEvtFn);
            hs.power.removeEventWatcher(_dupEvtFn);
        """)
        #expect(!harness.hasException)
    }

    // MARK: Event watcher — type validation

    @Test("addEventWatcher with a non-function string throws")
    func testAddEventWatcherStringThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addEventWatcher('not a function')")
        #expect(harness.hasException)
    }

    @Test("addEventWatcher with a number throws")
    func testAddEventWatcherNumberThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addEventWatcher(42)")
        #expect(harness.hasException)
    }

    @Test("addEventWatcher with null throws")
    func testAddEventWatcherNullThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addEventWatcher(null)")
        #expect(harness.hasException)
    }

    @Test("addEventWatcher with an object throws")
    func testAddEventWatcherObjectThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addEventWatcher({})")
        #expect(harness.hasException)
    }

    // MARK: Battery watcher — valid usage

    @Test("addBatteryWatcher and removeBatteryWatcher with the same function do not throw")
    func testAddThenRemoveBatteryWatcher() {
        let harness = makeHarness()
        harness.eval("""
            var _batHandler = function() {};
            hs.power.addBatteryWatcher(_batHandler);
            hs.power.removeBatteryWatcher(_batHandler);
        """)
        #expect(!harness.hasException)
    }

    @Test("removeBatteryWatcher with an unregistered function does not throw")
    func testRemoveBatteryWatcherUnregistered() {
        let harness = makeHarness()
        harness.eval("hs.power.removeBatteryWatcher(function() {})")
        #expect(!harness.hasException)
    }

    @Test("multiple battery watcher listeners can be added and removed")
    func testMultipleBatteryWatchersCanBeAdded() {
        let harness = makeHarness()
        harness.eval("""
            var _bat1 = function() {};
            var _bat2 = function() {};
            hs.power.addBatteryWatcher(_bat1);
            hs.power.addBatteryWatcher(_bat2);
            hs.power.removeBatteryWatcher(_bat1);
            hs.power.removeBatteryWatcher(_bat2);
        """)
        #expect(!harness.hasException)
    }

    @Test("duplicate addBatteryWatcher registration is idempotent and does not throw")
    func testDuplicateBatteryWatcherIsIdempotent() {
        let harness = makeHarness()
        harness.eval("""
            var _dupBatFn = function() {};
            hs.power.addBatteryWatcher(_dupBatFn);
            hs.power.addBatteryWatcher(_dupBatFn);
            hs.power.removeBatteryWatcher(_dupBatFn);
        """)
        #expect(!harness.hasException)
    }

    // MARK: Battery watcher — type validation

    @Test("addBatteryWatcher with a number throws")
    func testAddBatteryWatcherNumberThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addBatteryWatcher(42)")
        #expect(harness.hasException)
    }

    @Test("addBatteryWatcher with a string throws")
    func testAddBatteryWatcherStringThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addBatteryWatcher('callback')")
        #expect(harness.hasException)
    }

    @Test("addBatteryWatcher with null throws")
    func testAddBatteryWatcherNullThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addBatteryWatcher(null)")
        #expect(harness.hasException)
    }

    @Test("addBatteryWatcher with an object throws")
    func testAddBatteryWatcherObjectThrows() {
        let harness = makeHarness()
        harness.eval("hs.power.addBatteryWatcher({})")
        #expect(harness.hasException)
    }

    // MARK: Internal plumbing

    @Test("_addEventWatcher and _removeEventWatcher cycle is safe")
    func testAddRemoveEventWatcherDirectly() {
        let harness = makeHarness()
        harness.eval("""
            hs.power._addEventWatcher(function(e) {});
            hs.power._removeEventWatcher();
        """)
        #expect(!harness.hasException)
    }

    @Test("_removeEventWatcher is safe to call when not watching")
    func testRemoveEventWatcherWhenNotWatching() {
        let harness = makeHarness()
        harness.eval("hs.power._removeEventWatcher()")
        #expect(!harness.hasException)
    }

    @Test("_addBatteryWatcher and _removeBatteryWatcher cycle is safe")
    func testAddRemoveBatteryWatcherDirectly() {
        let harness = makeHarness()
        harness.eval("""
            hs.power._addBatteryWatcher(function() {});
            hs.power._removeBatteryWatcher();
        """)
        #expect(!harness.hasException)
    }

    @Test("_removeBatteryWatcher is safe to call when not watching")
    func testRemoveBatteryWatcherWhenNotWatching() {
        let harness = makeHarness()
        harness.eval("hs.power._removeBatteryWatcher()")
        #expect(!harness.hasException)
    }
}
