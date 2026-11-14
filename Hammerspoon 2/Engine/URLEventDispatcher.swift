//
//  URLEventDispatcher.swift
//  Hammerspoon 2
//

import Foundation
import HammerspoonSDK

/// Bridges URL opens received by the SwiftUI app layer into `hs.urlevent`.
///
/// The SwiftUI app calls `dispatch(_:)` from its `.onOpenURL` modifier. The
/// `hs.urlevent` module sets a handler via `setHandler(_:)` when it initialises
/// and clears it when it shuts down. URLs that arrive before the module loads are
/// logged at the debug level and discarded.
final class URLEventDispatcher {
    static let shared = URLEventDispatcher()
    private init() {}

    @MainActor private var handler: ((URL) -> Void)?

    @MainActor
    func setHandler(_ handler: ((URL) -> Void)?) {
        self.handler = handler
    }

    @MainActor
    func dispatch(_ url: URL) {
        guard let handler else {
            AKDebug("URLEventDispatcher: URL received before hs.urlevent was loaded — discarding: \(url.absoluteString)")
            return
        }
        handler(url)
    }
}
