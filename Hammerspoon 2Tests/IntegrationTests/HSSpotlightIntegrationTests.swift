//
//  HSSpotlightIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - Harness factory

private func makeHarness() -> JSTestHarness {
    let harness = JSTestHarness()
    harness.loadModule(HSSpotlightModule.self, as: "spotlight")
    return harness
}

// MARK: - Suite 1: API structure

@Suite("hs.spotlight API structure")
struct HSSpotlightStructureTests {

    @Test("create is a function")
    func testCreateIsFunction() {
        makeHarness().expectTrue("typeof hs.spotlight.create === 'function'")
    }

    @Test("search is a function")
    func testSearchIsFunction() {
        makeHarness().expectTrue("typeof hs.spotlight.search === 'function'")
    }

    @Test("scope is an object")
    func testScopeIsObject() {
        makeHarness().expectTrue("typeof hs.spotlight.scope === 'object'")
    }

    @Test("scope.home is an array")
    func testScopeHomeIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.home)")
    }

    @Test("scope.computer is an array")
    func testScopeComputerIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.computer)")
    }

    @Test("scope.network is an array")
    func testScopeNetworkIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.network)")
    }

    @Test("scope.applications is an array")
    func testScopeApplicationsIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.applications)")
    }

    @Test("scope.applications contains /Applications")
    func testScopeApplicationsContainsApplications() {
        makeHarness().expectTrue("hs.spotlight.scope.applications.includes('/Applications')")
    }

    @Test("scope.icloud is an array")
    func testScopeICloudIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.icloud)")
    }

    @Test("scope.icloudData is an array")
    func testScopeICloudDataIsArray() {
        makeHarness().expectTrue("Array.isArray(hs.spotlight.scope.icloudData)")
    }

    @Test("attribute is an object")
    func testAttributeIsObject() {
        makeHarness().expectTrue("typeof hs.spotlight.attribute === 'object'")
    }

    @Test("attribute.path is 'kMDItemPath'")
    func testAttributePathValue() {
        makeHarness().expectEqual("hs.spotlight.attribute.path", "kMDItemPath")
    }

    @Test("attribute.displayName is 'kMDItemDisplayName'")
    func testAttributeDisplayNameValue() {
        makeHarness().expectEqual("hs.spotlight.attribute.displayName", "kMDItemDisplayName")
    }

    @Test("attribute.contentType is 'kMDItemContentType'")
    func testAttributeContentTypeValue() {
        makeHarness().expectEqual("hs.spotlight.attribute.contentType", "kMDItemContentType")
    }

    @Test("attribute.fileSize is a string")
    func testAttributeFileSizeIsString() {
        makeHarness().expectTrue("typeof hs.spotlight.attribute.fileSize === 'string'")
    }

    @Test("attribute.bundleIdentifier is a string")
    func testAttributeBundleIdentifierIsString() {
        makeHarness().expectTrue("typeof hs.spotlight.attribute.bundleIdentifier === 'string'")
    }
}

// MARK: - Suite 2: Query object API structure

@Suite("HSSpotlightQuery API structure")
struct HSSpotlightQueryStructureTests {

    @Test("create() returns an object")
    func testCreateReturnsObject() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("typeof q === 'object'")
        #expect(!harness.hasException)
    }

    @Test("query has identifier string")
    func testQueryHasIdentifier() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("typeof q.identifier === 'string'")
        harness.expectTrue("q.identifier.length > 0")
    }

    @Test("two queries have different identifiers")
    func testQueriesHaveUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.spotlight.create()
                var b = hs.spotlight.create()
                return a.identifier !== b.identifier
            })()
        """)
    }

    @Test("count is a number defaulting to 0")
    func testCountDefaultsToZero() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("typeof q.count === 'number'")
        harness.expectEqual("q.count", 0)
    }

    @Test("isRunning defaults to false")
    func testIsRunningDefaultsFalse() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectFalse("q.isRunning")
    }

    @Test("isGathering defaults to false")
    func testIsGatheringDefaultsFalse() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectFalse("q.isGathering")
    }

    @Test("setQuery is a function returning the query")
    func testSetQueryIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.setQuery(\"kMDItemKind == 'Application'\") === q")
        #expect(!harness.hasException)
    }

    @Test("setScopes is a function returning the query")
    func testSetScopesIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.setScopes(hs.spotlight.scope.home) === q")
        #expect(!harness.hasException)
    }

    @Test("setSortDescriptors is a function returning the query")
    func testSetSortDescriptorsIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("""
            q.setSortDescriptors([{ attribute: 'kMDItemFSName', ascending: true }]) === q
        """)
        #expect(!harness.hasException)
    }

    @Test("setGroupingAttributes is a function returning the query")
    func testSetGroupingAttributesIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.setGroupingAttributes(['kMDItemContentType']) === q")
        #expect(!harness.hasException)
    }

    @Test("setValueListAttributes is a function returning the query")
    func testSetValueListAttributesIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.setValueListAttributes(['kMDItemKind']) === q")
        #expect(!harness.hasException)
    }

    @Test("setCallback is a function returning the query")
    func testSetCallbackIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.setCallback(() => {}) === q")
        #expect(!harness.hasException)
    }

    @Test("start is a function returning the query")
    func testStartIsChainable() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_FILE_DOES_NOT_EXIST_12345.xyz'")
        """)
        harness.expectTrue("q.start() === q")
        harness.eval("q.stop()")
        #expect(!harness.hasException)
    }

    @Test("stop is a function returning the query")
    func testStopIsChainable() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("q.stop() === q")
        #expect(!harness.hasException)
    }

    @Test("results is a function returning an array")
    func testResultsReturnsArray() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("Array.isArray(q.results())")
        #expect(!harness.hasException)
    }

    @Test("groups is a function returning an array")
    func testGroupsReturnsArray() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("Array.isArray(q.groups())")
        #expect(!harness.hasException)
    }

    @Test("valueLists is a function returning an array")
    func testValueListsReturnsArray() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("Array.isArray(q.valueLists())")
        #expect(!harness.hasException)
    }

    @Test("destroy is a function")
    func testDestroyIsFunction() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectTrue("typeof q.destroy === 'function'")
    }

    @Test("typeName is 'HSSpotlightQuery'")
    func testTypeName() {
        let harness = makeHarness()
        harness.eval("var q = hs.spotlight.create()")
        harness.expectEqual("q.typeName", "HSSpotlightQuery")
    }
}

// MARK: - Suite 3: Query configuration

@Suite("HSSpotlightQuery configuration")
struct HSSpotlightQueryConfigTests {

    @Test("chaining all setters does not throw")
    func testFullChainDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemKind == 'Application'")
             .setScopes(hs.spotlight.scope.computer)
             .setSortDescriptors([{ attribute: 'kMDItemFSName', ascending: true }])
             .setGroupingAttributes(['kMDItemContentType'])
             .setValueListAttributes(['kMDItemKind'])
             .setCallback(() => {})
        """)
        #expect(!harness.hasException)
    }

    @Test("setScopes with path string does not throw")
    func testSetScopesWithPath() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setScopes(['/Applications'])
        """)
        #expect(!harness.hasException)
    }

    @Test("setScopes with tilde path does not throw")
    func testSetScopesWithTildePath() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setScopes(['~/Documents'])
        """)
        #expect(!harness.hasException)
    }

    @Test("setScopes with non-array logs warning, does not throw")
    func testSetScopesWithNonArrayDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().setScopes('not an array')")
        #expect(!harness.hasException)
    }

    @Test("setSortDescriptors with empty array does not throw")
    func testSetSortDescriptorsEmptyArray() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().setSortDescriptors([])")
        #expect(!harness.hasException)
    }

    @Test("start without setQuery does not throw (logs error)")
    func testStartWithoutQueryDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().start()")
        #expect(!harness.hasException)
    }

    @Test("stop on non-running query does not throw")
    func testStopNonRunningDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().stop()")
        #expect(!harness.hasException)
    }

    @Test("destroy does not throw")
    func testDestroyDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().destroy()")
        #expect(!harness.hasException)
    }

    @Test("setQuery with empty string does not start query (logs error)")
    func testSetQueryEmptyStringDoesNotThrow() {
        let harness = makeHarness()
        harness.eval("hs.spotlight.create().setQuery('')")
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 4: Query lifecycle and isRunning state

@Suite("HSSpotlightQuery lifecycle")
struct HSSpotlightQueryLifecycleTests {

    @Test("isRunning becomes true after start()")
    func testIsRunningAfterStart() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'").start()
        """)
        harness.expectTrue("q.isRunning")
        harness.eval("q.stop()")
        #expect(!harness.hasException)
    }

    @Test("isRunning becomes false after stop()")
    func testIsRunningAfterStop() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'").start()
            q.stop()
        """)
        harness.expectFalse("q.isRunning")
        #expect(!harness.hasException)
    }

    @Test("search() returns a running query")
    func testSearchReturnsRunningQuery() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.search(
                "kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'",
                () => {}
            )
        """)
        harness.expectTrue("q.isRunning")
        harness.eval("q.stop()")
        #expect(!harness.hasException)
    }

    @Test("double start() is a no-op — does not throw")
    func testDoubleStartIsNoOp() {
        let harness = makeHarness()
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'")
            q.start()
            q.start()   // second call should be no-op
        """)
        harness.expectTrue("q.isRunning")
        harness.eval("q.stop()")
        #expect(!harness.hasException)
    }
}

// MARK: - Suite 5: Live query execution (requires Spotlight index)

private nonisolated func isSpotlightAvailable() -> Bool {
    // NSMetadataQuery always works on macOS desktop without special permissions.
    // If running in a severely restricted sandbox, this may not be true — skip conservatively.
    true
}

@Suite("HSSpotlightQuery live execution",
       .disabled(if: !isSpotlightAvailable(), "Spotlight not available in this environment"))
struct HSSpotlightQueryLiveTests {

    @Test("query fires didStart callback", .timeLimit(.minutes(1)))
    func testQueryFiresDidStart() {
        let harness = makeHarness()
        var didStart = false
        harness.registerCallback("onDidStart") { didStart = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'")
             .setCallback((event) => {
                 if (event === 'didStart') __test_callback('onDidStart')
             })
             .start()
        """)
        let ok = harness.waitFor(timeout: 5.0) { didStart }
        harness.eval("q.stop()")
        #expect(ok, "didStart callback should have fired within timeout")
        #expect(!harness.hasException)
    }

    @Test("query fires didFinish callback", .timeLimit(.minutes(1)))
    func testQueryFiresDidFinish() {
        let harness = makeHarness()
        var didFinish = false
        harness.registerCallback("onFinish") { didFinish = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'")
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        let ok = harness.waitFor(timeout: 10.0) { didFinish }
        harness.eval("q.stop()")
        #expect(ok, "didFinish callback should fire within timeout (0 results is fine)")
        #expect(!harness.hasException)
    }

    @Test("query returns count 0 for nonexistent file", .timeLimit(.minutes(1)))
    func testQueryZeroResultsForNonexistentFile() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'")
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 10.0) { finished }
        harness.eval("q.stop()")
        harness.expectEqual("q.count", 0)
        #expect(!harness.hasException)
    }

    @Test("search for application bundles finds results", .timeLimit(.minutes(1)))
    func testSearchFindsApplicationBundles() {
        let harness = makeHarness()
        var finished = false
        var resultCount = 0
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        let ok = harness.waitFor(timeout: 15.0) { finished }
        if ok {
            if let count = harness.evalValue("q.count")?.toInt32() {
                resultCount = Int(count)
            }
        }
        harness.eval("q.stop()")
        #expect(ok, "Query should complete within timeout")
        #expect(resultCount > 0, "Expected at least one app in scope.applications, found \(resultCount)")
        #expect(!harness.hasException)
    }

    @Test("results() returns array of HSSpotlightItem objects", .timeLimit(.minutes(1)))
    func testResultsContainItems() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("Array.isArray(q.results())")
        // If any results, verify the first item is an HSSpotlightItem
        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length === 0) return true  // 0 results is acceptable
                var item = items[0]
                return typeof item === 'object' && item !== null
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightItem has correct typeName", .timeLimit(.minutes(1)))
    func testItemTypeName() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length === 0) return true
                return items[0].typeName === 'HSSpotlightItem'
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightItem.attributes() returns an array", .timeLimit(.minutes(1)))
    func testItemAttributesReturnsArray() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length === 0) return true
                return Array.isArray(items[0].attributes())
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightItem.valueForAttribute() returns a value for known attribute", .timeLimit(.minutes(1)))
    func testItemValueForAttribute() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        // kMDItemPath is always available even when not in attributes()
        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length === 0) return true
                var path = items[0].valueForAttribute('kMDItemPath')
                return typeof path === 'string' && path.length > 0
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightItem.valueForAttribute() returns null for missing attribute", .timeLimit(.minutes(1)))
    func testItemValueForMissingAttribute() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length === 0) return true
                var val = items[0].valueForAttribute('kMDItemNONEXISTENT_FAKE_ATTR_XYZ')
                return val === null || val === undefined
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightItem has unique identifiers across results", .timeLimit(.minutes(1)))
    func testItemsHaveUniqueIdentifiers() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("""
            (function() {
                var items = q.results()
                if (items.length < 2) return true
                var ids = new Set(items.slice(0, 10).map(i => i.identifier))
                return ids.size === Math.min(10, items.length)
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("query with sort descriptors does not throw", .timeLimit(.minutes(1)))
    func testQueryWithSortDescriptors() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setSortDescriptors([{ attribute: 'kMDItemFSName', ascending: true }])
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")
        #expect(!harness.hasException)
    }

    @Test("query with grouping attributes produces groups", .timeLimit(.minutes(1)))
    func testQueryWithGroupingAttributes() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setGroupingAttributes([hs.spotlight.attribute.contentType])
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("Array.isArray(q.groups())")
        #expect(!harness.hasException)
    }

    @Test("HSSpotlightGroup has correct structure when groups exist", .timeLimit(.minutes(1)))
    func testGroupStructure() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setGroupingAttributes([hs.spotlight.attribute.contentType])
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("""
            (function() {
                var groups = q.groups()
                if (groups.length === 0) return true
                var g = groups[0]
                return (
                    typeof g === 'object' &&
                    g.typeName === 'HSSpotlightGroup' &&
                    typeof g.attribute === 'string' &&
                    typeof g.count === 'number' &&
                    Array.isArray(g.results()) &&
                    Array.isArray(g.subgroups())
                )
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("value list summaries are returned when configured", .timeLimit(.minutes(1)))
    func testValueListsWhenConfigured() {
        let harness = makeHarness()
        var finished = false
        harness.registerCallback("onFinish") { finished = true }
        harness.eval("""
            var q = hs.spotlight.create()
            q.setQuery("kMDItemContentType == 'com.apple.application-bundle'")
             .setScopes(hs.spotlight.scope.applications)
             .setValueListAttributes([hs.spotlight.attribute.kind])
             .setCallback((event) => {
                 if (event === 'didFinish') __test_callback('onFinish')
             })
             .start()
        """)
        _ = harness.waitFor(timeout: 15.0) { finished }
        harness.eval("q.stop()")

        harness.expectTrue("Array.isArray(q.valueLists())")
        // If results exist, verify each value list entry has the expected shape
        harness.expectTrue("""
            (function() {
                var vls = q.valueLists()
                if (vls.length === 0) return true
                var vl = vls[0]
                return (
                    typeof vl.attribute === 'string' &&
                    Array.isArray(vl.values)
                )
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("convenience search() fires didFinish callback", .timeLimit(.minutes(1)))
    func testSearchConvenienceFires() {
        let harness = makeHarness()
        var eventReceived = ""
        harness.registerCallback("onEvent") { eventReceived = "fired" }
        harness.eval("""
            var lastEvent = ''
            var q = hs.spotlight.search(
                "kMDItemFSName == 'THIS_DOES_NOT_EXIST_XXXXX.xyz'",
                (event) => {
                    lastEvent = event
                    if (event === 'didFinish') __test_callback('onEvent')
                }
            )
        """)
        let ok = harness.waitFor(timeout: 10.0) { eventReceived == "fired" }
        harness.eval("q.stop()")
        #expect(ok, "search() callback should fire didFinish")
        harness.expectEqual("lastEvent", "didFinish")
        #expect(!harness.hasException)
    }
}
