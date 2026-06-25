//
//  HSBonjourModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import dnssd

// MARK: - Module API protocol

/// Discover and publish Bonjour (mDNS / Zeroconf) network services.
///
/// Use `createSearch()` to search the network for services advertised by other
/// devices, and `advertise()` to advertise your own. The `networkServices()`
/// convenience function returns a snapshot of all service types currently
/// active on the local network.
///
/// ## Common service type strings
///
/// The `hs.bonjour.serviceTypes` object maps short names to their mDNS strings,
/// e.g. `hs.bonjour.serviceTypes.ssh` → `"_ssh._tcp."`.
///
/// ## Searching for a service
///
/// ```js
/// // Find all SSH services on the local network and resolve each one
/// const search = hs.bonjour.createSearch()
/// search.findServices('_ssh._tcp.', 'local.', (event, svc, moreComing) => {
///     if (event === 'serviceFound') {
///         svc.resolve(5, ev => {
///             if (ev === 'resolved') console.log(svc.hostname + ':' + svc.port)
///         })
///     }
/// })
/// ```
///
/// ## Advertising a service
///
/// ```js
/// hs.bonjour.advertise('My Web Server', '_http._tcp.', 8080, ev => {
///     if (ev === 'published') console.log('Now advertising!')
///     else if (ev === 'error') console.error('Advertising failed')
/// })
/// // Later, to stop:
/// hs.bonjour.stopAdvertising('My Web Server', '_http._tcp.')
/// ```
///
/// ## Listing all active service types
///
/// ```js
/// hs.bonjour.networkServices(5).then(types => {
///     console.log('Active service types: ' + types.join(', '))
/// })
/// ```
@objc protocol HSBonjourModuleAPI: JSExport {

    /// A frozen object mapping short service-type names to their mDNS strings.
    ///
    /// Populated by the JavaScript enhancement layer.
    /// - Example:
    /// ```js
    /// console.log(hs.bonjour.serviceTypes.ssh)  // "_ssh._tcp."
    /// ```
    @objc var serviceTypes: [String: String] { get }

    /// Creates a new Bonjour search for discovering services or domains.
    ///
    /// Call one of the `find…` methods on the returned search to start
    /// discovering. Remove it with `removeSearch()` when finished.
    /// - Returns: a new `HSBonjourSearch`
    /// - Example:
    /// ```js
    /// const search = hs.bonjour.createSearch()
    /// search.findServices('_http._tcp.', 'local.', (ev, svc, more) => {
    ///     if (ev === 'serviceFound') console.log('Found:', svc.name)
    /// })
    /// ```
    @objc func createSearch() -> HSBonjourSearch

    /// Stops and removes a previously created search.
    /// - Parameter search: the search returned by `createSearch()`
    /// - Example:
    /// ```js
    /// const s = hs.bonjour.createSearch()
    /// // ... use search ...
    /// hs.bonjour.removeSearch(s)
    /// ```
    @objc func removeSearch(_ search: HSBonjourSearch)

    /// Starts advertising a local service on the network.
    ///
    /// The optional callback receives `(event)` or `(event, errorMessage)`:
    /// - `"published"` — now advertising
    /// - `"stopped"` — advertisement stopped
    /// - `"error"` — publication failed; error message in second argument
    ///
    /// If `domain` is omitted or not a string, it defaults to `"local."`.
    /// If the 4th argument is a function, it is used as the callback and domain
    /// defaults to `"local."`.
    /// - Parameter name: human-readable name shown to browsers (e.g. `"My Web Server"`)
    /// - Parameter type: service type in `"_proto._tcp."` or `"_proto._udp."` form
    /// - Parameter port: port number the service listens on
    /// - Parameter domain: mDNS domain; defaults to `"local."` if an empty string is passed
    /// - Parameter callback?: optional `function(event, data?)` called on status changes
    /// - Example:
    /// ```js
    /// hs.bonjour.advertise('My Server', '_http._tcp.', 8080, '', ev => {
    ///     if (ev === 'published') console.log('Now advertising!')
    /// })
    /// ```
    @objc func advertise(_ name: String, _ type: String, _ port: Int, _ domain: String, _ callback: JSFunction)

    /// Stops advertising a service previously started with `advertise()`.
    /// - Parameter name: the name passed to `advertise()`
    /// - Parameter type: the type passed to `advertise()`
    /// - Example:
    /// ```js
    /// hs.bonjour.stopAdvertising('My Server', '_http._tcp.')
    /// ```
    @objc func stopAdvertising(_ name: String, _ type: String)

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
    ///     console.log('Active service types: ' + types.join(', '))
    /// })
    /// ```
    @objc func networkServices(_ timeout: Double) -> JSPromise?
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSBonjourModule: NSObject, HSModuleAPI, HSBonjourModuleAPI {
    var name = "hs.bonjour"
    let engineID: UUID

    @objc var serviceTypes: [String: String] = [
        "airplay":      "_airplay._tcp.",
        "airport":      "_airport._tcp.",
        "afp":          "_afpovertcp._tcp.",
        "daap":         "_daap._tcp.",
        "ftp":          "_ftp._tcp.",
        "googleCast":   "_googlecast._tcp.",
        "homekit":      "_hap._tcp.",
        "http":         "_http._tcp.",
        "https":        "_https._tcp.",
        "ipp":          "_ipp._tcp.",
        "ipps":         "_ipps._tcp.",
        "nfs":          "_nfs._tcp.",
        "printer":      "_printer._tcp.",
        "raop":         "_raop._tcp.",
        "rdp":          "_rdp._tcp.",
        "sftp":         "_sftp-ssh._tcp.",
        "smb":          "_smb._tcp.",
        "smtp":         "_smtp._tcp.",
        "snmp":         "_snmp._udp.",
        "ssh":          "_ssh._tcp.",
        "telnet":       "_telnet._tcp.",
        "vnc":          "_rfb._tcp.",
        "workstation":  "_workstation._tcp.",
    ]

    // Weak refs: searches stay active via their NSNetServiceBrowser delegate chain;
    // weak refs allow dropped searches to be GC'd without an explicit removeSearch() call.
    private var searches = HSWeakObjectSet<HSBonjourSearch>()
    private var advertisedServices: [String: AdvertisedService] = [:]

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for search in searches.allObjects {
            search.destroy()
        }
        searches.removeAllObjects()
        advertisedServices.values.forEach { $0.stop() }
        advertisedServices.removeAll()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - HSBonjourModuleAPI

    @objc func createSearch() -> HSBonjourSearch {
        let search = HSBonjourSearch()
        searches.add(search)
        AKTrace("HSBonjourModule: Created search \(search.identifier)")
        return search
    }

    @objc func removeSearch(_ search: HSBonjourSearch) {
        search.destroy()
        searches.remove(search)
        AKTrace("HSBonjourModule: Removed search \(search.identifier)")
    }

    @objc func advertise(_ name: String, _ type: String, _ port: Int, _ domain: String, _ callback: JSFunction) {
        let effectiveDomain: String
        let effectiveCallback: JSFunction?
        effectiveDomain = domain == "" ? "local." : domain
        effectiveCallback = callback.isObject ? callback : nil

        let key = "\(name):\(type)"
        guard advertisedServices[key] == nil else {
            AKWarning("hs.bonjour.advertise: '\(name)' (\(type)) is already being advertised — ignoring")
            return
        }
        let handle = AdvertisedService(name: name, type: type, port: port, domain: effectiveDomain, callback: effectiveCallback)
        advertisedServices[key] = handle
        handle.publish()
        AKTrace("hs.bonjour.advertise: Started advertising '\(name)' (\(type)) port \(port) in \(effectiveDomain)")
    }

    @objc func stopAdvertising(_ name: String, _ type: String) {
        let key = "\(name):\(type)"
        guard let handle = advertisedServices.removeValue(forKey: key) else {
            AKWarning("hs.bonjour.stopAdvertising: '\(name)' (\(type)) is not being advertised")
            return
        }
        handle.stop()
        AKTrace("hs.bonjour.stopAdvertising: Stopped advertising '\(name)' (\(type))")
    }

    @objc func networkServices(_ timeout: Double) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let waitSeconds = timeout > 0 ? timeout : 5.0
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                // NSMutableSet is an ObjC reference type that can be passed through the
                // @convention(c) callback's context pointer without a custom wrapper class.
                // The meta-query splits the service type across two callback parameters:
                //   namePtr    = "_ssh"         (first label)
                //   regtypePtr = "_tcp.local."  (protocol.domain.)
                // Full service type = "\(name).\(proto)." e.g. "_ssh._tcp."
                let found = NSMutableSet()
                let ctxPtr = unsafe Unmanaged.passRetained(found).toOpaque()

                let browseReply: DNSServiceBrowseReply = { _, flags, _, error, namePtr, regtypePtr, _, ctx in
                    guard let ctx = unsafe ctx,
                          error == kDNSServiceErr_NoError,
                          (flags & kDNSServiceFlagsAdd) != 0,
                          let name    = unsafe namePtr.flatMap({ unsafe String(utf8String: $0) }),
                          let regtype = unsafe regtypePtr.flatMap({ unsafe String(utf8String: $0) }),
                          let proto   = regtype.components(separatedBy: ".").first,
                          !proto.isEmpty else { return }
                    unsafe Unmanaged<NSMutableSet>.fromOpaque(ctx).takeUnretainedValue()
                        .add("\(name).\(proto).")
                }

                var sdRef: DNSServiceRef?
                let err = unsafe DNSServiceBrowse(&sdRef, 0, 0, "_services._dns-sd._udp", "local.", browseReply, ctxPtr)
                guard err == kDNSServiceErr_NoError, let sdRef = unsafe sdRef else {
                    unsafe Unmanaged<NSMutableSet>.fromOpaque(ctxPtr).release()
                    AKError("hs.bonjour.networkServices: DNSServiceBrowse failed (error \(err))")
                    holder.resolveWith([String]())
                    return
                }
                unsafe DNSServiceSetDispatchQueue(sdRef, .main)

                try? await Task.sleep(for: .seconds(waitSeconds))

                unsafe DNSServiceRefDeallocate(sdRef)
                // takeRetainedValue() releases the +1 from passRetained above.
                let result = unsafe Unmanaged<NSMutableSet>.fromOpaque(ctxPtr).takeRetainedValue()
                holder.resolveWith(result.allObjects as! [String])
            }
        }
    }
}

// MARK: - AdvertisedService (private delegate wrapper for published services)

@MainActor
private class AdvertisedService: NSObject, NetServiceDelegate {
    private var service: NetService?
    private var callback: JSCallback?

    init(name: String, type: String, port: Int, domain: String, callback: JSFunction?) {
        super.init()

        self.service = NetService(domain: domain, type: type, name: name, port: Int32(port))
        unsafe self.service?.delegate = self

        if let callback {
            self.callback = JSCallback(value: callback, owner: self)
        }
    }

    func publish() {
        service?.publish()
    }

    func stop() {
        service?.stop()
        unsafe service?.delegate = nil
        self.callback?.detach(from: self)
        callback = nil
        service = nil
    }

    func netServiceDidPublish(_ sender: NetService) {
        guard let service else { return }
        AKTrace("hs.bonjour: Published '\(service.name)'")
        _ = callback?.call(withArguments: ["published"])
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        guard let service else { return }
        let msg = HSBonjourService.errorMessage(from: errorDict)
        AKError("hs.bonjour: Failed to publish '\(service.name)': \(msg)")
        _ = callback?.call(withArguments: ["error", msg])
    }

    func netServiceDidStop(_ sender: NetService) {
        guard let service else { return }
        AKTrace("hs.bonjour: Stopped '\(service.name)'")
        _ = callback?.call(withArguments: ["stopped"])
        callback = nil
    }
}

