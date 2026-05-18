//
//  HSBonjourSearch.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Search API protocol

/// Discovers Bonjour services and domains advertised on the local network.
///
/// Create via `hs.bonjour.newSearch()`, then call one of the `find…` methods.
/// Each search type uses its own underlying `NetServiceBrowser`, so service and
/// domain searches can run concurrently. Restarting any single search type stops
/// only that browser before beginning the new one.
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
/// const search = hs.bonjour.newSearch()
/// search.findServices('_ssh._tcp.', 'local.', (event, svc, moreComing) => {
///     if (event === 'serviceFound') {
///         console.log('Found:', svc.name, '— more coming:', moreComing)
///     }
/// })
/// ```
@objc protocol HSBonjourSearchAPI: HSTypeAPI, JSExport {

    /// A unique identifier for this search object.
    /// - Example:
    /// ```js
    /// console.log(hs.bonjour.newSearch().identifier)
    /// ```
    @objc var identifier: String { get }

    /// Whether to search over peer-to-peer Bluetooth/Wi-Fi in addition to
    /// standard network interfaces. Defaults to `false`.
    /// - Example:
    /// ```js
    /// search.includesPeerToPeer = true
    /// ```
    @objc var includesPeerToPeer: Bool { get set }

    /// Searches for services of the given type in the given domain.
    ///
    /// If a service search is already active it is stopped before starting the
    /// new one. Domain searches are unaffected. The callback receives
    /// `(event, service, moreComing)` — see the type documentation for the
    /// complete event table.
    /// - Parameter type: service type string, e.g. `"_http._tcp."` or `"_ssh._tcp."`
    /// - Parameter domain: mDNS domain; `"local."` for the local link, `""` for all domains
    /// - Parameter callback: `function(event, service, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// search.findServices('_http._tcp.', 'local.', (ev, svc, more) => {
    ///     if (ev === 'serviceFound') console.log('Found:', svc.name)
    /// })
    /// ```
    @objc @discardableResult func findServices(_ type: String, _ domain: String, _ callback: JSValue) -> HSBonjourSearch

    /// Searches for domains visible to this machine (browsable domains).
    ///
    /// If a browsable-domain search is already active it is stopped before
    /// starting the new one. Service and registration-domain searches are
    /// unaffected. The callback receives `(event, domain, moreComing)`.
    /// - Parameter callback: `function(event, domain, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// search.findBrowsableDomains((ev, domain, more) => {
    ///     if (ev === 'domainFound') console.log('Domain:', domain)
    /// })
    /// ```
    @objc @discardableResult func findBrowsableDomains(_ callback: JSValue) -> HSBonjourSearch

    /// Searches for domains on which this machine can register services.
    ///
    /// If a registration-domain search is already active it is stopped before
    /// starting the new one. Service and browsable-domain searches are
    /// unaffected. The callback receives `(event, domain, moreComing)`.
    /// - Parameter callback: `function(event, domain, moreComing)` called for each result
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// search.findRegistrationDomains((ev, domain, more) => {
    ///     if (ev === 'domainFound') console.log('Can register in:', domain)
    /// })
    /// ```
    @objc @discardableResult func findRegistrationDomains(_ callback: JSValue) -> HSBonjourSearch

    /// Stops all active searches. Safe to call when no search is active.
    /// - Returns: self, for chaining
    /// - Example:
    /// ```js
    /// search.stop()
    /// ```
    @objc @discardableResult func stop() -> HSBonjourSearch
}

// MARK: - Search implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourSearch: NSObject, HSBonjourSearchAPI, NetServiceBrowserDelegate {
    @objc var typeName = "HSBonjourSearch"
    @objc let identifier = UUID().uuidString

    private let servicesBrowser = NetServiceBrowser()
    private let domainsBrowser = NetServiceBrowser()
    private let registrationBrowser = NetServiceBrowser()

    private var servicesCallback: JSValue?
    private var domainsCallback: JSValue?
    private var registrationCallback: JSValue?

    // Tracks NetService → HSBonjourService identity so the same wrapper object
    // is delivered for both "found" and "removed" events.
    private var serviceTable: [ObjectIdentifier: HSBonjourService] = [:]

    @objc var includesPeerToPeer: Bool {
        get { servicesBrowser.includesPeerToPeer }
        set {
            servicesBrowser.includesPeerToPeer = newValue
            domainsBrowser.includesPeerToPeer = newValue
            registrationBrowser.includesPeerToPeer = newValue
        }
    }

    override init() {
        super.init()
        unsafe servicesBrowser.delegate = self
        unsafe domainsBrowser.delegate = self
        unsafe registrationBrowser.delegate = self
    }

    // MARK: - HSBonjourSearchAPI

    @objc @discardableResult func findServices(_ type: String, _ domain: String, _ callback: JSValue) -> HSBonjourSearch {
        servicesBrowser.stop()
        serviceTable.removeAll()
        servicesCallback = callback.isObject ? callback : nil
        servicesBrowser.searchForServices(ofType: type, inDomain: domain)
        AKTrace("HSBonjourSearch(\(identifier)): Searching for \(type) in '\(domain)'")
        return self
    }

    @objc @discardableResult func findBrowsableDomains(_ callback: JSValue) -> HSBonjourSearch {
        domainsBrowser.stop()
        domainsCallback = callback.isObject ? callback : nil
        domainsBrowser.searchForBrowsableDomains()
        AKTrace("HSBonjourSearch(\(identifier)): Searching for browsable domains")
        return self
    }

    @objc @discardableResult func findRegistrationDomains(_ callback: JSValue) -> HSBonjourSearch {
        registrationBrowser.stop()
        registrationCallback = callback.isObject ? callback : nil
        registrationBrowser.searchForRegistrationDomains()
        AKTrace("HSBonjourSearch(\(identifier)): Searching for registration domains")
        return self
    }

    @objc @discardableResult func stop() -> HSBonjourSearch {
        servicesBrowser.stop()
        domainsBrowser.stop()
        registrationBrowser.stop()
        servicesCallback = nil
        domainsCallback = nil
        registrationCallback = nil
        serviceTable.removeAll()
        AKTrace("HSBonjourSearch(\(identifier)): Stopped all searches")
        return self
    }

    // MARK: - Internal shutdown helper

    func stopAllDiscoveredServices() {
        serviceTable.values.forEach {
            $0.clearCallbacks()
            _ = $0.stop()
        }
    }

    // MARK: - NetServiceBrowserDelegate
    // Apple guarantees main-thread delivery, so these are inferred @MainActor.

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = ObjectIdentifier(service)
        let wrapper: HSBonjourService
        if let existing = serviceTable[key] {
            wrapper = existing
        } else {
            wrapper = HSBonjourService(netService: service)
            serviceTable[key] = wrapper
        }
        AKTrace("HSBonjourSearch(\(identifier)): serviceFound '\(service.name)' (moreComing: \(moreComing))")
        _ = servicesCallback?.call(withArguments: ["serviceFound", wrapper, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let key = ObjectIdentifier(service)
        let wrapper = serviceTable.removeValue(forKey: key) ?? HSBonjourService(netService: service)
        AKTrace("HSBonjourSearch(\(identifier)): serviceRemoved '\(service.name)' (moreComing: \(moreComing))")
        _ = servicesCallback?.call(withArguments: ["serviceRemoved", wrapper, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domain: String, moreComing: Bool) {
        AKTrace("HSBonjourSearch(\(identifier)): domainFound '\(domain)' (moreComing: \(moreComing))")
        let cb = browser === domainsBrowser ? domainsCallback : registrationCallback
        _ = cb?.call(withArguments: ["domainFound", domain, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domain: String, moreComing: Bool) {
        AKTrace("HSBonjourSearch(\(identifier)): domainRemoved '\(domain)' (moreComing: \(moreComing))")
        let cb = browser === domainsBrowser ? domainsCallback : registrationCallback
        _ = cb?.call(withArguments: ["domainRemoved", domain, moreComing])
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        let code = errorDict["NSNetServicesErrorCode"]?.intValue ?? -1
        let message = "Bonjour search failed (error code \(code))"
        AKError("HSBonjourSearch(\(identifier)): \(message)")
        let cb: JSValue?
        switch browser {
        case servicesBrowser:     cb = servicesCallback
        case domainsBrowser:      cb = domainsCallback
        case registrationBrowser: cb = registrationCallback
        default:                  cb = nil
        }
        _ = cb?.call(withArguments: ["error", message])
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        AKTrace("HSBonjourSearch(\(identifier)): Search stopped")
    }
}
