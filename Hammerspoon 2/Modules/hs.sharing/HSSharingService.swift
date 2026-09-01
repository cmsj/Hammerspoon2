//
//  HSSharingService.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import AppKit

// MARK: - API protocol

/// A configured sharing service, wrapping `NSSharingService`.
///
/// Create instances via `hs.sharing.createShare()` or `hs.sharing.servicesFor()`.
/// Configure with `setCallback()`, `recipients`, and `subject` as needed, then call
/// `shareItems()`.
///
/// - Example:
/// ```js
/// hs.sharing.createShare(hs.sharing.builtinServices.mail)
///     .setCallback((event, items, error) => {
///         if (event === 'didShare') console.log('Shared!')
///         else if (event === 'didFail') console.error('Failed: ' + error)
///     })
///     .shareItems(['Check this out', 'https://www.hammerspoon.org'])
/// ```
@objc protocol HSSharingServiceAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this share object (UUID string).
    @objc var identifier: String { get }

    /// The user-visible title of the service, e.g. "Mail" or "AirDrop".
    /// - Example:
    /// ```js
    /// console.log(share.title)  // "Mail"
    /// ```
    @objc var title: String { get }

    /// The service's icon.
    /// - Example:
    /// ```js
    /// const icon = share.image
    /// ```
    @objc var image: HSImage { get }

    /// An alternate icon for the service, if one is provided, otherwise null.
    @objc var alternateImage: HSImage? { get }

    /// Recipients (e.g. email addresses) for services that support them, such as Mail or Messages.
    /// - Example:
    /// ```js
    /// share.recipients = ['someone@example.com']
    /// ```
    @objc var recipients: [String] { get set }

    /// The subject line, for services that support one, such as Mail.
    /// - Example:
    /// ```js
    /// share.subject = 'Look at this'
    /// ```
    @objc var subject: String { get set }

    /// The message body, populated once the share is in progress. Empty until then.
    @objc var messageBody: String? { get }

    /// A permanent link to the shared content, if the service provides one. Populated once
    /// the share is in progress; otherwise null.
    @objc var permanentLink: String? { get }

    /// The account name used to perform the share, if applicable. Populated once the share
    /// is in progress; otherwise null.
    @objc var accountName: String? { get }

    /// File paths of any attachments included in the share, populated once the share
    /// completes. Empty until then.
    @objc var attachments: [String] { get }

    /// Checks whether this service can share the given items.
    ///
    /// Items may be strings (treated as a web/mailto URL if they parse as one, a file
    /// path if they start with `/` or `~` and the file exists, otherwise plain text) or
    /// `HSImage` objects.
    /// - Parameter items: {Array<string|HSImage>} The items to check
    /// - Returns: true if this service can share all of the given items
    /// - Note: Unsupported items will be ignored
    /// - Example:
    /// ```js
    /// if (share.canShareItems(['hello'])) { ... }
    /// ```
    @objc func canShareItems(_ items: [Any]) -> Bool

    /// Attempts to share the given items with this service.
    ///
    /// If the service cannot handle the items, this logs a warning and returns `false`
    /// without doing anything further. Otherwise the share is started; it is asynchronous
    /// — use `setCallback()` to find out when it completes.
    /// - Parameter items: {Array<string|HSImage>} The items to share
    /// - Returns: true if the share was started
    /// - Note: Unsupported items will be ignored
    /// - Example:
    /// ```js
    /// share.shareItems(['Check this out', 'https://www.hammerspoon.org'])
    /// ```
    @objc @discardableResult func shareItems(_ items: [Any]) -> Bool

    /// Registers a callback for share lifecycle events.
    ///
    /// The callback is called with:
    /// - `event` (string): one of `"willShare"`, `"didShare"`, `"didFail"`
    /// - `items` (array): the items involved
    /// - `error` (string, `"didFail"` only): a description of the failure
    /// - Parameter fn: {(event: string, items: any[], error?: string) => void} Called with the lifecycle event name, items, and optional error message
    /// - Returns: this share object, for chaining
    /// - Example:
    /// ```js
    /// share.setCallback((event, items, error) => console.log(event))
    /// ```
    @objc @discardableResult func setCallback(_ fn: JSFunction) -> HSSharingService
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSSharingService: NSObject, HSSharingServiceAPI, NSSharingServiceDelegate {
    @objc var typeName = "HSSharingService"

    @objc func toString() -> String {
        return "<\(typeName): \(title)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }
    @objc let identifier = UUID().uuidString

    let service: NSSharingService
    weak var module: HSSharingModule?
    private var callback: JSCallback?

    init(service: NSSharingService, module: HSSharingModule) {
        self.service = service
        self.module = module
        super.init()
        service.delegate = self
        AKGarbage("Init of HSSharingService(\(identifier)): \(service.title)")
    }

    isolated deinit {
        destroy()
        AKGarbage("deinit of HSSharingService(\(identifier))")
    }

    func destroy() {
        service.delegate = nil
        callback?.detach(from: self)
        callback = nil
    }

    // MARK: - HSSharingServiceAPI

    @objc var title: String { service.title }
    @objc var image: HSImage { service.image.toBridge() }
    @objc var alternateImage: HSImage? { service.alternateImage?.toBridge() }

    @objc var recipients: [String] {
        get { service.recipients ?? [] }
        set { service.recipients = newValue }
    }

    @objc var subject: String {
        get { service.subject ?? "" }
        set { service.subject = newValue }
    }

    @objc var messageBody: String? { service.messageBody }
    @objc var permanentLink: String? { service.permanentLink?.absoluteString }
    @objc var accountName: String? { service.accountName }
    @objc var attachments: [String] { service.attachmentFileURLs?.map(\.path) ?? [] }

    @objc func canShareItems(_ items: [Any]) -> Bool {
        service.canPerform(withItems: HSSharingService.coerceItems(items))
    }

    @objc @discardableResult func shareItems(_ items: [Any]) -> Bool {
        let coerced = HSSharingService.coerceItems(items)
        guard service.canPerform(withItems: coerced) else {
            AKWarning("hs.sharing: '\(service.title)' cannot share the given items")
            return false
        }
        module?.markActive(self)
        service.perform(withItems: coerced)
        return true
    }

    @objc @discardableResult func setCallback(_ fn: JSFunction) -> HSSharingService {
        callback?.detach(from: self)
        callback = JSCallback(value: fn, owner: self)
        return self
    }

    // MARK: - NSSharingServiceDelegate
    // These methods are imported as @MainActor (NS_SWIFT_UI_ACTOR in the SDK header),
    // matching this class's own isolation, so no assumeIsolated bridging is needed.

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        _ = callback?.call(withArguments: ["willShare", items])
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        _ = callback?.call(withArguments: ["didShare", items])
        module?.markInactive(self)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        _ = callback?.call(withArguments: ["didFail", items, error.localizedDescription])
        module?.markInactive(self)
    }

    // MARK: - Item coercion

    /// Converts JS-supplied items (strings, HSImage objects) into the native types
    /// NSSharingService requires (NSURL, NSImage, NSString — all NSPasteboardWriting).
    static func coerceItems(_ items: [Any]) -> [Any] {
        items.compactMap { item -> Any? in
            if let hsImage = item as? HSImage {
                return hsImage.image
            }
            if let str = item as? String {
                if let url = URL(string: str), url.scheme != nil {
                    return url as NSURL
                }
                if str.hasPrefix("/") || str.hasPrefix("~") {
                    let expanded = (str as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expanded) {
                        return URL(fileURLWithPath: expanded) as NSURL
                    }
                }
                return str as NSString
            }
            AKWarning("hs.sharing: Ignoring unsupported item of type \(type(of: item))")
            return nil
        }
    }
}
