//
//  OpenedURLRoute.swift
//  Hammerspoon 2
//

import Foundation

/// Where `AppDelegate.application(_:open:)` sends a URL opened with the app
@_documentation(visibility: private)
enum OpenedURLRoute: Equatable {
    /// A `.spoon2` bundle to install
    case importSpoon
    /// A file or folder to pass to `hs.onOpenFile`, via `OpenFileQueue`
    case openFile
    /// A non-file URL, such as `hammerspoon2://`, for `URLEventDispatcher`
    case urlEvent

    /// - Parameters:
    ///   - url: The URL that was opened
    ///   - importSpoonsOnOpen: Whether opened `.spoon2` bundles are installed, rather than
    ///     treated like any other file
    init(for url: URL, importSpoonsOnOpen: Bool) {
        if !url.isFileURL {
            self = .urlEvent
        } else if importSpoonsOnOpen, url.pathExtension.lowercased() == "spoon2" {
            self = .importSpoon
        } else {
            self = .openFile
        }
    }
}
