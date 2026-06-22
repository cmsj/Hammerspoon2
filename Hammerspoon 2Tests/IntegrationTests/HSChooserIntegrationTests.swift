//
//  HSChooserIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

// MARK: - API structure

@Suite("hs.chooser API structure tests")
struct HSChooserStructureTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSChooserModule.self, as: "chooser")
        return harness
    }

    @Test("create is a function")
    func testCreateIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create === 'function'")
    }

    @Test("create returns an object")
    func testCreateReturnsObject() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("typeof c === 'object' && c !== null")
        #expect(!harness.hasException)
    }

    @Test("typeName is HSChooser")
    func testTypeName() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectEqual("c.typeName", "HSChooser")
    }

    @Test("identifier is a non-empty string")
    func testIdentifier() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("typeof c.identifier === 'string' && c.identifier.length > 0")
    }

    @Test("query property exists and defaults to empty string")
    func testQueryDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectEqual("c.query", "")
    }

    @Test("placeholder property exists and defaults to Search...")
    func testPlaceholderDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectEqual("c.placeholder", "Search...")
    }

    @Test("searchSubText defaults to false")
    func testSearchSubTextDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("c.searchSubText === false")
    }

    @Test("enableDefaultForQuery defaults to false")
    func testEnableDefaultForQueryDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("c.enableDefaultForQuery === false")
    }

    @Test("width defaults to 0.5")
    func testWidthDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("Math.abs(c.width - 0.5) < 0.01")
    }

    @Test("visibleRows defaults to 10")
    func testVisibleRowsDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectEqual("c.visibleRows", 10)
    }

    @Test("isVisible defaults to false")
    func testIsVisibleDefault() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create()")
        harness.expectTrue("c.isVisible === false")
    }

    @Test("setChoices is a function")
    func testSetChoicesIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().setChoices === 'function'")
    }

    @Test("refreshChoices is a function")
    func testRefreshChoicesIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().refreshChoices === 'function'")
    }

    @Test("show is a function")
    func testShowIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().show === 'function'")
    }

    @Test("hide is a function")
    func testHideIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().hide === 'function'")
    }

    @Test("onSelect property is writable")
    func testOnSelectWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onSelect = () => {}")
        #expect(!harness.hasException)
    }

    @Test("onQueryChange property is writable")
    func testOnQueryChangeWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onQueryChange = () => {}")
        #expect(!harness.hasException)
    }

    @Test("onShow property is writable")
    func testOnShowWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onShow = () => {}")
        #expect(!harness.hasException)
    }

    @Test("onHide property is writable")
    func testOnHideWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onHide = () => {}")
        #expect(!harness.hasException)
    }

    @Test("onRightClick property is writable")
    func testOnRightClickWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onRightClick = () => {}")
        #expect(!harness.hasException)
    }

    @Test("onInvalid property is writable")
    func testOnInvalidWritable() {
        let harness = makeHarness()
        harness.eval("var c = hs.chooser.create(); c.onInvalid = () => {}")
        #expect(!harness.hasException)
    }

    @Test("select is a function")
    func testSelectIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().select === 'function'")
    }

    @Test("selectedRowContents is a function")
    func testSelectedRowContentsIsFunction() {
        makeHarness().expectTrue("typeof hs.chooser.create().selectedRowContents === 'function'")
    }
}

// MARK: - Behaviour

@Suite("hs.chooser behaviour tests")
struct HSChooserBehaviourTests {

    private func makeHarness() -> JSTestHarness {
        let harness = JSTestHarness()
        harness.loadModule(HSChooserModule.self, as: "chooser")
        return harness
    }

    @Test("each created chooser has a unique identifier")
    func testUniqueIdentifiers() {
        let harness = makeHarness()
        harness.expectTrue("""
            (function() {
                var a = hs.chooser.create()
                var b = hs.chooser.create()
                return a.identifier !== b.identifier
            })()
        """)
        #expect(!harness.hasException)
    }

    @Test("setChoices with array does not throw")
    func testSetChoicesArray() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Foo"}, {text: "Bar"}])
        """)
        #expect(!harness.hasException)
    }

    @Test("setChoices with function does not throw")
    func testSetChoicesFunction() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices(function(q) { return [{text: "Result"}] })
        """)
        #expect(!harness.hasException)
    }

    @Test("setChoices returns self for chaining")
    func testSetChoicesChaining() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            var result = c.setChoices([{text: "Foo"}])
            var isSelf = result === c
        """)
        harness.expectTrue("isSelf")
        #expect(!harness.hasException)
    }

    @Test("refreshChoices returns self for chaining")
    func testRefreshChoicesChaining() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Foo"}])
            var result = c.refreshChoices()
            var isSelf = result === c
        """)
        harness.expectTrue("isSelf")
        #expect(!harness.hasException)
    }

    @Test("query setter updates value")
    func testQuerySetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.query = "hello"
        """)
        harness.expectEqual("c.query", "hello")
        #expect(!harness.hasException)
    }

    @Test("placeholder setter updates value")
    func testPlaceholderSetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.placeholder = "Type here..."
        """)
        harness.expectEqual("c.placeholder", "Type here...")
        #expect(!harness.hasException)
    }

    @Test("width setter updates value")
    func testWidthSetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.width = 0.6
        """)
        harness.expectTrue("Math.abs(c.width - 0.6) < 0.01")
        #expect(!harness.hasException)
    }

    @Test("visibleRows setter updates value")
    func testVisibleRowsSetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.visibleRows = 5
        """)
        harness.expectEqual("c.visibleRows", 5)
        #expect(!harness.hasException)
    }

    @Test("searchSubText setter updates value")
    func testSearchSubTextSetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.searchSubText = true
        """)
        harness.expectTrue("c.searchSubText === true")
        #expect(!harness.hasException)
    }

    @Test("full configuration chain does not throw")
    func testFullChain() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.placeholder = "Search apps..."
            c.width = 0.45
            c.visibleRows = 8
            c.searchSubText = true
            c.setChoices([
                {text: "Safari", subText: "com.apple.Safari"},
                {text: "Terminal", subText: "com.apple.Terminal"}
            ])
            c.onSelect = (item) => {}
            c.onQueryChange = (q) => {}
            c.onShow = () => {}
            c.onHide = () => {}
        """)
        #expect(!harness.hasException)
    }

    @Test("setChoices with empty array does not throw")
    func testSetChoicesEmpty() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([])
        """)
        #expect(!harness.hasException)
    }

    @Test("selectedRow setter does not throw")
    func testSelectedRowSetter() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "A"}, {text: "B"}])
            c.selectedRow = 1
        """)
        #expect(!harness.hasException)
    }

    @Test("enableDefaultForQuery setter does not throw")
    func testEnableDefaultForQuery() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.enableDefaultForQuery = true
        """)
        harness.expectTrue("c.enableDefaultForQuery === true")
        #expect(!harness.hasException)
    }

    @Test("selectedRowContents returns dict for the highlighted row")
    func testSelectedRowContentsHighlighted() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Alpha", subText: "sub", extra: 99}])
            var item = c.selectedRowContents()
        """)
        harness.expectTrue("item !== null && item !== undefined")
        harness.expectEqual("item.text", "Alpha")
        harness.expectEqual("item.subText", "sub")
        harness.expectTrue("item.valid === true")
        #expect(!harness.hasException)
    }

    @Test("selectedRowContents returns dict for an explicit index")
    func testSelectedRowContentsByIndex() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "First"}, {text: "Second"}])
            var item = c.selectedRowContents(1)
        """)
        harness.expectEqual("item.text", "Second")
        #expect(!harness.hasException)
    }

    @Test("selectedRowContents returns null for out-of-range index")
    func testSelectedRowContentsOutOfRange() {
        let harness = makeHarness()
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Only"}])
            var item = c.selectedRowContents(99)
        """)
        harness.expectTrue("item === null || item === undefined")
        #expect(!harness.hasException)
    }

    @Test("select fires onSelect with the item dict")
    func testSelectFiresOnSelect() {
        let harness = makeHarness()
        var fired = false
        harness.registerCallback("onSelect") {
            fired = true
        }
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Pick me", valid: true}])
            c.onSelect = function(item) {
                if (item) __test_callback('onSelect')
            }
            c.select(0)
        """)
        let ok = harness.waitFor(timeout: 0.2) { fired }
        #expect(ok, "onSelect should fire when select(0) is called")
        #expect(!harness.hasException)
    }

    @Test("activating an invalid row fires onInvalid and does not fire onSelect")
    func testInvalidRowFiresOnInvalid() {
        let harness = makeHarness()
        var invalidFired = false
        var selectFired = false
        harness.registerCallback("onInvalid") { invalidFired = true }
        harness.registerCallback("onSelect") { selectFired = true }
        harness.eval("""
            var c = hs.chooser.create()
            c.setChoices([{text: "Building…", valid: false}])
            c.onSelect  = function(item) { __test_callback('onSelect') }
            c.onInvalid = function(item) { __test_callback('onInvalid') }
            c.select(0)
        """)
        let ok = harness.waitFor(timeout: 0.2) { invalidFired }
        #expect(ok, "onInvalid should fire for an invalid row")
        #expect(!selectFired, "onSelect should NOT fire for an invalid row")
        #expect(!harness.hasException)
    }
}
