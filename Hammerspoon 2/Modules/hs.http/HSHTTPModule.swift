//
//  HSHTTPModule.swift
//  Hammerspoon 2

import Foundation
import JavaScriptCore

/// HTTP client module for making network requests from JavaScript.
///
/// All request methods return Promises that resolve with a result object containing
/// `status` (number), `body` (string), and `headers` (object). On network failure,
/// `status` is -1 and `body` is an empty string.
///
/// ## Quick start
///
/// ```js
/// hs.http.get("https://api.example.com/data").then(r => {
///     if (r.status === 200) {
///         console.log("Got: " + r.body)
///     }
/// })
/// ```
@objc protocol HSHTTPModuleAPI: JSExport {

    /// Perform an HTTP GET request.
    /// - Parameter url: The URL to request.
    /// - Parameter headers?: Optional dictionary of request headers.
    /// - Returns: {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
    /// - Example:
    /// ```js
    /// hs.http.get("https://httpbin.org/get").then(r => console.log(r.status))
    /// ```
    @objc func get(_ url: String, _ headers: [String: String]?) -> JSPromise?

    /// Perform an HTTP POST request.
    /// - Parameter url: The URL to request.
    /// - Parameter body?: Optional request body string.
    /// - Parameter headers?: Optional dictionary of request headers.
    /// - Returns: {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
    /// - Example:
    /// ```js
    /// hs.http.post("https://httpbin.org/post", '{"key":"val"}', {"Content-Type": "application/json"}).then(r => console.log(r.status))
    /// ```
    @objc func post(_ url: String, _ body: String?, _ headers: [String: String]?) -> JSPromise?

    /// Perform an HTTP PUT request.
    /// - Parameter url: The URL to request.
    /// - Parameter body?: Optional request body string.
    /// - Parameter headers?: Optional dictionary of request headers.
    /// - Returns: {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
    /// - Example:
    /// ```js
    /// hs.http.put("https://httpbin.org/put", "updated data", null).then(r => console.log(r.status))
    /// ```
    @objc func put(_ url: String, _ body: String?, _ headers: [String: String]?) -> JSPromise?

    /// Perform an HTTP request with any method (GET, POST, PUT, DELETE, PATCH, etc.).
    ///
    /// Use this for methods not covered by the convenience helpers, such as DELETE or PATCH.
    ///
    /// - Parameter url: The URL to request.
    /// - Parameter method: The HTTP method string (e.g. "DELETE", "PATCH", "HEAD").
    /// - Parameter body?: Optional request body string.
    /// - Parameter headers?: Optional dictionary of request headers.
    /// - Returns: {Promise<{status: number, body: string, headers: object}>} Resolves with the HTTP response.
    /// - Example:
    /// ```js
    /// hs.http.doRequest("https://httpbin.org/delete", "DELETE", null, null).then(r => console.log(r.status))
    /// ```
    @objc func doRequest(_ url: String, _ method: String, _ body: String?, _ headers: [String: String]?) -> JSPromise?

    /// URL-encode a string for use as a query parameter value.
    ///
    /// Encodes characters that are illegal in a URL query string (including `?`, `=`, `+`, `&`, `#`)
    /// using percent-encoding.
    ///
    /// - Parameter string: The string to encode.
    /// - Returns: The percent-encoded string.
    /// - Example:
    /// ```js
    /// console.log(hs.http.encodeForQuery("hello world & more=stuff"))
    /// // "hello%20world%20%26%20more%3Dstuff"
    /// ```
    @objc func encodeForQuery(_ string: String) -> String

    /// Parse a URL into its component parts.
    ///
    /// Returns an object containing only the fields present in the URL. The `queryItems` field
    /// is an array of `{name, value}` objects from the query string.
    ///
    /// - Parameter url: The URL string to parse.
    /// - Returns: An object with any of the fields: `scheme`, `host`, `port`, `user`, `password`, `path`, `query`, `fragment`, `queryItems`. Returns `null` if the URL is unparseable.
    /// - Example:
    /// ```js
    /// const parts = hs.http.urlParts("https://user:pass@example.com:8080/path?key=val#frag")
    /// console.log(parts.host)  // "example.com"
    /// console.log(parts.port)  // 8080
    /// ```
    @objc func urlParts(_ url: String) -> [String: Any]?

    /// Convert HTML entities in a string to their UTF-8 character equivalents.
    ///
    /// Handles named entities (e.g. `&amp;`, `&lt;`, `&copy;`), decimal numeric references
    /// (`&#38;`), and hexadecimal numeric references (`&#x26;`).
    ///
    /// - Parameter string: The string containing HTML entities.
    /// - Returns: The string with HTML entities replaced by their UTF-8 characters.
    /// - Example:
    /// ```js
    /// console.log(hs.http.convertHtmlEntities("&lt;div&gt;Hello &amp; World&lt;/div&gt;"))
    /// // "<div>Hello & World</div>"
    /// ```
    @objc func convertHtmlEntities(_ string: String) -> String

    /// Open a WebSocket connection to the given URL.
    ///
    /// The connection begins immediately. Use the returned object's chainable setter methods to
    /// register event callbacks. The connection is automatically closed when `hs.reload()` is
    /// called or the engine shuts down.
    ///
    /// - Parameter url: The WebSocket URL (`ws://` or `wss://`).
    /// - Returns: An `HSWebSocket` object, or `null` if the URL is invalid.
    /// - Example:
    /// ```js
    /// const ws = hs.http.openWebSocket("ws://localhost:8080/ws")
    ///     .setOpenCallback(() => ws.send("Hello!"))
    ///     .setMessageCallback(msg => console.log("Got: " + msg))
    ///     .setCloseCallback((code, reason) => console.log("Closed: " + code))
    /// ```
    @objc func openWebSocket(_ url: String) -> HSWebSocket?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSHTTPModule: NSObject, HSModuleAPI, HSHTTPModuleAPI {
    var name = "hs.http"
    let engineID: UUID
    private var webSockets = HSWeakObjectSet<HSWebSocket>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for ws in webSockets.allObjects { ws.destroy() }
        webSockets.removeAllObjects()
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Private

    private func performRequest(
        urlString: String,
        method: String,
        body: String?,
        headers: [String: String]?,
        context: JSContext
    ) -> JSPromise? {
        guard let url = URL(string: urlString) else {
            return context.createRejectedPromise(with: "Invalid URL: \(urlString)")
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                var request = URLRequest(url: url)
                request.httpMethod = method
                if let body {
                    request.httpBody = body.data(using: .utf8)
                }
                headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let httpResponse = response as? HTTPURLResponse
                    let status = httpResponse?.statusCode ?? -1
                    let responseBody = String(data: data, encoding: .utf8) ?? ""
                    var responseHeaders: [String: String] = [:]
                    httpResponse?.allHeaderFields.forEach { k, v in
                        if let key = k as? String, let val = v as? String {
                            responseHeaders[key] = val
                        }
                    }
                    holder.resolveWith([
                        "status": status,
                        "body": responseBody,
                        "headers": responseHeaders
                    ] as [String: Any])
                } catch {
                    AKWarning("hs.http: \(method) \(urlString) failed: \(error.localizedDescription)")
                    holder.resolveWith([
                        "status": -1,
                        "body": "",
                        "headers": [:] as [String: String]
                    ] as [String: Any])
                }
            }
        }
    }

    // MARK: - HSHTTPModuleAPI

    @objc func get(_ url: String, _ headers: [String: String]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return performRequest(urlString: url, method: "GET", body: nil, headers: headers, context: context)
    }

    @objc func post(_ url: String, _ body: String?, _ headers: [String: String]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return performRequest(urlString: url, method: "POST", body: body, headers: headers, context: context)
    }

    @objc func put(_ url: String, _ body: String?, _ headers: [String: String]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return performRequest(urlString: url, method: "PUT", body: body, headers: headers, context: context)
    }

    @objc func doRequest(_ url: String, _ method: String, _ body: String?, _ headers: [String: String]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return performRequest(urlString: url, method: method, body: body, headers: headers, context: context)
    }

    @objc func openWebSocket(_ url: String) -> HSWebSocket? {
        let lower = url.lowercased()
        guard lower.hasPrefix("ws://") || lower.hasPrefix("wss://"),
              let parsedURL = URL(string: url) else {
            AKWarning("hs.http.openWebSocket: Invalid URL: \(url)")
            return nil
        }
        let ws = HSWebSocket(url: parsedURL)
        webSockets.add(ws)
        ws.connect()
        return ws
    }

    @objc func encodeForQuery(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "?=+&#")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    @objc func urlParts(_ url: String) -> [String: Any]? {
        guard let components = URLComponents(string: url) else { return nil }
        var result: [String: Any] = [:]
        if let scheme = components.scheme { result["scheme"] = scheme }
        if let host = components.host { result["host"] = host }
        if let port = components.port { result["port"] = port }
        if let user = components.user { result["user"] = user }
        if let password = components.password { result["password"] = password }
        result["path"] = components.path
        if let query = components.query { result["query"] = query }
        if let fragment = components.fragment { result["fragment"] = fragment }
        if let items = components.queryItems {
            result["queryItems"] = items.map { ["name": $0.name, "value": $0.value ?? ""] as [String: Any] }
        }
        return result
    }

    @objc func convertHtmlEntities(_ string: String) -> String {
        var output = ""
        output.reserveCapacity(string.count)
        var idx = string.startIndex
        while idx < string.endIndex {
            guard string[idx] == "&" else {
                output.append(string[idx])
                idx = string.index(after: idx)
                continue
            }
            let afterAmp = string.index(after: idx)
            if let semiIdx = string[afterAmp...].firstIndex(of: ";") {
                let entityContent = String(string[afterAmp..<semiIdx])
                if (entityContent.hasPrefix("#x") || entityContent.hasPrefix("#X")),
                   let cp = UInt32(entityContent.dropFirst(2), radix: 16),
                   let scalar = Unicode.Scalar(cp) {
                    output.append(Character(scalar))
                    idx = string.index(after: semiIdx)
                    continue
                } else if entityContent.hasPrefix("#"),
                          let cp = UInt32(entityContent.dropFirst()),
                          let scalar = Unicode.Scalar(cp) {
                    output.append(Character(scalar))
                    idx = string.index(after: semiIdx)
                    continue
                } else if let replacement = Self.namedHtmlEntity(entityContent) {
                    output.append(contentsOf: replacement)
                    idx = string.index(after: semiIdx)
                    continue
                }
            }
            output.append(string[idx])
            idx = string.index(after: idx)
        }
        return output
    }

    private static func namedHtmlEntity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        case "copy": return "\u{00A9}"
        case "reg": return "\u{00AE}"
        case "trade": return "\u{2122}"
        case "euro": return "\u{20AC}"
        case "pound": return "\u{00A3}"
        case "yen": return "\u{00A5}"
        case "cent": return "\u{00A2}"
        case "mdash": return "\u{2014}"
        case "ndash": return "\u{2013}"
        case "laquo": return "\u{00AB}"
        case "raquo": return "\u{00BB}"
        case "lsquo": return "\u{2018}"
        case "rsquo": return "\u{2019}"
        case "ldquo": return "\u{201C}"
        case "rdquo": return "\u{201D}"
        case "hellip": return "\u{2026}"
        case "middot": return "\u{00B7}"
        case "bull": return "\u{2022}"
        case "sect": return "\u{00A7}"
        case "para": return "\u{00B6}"
        case "deg": return "\u{00B0}"
        case "plusmn": return "\u{00B1}"
        case "frac12": return "\u{00BD}"
        case "frac14": return "\u{00BC}"
        case "frac34": return "\u{00BE}"
        case "times": return "\u{00D7}"
        case "divide": return "\u{00F7}"
        case "iexcl": return "\u{00A1}"
        case "iquest": return "\u{00BF}"
        case "micro": return "\u{00B5}"
        case "sup1": return "\u{00B9}"
        case "sup2": return "\u{00B2}"
        case "sup3": return "\u{00B3}"
        default: return nil
        }
    }
}
