//
//  SemanticVersion.swift
//  Hammerspoon 2
//

import Foundation

/// A version number such as `1.2.3` or `1.0.0-beta.4`, ordered the way Semantic Versioning orders
/// them: numerically, component by component, with a prerelease before the release it leads up
/// to (`1.0.0-beta.9` < `1.0.0-beta.10` < `1.0.0-rc.1` < `1.0.0`).
///
/// One to three numeric components are accepted, and missing ones count as zero, so `1.2` equals
/// `1.2.0`. As in Semantic Versioning, numbers (other than zero) can't start with a zero. Build
/// metadata after a `+` is accepted and ignored.
struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    /// The major, minor and patch numbers
    let numbers: [Int]
    /// The dot-separated prerelease identifiers, empty for a release
    let prerelease: [String]
    /// The version as it was written
    let description: String

    init?(_ string: String) {
        let text = string.trimmingCharacters(in: .whitespaces)
        var rest = Substring(text)

        if let plus = rest.firstIndex(of: "+") {
            let build = rest[rest.index(after: plus)...]
            guard Self.isValidIdentifierList(build) else { return nil }
            rest = rest[..<plus]
        }

        var prerelease: [String] = []
        if let dash = rest.firstIndex(of: "-") {
            let identifiers = rest[rest.index(after: dash)...]
            guard Self.isValidIdentifierList(identifiers) else { return nil }
            prerelease = identifiers.split(separator: ".").map(String.init)
            guard !prerelease.contains(where: { $0.allSatisfy(\.isASCIIDigit) && Self.hasLeadingZero($0) }) else { return nil }
            rest = rest[..<dash]
        }

        let components = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy(\.isASCIIDigit), !Self.hasLeadingZero(component),
                  let number = Int(component) else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)

        self.numbers = numbers
        self.prerelease = prerelease
        self.description = text
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.numbers == rhs.numbers && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.numbers != rhs.numbers {
            return lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
        }
        // A prerelease comes before the release itself
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false): break
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            return precedes(left, right)
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    /// Orders two differing prerelease identifiers: numbers numerically, before any word, and
    /// words in ASCII order
    private static func precedes(_ left: String, _ right: String) -> Bool {
        switch (left.allSatisfy(\.isASCIIDigit), right.allSatisfy(\.isASCIIDigit)) {
        case (true, true):
            // Compared as digit strings, so numbers too big for an Int still order correctly. They
            // have no leading zeroes, so the longer one is the bigger.
            return left.count != right.count ? left.count < right.count : left < right
        case (true, false): return true
        case (false, true): return false
        case (false, false): return left < right
        }
    }

    /// Whether a number has a leading zero, which Semantic Versioning doesn't allow
    private static func hasLeadingZero(_ digits: some StringProtocol) -> Bool {
        digits.count > 1 && digits.first == "0"
    }

    /// Whether `list` is one or more non-empty dot-separated identifiers of ASCII letters, digits
    /// and hyphens
    private static func isValidIdentifierList(_ list: Substring) -> Bool {
        let identifiers = list.split(separator: ".", omittingEmptySubsequences: false)
        return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
            !identifier.isEmpty && identifier.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" }
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
