//
//  HSPowerIntegrationTests.swift
//  Hammerspoon 2Tests
//

import IOKit
import Testing
import JavaScriptCore
@testable import Hammerspoon_2

private nonisolated func hasNoBattery() -> Bool {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMPowerSource")
    )
    guard service != IO_OBJECT_NULL else { return true }
    defer { IOObjectRelease(service) }
    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
          let props = unsafe propsRef?.takeRetainedValue() as? [String: Any] else { return true }
    return (props["BatteryInstalled"] as? Bool) != true
}

@Suite("hs.power tests")
struct HSPowerTests {
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
            #expect(makeHarness().evalTypeOf("hs.power") == "object")
        }

        // MARK: Functions

        @Test("preventSleep is a function")
        func testPreventSleepIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.preventSleep") == "function")
        }

        @Test("allowSleep is a function")
        func testAllowSleepIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.allowSleep") == "function")
        }

        @Test("isSleepPrevented is a function")
        func testIsSleepPreventedIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.isSleepPrevented") == "function")
        }

        @Test("declareActivity is a function")
        func testDeclareActivityIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.declareActivity") == "function")
        }

        @Test("currentAssertions is a function")
        func testCurrentAssertionsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.currentAssertions") == "function")
        }

        @Test("systemSleep is a function")
        func testSystemSleepIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.systemSleep") == "function")
        }

        @Test("lockScreen is a function")
        func testLockScreenIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.lockScreen") == "function")
        }

        @Test("startScreensaver is a function")
        func testStartScreensaverIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.startScreensaver") == "function")
        }

        @Test("batteryInfo is a function")
        func testBatteryInfoIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.batteryInfo") == "function")
        }

        @Test("on is a function")
        func testOnIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.on") == "function")
        }

        @Test("off is a function")
        func testOffIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.off") == "function")
        }

        @Test("once is a function")
        func testOnceIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.power.once") == "function")
        }

        // MARK: Properties (not functions)

        @Test("percentage is a number property")
        func testPercentageIsProperty() {
            #expect(makeHarness().evalTypeOf("hs.power.percentage") == "number")
        }

        @Test("isCharging is a boolean property")
        func testIsChargingIsProperty() {
            #expect(makeHarness().evalTypeOf("hs.power.isCharging") == "boolean")
        }

        @Test("powerSource is a string property")
        func testPowerSourceIsProperty() {
            #expect(makeHarness().evalTypeOf("hs.power.powerSource") == "string")
        }

        @Test("isLowPowerMode is a boolean property")
        func testIsLowPowerModeIsProperty() {
            #expect(makeHarness().evalTypeOf("hs.power.isLowPowerMode") == "boolean")
        }

        @Test("thermalState is a string property")
        func testThermalStateIsProperty() {
            #expect(makeHarness().evalTypeOf("hs.power.thermalState") == "string")
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
            #expect(makeHarness().evalTypeOf("hs.power.isLowPowerMode") == "boolean")
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
            #expect(makeHarness().evalTypeOf("hs.power.percentage") == "number")
        }

        @Test("isCharging is a boolean")
        func testIsChargingIsBoolean() {
            #expect(makeHarness().evalTypeOf("hs.power.isCharging") == "boolean")
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

        @Test("powerSource is consistent with batteryInfo source", .disabled(if: hasNoBattery()))
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

        @Test("isCharging is consistent with batteryInfo isCharging", .disabled(if: hasNoBattery()))
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

        @Test("percentage is consistent with batteryInfo percentage", .disabled(if: hasNoBattery()))
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

    @Suite("hs.power battery info", .disabled(if: hasNoBattery(), "No battery hardware present"))
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

    // MARK: - Suite 5: Watcher API

    @Suite("hs.power watcher API")
    struct HSPowerWatcherAPITests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSPowerModule.self, as: "power")
            return harness
        }

        // MARK: Event watcher — valid usage

        @Test("on and off with the same function do not throw")
        func testAddThenRemoveEventWatcher() {
            let harness = makeHarness()
            harness.eval("""
            var _evtHandler = function() {};
            hs.power.on('systemWillSleep', _evtHandler);
            hs.power.off('systemWillSleep', _evtHandler);
        """)
            #expect(!harness.hasException)
        }

        @Test("off with an unregistered function does not throw")
        func testRemoveEventWatcherUnregistered() {
            let harness = makeHarness()
            harness.eval("hs.power.off('systemWillSleep', function() {})")
            #expect(!harness.hasException)
        }

        @Test("multiple event watcher listeners can be added and removed")
        func testMultipleEventWatchersCanBeAdded() {
            let harness = makeHarness()
            harness.eval("""
            var _fn1 = function() {};
            var _fn2 = function() {};
            hs.power.on('systemWillSleep', _fn1);
            hs.power.on('systemDidWake', _fn2);
            hs.power.off('systemWillSleep', _fn1);
            hs.power.off('systemDidWake', _fn2);
        """)
            #expect(!harness.hasException)
        }

        @Test("duplicate on registration is idempotent and does not throw")
        func testDuplicateEventWatcherIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
            var _dupEvtFn = function() {};
            hs.power.on('systemWillSleep', _dupEvtFn);
            hs.power.on('systemWillSleep', _dupEvtFn);
            hs.power.off('systemWillSleep', _dupEvtFn);
        """)
            #expect(!harness.hasException)
        }

        @Test("on with a named power event routes to the event emitter, not the battery emitter")
        func testPowerEventRoutesToEventEmitter() {
            let harness = makeHarness()
            harness.eval("""
            var _routeFn = function() {};
            hs.power.on('systemWillSleep', _routeFn);
        """)
            harness.expectTrue("hs.power._eventWatcherEmitter.events['systemWillSleep'].includes(_routeFn)")
            harness.expectFalse(
                "hs.power._batteryWatcherEmitter.events['systemWillSleep'] && hs.power._batteryWatcherEmitter.events['systemWillSleep'].includes(_routeFn)"
            )
            harness.eval("hs.power.off('systemWillSleep', _routeFn)")
            #expect(!harness.hasException)
        }

        // MARK: Event watcher — type validation

        @Test("on with a non-function string throws")
        func testAddEventWatcherStringThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('systemWillSleep', 'not a function')")
            #expect(harness.hasException)
        }

        @Test("on with a number throws")
        func testAddEventWatcherNumberThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('systemWillSleep', 42)")
            #expect(harness.hasException)
        }

        @Test("on with null throws")
        func testAddEventWatcherNullThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('systemWillSleep', null)")
            #expect(harness.hasException)
        }

        @Test("on with an object throws")
        func testAddEventWatcherObjectThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('systemWillSleep', {})")
            #expect(harness.hasException)
        }

        // MARK: Battery watcher — valid usage

        @Test("on and off with the same function do not throw (battery)")
        func testAddThenRemoveBatteryWatcher() {
            let harness = makeHarness()
            harness.eval("""
            var _batHandler = function() {};
            hs.power.on('change', _batHandler);
            hs.power.off('change', _batHandler);
        """)
            #expect(!harness.hasException)
        }

        @Test("off with an unregistered function does not throw (battery)")
        func testRemoveBatteryWatcherUnregistered() {
            let harness = makeHarness()
            harness.eval("hs.power.off('change', function() {})")
            #expect(!harness.hasException)
        }

        @Test("multiple battery watcher listeners can be added and removed")
        func testMultipleBatteryWatchersCanBeAdded() {
            let harness = makeHarness()
            harness.eval("""
            var _bat1 = function() {};
            var _bat2 = function() {};
            hs.power.on('change', _bat1);
            hs.power.on('change', _bat2);
            hs.power.off('change', _bat1);
            hs.power.off('change', _bat2);
        """)
            #expect(!harness.hasException)
        }

        @Test("duplicate on registration is idempotent and does not throw (battery)")
        func testDuplicateBatteryWatcherIsIdempotent() {
            let harness = makeHarness()
            harness.eval("""
            var _dupBatFn = function() {};
            hs.power.on('change', _dupBatFn);
            hs.power.on('change', _dupBatFn);
            hs.power.off('change', _dupBatFn);
        """)
            #expect(!harness.hasException)
        }

        @Test("on with 'change' routes to the battery emitter, not the event emitter")
        func testChangeRoutesToBatteryEmitter() {
            let harness = makeHarness()
            harness.eval("""
            var _routeFn = function() {};
            hs.power.on('change', _routeFn);
        """)
            harness.expectTrue("hs.power._batteryWatcherEmitter.events['change'].includes(_routeFn)")
            harness.expectFalse(
                "hs.power._eventWatcherEmitter.events['change'] && hs.power._eventWatcherEmitter.events['change'].includes(_routeFn)"
            )
            harness.eval("hs.power.off('change', _routeFn)")
            #expect(!harness.hasException)
        }

        // MARK: Battery watcher — type validation

        @Test("on with a number throws (battery)")
        func testAddBatteryWatcherNumberThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('change', 42)")
            #expect(harness.hasException)
        }

        @Test("on with a string throws (battery)")
        func testAddBatteryWatcherStringThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('change', 'callback')")
            #expect(harness.hasException)
        }

        @Test("on with null throws (battery)")
        func testAddBatteryWatcherNullThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('change', null)")
            #expect(harness.hasException)
        }

        @Test("on with an object throws (battery)")
        func testAddBatteryWatcherObjectThrows() {
            let harness = makeHarness()
            harness.eval("hs.power.on('change', {})")
            #expect(harness.hasException)
        }

        // MARK: once

        @Test("once-registered listener fires only one time for a power event")
        func testOnceFiresOnlyOnceForEvent() {
            let harness = makeHarness()
            harness.eval("""
                var count = 0;
                hs.power.once('systemWillSleep', function() { count++; });
                hs.power._eventWatcherEmitter.emit('systemWillSleep');
                hs.power._eventWatcherEmitter.emit('systemWillSleep');
            """)
            harness.expectEqual("count", 1)
            #expect(!harness.hasException)
        }

        @Test("once-registered listener fires only one time for battery change")
        func testOnceFiresOnlyOnceForBattery() {
            let harness = makeHarness()
            harness.eval("""
                var count = 0;
                hs.power.once('change', function() { count++; });
                hs.power._batteryWatcherEmitter.emit('change');
                hs.power._batteryWatcherEmitter.emit('change');
            """)
            harness.expectEqual("count", 1)
            #expect(!harness.hasException)
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSPowerModule.self, as: "power")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.power.on") == "function")
            #expect(harness.evalTypeOf("hs.power.off") == "function")
            #expect(harness.evalTypeOf("hs.power.once") == "function")

            harness.eval("""
                var fn1 = function() {};
                hs.power.on('systemWillSleep', fn1);
                hs.power.off('systemWillSleep', fn1);

                var fn2 = function() {};
                hs.power.on('change', fn2);
                hs.power.off('change', fn2);
            """)
            #expect(!harness.hasException)
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

        @Test("on('change', ...) throws if the native battery watcher fails to start")
        func testOnBatteryThrowsWhenNativeStartFails() {
            // Regression test for a code review comment: _addBatteryWatcher can fail (e.g.
            // IOPSNotificationCreateRunLoopSource returning nil) without the LazyWatcherEmitter's
            // start() throwing, which would record the listener as if the watcher were running -
            // stranding it until every listener is removed and re-added. Simulates the native
            // failure by swapping in a stub that returns false, since the real IOPS call can't be
            // forced to fail from a test.
            let harness = makeHarness()
            harness.eval("""
                hs.power._addBatteryWatcher = function(fn) { return false; };
                var threw = false;
                try {
                    hs.power.on('change', function() {});
                } catch (err) {
                    threw = true;
                }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
            harness.expectFalse(
                "hs.power._batteryWatcherEmitter.events['change'] && hs.power._batteryWatcherEmitter.events['change'].length > 0"
            )
        }
    }
}
