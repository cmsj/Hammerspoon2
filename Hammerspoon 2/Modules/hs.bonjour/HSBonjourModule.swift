//
//  HSBonjourModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Module API protocol

/// Discover and publish Bonjour (mDNS / Zeroconf) network services.
///
/// Use `createBrowser()` to search the network for services advertised by other
/// devices, and `createService()` to advertise your own. The `networkServices()`
/// convenience function returns a snapshot of all service types currently active
/// on the local network.
///
/// ## Common service type strings
///
/// The `hs.bonjour.serviceTypes` object maps short names to their mDNS strings,
/// e.g. `hs.bonjour.serviceTypes.ssh` →`"_ssh._tcp."`.
///
/// ## Quick example
///
/// ```js
/// // Find all SSH services on the local network and resolve each one
/// const browser = hs.bonjour.createBrowser()
/// browser.searchForServices('_ssh._tcp.', 'local.', (event, svc, moreComing) => {
///     if (event === 'serviceFound') {
///         svc.resolve(5, ev => {
///             if (ev === 'resolved') console.log(svc.hostname, svc.port)
///         })
///     }
/// })
/// ```
@objc protocol HSBonjourModuleAPI: JSExport {

    /// Creates a new Bonjour browser for discovering services or domains.
    ///
    /// Call one of the `searchFor…` methods on the returned browser to start
    /// discovering. Remove it with `removeBrowser()` when finished.
    /// - Returns: a new `HSBonjourBrowser`
    /// - Example:
    /// ```js
    /// const browser = hs.bonjour.createBrowser()
    /// browser.searchForServices('_http._tcp.', 'local.', (ev, svc, more) => {
    ///     if (ev === 'serviceFound') console.log('Found:', svc.name)
    /// })
    /// ```
    @objc func createBrowser() -> HSBonjourBrowser

    /// Stops and removes a previously created browser.
    /// - Parameter browser: the browser returned by `createBrowser()`
    /// - Example:
    /// ```js
    /// const b = hs.bonjour.createBrowser()
    /// // ... use browser ...
    /// hs.bonjour.removeBrowser(b)
    /// ```
    @objc func removeBrowser(_ browser: HSBonjourBrowser)

    /// Creates a new local Bonjour service for publishing.
    ///
    /// Call `publish()` on the returned object to begin advertising. Remove it
    /// with `removeService()` when finished.
    /// - Parameter name: human-readable name shown to browsers (e.g. `"My Web Server"`)
    /// - Parameter type: service type in `"_proto._tcp."` or `"_proto._udp."` form (e.g. `"_http._tcp."`)
    /// - Parameter port: port number the service listens on
    /// - Parameter domain: mDNS domain; almost always `"local."`
    /// - Returns: a new `HSBonjourService`
    /// - Example:
    /// ```js
    /// const svc = hs.bonjour.createService('My Server', '_http._tcp.', 8080, 'local.')
    /// svc.publish(ev => console.log('Publish event:', ev))
    /// ```
    @objc func createService(_ name: String, _ type: String, _ port: Int32, _ domain: String) -> HSBonjourService

    /// Stops and removes a previously created local service.
    /// - Parameter service: the service returned by `createService()`
    /// - Example:
    /// ```js
    /// const svc = hs.bonjour.createService('Test', '_http._tcp.', 9000, 'local.')
    /// svc.publish(ev => {})
    /// hs.bonjour.removeService(svc)
    /// ```
    @objc func removeService(_ service: HSBonjourService)

    /// Returns a Promise that resolves to an array of service-type strings
    /// currently advertised on the local network.
    ///
    /// Internally searches for `_services._dns-sd._udp.` services, collects
    /// results for up to `timeout` seconds (or until the browser signals no more
    /// results), then resolves.
    /// - Parameter timeout: maximum seconds to wait (pass `0` to use the default 5 s)
    /// - Returns: {Promise<string[]>} a Promise resolving to an array of service-type strings such as `"_http._tcp."`
    /// - Example:
    /// ```js
    /// hs.bonjour.networkServices(5).then(types => {
    ///     console.log('Active service types:', types.join(', '))
    /// })
    /// ```
    @objc func networkServices(_ timeout: Double) -> JSPromise?
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourModule: NSObject, HSModuleAPI, HSBonjourModuleAPI {
    var name = "hs.bonjour"

    private var browsers: [HSBonjourBrowser] = []
    private var localServices: [HSBonjourService] = []

    override required init() {
        super.init()
    }

    func shutdown() {
        browsers.forEach { $0.stopAllDiscoveredServices() }
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        localServices.forEach {
            $0.clearCallbacks()
            _ = $0.stop()
        }
        localServices.removeAll()
    }

    isolated deinit {
        print("Deinit of \(name)")
    }

    // MARK: - HSBonjourModuleAPI

    @objc func createBrowser() -> HSBonjourBrowser {
        let browser = HSBonjourBrowser()
        browsers.append(browser)
        AKTrace("HSBonjourModule: Created browser \(browser.identifier)")
        return browser
    }

    @objc func removeBrowser(_ browser: HSBonjourBrowser) {
        browser.stopAllDiscoveredServices()
        browser.stop()
        browsers.removeAll { $0 === browser }
        AKTrace("HSBonjourModule: Removed browser \(browser.identifier)")
    }

    @objc func createService(_ name: String, _ type: String, _ port: Int32, _ domain: String) -> HSBonjourService {
        let service = HSBonjourService(name: name, type: type, port: port, domain: domain)
        localServices.append(service)
        AKTrace("HSBonjourModule: Created service '\(name)' (\(type)) port \(port) in \(domain)")
        return service
    }

    @objc func removeService(_ service: HSBonjourService) {
        service.clearCallbacks()
        _ = service.stop()
        localServices.removeAll { $0 === service }
        AKTrace("HSBonjourModule: Removed service '\(service.name)'")
    }

    @objc func networkServices(_ timeout: Double) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let waitSeconds = timeout > 0 ? timeout : 5.0
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                let types = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
                    let collector = NetworkServicesCollector { found in
                        continuation.resume(returning: found)
                    }
                    let browser = NetServiceBrowser()
                    collector.browser = browser
                    unsafe browser.delegate = collector
                    browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: "local.")

                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(waitSeconds))
                        collector.complete()
                    }
                }
                holder.resolveWith(types)
            }
        }
    }
}

// MARK: - NetworkServicesCollector (private helper for networkServices)

@MainActor
private class NetworkServicesCollector: NSObject {
    private(set) var found: [String] = []
    private var hasCompleted = false
    private var onComplete: (([String]) -> Void)?
    var browser: NetServiceBrowser?

    init(onComplete: @escaping @MainActor ([String]) -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        browser?.stop()
        browser = nil
        onComplete?(found)
        onComplete = nil
    }
}

extension NetworkServicesCollector: NetServiceBrowserDelegate {
    // Apple guarantees main-thread delivery for NSNetServiceBrowserDelegate —
    // @MainActor class inference covers these without nonisolated.

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        var typeName = service.name
        if !typeName.hasSuffix(".") { typeName += "." }
        if !found.contains(typeName) { found.append(typeName) }
        if !moreComing { complete() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        complete()
    }
}
