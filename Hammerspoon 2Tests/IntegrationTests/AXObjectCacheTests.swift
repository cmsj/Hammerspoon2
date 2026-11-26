//
//  AXObjectCacheTests.swift
//  Hammerspoon 2Tests
//

import Testing
import AppKit
import AXSwift
@testable import Hammerspoon_2

/// The cache doesn't look at a window's element beyond its ID, so these use this process's own
/// application element, with made-up window IDs far beyond any real window's
@MainActor
@Suite("AXObjectCache")
struct AXObjectCacheTests {
    private let element = UIElement(AXUIElementCreateApplication(getpid()))

    private func unusedWindowID() -> Int {
        Int.random(in: 2_000_000_000..<3_000_000_000)
    }

    @Test("the same window ID gives the same window, while something holds it")
    func testSameWindow() {
        let id = unusedWindowID()
        let first = AXObjectCache.shared.window(element: element, app: .current, id: id)
        let second = AXObjectCache.shared.window(element: element, app: .current, id: id)
        #expect(first === second)
        #expect(AXObjectCache.shared.window(element: element, app: .current, id: id + 1) !== first)
    }

    @Test("a window nothing else holds is released")
    func testWindowIsHeldWeakly() {
        let id = unusedWindowID()
        weak var window: HSWindow?
        autoreleasepool {
            let held = AXObjectCache.shared.window(element: element, app: .current, id: id)
            window = held
            #expect(AXObjectCache.shared.window(element: element, app: .current, id: id) === held)
        }
        #expect(window == nil)
    }

    @Test("windows whose IDs can't be read aren't shared")
    func testUnknownIDsAreNotShared() {
        let first = AXObjectCache.shared.window(element: element, app: .current, id: 0)
        let second = AXObjectCache.shared.window(element: element, app: .current, id: 0)
        #expect(first !== second)
    }

    @Test("the same running application gives the same application, while something holds it")
    func testSameApplication() {
        let first = AXObjectCache.shared.application(for: .current)
        let again = NSRunningApplication(processIdentifier: getpid())
        #expect(AXObjectCache.shared.application(for: .current) === first)
        if let again {
            #expect(AXObjectCache.shared.application(for: again) === first)
        }
    }

    @Test("only the same process counts as the same application")
    func testSameProcess() throws {
        let current = NSRunningApplication.current
        #expect(AXObjectCache.isSameProcess(current, current))
        let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        #expect(!AXObjectCache.isSameProcess(current, finder))
    }
}
