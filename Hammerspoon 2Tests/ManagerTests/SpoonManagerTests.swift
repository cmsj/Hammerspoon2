//
//  SpoonManagerTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
@testable import Hammerspoon_2

struct SpoonManagerTests {

    // MARK: - validateSpoon()

    @Suite("validateSpoon()")
    struct ValidateSpoonTests {

        @Test("throws when spoon.json is missing")
        func testMissingSpoonJSON() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs)

            #expect(throws: SpoonValidationError.self) {
                try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            }
        }

        @Test("throws when spoon.json is malformed JSON")
        func testMalformedSpoonJSON() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/spoon.json", contents: "{ not valid json")
            fs.addFile(atPath: "/Spoons/Foo/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs)

            #expect(throws: SpoonValidationError.self) {
                try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            }
        }

        @Test("throws when a required field is missing")
        func testMissingRequiredField() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/spoon.json", contents: """
                { "name": "Foo", "author": "Someone", "version": "1.0.0" }
            """)
            fs.addFile(atPath: "/Spoons/Foo/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs)

            #expect(throws: SpoonValidationError.self) {
                try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            }
        }

        @Test("throws when a required field is empty")
        func testEmptyRequiredField() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/spoon.json", contents: """
                { "name": "Foo", "author": "", "version": "1.0.0", "description": "A Spoon" }
            """)
            fs.addFile(atPath: "/Spoons/Foo/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs)

            #expect(throws: SpoonValidationError.self) {
                try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            }
        }

        @Test("throws when init.js is missing")
        func testMissingInitJS() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/spoon.json", contents: """
                { "name": "Foo", "author": "Someone", "version": "1.0.0", "description": "A Spoon" }
            """)
            let manager = SpoonManager(fileSystem: fs)

            #expect(throws: SpoonValidationError.self) {
                try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            }
        }

        @Test("returns parsed metadata for a well-formed Spoon")
        func testWellFormedSpoon() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Spoons/Foo/spoon.json", contents: """
                { "name": "Foo", "author": "Someone", "version": "1.0.0", "description": "A Spoon" }
            """)
            fs.addFile(atPath: "/Spoons/Foo/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs)

            let metadata = try manager.validateSpoon(at: URL(fileURLWithPath: "/Spoons/Foo"))
            #expect(metadata.name == "Foo")
            #expect(metadata.author == "Someone")
            #expect(metadata.version == "1.0.0")
            #expect(metadata.description == "A Spoon")
        }
    }

    // MARK: - planImport()

    @Suite("planImport()")
    struct PlanImportTests {

        private func wellFormedBundle(_ fs: MockFileSystem, at path: String, name: String = "Foo", version: String = "1.0.0") {
            fs.addFile(atPath: "\(path)/spoon.json", contents: """
                { "name": "\(name)", "author": "Someone", "version": "\(version)", "description": "A Spoon" }
            """)
            fs.addFile(atPath: "\(path)/init.js", contents: "module.exports = {};")
        }

        @Test("rejects a bundle that isn't a .spoon2")
        func testRejectsWrongExtension() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.zip")
            let manager = SpoonManager(fileSystem: fs, settings: MockSettingsManager())

            #expect(throws: SpoonImportError.self) {
                try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.zip"))
            }
        }

        @Test("propagates validation errors for a malformed bundle")
        func testPropagatesValidationError() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Downloads/Foo.spoon2/init.js", contents: "module.exports = {};")
            let manager = SpoonManager(fileSystem: fs, settings: MockSettingsManager())

            #expect(throws: SpoonValidationError.self) {
                try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))
            }
        }

        @Test("computes the correct name and destination from the bundle's own filename")
        func testComputesDestination() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            #expect(plan.name == "Foo")
            #expect(plan.newMetadata.name == "Foo")
            #expect(plan.destination == URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/Spoons/Foo"))
        }

        @Test("reports no conflict when nothing exists at the destination")
        func testNoConflict() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            guard case .none = plan.conflict else {
                Issue.record("Expected no conflict, got \(plan.conflict)")
                return
            }
        }

        @Test("reports the existing Spoon's metadata when one is already installed under the same name")
        func testConflictWithExistingSpoon() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2", version: "2.0.0")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            wellFormedBundle(fs, at: "/Users/test/.config/Hammerspoon2/Spoons/Foo", version: "1.0.0")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            guard case .existingSpoon(let existing) = plan.conflict else {
                Issue.record("Expected an existingSpoon conflict, got \(plan.conflict)")
                return
            }
            #expect(existing.version == "1.0.0")
            #expect(plan.newMetadata.version == "2.0.0")
        }

        @Test("reports an unreadable conflict when something non-Spoon already exists at the destination")
        func testConflictWithUnreadableExisting() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            fs.addDirectory(atPath: "/Users/test/.config/Hammerspoon2/Spoons/Foo")
            fs.addFile(atPath: "/Users/test/.config/Hammerspoon2/Spoons/Foo/random.txt", contents: "not a spoon")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            guard case .existingUnreadable = plan.conflict else {
                Issue.record("Expected an existingUnreadable conflict, got \(plan.conflict)")
                return
            }
        }
    }

    // MARK: - performImport()

    @Suite("performImport()")
    struct PerformImportTests {

        private func wellFormedBundle(_ fs: MockFileSystem, at path: String) {
            fs.addFile(atPath: "\(path)/spoon.json", contents: """
                { "name": "Foo", "author": "Someone", "version": "1.0.0", "description": "A Spoon" }
            """)
            fs.addFile(atPath: "\(path)/init.js", contents: "module.exports = {};")
        }

        @Test("creates the Spoons directory if it doesn't exist yet")
        func testCreatesSpoonsDirectory() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)
            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            try manager.performImport(plan)

            let spoonsDir = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/Spoons")
            #expect(fs.createdDirectories.contains(spoonsDir))
        }

        @Test("copies the bundle to the plan's destination")
        func testCopiesToDestination() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)
            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            try manager.performImport(plan)

            #expect(fs.copiedItems.count == 1)
            #expect(fs.copiedItems.first?.src == URL(fileURLWithPath: "/Downloads/Foo.spoon2"))
            #expect(fs.copiedItems.first?.dst == URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/Spoons/Foo"))
        }

        @Test("overwrites an existing Spoon with the same name")
        func testOverwritesExistingSpoon() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let existingDestination = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/Spoons/Foo")
            fs.addDirectory(atPath: existingDestination.path)
            fs.addFile(atPath: existingDestination.appendingPathComponent("init.js").path, contents: "old version")
            let manager = SpoonManager(fileSystem: fs, settings: settings)
            let plan = try manager.planImport(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            try manager.performImport(plan)

            #expect(fs.removedItems.contains(existingDestination))
        }
    }
}
