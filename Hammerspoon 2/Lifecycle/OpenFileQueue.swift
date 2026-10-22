//
//  OpenFileQueue.swift
//  Hammerspoon 2
//

import Foundation

/// Delivers files opened with the app to `hs.onOpenFile`, holding any that arrive before the
/// config has loaded. AppKit delivers the file that launched the app before
/// `applicationDidFinishLaunching`, which is where the config is loaded, so without this
/// it would always be dropped.
@_documentation(visibility: private)
final class OpenFileQueue {
    private let deliver: (URL) -> Void
    private var isReady = false
    private var pending: [URL] = []

    /// - Parameter deliver: Called with each opened file, once the queue is ready
    init(deliver: @escaping (URL) -> Void) {
        self.deliver = deliver
    }

    /// Delivers `url` now if the queue is ready, or holds it until it is
    /// - Parameter url: The file that was opened
    func open(_ url: URL) {
        if isReady {
            deliver(url)
        } else {
            pending.append(url)
        }
    }

    /// Marks the queue ready, after the config has loaded, and delivers any held files in the
    /// order they were opened
    func markReady() {
        isReady = true
        let files = pending
        pending.removeAll()
        files.forEach(deliver)
    }
}
