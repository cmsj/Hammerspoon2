//
//  HSURLEventModule.swift
//  Hammerspoon 2
//

import AppKit
import CoreServices
import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - Module API protocol

/// Handle URL events received by Hammerspoon 2.
///
/// The module responds to `hammerspoon2://` URLs and, when Hammerspoon 2 is
/// configured as the system default handler, also to `http://`, `https://`,
/// and `mailto:` URLs.
///
/// ## Responding to custom hammerspoon2:// events
///
/// URLs take the form `hammerspoon2://eventName?key=value&key2=value2`.
/// The host component (`eventName`) selects the registered callback.
///
/// ```js
/// hs.urlevent.bind("myEvent", (eventName, params, pid, url) => {
///     console.log("param foo = " + params["foo"])
/// })
///
/// // Remove a binding
/// hs.urlevent.bind("myEvent", null)
/// ```
///
/// ## Intercepting http / https / mailto URLs
///
/// Set `hs.urlevent.httpCallback` (or `mailtoCallback`) to a function.
/// You must also set Hammerspoon 2 as the system default handler for the
/// relevant scheme — see `setDefaultHandler(_:_:)`.
///
/// ```js
/// hs.urlevent.httpCallback = (scheme, host, params, fullURL, pid) => {
///     // Forward to a real browser rather than swallowing the link
///     hs.urlevent.openURLWithBundle(fullURL, "com.apple.safari")
/// }
/// ```
///
/// ## Querying and changing default handlers
///
/// ```js
/// const current = hs.urlevent.getDefaultHandler("https")
/// console.log("Current HTTPS handler: " + current)
///
/// const all = hs.urlevent.getAllHandlersForScheme("https")
/// console.log("Available: " + all.join(", "))
///
/// hs.urlevent.setDefaultHandler("https", "com.apple.safari")
/// ```
@objc protocol HSURLEventModuleAPI: JSExport {

    // MARK: hammerspoon2:// event binding

    /// Register or remove a callback for a named `hammerspoon2://` URL event.
    ///
    /// The URL format is `hammerspoon2://eventName?key=value`. The host
    /// component (`eventName`) selects the callback to invoke.
    ///
    /// - Parameters:
    ///   - eventName: The URL host component identifying the event.
    ///   - callback: A function receiving `(eventName, params, senderPID, fullURL)`,
    ///     or `null` to remove any existing binding.
    /// - Example:
    /// ```js
    /// hs.urlevent.bind("myEvent", (name, params, pid, url) => {
    ///     console.log("myEvent — foo=" + params["foo"])
    /// })
    /// // Remove:
    /// hs.urlevent.bind("myEvent", null)
    /// ```
    @objc func bind(_ eventName: String, _ callback: JSFunction)

    // MARK: Callbacks for other URL schemes

    /// Callback invoked when Hammerspoon 2 receives an `http://` or `https://` URL.
    ///
    /// Fires only when Hammerspoon 2 is the system default handler for `http`/`https`.
    /// The callback receives `(scheme, host, params, fullURL, senderPID)`.
    /// Assign `null` to remove the callback.
    ///
    /// - Example:
    /// ```js
    /// hs.urlevent.httpCallback = (scheme, host, params, fullURL, pid) => {
    ///     hs.urlevent.openURLWithBundle(fullURL, "com.apple.safari")
    /// }
    /// ```
    @objc var httpCallback: JSFunction? { get set }

    /// Callback invoked when Hammerspoon 2 receives a `mailto:` URL.
    ///
    /// Fires only when Hammerspoon 2 is the system default handler for `mailto`.
    /// The callback receives `(scheme, host, params, fullURL, senderPID)`.
    /// Assign `null` to remove the callback.
    ///
    /// - Example:
    /// ```js
    /// hs.urlevent.mailtoCallback = (scheme, host, params, fullURL, pid) => {
    ///     console.log("mailto received: " + host)
    /// }
    /// ```
    @objc var mailtoCallback: JSFunction? { get set }

    // MARK: Opening URLs

    /// Open a URL using the system default application for its scheme.
    ///
    /// - Parameter urlString: The URL to open.
    /// - Returns: `true` if the URL was successfully dispatched.
    /// - Example:
    /// ```js
    /// hs.urlevent.openURL("https://www.hammerspoon.org")
    /// ```
    @objc func openURL(_ urlString: String) -> Bool

    /// Open a URL with a specific application identified by bundle ID.
    ///
    /// - Parameters:
    ///   - urlString: The URL to open.
    ///   - bundleID: Bundle identifier of the application to use.
    /// - Returns: `true` if the URL was dispatched to the application.
    /// - Example:
    /// ```js
    /// hs.urlevent.openURLWithBundle("https://example.com", "com.apple.safari")
    /// ```
    @objc func openURLWithBundle(_ urlString: String, _ bundleID: String) -> Bool

    // MARK: Default handler management

    /// Returns the bundle identifier of the default application for a URL scheme.
    ///
    /// - Parameter scheme: The scheme to query, without `://` (e.g. `"https"`, `"mailto"`).
    /// - Returns: The bundle identifier string, or `null` if none is registered.
    /// - Example:
    /// ```js
    /// const handler = hs.urlevent.getDefaultHandler("https")
    /// console.log("Default HTTPS handler: " + handler)
    /// ```
    @objc func getDefaultHandler(_ scheme: String) -> String?

    /// Returns all bundle identifiers capable of handling a URL scheme.
    ///
    /// - Parameter scheme: The scheme to query, without `://` (e.g. `"https"`, `"mailto"`).
    /// - Returns: An array of bundle identifier strings.
    /// - Example:
    /// ```js
    /// const browsers = hs.urlevent.getAllHandlersForScheme("https")
    /// console.log("Available browsers: " + browsers.join(", "))
    /// ```
    @objc func getAllHandlersForScheme(_ scheme: String) -> [String]

    /// Set the default application for a URL scheme.
    ///
    /// macOS may display a confirmation dialog for sensitive schemes such as
    /// `http` and `https`. For custom schemes (`hammerspoon2`) no dialog is shown.
    ///
    /// - Parameters:
    ///   - scheme: The scheme to configure, without `://` (e.g. `"https"`, `"mailto"`).
    ///   - bundleID: Bundle identifier of the application to set as default.
    /// - Returns: `true` if the change was accepted by the system.
    /// - Example:
    /// ```js
    /// hs.urlevent.setDefaultHandler("https", "com.apple.safari")
    /// ```
    @objc func setDefaultHandler(_ scheme: String, _ bundleID: String) -> Bool
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSURLEventModule: NSObject, HSModuleAPI, HSURLEventModuleAPI {
    var name = "hs.urlevent"
    let engineID: UUID

    private var bindings: [String: JSCallback] = [:]
    private var _httpCallback: JSCallback?
    private var _mailtoCallback: JSCallback?

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        URLEventDispatcher.shared.setHandler { [weak self] url in
            self?.handleURL(url)
        }
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        URLEventDispatcher.shared.setHandler(nil)
        for (_, cb) in bindings { cb.detach(from: self) }
        bindings.removeAll()
        _httpCallback?.detach(from: self)
        _httpCallback = nil
        _mailtoCallback?.detach(from: self)
        _mailtoCallback = nil
        AKDebug("Shutdown of \(name): \(engineID)")
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Internal URL dispatch

    func handleURL(_ url: URL) {
        let scheme = url.scheme ?? ""
        let fullURL = url.absoluteString
        let params = parseQueryParams(from: url)
        let senderPID = -1

        switch scheme {
        case "hammerspoon2":
            let eventName = url.host ?? ""
            if let cb = bindings[eventName] {
                _ = cb.call(withArguments: [eventName, params, senderPID, fullURL])
            } else {
                AKWarning("hs.urlevent: No callback bound for event '\(eventName)' (URL: \(fullURL))")
            }

        case "http", "https":
            if let cb = _httpCallback {
                _ = cb.call(withArguments: [scheme, url.host ?? "", params, fullURL, senderPID])
            } else {
                AKWarning("hs.urlevent: Received \(scheme):// URL but httpCallback is not set")
            }

        case "mailto":
            if let cb = _mailtoCallback {
                _ = cb.call(withArguments: [scheme, url.host ?? "", params, fullURL, senderPID])
            } else {
                AKWarning("hs.urlevent: Received mailto: URL but mailtoCallback is not set")
            }

        default:
            AKWarning("hs.urlevent: Received URL with unhandled scheme '\(scheme)': \(fullURL)")
        }
    }

    private func parseQueryParams(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return [:]
        }
        var params: [String: String] = [:]
        for item in items {
            params[item.name] = item.value ?? ""
        }
        return params
    }

    // MARK: - HSURLEventModuleAPI

    @objc func bind(_ eventName: String, _ callback: JSFunction) {
        bindings[eventName]?.detach(from: self)
        if callback.isFunction {
            bindings[eventName] = JSCallback(value: callback, owner: self)
        }
    }

    @objc var httpCallback: JSValue? {
        get { _httpCallback?.value }
        set {
            _httpCallback?.detach(from: self)
            _httpCallback = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc var mailtoCallback: JSValue? {
        get { _mailtoCallback?.value }
        set {
            _mailtoCallback?.detach(from: self)
            _mailtoCallback = newValue.flatMap { JSCallback(value: $0, owner: self) }
        }
    }

    @objc func openURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            AKError("hs.urlevent.openURL(): Invalid URL string: '\(urlString)'")
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    @objc func openURLWithBundle(_ urlString: String, _ bundleID: String) -> Bool {
        guard let url = URL(string: urlString) else {
            AKError("hs.urlevent.openURLWithBundle(): Invalid URL string: '\(urlString)'")
            return false
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            AKError("hs.urlevent.openURLWithBundle(): No application found with bundle ID '\(bundleID)'")
            return false
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    @diagnose(DeprecatedDeclaration, as: ignored, reason: "No suitable non-deprecated alternative exists")
    @objc func getDefaultHandler(_ scheme: String) -> String? {
        // LSCopyDefaultHandlerForURLScheme is deprecated in macOS 12 but has no modern
        // replacement for scheme-only queries (NSWorkspace requires a full URL with host).
        return unsafe LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?
    }

    @diagnose(DeprecatedDeclaration, as: ignored, reason: "No suitable non-deprecated alternative exists")
    @objc func getAllHandlersForScheme(_ scheme: String) -> [String] {
        // LSCopyAllHandlersForURLScheme is deprecated in macOS 12 but has no modern replacement.
        guard let cfArray = unsafe LSCopyAllHandlersForURLScheme(scheme as CFString)?.takeRetainedValue() else {
            return []
        }
        return (cfArray as NSArray).compactMap { $0 as? String }
    }

    @diagnose(DeprecatedDeclaration, as: ignored, reason: "No suitable non-deprecated alternative exists")
    @objc func setDefaultHandler(_ scheme: String, _ bundleID: String) -> Bool {
        // LSSetDefaultHandlerForURLScheme is deprecated in macOS 12 but has no modern replacement.
        return LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString) == noErr
    }
}
