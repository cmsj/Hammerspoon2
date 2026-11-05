//
//  NPMRC.swift
//  Hammerspoon 2
//

import Foundation

/// The parts of an `.npmrc` that matter for fetching packages: which registry serves each
/// scope, and which credentials go to which registry host.
nonisolated struct NPMRC: Equatable, Sendable {
    static let publicRegistry = URL(string: "https://registry.npmjs.org/")!

    var defaultRegistry = NPMRC.publicRegistry
    /// `"@scope"` → registry URL (always with a trailing slash).
    var scopedRegistries: [String: URL] = [:]
    /// npm "nerf dart" (`"host/path/"`) → complete `Authorization` header value.
    var credentials: [String: String] = [:]

    /// Merges `~/.npmrc` and `<projectDir>/.npmrc` (the project's settings win), like npm does.
    static func load(projectDir: URL) -> NPMRC {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npmrc")
        let text = [home, projectDir.appendingPathComponent(".npmrc")]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        return parse(text)
    }

    /// Parses ini-style `.npmrc` text. `#` and `;` lines are comments, later lines win, and
    /// `${VAR}` in a value expands from `environment`.
    static func parse(_ text: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> NPMRC {
        var rc = NPMRC()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" { value = String(value.dropFirst().dropLast()) }
            value = value.replacing(#/\$\{(\w+)\}/#) { environment[String($0.output.1)] ?? "" }

            if key == "registry" {
                if let url = registryURL(value) { rc.defaultRegistry = url }
            } else if key.hasPrefix("@"), key.hasSuffix(":registry") {
                if let url = registryURL(value) { rc.scopedRegistries[String(key.dropLast(":registry".count))] = url }
            } else if key.hasPrefix("//"), let colon = key.lastIndex(of: ":") {
                // //host/path/:_authToken=TOKEN  or  //host/path/:_auth=BASE64(user:pass)
                var nerf = String(key[key.index(key.startIndex, offsetBy: 2)..<colon])
                if !nerf.hasSuffix("/") { nerf += "/" }
                switch key[key.index(after: colon)...] {
                case "_authToken": rc.credentials[nerf] = "Bearer \(value)"
                case "_auth": rc.credentials[nerf] = "Basic \(value)"
                default: break
                }
            }
        }
        return rc
    }

    /// The registry that serves `packageName`: its scope's, if `.npmrc` names one, else the default.
    func registry(for packageName: String) -> URL {
        if packageName.hasPrefix("@"), let slash = packageName.firstIndex(of: "/"),
           let url = scopedRegistries[String(packageName[..<slash])] {
            return url
        }
        return defaultRegistry
    }

    /// The registry document for `packageName`; a scoped name keeps its `@` and encodes the `/`
    /// as `%2F` (`@my-org/my-pkg` → `.../@my-org%2Fmy-pkg`).
    func metadataURL(for packageName: String) -> URL? {
        URL(string: registry(for: packageName).absoluteString + packageName.replacingOccurrences(of: "/", with: "%2F"))
    }

    /// The `Authorization` value for a request to `url`: the credential whose host/path prefix
    /// matches it best. A tarball on the registry's host therefore carries the registry's
    /// token, and a token is never sent to another host.
    func authorization(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        let target = host + (url.port.map { ":\($0)" } ?? "") + url.path + "/"
        return credentials
            .filter { target.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    private static func registryURL(_ value: String) -> URL? {
        URL(string: value.hasSuffix("/") ? value : value + "/")
    }
}
