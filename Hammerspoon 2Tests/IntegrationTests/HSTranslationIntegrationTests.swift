//
//  HSTranslationIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import Translation
@testable import Hammerspoon_2

// MARK: - API Structure Tests

@Suite("hs.translation tests", .serialized)
struct HSTranslationTests {

    @Suite("hs.translation API structure tests")
    struct HSTranslationStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSTranslationModule.self, as: "translation")
            return harness
        }

        @Test("hs.translation module exists")
        func testModuleExists() {
            makeHarness().expectTrue("typeof hs.translation === 'object'")
        }

        @Test("supportedLanguages is a function")
        func testSupportedLanguagesIsFunction() {
            makeHarness().expectTrue("typeof hs.translation.supportedLanguages === 'function'")
        }

        @Test("status is a function")
        func testStatusIsFunction() {
            makeHarness().expectTrue("typeof hs.translation.status === 'function'")
        }

        @Test("session is a function")
        func testSessionIsFunction() {
            makeHarness().expectTrue("typeof hs.translation.session === 'function'")
        }

        @Test("supportedLanguages() returns a thenable Promise")
        func testSupportedLanguagesReturnsPromise() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.translation.supportedLanguages().then === 'function'")
            #expect(!harness.hasException)
        }

        @Test("status() returns a thenable Promise")
        func testStatusReturnsPromise() {
            let harness = makeHarness()
            harness.expectTrue("typeof hs.translation.status('en', 'fr').then === 'function'")
            #expect(!harness.hasException)
        }

        @Test("session() returns null or an object without throwing")
        func testSessionDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("var s = hs.translation.session('en', 'fr')")
            harness.expectTrue("s === null || typeof s === 'object'")
            #expect(!harness.hasException)
        }

        @Test("session object has correct shape when non-null")
        func testSessionObjectShape() {
            let harness = makeHarness()
            harness.eval("var s = hs.translation.session('en', 'fr')")
            let sessionIsNull = harness.evalValue("s === null || s === undefined")?.toBool() ?? true
            guard !sessionIsNull else { return } // en→fr not installed; shape check is vacuously satisfied
            harness.expectTrue("s.typeName === 'HSTranslationSession'")
            harness.expectTrue("s.sourceLanguage === 'en'")
            harness.expectTrue("s.targetLanguage === 'fr'")
            harness.expectTrue("typeof s.translate === 'function'")
        }

        @Test("translate() returns a thenable Promise when session is available")
        func testTranslateReturnsPromise() {
            let harness = makeHarness()
            harness.eval("var s = hs.translation.session('en', 'fr')")
            let sessionIsNull = harness.evalValue("s === null || s === undefined")?.toBool() ?? true
            guard !sessionIsNull else { return } // en→fr not installed
            harness.expectTrue("typeof s.translate('hello').then === 'function'")
            #expect(!harness.hasException)
        }
    }

    // MARK: - supportedLanguages() content tests

    @Suite("hs.translation supportedLanguages() tests")
    struct HSTranslationLanguageListTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSTranslationModule.self, as: "translation")
            return harness
        }

        @Test("supportedLanguages() resolves to a non-empty array of strings")
        @MainActor
        func testSupportedLanguagesResolvesNonEmpty() async {
            let harness = makeHarness()
            harness.eval("""
            var _langs = null
            hs.translation.supportedLanguages().then(function(l) { _langs = l })
        """)
            let completed = await harness.waitForAsync(timeout: 5.0) {
                harness.evalValue("_langs") != nil && !(harness.evalValue("_langs")?.isNull ?? true)
            }
            #expect(completed, "supportedLanguages() did not resolve within 5 seconds")
            harness.expectTrue("Array.isArray(_langs) && _langs.length > 0")
            harness.expectTrue("_langs.every(function(l) { return typeof l === 'string' && l.length > 0 })")
        }

        @Test("supportedLanguages() includes common Western language codes")
        @MainActor
        func testCommonLanguagesPresent() async {
            let harness = makeHarness()
            harness.eval("""
            var _langs2 = null
            hs.translation.supportedLanguages().then(function(l) { _langs2 = l })
        """)
            let completed = await harness.waitForAsync(timeout: 5.0) {
                harness.evalValue("_langs2") != nil && !(harness.evalValue("_langs2")?.isNull ?? true)
            }
            #expect(completed)
            for code in ["en", "fr", "es", "de"] {
                harness.expectTrue("_langs2.includes('\(code)')")
            }
        }
    }

    // MARK: - status() resolution tests

    @Suite("hs.translation status() resolution tests")
    struct HSTranslationStatusTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSTranslationModule.self, as: "translation")
            return harness
        }

        @Test("status() for a real language pair resolves to a valid status string")
        @MainActor
        func testStatusResolvesToValidString() async {
            let harness = makeHarness()
            harness.eval("""
            var _statusResult = null
            hs.translation.status('en', 'fr').then(function(s) { _statusResult = s })
        """)
            let completed = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_statusResult") as? String != nil
            }
            #expect(completed, "status('en', 'fr') did not resolve within 30 seconds")
            let result = harness.eval("_statusResult") as? String
            #expect(["installed", "supported", "unsupported"].contains(result ?? ""),
                    "Unexpected status: \(result ?? "nil")")
        }

        @Test("status() for invalid language codes resolves to 'unsupported'")
        @MainActor
        func testStatusUnsupportedForInvalidCodes() async {
            let harness = makeHarness()
            harness.eval("""
            var _statusInvalid = null
            hs.translation.status('xx', 'yy').then(function(s) { _statusInvalid = s })
        """)
            let completed = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_statusInvalid") as? String != nil
            }
            #expect(completed, "status('xx', 'yy') did not resolve within 5 seconds")
            #expect(harness.eval("_statusInvalid") as? String == "unsupported")
        }

        @Test("status() for the same pair called twice gives consistent results")
        @MainActor
        func testStatusIsConsistent() async {
            let harness = makeHarness()
            harness.eval("""
            var _s1 = null, _s2 = null
            hs.translation.status('en', 'fr').then(function(s) { _s1 = s })
            hs.translation.status('en', 'fr').then(function(s) { _s2 = s })
        """)
            let completed = await harness.waitForAsync(timeout: 5.0) {
                harness.eval("_s1") as? String != nil && harness.eval("_s2") as? String != nil
            }
            #expect(completed)
            #expect(harness.eval("_s1") as? String == harness.eval("_s2") as? String)
        }
    }

    // MARK: - Translation execution tests (requires installed language packs)

    @Suite("hs.translation session execution tests", .serialized)
    struct HSTranslationExecutionTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSTranslationModule.self, as: "translation")
            return harness
        }

        @Test("translate() completes (resolves or rejects) when session is available")
        @MainActor
        func testTranslateCompletesWithSession() async {
            let harness = makeHarness()
            harness.eval("var _execSession = hs.translation.session('en', 'fr')")
            let sessionIsNull = harness.evalValue("_execSession === null || _execSession === undefined")?.toBool() ?? true
            guard !sessionIsNull else { return } // en→fr not installed; skip without failure

            harness.eval("""
            var _translateDone = false
            var _translateResult = null
            var _translateError = null
            _execSession.translate('Hello').then(function(r) {
                _translateResult = r
                _translateDone = true
            }).catch(function(e) {
                _translateError = String(e)
                _translateDone = true
            })
        """)

            let completed = await harness.waitForAsync(timeout: 10.0) {
                harness.eval("_translateDone") as? Bool ?? false
            }
            #expect(completed, "translate() did not complete within 10 seconds")

            let result = harness.eval("_translateResult") as? String
            let error = harness.eval("_translateError") as? String
            #expect(result != nil || error != nil, "translate() neither resolved nor rejected")
            if let result {
                #expect(!result.isEmpty)
            }
        }

        @Test("two translate() calls on the same session both complete")
        @MainActor
        func testConcurrentTranslationsOnSameSession() async {
            let harness = makeHarness()
            harness.eval("var _concSession = hs.translation.session('en', 'fr')")
            let sessionIsNull = harness.evalValue("_concSession === null || _concSession === undefined")?.toBool() ?? true
            guard !sessionIsNull else { return }

            harness.eval("""
            var _t1Done = false, _t2Done = false
            _concSession.translate('Hello').then(function() { _t1Done = true }).catch(function() { _t1Done = true })
            _concSession.translate('Goodbye').then(function() { _t2Done = true }).catch(function() { _t2Done = true })
        """)

            let completed = await harness.waitForAsync(timeout: 15.0) {
                let d1 = harness.eval("_t1Done") as? Bool ?? false
                let d2 = harness.eval("_t2Done") as? Bool ?? false
                return d1 && d2
            }
            #expect(completed, "One or both translate() calls did not complete within 15 seconds")
        }

        @Test("sessions for different language pairs have independent language properties")
        func testTwoSessionsAreIndependent() {
            let harness = makeHarness()
            harness.eval("""
            var _indepA = hs.translation.session('en', 'fr')
            var _indepB = hs.translation.session('en', 'de')
        """)
            harness.expectTrue("""
            (_indepA === null || _indepA.targetLanguage === 'fr') &&
            (_indepB === null || _indepB.targetLanguage === 'de')
        """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - Memory Leak Tests

    @Test("Active HSTranslationSession is released after shutdown")
    func testTranslationSessionDoesNotLeakAfterReload() {
        let tracker = WeakLeakTracker()
        autoreleasepool {
            let harness = JSTestHarness()
            harness.loadModule(HSTranslationModule.self, as: "translation")
            // session() returns null on macOS < 26; on macOS 26+ it creates a session.
            // translate() starts an async translation (exercising the active path).
            // The tracker only records the object if it was actually created, so this
            // test is a no-op on unsupported OS versions without marking as skipped.
            // shutdown() calls cancel() on all live sessions, freeing them.
            harness.eval("""
                var s = hs.translation.session('en', 'fr')
                if (s !== null && s !== undefined) s.translate('Hello')
            """)
            if let obj = harness.evalValue("s")?.toObjectOf(HSTranslationSession.self) as? HSTranslationSession {
                tracker.track(obj)
            }
            harness.eval("s = null")
            harness.shutdownForLeakTest()
        }
        tracker.assertNoLeaks()
    }
}
