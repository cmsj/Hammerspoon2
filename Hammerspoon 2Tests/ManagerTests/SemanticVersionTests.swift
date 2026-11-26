//
//  SemanticVersionTests.swift
//  Hammerspoon 2Tests
//

import Testing
@testable import Hammerspoon_2

struct SemanticVersionTests {

    @Test("versions are ordered as Semantic Versioning orders them", arguments: [
        ("1.0.0-alpha", "1.0.0-alpha.1"),
        ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
        ("1.0.0-alpha.beta", "1.0.0-beta"),
        ("1.0.0-beta", "1.0.0-beta.2"),
        ("1.0.0-beta.2", "1.0.0-beta.11"),
        ("1.0.0-beta.0", "1.0.0-beta.1"),
        ("1.0.0-beta.9", "1.0.0-beta.0a"),
        ("1.0.0-beta.9", "1.0.0-beta.10"),
        ("1.0.0-beta.11", "1.0.0-rc.1"),
        ("1.0.0-rc.1", "1.0.0"),
        ("1.0.0", "1.0.1"),
        ("1.0.1", "1.1"),
        ("1.2", "1.10.0"),
        ("1.10.0", "2.0.0-beta.1"),
        ("1.0.0-beta.99999999999999999999", "1.0.0-beta.100000000000000000000"),
    ])
    func ordering(older: String, newer: String) throws {
        let older = try #require(SemanticVersion(older))
        let newer = try #require(SemanticVersion(newer))
        #expect(older < newer)
        #expect((newer < older) == false)
        #expect(older != newer)
    }

    @Test("missing components count as zero, and build metadata is ignored", arguments: [
        ("1", "1.0.0"),
        ("1.2", "1.2.0"),
        ("1.2.3+build.7", "1.2.3"),
        ("1.0.0-beta.4+abc", "1.0.0-beta.4"),
        ("1.0.0-beta.4+007", "1.0.0-beta.4"),
        ("0.0.0", "0"),
        (" 1.2.3 ", "1.2.3"),
    ])
    func equality(left: String, right: String) throws {
        let left = try #require(SemanticVersion(left))
        let right = try #require(SemanticVersion(right))
        #expect(left == right)
        #expect((left < right) == false)
        #expect((right < left) == false)
    }

    @Test("strings that aren't versions aren't parsed", arguments: [
        "", "v1.2.3", "1.2.3.4", "1..2", "1.2.", ".1", "1.x", "-1.0", "1.0.0-", "1.0.0-beta..1",
        "1.0.0+", "1.0.0-beta_1", "(unknown app version)", "١.٢.٣", "01.0.0", "1.02", "1.0.0-beta.01",
    ])
    func malformed(string: String) {
        #expect(SemanticVersion(string) == nil)
    }

    @Test("description is the version as written")
    func description() throws {
        #expect(try #require(SemanticVersion("1.0.0-beta.4")).description == "1.0.0-beta.4")
    }
}
