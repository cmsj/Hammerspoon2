//
//  ConfigProblemTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 15/11/2026.
//

import Foundation
import Testing
@testable import Hammerspoon_2

/// The notification shown for each config problem: what it says, and where its action takes the user.
@Suite("Config problem notifications")
struct ConfigProblemTests {
    private nonisolated static let configURL = URL(fileURLWithPath: "/Users/me/.config/Hammerspoon2/init.js")

    @Test("Missing or unreadable config offers Settings, a script error offers the Console", arguments: [
        (ConfigProblem.missingDirectory(configURL.deletingLastPathComponent()), ConfigProblem.Remedy.openSettings),
        (.missingFile(configURL), .openSettings),
        (.unreadableFile(configURL, reason: "Permission denied."), .openSettings),
        (.scriptError("TypeError: boom (init.js:2)"), .openConsole),
    ])
    func remedy(problem: ConfigProblem, remedy: ConfigProblem.Remedy) {
        #expect(problem.remedy == remedy)
    }

    @Test("The notification names what's missing")
    func missingPathsAreNamed() {
        #expect(ConfigProblem.missingDirectory(Self.configURL.deletingLastPathComponent()).body.contains("/Users/me/.config/Hammerspoon2/"))
        #expect(ConfigProblem.missingFile(Self.configURL).body.contains("/Users/me/.config/Hammerspoon2/init.js"))
    }

    @Test("The notification includes the error")
    func errorsAreIncluded() {
        #expect(ConfigProblem.unreadableFile(Self.configURL, reason: "Permission denied.").body.hasPrefix("Permission denied."))
        #expect(ConfigProblem.scriptError("TypeError: boom (init.js:2)").body.hasPrefix("TypeError: boom (init.js:2)"))
    }

    @Test("Each remedy has its own notification category")
    func categoriesAreDistinct() {
        let identifiers = ConfigProblem.Remedy.allCases.map(\.categoryIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
    }
}
