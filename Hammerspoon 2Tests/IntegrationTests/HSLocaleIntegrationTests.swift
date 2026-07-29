//
//  HSLocaleIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.locale tests")
struct HSLocaleTests {

    // MARK: - API structure

    @Suite("hs.locale API structure tests")
    struct HSLocaleStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSLocaleModule.self, as: "locale")
            return harness
        }

        @Test("availableLocales is a function")
        func testAvailableLocalesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.availableLocales") == "function")
        }

        @Test("current is a function")
        func testCurrentIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.current") == "function")
        }

        @Test("preferredLanguages is a function")
        func testPreferredLanguagesIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.preferredLanguages") == "function")
        }

        @Test("details is a function")
        func testDetailsIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.details") == "function")
        }

        @Test("localizedName is a function")
        func testLocalizedNameIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.localizedName") == "function")
        }

        @Test("addWatcher is a function")
        func testAddWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.addWatcher") == "function")
        }

        @Test("removeWatcher is a function")
        func testRemoveWatcherIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.locale.removeWatcher") == "function")
        }

        @Test("_watcherEmitter is initialized by hs.locale.js")
        func testWatcherEmitterInitialized() {
            makeHarness().expectTrue(
                "hs.locale._watcherEmitter !== null && hs.locale._watcherEmitter !== undefined"
            )
        }
    }

    // MARK: - Locale enumeration

    @Suite("hs.locale enumeration tests")
    struct HSLocaleEnumerationTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSLocaleModule.self, as: "locale")
            return harness
        }

        @Test("availableLocales returns a non-empty array of strings")
        func testAvailableLocalesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.locale.availableLocales())")
            harness.expectTrue("hs.locale.availableLocales().length > 0")
            #expect(harness.evalTypeOf("hs.locale.availableLocales()[0]") == "string")
            #expect(!harness.hasException)
        }

        @Test("availableLocales includes en_US")
        func testAvailableLocalesIncludesEnUS() {
            let harness = makeHarness()
            harness.expectTrue("hs.locale.availableLocales().includes('en_US')")
            #expect(!harness.hasException)
        }

        @Test("current returns a non-empty string")
        func testCurrentReturnsString() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.locale.current()") == "string")
            harness.expectTrue("hs.locale.current().length > 0")
            #expect(!harness.hasException)
        }

        @Test("preferredLanguages returns a non-empty array of strings")
        func testPreferredLanguagesReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.locale.preferredLanguages())")
            harness.expectTrue("hs.locale.preferredLanguages().length > 0")
            #expect(harness.evalTypeOf("hs.locale.preferredLanguages()[0]") == "string")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Locale details

    @Suite("hs.locale details tests")
    struct HSLocaleDetailsTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSLocaleModule.self, as: "locale")
            return harness
        }

        @Test("details() with no argument returns the current locale's identifier")
        func testDetailsDefaultsToCurrentLocale() {
            let harness = makeHarness()
            harness.eval("var info = hs.locale.details()")
            #expect(!harness.hasException)
            harness.expectTrue("typeof info === 'object' && info !== null")
            #expect(harness.evalBool("info.identifier === hs.locale.current()") == true)
        }

        @Test("details('de_CH') returns expected Swiss German locale information")
        func testDetailsForDeCH() {
            let harness = makeHarness()
            harness.eval("var info = hs.locale.details('de_CH')")
            #expect(!harness.hasException)
            #expect(harness.evalString("info.identifier") == "de_CH")
            #expect(harness.evalString("info.languageCode") == "de")
            #expect(harness.evalString("info.countryCode") == "CH")
            #expect(harness.evalString("info.currencyCode") == "CHF")
            #expect(harness.evalString("info.decimalSeparator") == ".")
            #expect(harness.evalString("info.groupingSeparator") == "'")
            #expect(harness.evalBool("info.usesMetricSystem") == true)
            #expect(harness.evalBool("info.timeFormatIs24Hour") == true)
        }

        @Test("details() includes a calendar object with symbol arrays")
        func testDetailsCalendar() {
            let harness = makeHarness()
            harness.eval("var info = hs.locale.details('en_US')")
            #expect(!harness.hasException)
            harness.expectTrue("typeof info.calendar === 'object' && info.calendar !== null")
            #expect(harness.evalString("info.calendar.identifier") == "gregorian")
            harness.expectTrue("Array.isArray(info.calendar.monthSymbols)")
            harness.expectTrue("info.calendar.monthSymbols.length === 12")
            harness.expectTrue("Array.isArray(info.calendar.weekdaySymbols)")
            harness.expectTrue("info.calendar.weekdaySymbols.length === 7")
            #expect(!harness.hasException)
        }

        @Test("details() with an unrecognized identifier does not throw")
        func testDetailsUnrecognizedIdentifier() {
            let harness = makeHarness()
            harness.eval("var info = hs.locale.details('not-a-real-locale-xyz')")
            #expect(!harness.hasException)
            harness.expectTrue("typeof info === 'object' && info !== null")
        }
    }

    // MARK: - Localized strings

    @Suite("hs.locale localizedName tests")
    struct HSLocaleLocalizedNameTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSLocaleModule.self, as: "locale")
            return harness
        }

        @Test("localizedName('de_CH') returns German names in English")
        func testLocalizedNameDeCH() {
            let harness = makeHarness()
            harness.eval("var name = hs.locale.localizedName('de_CH', 'en_US')")
            #expect(!harness.hasException)
            #expect(harness.evalString("name.name") == "German")
            #expect(harness.evalString("name.nameWithDialect") == "German (Switzerland)")
        }

        @Test("localizedName() with no baseLocaleCode uses the current locale")
        func testLocalizedNameDefaultsToCurrentLocale() {
            let harness = makeHarness()
            harness.eval("var name = hs.locale.localizedName('de_CH')")
            #expect(!harness.hasException)
            harness.expectTrue("typeof name === 'object' && name !== null")
            harness.expectTrue("typeof name.name === 'string' && name.name.length > 0")
        }

        @Test("localizedName() with an invalid localeCode returns null")
        func testLocalizedNameInvalidLocaleCode() {
            let harness = makeHarness()
            harness.eval("var name = hs.locale.localizedName('not-a-real-locale-xyz', 'en_US')")
            #expect(!harness.hasException)
            // nil Optional<[String: String]> bridges to undefined, not null — loose equality accepts both
            harness.expectTrue("name == null")
        }

        @Test("localizedName() with an invalid baseLocaleCode returns null")
        func testLocalizedNameInvalidBaseLocaleCode() {
            let harness = makeHarness()
            harness.eval("var name = hs.locale.localizedName('de_CH', 'not-a-real-locale-xyz')")
            #expect(!harness.hasException)
            harness.expectTrue("name == null")
        }
    }

    // MARK: - Watcher pattern

    @Suite("hs.locale watcher tests")
    struct HSLocaleWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSLocaleModule.self, as: "locale")
            return harness
        }

        @Test("addWatcher with non-function throws")
        func testAddWatcherNonFunction() {
            let harness = makeHarness()
            harness.eval("hs.locale.addWatcher('not a function')")
            harness.expectException()
        }

        @Test("addWatcher and removeWatcher do not throw with a valid function")
        func testAddRemoveWatcherValid() {
            let harness = makeHarness()
            harness.eval("""
                var handler = function() {};
                hs.locale.addWatcher(handler);
                hs.locale.removeWatcher(handler);
            """)
            #expect(!harness.hasException)
        }

        @Test("registering the same listener twice does not throw")
        func testDuplicateListenerIgnored() {
            let harness = makeHarness()
            harness.eval("""
                var handler = function() {};
                hs.locale.addWatcher(handler);
                hs.locale.addWatcher(handler);
                hs.locale.removeWatcher(handler);
            """)
            #expect(!harness.hasException)
        }
    }
}
