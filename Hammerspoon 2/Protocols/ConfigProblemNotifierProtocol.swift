//
//  ConfigProblemNotifierProtocol.swift
//  Hammerspoon 2
//
//  Created by Claude on 15/11/2026.
//

import Foundation

/// Something that stopped the user's config from loading cleanly
@_documentation(visibility: private)
nonisolated enum ConfigProblem: Equatable, Sendable {
    /// The directory the config file should be in doesn't exist
    case missingDirectory(URL)
    /// The config directory exists, but the config file doesn't
    case missingFile(URL)
    /// The config file exists, but couldn't be read
    case unreadableFile(URL, reason: String)
    /// Evaluating the config raised an uncaught JavaScript exception
    case scriptError(String)
}

/// Protocol abstraction for telling the user about config problems, to enable dependency injection and testability
@_documentation(visibility: private)
protocol ConfigProblemNotifierProtocol {
    /// Tells the user about a problem with their config, replacing any earlier notification about one
    /// - Parameter problem: The problem to tell them about
    func notify(_ problem: ConfigProblem)

    /// Removes any notification about a config problem, e.g. because the config is being loaded again
    func withdraw()
}
