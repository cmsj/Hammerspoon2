//
//  HSSharingModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

// MARK: - Module API protocol

/// Share data with other people and apps via macOS sharing services (Mail, Messages,
/// AirDrop, and more).
///
/// `hs.sharing` wraps `NSSharingService`. Some services from older macOS/Hammerspoon
/// versions are no longer offered here because Apple removed them from the system:
/// Aperture (discontinued in 2015) and the built-in Facebook/Twitter/Sina Weibo/Tencent
/// Weibo/LinkedIn posting and profile-image services (removed in macOS 10.14).
///
/// Items to share can be plain strings — treated as a web/mailto URL if they parse as
/// one, a file path if they start with `/` or `~` and the file exists, otherwise plain
/// text — or `HSImage` objects.
///
/// ## Quick start
///
/// ```js
/// hs.sharing.createShare(hs.sharing.builtinServices.mail)
///     .setCallback((event) => {
///         if (event === 'didShare') console.log('Sent!')
///     })
///     .shareItems(['Check this out', 'https://www.hammerspoon.org'])
/// ```
///
/// ## Sharing a file via AirDrop
///
/// ```js
/// hs.sharing.createShare(hs.sharing.builtinServices.airdrop)
///     .shareItems(['~/Desktop/photo.jpg'])
/// ```
///
/// ## Discovering what can handle an item
///
/// ```js
/// const services = hs.sharing.servicesFor(['https://www.hammerspoon.org'])
/// services.forEach(s => console.log(s.title))
/// ```
@objc protocol HSSharingModuleAPI: JSExport {

    /// A table of shortcut names for the sharing services that are still functional on
    /// modern macOS, mapped to the raw service identifiers `createShare()` expects.
    ///
    /// | Key | Service |
    /// |-----|---------|
    /// | `mail` | Compose an email in Mail |
    /// | `message` | Compose a message in Messages |
    /// | `airdrop` | Send via AirDrop |
    /// | `safariReadingList` | Add to Safari's Reading List |
    /// | `photos` | Add to the Photos library |
    /// | `desktopPicture` | Use as the desktop picture |
    ///
    /// - Example:
    /// ```js
    /// hs.sharing.createShare(hs.sharing.builtinServices.airdrop)
    /// ```
    @objc var builtinServices: [String: String] { get }

    /// Creates a sharing service for the given name.
    /// - Parameter name: A service identifier — one of `hs.sharing.builtinServices`'s values
    /// - Returns: An `HSSharingService`, or null if `name` isn't recognized or the service is unavailable on this system
    /// - Example:
    /// ```js
    /// const share = hs.sharing.createShare(hs.sharing.builtinServices.mail)
    /// ```
    @objc func createShare(_ name: String) -> HSSharingService?

    /// Finds every sharing service — built-in and third-party (e.g. Notes, Reminders,
    /// installed apps' Share Extensions) — that can handle the given items.
    /// - Parameter items: {Array<string|HSImage>} The items to find services for
    /// - Returns: An array of ready-to-use `HSSharingService` objects
    /// - Note: This uses functionality that was deprecated in macOS 13, it may be removed in a future release
    /// - Example:
    /// ```js
    /// const services = hs.sharing.servicesFor(['hello world'])
    /// services.forEach(s => console.log(s.title))
    /// ```
    @objc func servicesFor(_ items: [Any]) -> [HSSharingService]
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSharingModule: NSObject, HSModuleAPI, HSSharingModuleAPI {
    var moduleName = "hs.sharing"
    let engineID: UUID

    private var shares = HSWeakObjectSet<HSSharingService>()
    // Strong retention for shares mid-flight (between shareItems() and the terminal
    // delegate callback), since JS may not keep a reference to a one-liner share chain.
    private var activeShares = Set<HSSharingService>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(moduleName): \(engineID)")
    }

    isolated deinit {
        AKDebug("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = shares.allObjects.count
        return "<hs.sharing: \(n) active share\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    func shutdown() {
        shares.allObjects.forEach { $0.destroy() }
        shares.removeAllObjects()
        activeShares.removeAll()
    }

    // MARK: - HSSharingModuleAPI

    @objc var builtinServices: [String: String] {
        [
            "mail":              NSSharingService.Name.composeEmail.rawValue,
            "message":           NSSharingService.Name.composeMessage.rawValue,
            "airdrop":           NSSharingService.Name.sendViaAirDrop.rawValue,
            "safariReadingList": NSSharingService.Name.addToSafariReadingList.rawValue,
            "photos":            NSSharingService.Name.addToIPhoto.rawValue,
            "desktopPicture":    NSSharingService.Name.useAsDesktopPicture.rawValue,
        ]
    }

    @objc func createShare(_ name: String) -> HSSharingService? {
        // Only accept names from our own curated whitelist, rather than trusting
        // NSSharingService(named:) to validate arbitrary strings — it's undocumented
        // whether it reliably rejects names outside its known set.
        guard builtinServices.values.contains(name),
              let service = NSSharingService(named: NSSharingService.Name(name)) else {
            AKWarning("hs.sharing.createShare(): '\(name)' is not a recognized or available service name — use one of hs.sharing.builtinServices's values")
            return nil
        }
        return wrap(service)
    }

    // FIXME: Remove this when our GitHub Actions workflows are using Xcode27
    //    @diagnose(DeprecatedDeclaration, as: ignored, reason: "No suitable replacement exists")
    @objc func servicesFor(_ items: [Any]) -> [HSSharingService] {
        let coerced = HSSharingService.coerceItems(items)
        return NSSharingService.sharingServices(forItems: coerced).map { wrap($0) }
    }

    // MARK: - Internal

    private func wrap(_ service: NSSharingService) -> HSSharingService {
        let share = HSSharingService(service: service, module: self)
        shares.add(share)
        return share
    }

    func markActive(_ share: HSSharingService) {
        activeShares.insert(share)
    }

    func markInactive(_ share: HSSharingService) {
        activeShares.remove(share)
    }
}
