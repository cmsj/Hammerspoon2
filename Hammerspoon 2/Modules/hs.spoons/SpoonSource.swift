//
//  SpoonSource.swift
//  Hammerspoon 2
//

import Foundation

/// Why an `hs.spoons` operation failed. `code` reaches JS as the rejected Error's `code` property.
nonisolated struct SpoonInstallError: LocalizedError, Equatable {
    enum Code: String {
        /// An argument was malformed, e.g. an unparseable source or a `ref` given for a zip URL
        case invalidArgument = "EINVALIDARG"
        /// The download wasn't found, or the archive has no Spoon with the requested name
        case notFound = "ENOTFOUND"
        /// The download failed for any other reason
        case network = "ENETWORK"
        /// The download didn't match the expected SHA-256
        case integrity = "EINTEGRITY"
        /// The archive, or the Spoon in it, isn't well-formed
        case invalidSpoon = "EINVALIDSPOON"
        /// A Spoon with that name is already installed
        case exists = "EEXISTS"
        /// No Spoon with that name is installed
        case notInstalled = "ENOTINSTALLED"
        /// The Spoon is installed, but wasn't installed by `hs.spoons.install()`, so there's
        /// nowhere to update it from
        case noSource = "ENOSOURCE"
        /// Anything else, such as failing to write the Spoon to disk
        case io = "EIO"
    }

    let code: Code
    let message: String

    init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    var errorDescription: String? { message }
}

/// Where a Spoon is downloaded from: a GitHub repository, or any zip file served over HTTPS
enum SpoonSource: Equatable {
    case gitHub(owner: String, repository: String)
    case zip(URL)

    /// Parses `"owner/repo"`, `"https://github.com/owner/repo"`, or any `https://` URL, which is
    /// taken to point at a zip file
    init(parsing string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        if let (owner, repository) = Self.parseGitHubShorthand(trimmed) {
            self = .gitHub(owner: owner, repository: repository)
            return
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host() != nil else {
            throw SpoonInstallError(.invalidArgument, "'\(string)' is not a GitHub repository (\"owner/repo\") or a URL")
        }
        guard scheme == "https" else {
            throw SpoonInstallError(.invalidArgument, "'\(string)' must be an https:// URL")
        }

        // A URL to a repository's page on GitHub, rather than to a file
        let host = url.host()?.lowercased()
        if host == "github.com" || host == "www.github.com" {
            let components = url.path().split(separator: "/").map(String.init)
            if components.count == 2, let (owner, repository) = Self.parseGitHubShorthand(components.joined(separator: "/")) {
                self = .gitHub(owner: owner, repository: repository)
                return
            }
        }

        self = .zip(url)
    }

    /// The URL of the zip file to download
    /// - Parameter ref: A branch, tag or commit SHA. Only valid for GitHub sources, which use the
    ///   repository's default branch when it's nil.
    func downloadURL(ref: String?) throws -> URL {
        switch self {
        case .gitHub(let owner, let repository):
            let ref = ref ?? "HEAD"
            guard Self.isValidRef(ref) else {
                throw SpoonInstallError(.invalidArgument, "'\(ref)' is not a valid branch, tag or commit")
            }
            guard let url = URL(string: "https://github.com/\(owner)/\(repository)/archive/\(ref).zip") else {
                throw SpoonInstallError(.invalidArgument, "Couldn't build a download URL for \(owner)/\(repository)@\(ref)")
            }
            return url
        case .zip(let url):
            if ref != nil {
                throw SpoonInstallError(.invalidArgument, "'ref' can only be used with a GitHub repository, not a zip URL")
            }
            return url
        }
    }

    /// How the source is shown to the user and recorded: `"owner/repo"` or the URL
    var displayString: String {
        switch self {
        case .gitHub(let owner, let repository): "\(owner)/\(repository)"
        case .zip(let url): url.absoluteString
        }
    }

    // MARK: - Private

    private static func parseGitHubShorthand(_ string: String) -> (String, String)? {
        guard let match = string.wholeMatch(of: #/([A-Za-z0-9][A-Za-z0-9\-]{0,38})\/([A-Za-z0-9._\-]+)/#) else {
            return nil
        }
        var repository = String(match.2)
        if repository.lowercased().hasSuffix(".git") {
            repository = String(repository.dropLast(4))
        }
        guard !repository.isEmpty, repository != ".", repository != ".." else { return nil }
        return (String(match.1), repository)
    }

    private static func isValidRef(_ ref: String) -> Bool {
        ref.wholeMatch(of: #/[A-Za-z0-9._\-\/]+/#) != nil
            && !ref.hasPrefix("/") && !ref.hasPrefix("-") && !ref.hasSuffix("/")
            && !ref.contains("..") && !ref.contains("//")
    }
}
