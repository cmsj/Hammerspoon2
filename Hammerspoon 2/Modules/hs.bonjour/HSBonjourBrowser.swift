//
//  HSBonjourBrowser.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Browser API protocol

/// Discovers Bonjour services and domains advertised on the local network.
///
/// Create via `hs.bonjour.createBrowser()`, then call one of the `searchFor…`
/// methods. Only one search may be active at a time; starting a new search
/// implicitly cancels the current one.
///
/// ## Service search callback events
///
/// | Event | Data | Description |
/// |-------|------|-------------|
/// | `"serviceFound"` | `HSBonjourService` | A matching service appeared |
/// | `"serviceRemoved"` | `HSBonjourService` | A previously found service disappeared |
/// | `"error"` | error string | The search failed |
///
/// ## Domain search callback events
///
/// | Event | Data | Description |
/// |-------|------|-------------|
/// | `"domainFound"` | domain string | A domain was discovered |
/// | `"domainRemoved"` | domain string | A domain disappeared |
/// | `"error"` | error string | The search failed |
///
/// Example:
/// ```js
/// const browser = hs.bonjour.createBrowser()
/// browser.searchForServices('_ssh._tcp.', 'local.', (event, item, moreComing) => {
///     if (event === 'serviceFound') {
///         console.log('Found:', item.name, '— more coming:', moreComing)
///     }
/// })
/// ```
@objc protocol HSBonjourBrowserAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this browser object.
    /// - Example:
    /// ```js
    /// console.log(hs.bonjour.createBrowser().identifier)
    /// ```
    @objc var identifier: String { get }

    /// Whether to search over peer-to-peer Bluetooth/Wi-Fi in addition to
    /// standard network interfaces. Defaults to `false`.
    /// - Example:
    /// ```js
    /// browser.includesPeerToPeer = true
    /// ```
    @objc var includesPeerToPeer: Bool { get set }

    /// Searches for services of the given type in the given domain.
    ///
    /// The callback receives `(event, service, moreComing)` — see the type
    /// documentation for the complete event table.
    /// - Parameter type: service type string, e.g. `"_http._tcp."` or `"_ssh._tcp."`
    /// - Parameter domain: mDNS domain; `"local."` for the local link, `""` for all domains
    /// - Parameter callback: `function(event, service, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// browser.searchForServices('_http._tcp.', 'local.', (ev, svc, more) => {
    ///     if (ev === 'serviceFound') console.log('Found:', svc.name)
    /// })
    /// ```
    @objc @discardableResult func searchForServices(_ type: String, _ domain: String, _ callback: JSValue) -> HSBonjourBrowser

    /// Searches for domains visible to this machine (browsable domains).
    ///
    /// The callback receives `(event, domain, moreComing)` — see the type
    /// documentation for the complete event table.
    /// - Parameter callback: `function(event, domain, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// browser.searchForBrowsableDomains((ev, domain, more) => {
    ///     if (ev === 'domainFound') console.log('Domain:', domain)
    /// })
    /// ```
    @objc @discardableResult func searchForBrowsableDomains(_ callback: JSValue) -> HSBonjourBrowser

    /// Searches for domains on which this machine can register services.
    ///
    /// The callback receives `(event, domain, moreComing)` — see the type
    /// documentation for the complete event table.
    /// - Parameter callback: `function(event, domain, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// browser.searchForRegistrationDomains((ev, domain, more) => {
    ///     if (ev === 'domainFound') console.log('Can register in:', domain)
    /// })
    /// ```
    @objc @discardableResult func searchForRegistrationDomains(_ callback: JSValue) -> HSBonjourBrowser

    /// Stops the current search. Safe to call when no search is active.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// browser.stop()
    /// ```
    @objc @discardableResult func stop() -> HSBonjourBrowser
}

// MARK: - Browser implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourBrowser: NSObject, HSBonjourBrowserAPI, NetServiceBrowserDelegate {
    @objc var typeName = "HSBonjourBrowser"
    @objc let identifier = UUID().uuidString

    private let browser = NetServiceBrowser()
    private var callback: JSValue?

    // Tracks NetService → HSBonjourService identity so the same wrapper object
    // is delivered for both "found" and "removed" events.
    private var serviceTable: [ObjectIdentifier: HSBonjourService] = [:]

    @objc var includesPeerToPeer: Bool {
        get { browser.includesPeerToPeer }
        set { browser.includesPeerToPeer = newValue }
    }

    override init() {
        super.init()
        unsafe browser.delegate = self
    }

    // MARK: - HSBonjourBrowserAPI

    @objc @discardableResult func searchForServices(_ type: String, _ domain: String, _ callback: JSValue) -> HSBonjourBrowser {
        self.callback = callback.isObject ? callback : nil
        browser.searchForServices(ofType: type, inDomain: domain)
        AKTrace("HSBonjourBrowser(\(identifier)): Searching for \(type) in '\(domain)'")
        return self
    }

    @objc @discardableResult func searchForBrowsableDomains(_ callback: JSValue) -> HSBonjourBrowser {
        self.callback = callback.isObject ? callback : nil
        browser.searchForBrowsableDomains()
        AKTrace("HSBonjourBrowser(\(identifier)): Searching for browsable domains")
        return self
    }

    @objc @discardableResult func searchForRegistrationDomains(_ callback: JSValue) -> HSBonjourBrowser {
        self.callback = callback.isObject ? callback : nil
        browser.searchForRegistrationDomains()
        AKTrace("HSBonjourBrowser(\(identifier)): Searching for registration domains")
        return self
    }

    @objc @discardableResult func stop() -> HSBonjourBrowser {
        browser.stop()
        callback = nil
        serviceTable.removeAll()
        AKTrace("HSBonjourBrowser(\(identifier)): Stopped")
        return self
    }

    // MARK: - Internal shutdown helpers

    func stopAllDiscoveredServices() {
        serviceTable.values.forEach {
            $0.clearCallbacks()
            _ = $0.stop()
        }
    }

    // MARK: - NetServiceBrowserDelegate
    // Apple guarantees that these callbacks arrive on the main thread, so they
    // are inferred @MainActor alongside the class — no nonisolated needed.

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = ObjectIdentifier(service)
        let wrapper: HSBonjourService
        if let existing = serviceTable[key] {
            wrapper = existing
        } else {
            wrapper = HSBonjourService(netService: service)
            serviceTable[key] = wrapper
        }
        AKTrace("HSBonjourBrowser(\(identifier)): serviceFound '\(service.name)' (moreComing: \(moreComing))")
        _ = callback?.call(withArguments: ["serviceFound", wrapper, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let key = ObjectIdentifier(service)
        let wrapper = serviceTable.removeValue(forKey: key) ?? HSBonjourService(netService: service)
        AKTrace("HSBonjourBrowser(\(identifier)): serviceRemoved '\(service.name)' (moreComing: \(moreComing))")
        _ = callback?.call(withArguments: ["serviceRemoved", wrapper, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domain: String, moreComing: Bool) {
        AKTrace("HSBonjourBrowser(\(identifier)): domainFound '\(domain)' (moreComing: \(moreComing))")
        _ = callback?.call(withArguments: ["domainFound", domain, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domain: String, moreComing: Bool) {
        AKTrace("HSBonjourBrowser(\(identifier)): domainRemoved '\(domain)' (moreComing: \(moreComing))")
        _ = callback?.call(withArguments: ["domainRemoved", domain, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        let code = errorDict["NSNetServicesErrorCode"]?.intValue ?? -1
        let message = "Bonjour search failed (error code \(code))"
        AKError("HSBonjourBrowser(\(identifier)): \(message)")
        _ = callback?.call(withArguments: ["error", message])
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        AKTrace("HSBonjourBrowser(\(identifier)): Search stopped")
    }
}
