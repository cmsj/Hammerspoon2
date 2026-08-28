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

    // MARK: - importSpoon()

    @Suite("importSpoon()")
    struct ImportSpoonTests {

        private func wellFormedBundle(_ fs: MockFileSystem, at path: String) {
            fs.addFile(atPath: "\(path)/spoon.json", contents: """
                { "name": "Foo", "author": "Someone", "version": "1.0.0", "description": "A Spoon" }
            """)
            fs.addFile(atPath: "\(path)/init.js", contents: "module.exports = {};")
        }

        @Test("rejects a bundle that isn't a .spoon2")
        func testRejectsWrongExtension() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.zip")
            let settings = MockSettingsManager()
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            #expect(throws: SpoonImportError.self) {
                try manager.importSpoon(from: URL(fileURLWithPath: "/Downloads/Foo.zip"))
            }
        }

        @Test("propagates validation errors for a malformed bundle")
        func testPropagatesValidationError() throws {
            let fs = MockFileSystem()
            fs.addFile(atPath: "/Downloads/Foo.spoon2/init.js", contents: "module.exports = {};")
            let settings = MockSettingsManager()
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            #expect(throws: SpoonValidationError.self) {
                try manager.importSpoon(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))
            }
        }

        @Test("creates the Spoons directory if it doesn't exist yet")
        func testCreatesSpoonsDirectory() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            try manager.importSpoon(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            let spoonsDir = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/Spoons")
            #expect(fs.createdDirectories.contains(spoonsDir))
        }

        @Test("copies the bundle to <configDir>/Spoons/<name>, using the bundle's own filename as the name")
        func testCopiesToCorrectDestination() throws {
            let fs = MockFileSystem()
            wellFormedBundle(fs, at: "/Downloads/Foo.spoon2")
            let settings = MockSettingsManager()
            settings.configLocation = URL(fileURLWithPath: "/Users/test/.config/Hammerspoon2/init.js")
            let manager = SpoonManager(fileSystem: fs, settings: settings)

            let (name, metadata) = try manager.importSpoon(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            #expect(name == "Foo")
            #expect(metadata.name == "Foo")
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

            try manager.importSpoon(from: URL(fileURLWithPath: "/Downloads/Foo.spoon2"))

            #expect(fs.removedItems.contains(existingDestination))
        }
    }
}
