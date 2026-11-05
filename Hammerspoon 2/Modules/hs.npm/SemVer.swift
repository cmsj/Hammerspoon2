//
//  SemVer.swift
//  Hammerspoon 2
//

import Foundation

/// A semantic version, with just enough npm range syntax to pick a dependency version.
nonisolated struct SemVer: Comparable, Hashable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    /// Empty for a release version.
    let prerelease: String

    init(_ major: Int, _ minor: Int, _ patch: Int, prerelease: String = "") {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `1.2.3`, `v1.2.3`, `=1.2.3`, `1.2.3-beta.1`; build metadata (`+abc`) is ignored.
    init?(_ string: String) {
        var s = Substring(string.trimmingCharacters(in: .whitespaces))
        while let f = s.first, f == "v" || f == "=" { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = s[..<plus] }
        var pre = ""
        if let dash = s.firstIndex(of: "-") {
            pre = String(s[s.index(after: dash)...])
            s = s[..<dash]
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let a = parts[0], let b = parts[1], let c = parts[2] else { return nil }
        self.init(a, b, c, prerelease: pre)
    }

    var description: String { "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-\(prerelease)") }

    static func < (l: SemVer, r: SemVer) -> Bool {
        if (l.major, l.minor, l.patch) != (r.major, r.minor, r.patch) {
            return (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
        }
        // A prerelease sorts before its release.
        // ponytail: two prereleases compare as plain strings, not per semver identifier rules
        switch (l.prerelease.isEmpty, r.prerelease.isEmpty) {
        case (false, true): return true
        case (true, false): return false
        default: return l.prerelease < r.prerelease
        }
    }

    /// Whether this version satisfies an npm range: `1.2.3`, `^1.2`, `~1.2.3`, `1.x`, `*`,
    /// `>=1.2 <2`, `1.2 - 1.8`, joined with `||`. A prerelease only matches itself exactly.
    func satisfies(_ range: String) -> Bool {
        if let exact = SemVer(range) { return self == exact }
        guard prerelease.isEmpty else { return false }
        return range.components(separatedBy: "||").contains { alternative in
            // Unsupported range text matches nothing, never everything.
            guard let comparators = SemVer.comparators(alternative) else { return false }
            return comparators.allSatisfy { $0.matches(self) }
        }
    }

    // MARK: - Ranges

    private struct Comparator {
        let op: String
        let version: SemVer

        func matches(_ v: SemVer) -> Bool {
            switch op {
            case ">=": return v >= version
            case ">": return v > version
            case "<=": return v <= version
            case "<": return v < version
            default: return v == version
            }
        }
    }

    /// `1`, `1.2`, `1.x`, `*`, `1.2.3-beta.1`: a version with trailing parts missing.
    private struct Partial {
        let major: Int?
        let minor: Int?
        let patch: Int?
        let prerelease: String

        init?(_ text: String) {
            var text = Substring(text)
            if let plus = text.firstIndex(of: "+") { text = text[..<plus] }
            if let dash = text.firstIndex(of: "-") {
                prerelease = String(text[text.index(after: dash)...])
                text = text[..<dash]
            } else {
                prerelease = ""
            }
            let parts = text.isEmpty ? [] : text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            // Every part must be a number or a wildcard; anything else ("latest", "garbage") isn't a version.
            guard parts.count <= 3, parts.allSatisfy({ Int($0) != nil || ["x", "X", "*"].contains($0) }) else { return nil }
            func number(_ i: Int) -> Int? { i < parts.count ? Int(parts[i]) : nil }
            major = number(0)
            minor = major == nil ? nil : number(1)
            patch = minor == nil ? nil : number(2)
        }

        var floor: SemVer { SemVer(major ?? 0, minor ?? 0, patch ?? 0, prerelease: prerelease) }
        var isComplete: Bool { patch != nil }

        /// The first version above everything this partial covers (`1.2` → `1.3.0`), nil if complete.
        var next: SemVer? {
            guard let major else { return nil }
            guard let minor else { return SemVer(major + 1, 0, 0) }
            guard patch == nil else { return nil }
            return SemVer(major, minor + 1, 0)
        }
    }

    /// Expands one space-separated comparator set into bounds, or nil if any part of it isn't
    /// range syntax this understands.
    private static let operators = [">=", "<=", ">", "<", "=", "^", "~"]

    private static func comparators(_ text: String) -> [Comparator]? {
        // npm allows a space between an operator and its version (">= 1.2.3 < 2"): rejoin them.
        var tokens: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let last = tokens.last, operators.contains(last) {
                tokens[tokens.count - 1] = last + token
            } else {
                tokens.append(token)
            }
        }
        var out: [Comparator] = []
        // Hyphen range: "1.2.3 - 2.3.4"
        if let i = tokens.firstIndex(of: "-"), i > 0, i + 1 < tokens.count {
            guard let lo = comparators(">=" + tokens[i - 1]), let hi = Partial(tokens[i + 1]) else { return nil }
            out += lo
            out.append(hi.next.map { Comparator(op: "<", version: $0) } ?? Comparator(op: "<=", version: hi.floor))
            tokens.removeSubrange((i - 1)...(i + 1))
        }
        for token in tokens {
            let op = operators.first { token.hasPrefix($0) } ?? ""
            let body = String(token.dropFirst(op.count)).trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard let p = Partial(body) else { return nil }
            guard let major = p.major else { continue }   // "*" / "x" / "": anything
            let lo = p.floor
            switch op {
            case ">=": out.append(Comparator(op: ">=", version: lo))
            case ">": out.append(p.next.map { Comparator(op: ">=", version: $0) } ?? Comparator(op: ">", version: lo))
            case "<": out.append(Comparator(op: "<", version: lo))
            case "<=": out.append(p.next.map { Comparator(op: "<", version: $0) } ?? Comparator(op: "<=", version: lo))
            case "^":
                let hi: SemVer
                if major != 0 { hi = SemVer(major + 1, 0, 0) }
                else if let minor = p.minor, minor != 0 { hi = SemVer(0, minor + 1, 0) }
                else if p.minor == nil { hi = SemVer(1, 0, 0) }
                else if let patch = p.patch { hi = SemVer(0, 0, patch + 1) }
                else { hi = SemVer(0, 1, 0) }
                out += [Comparator(op: ">=", version: lo), Comparator(op: "<", version: hi)]
            case "~":
                let hi = p.minor.map { SemVer(major, $0 + 1, 0) } ?? SemVer(major + 1, 0, 0)
                out += [Comparator(op: ">=", version: lo), Comparator(op: "<", version: hi)]
            default:   // "" or "=": exact if complete, else the partial's whole span
                if let hi = p.next {
                    out += [Comparator(op: ">=", version: lo), Comparator(op: "<", version: hi)]
                } else {
                    out.append(Comparator(op: "=", version: lo))
                }
            }
        }
        return out
    }
}
