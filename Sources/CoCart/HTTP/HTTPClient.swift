import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLSession on Linux and Windows
#endif

public enum CoCartEvent: Hashable { case request, response, error }
public typealias CoCartEventPayload = [String: Any]

/// A single sub-request queued for `HTTPClient.batch()` / `CoCart.batch()`.
public struct BatchRequestItem {
    public let method: String
    public let path: String
    public let body: [String: Any]?

    public init(method: String, path: String, body: [String: Any]? = nil) {
        self.method = method
        self.path = path
        self.body = body
    }
}

/// Coalesces concurrent identical GET requests into a single in-flight task,
/// so simultaneous callers share one network round trip instead of firing
/// one request each.
private actor InFlightGetTracker {
    private var tasks: [String: Task<CoCartResponse, Error>] = [:]

    func run(key: String, operation: @escaping () async throws -> CoCartResponse) async throws -> CoCartResponse {
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

final class HTTPClient {
    private let siteURL: String
    private var options: CoCartOptions
    private let auth: AuthManager
    private let session: URLSession
    private var etagCache: [String: ETagCacheEntry] = [:]
    private var eventHandlers: [CoCartEvent: [(CoCartEventPayload) -> Void]] = [:]
    private let inFlightGets = InFlightGetTracker()

    private struct ETagCacheEntry {
        let etag: String
        let body: [String: Any]
        let list: [Any]?
        let headers: [String: String]
    }

    init(siteURL: String, options: CoCartOptions, auth: AuthManager,
         session: URLSession = .shared) {
        self.siteURL = siteURL
        self.options = options
        self.auth = auth
        self.session = session
    }

    var namespace: String { options.namespace }

    private var restBase: String {
        "\(siteURL.trimmingCharacters(in: .init(charactersIn: "/")))/\(options.restPrefix)"
    }

    // MARK: - Namespaced requests (`{namespace}/v2/...`)

    func get(_ path: String, queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        try await send("GET", route: "\(options.namespace)/v2/\(path)", queryParams: queryParams, retryInvalidCart: true,
                       retryNetwork: true)
    }

    func post(_ path: String, body: [String: Any]? = nil,
              queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        try await send("POST", route: "\(options.namespace)/v2/\(path)", queryParams: queryParams, body: body,
                       retryInvalidCart: true)
    }

    func put(_ path: String, body: [String: Any]? = nil) async throws -> CoCartResponse {
        try await send("PUT", route: "\(options.namespace)/v2/\(path)", body: body, retryInvalidCart: true)
    }

    func delete(_ path: String, queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        try await send("DELETE", route: "\(options.namespace)/v2/\(path)", queryParams: queryParams,
                       retryInvalidCart: true)
    }

    // MARK: - Raw requests (a full REST route, relative to the REST prefix)
    //
    // The CoCart Plus routes (checkout, account…). They emit the same events as the other
    // requests, but are never sent again: a raw request can take payment.

    func getRaw(_ route: String, queryParams: [String: String]? = nil,
                includeCartKey: Bool = true) async throws -> CoCartResponse {
        try await send("GET", route: route, queryParams: queryParams, includeCartKey: includeCartKey)
    }

    func postRaw(_ route: String, body: [String: Any]? = nil,
                 queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        try await send("POST", route: route, queryParams: queryParams, body: body)
    }

    func putRaw(_ route: String, body: [String: Any]? = nil) async throws -> CoCartResponse {
        try await send("PUT", route: route, body: body)
    }

    func deleteRaw(_ route: String) async throws -> CoCartResponse {
        try await send("DELETE", route: route)
    }

    /// Dispatch multiple sub-requests in a single call via `{namespace}/batch`
    /// (requires CoCart Plus). Throws `cocart_plugin_required` if the batch
    /// route isn't registered on the server.
    func batch(_ requests: [BatchRequestItem]) async throws -> CoCartResponse {
        guard !requests.isEmpty else {
            throw CoCartError.validation("batch() requires at least one request.")
        }
        let items: [[String: Any]] = requests.map { request in
            var dict: [String: Any] = ["method": request.method, "path": request.path]
            if let body = request.body { dict["body"] = body }
            return dict
        }
        do {
            return try await postRaw("\(options.namespace)/batch", body: ["requests": items])
        } catch {
            if case CoCartError.api(_, let statusCode, let code, _) = error, code == "rest_no_route" {
                throw CoCartError.api(
                    "This method requires the CoCart Plus plugin. Please ask support for assistance!",
                    statusCode: statusCode,
                    code: "cocart_plugin_required",
                    data: [:]
                )
            }
            throw error
        }
    }

    // MARK: - Sending

    /// Build and send a request. If a guest's cart no longer exists (CoCart
    /// Starter 5 refuses the cart key with `cocart_invalid_cart`, for example
    /// after the cart expired), the stored cart key is forgotten and the
    /// request retried once as a new guest.
    private func send(_ method: String, route: String, queryParams: [String: String]? = nil,
                      body: [String: Any]? = nil, includeCartKey: Bool = true,
                      retryInvalidCart: Bool = false, retryNetwork: Bool = false) async throws -> CoCartResponse {
        do {
            return try await sendOnce(method, route: route, queryParams: queryParams, body: body,
                                      includeCartKey: includeCartKey, retryNetwork: retryNetwork)
        } catch {
            // The stored guest cart no longer exists (e.g. it expired). CoCart refuses the
            // request before running it, so forget the key and retry once as a new guest.
            guard retryInvalidCart, (error as? CoCartError)?.errorCode == "cocart_invalid_cart",
                  auth.guestCartKey != nil else { throw error }
            try await auth.forgetCartKey()
            return try await sendOnce(method, route: route, queryParams: queryParams, body: body,
                                      includeCartKey: includeCartKey, retryNetwork: retryNetwork)
        }
    }

    private func sendOnce(_ method: String, route: String, queryParams: [String: String]?,
                          body: [String: Any]?, includeCartKey: Bool,
                          retryNetwork: Bool) async throws -> CoCartResponse {
        var request = try buildRequest(method: method, route: route, queryParams: queryParams,
                                       includeCartKey: includeCartKey)
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        guard method == "GET" else { return try await execute(request, path: route, retryNetwork: false) }
        let key = request.url?.absoluteString ?? route
        return try await inFlightGets.run(key: key) { [self] in
            try await execute(request, path: route, retryNetwork: retryNetwork)
        }
    }

    private func buildRequest(method: String, route: String, queryParams: [String: String]?,
                              includeCartKey: Bool) throws -> URLRequest {
        let routeWithoutLeadingSlash = route.hasPrefix("/") ? String(route.dropFirst()) : route
        guard var components = URLComponents(string: "\(restBase)/\(routeWithoutLeadingSlash)") else {
            throw CoCartError.network("Invalid URL for route: \(routeWithoutLeadingSlash)")
        }
        var params = queryParams ?? [:]
        let cartKey = includeCartKey ? auth.guestCartKey : nil
        if let cartKey {
            params["cart_key"] = cartKey
        }
        if !params.isEmpty {
            components.queryItems = params
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLQueryItem leaves "+" as is, which servers read as a space (e.g. in an email).
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else {
            throw CoCartError.network("Could not construct URL for route: \(routeWithoutLeadingSlash)")
        }
        var request = URLRequest(url: url, timeoutInterval: options.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CoCart-Swift-SDK/1.0.0", forHTTPHeaderField: "User-Agent")

        if let authValue = auth.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: options.authHeaderName)
        }

        // Cart key header — send only the header name the configured plugin actually
        // reads: legacy plugin versions expect `CoCart-API-Cart-Key`, current ones `Cart-Key`.
        if let cartKey {
            let cartKeyHeader = options.mainPlugin == .legacy ? "CoCart-API-Cart-Key" : "Cart-Key"
            request.setValue(cartKey, forHTTPHeaderField: cartKeyHeader)
        }

        if options.etag, method == "GET", let cached = etagCache[url.absoluteString] {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        for (key, value) in options.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func execute(_ request: URLRequest, path: String, retryNetwork: Bool,
                         attempt: Int = 0) async throws -> CoCartResponse {
        let method = request.httpMethod ?? "GET"
        // Events carry the full URL, query string included (it can hold the cart key, an order
        // key or an email): a listener must not forward it. Debug output hides every query value.
        let url = request.url?.absoluteString ?? path
        emit(.request, payload: ["method": method, "url": url])
        debugLog("\(method) \(Self.redactQuery(url))")
        let start = Date()
        let isGet = method == "GET"
        let cacheKey = url

        do {
            let (data, urlResponse) = try await session.data(for: request)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw CoCartError.network("Invalid response")
            }

            let duration = Date().timeIntervalSince(start) * 1000

            let headers = Dictionary(
                http.allHeaderFields.compactMap { k, v -> (String, String)? in
                    guard let key = k as? String, let val = v as? String else { return nil }
                    return (key.lowercased(), val)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // A 304 has no body — reuse the body/headers cached alongside the ETag
            // that produced the match, so callers still get the actual data instead
            // of an empty object. Falls back to the live (empty) response if we
            // somehow have no cache entry for this URL.
            if http.statusCode == 304 {
                let response = etagCache[cacheKey].map {
                    CoCartResponse(data: $0.body, headers: $0.headers, statusCode: 304, list: $0.list)
                } ?? CoCartResponse(data: [:], headers: headers, statusCode: 304)
                emitResponse(method: method, url: url, duration: duration, response: response)
                return response
            }

            // Some routes answer with a list (categories, tags, attributes, reviews,
            // variations, payment methods, downloads): keep it as well as an object body.
            let root = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let body = root as? [String: Any] ?? [:]
            let list = root as? [Any]

            emitResponse(method: method, url: url, duration: duration,
                         response: CoCartResponse(data: body, headers: headers, statusCode: http.statusCode,
                                                  list: list, raw: data))

            // ETag: cache the ETag + body from a fresh (non-304) GET response, unless the store
            // says the response mustn't be kept (checkout, orders and the account are
            // `no-store, private`).
            if options.etag, isGet, let etag = headers["etag"], Self.mayStore(headers["cache-control"]) {
                etagCache[cacheKey] = ETagCacheEntry(etag: etag, body: body, list: list, headers: headers)
            }

            auth.captureCartKey(from: body, headers: headers)

            return try handleResponse(body: body, list: list, headers: headers, statusCode: http.statusCode, raw: data)

        } catch let error as CoCartError {
            emitError(method: method, url: url, error: error)
            throw error
        } catch {
            // Only a GET is sent again, and not on the raw (CoCart Plus) routes: a request that
            // changes something may have run before the connection dropped, and running it
            // twice could, for example, charge a card twice.
            if retryNetwork, isGet, attempt < options.maxRetries {
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(attempt: attempt))
                return try await execute(request, path: path, retryNetwork: retryNetwork, attempt: attempt + 1)
            }
            let failure = CoCartError.network(Self.safeErrorMessage(error.localizedDescription))
            emitError(method: method, url: url, error: failure)
            throw failure
        }
    }

    private func emitResponse(method: String, url: String, duration: Double, response: CoCartResponse) {
        emit(.response, payload: [
            "method": method, "url": url, "status": response.statusCode, "duration": duration, "response": response,
        ])
        debugLog("\(method) \(Self.redactQuery(url)) \(response.statusCode) (\(Int(duration))ms)")
    }

    private func emitError(method: String, url: String, error: CoCartError) {
        emit(.error, payload: ["method": method, "url": url, "error": error.localizedDescription])
        debugLog("\(method) \(Self.redactQuery(url)) failed: \(Self.safeErrorMessage(error.localizedDescription))")
    }

    /// Writes a line of debug output when `debug` is on.
    private func debugLog(_ line: String) {
        if options.debug { print("[CoCart] \(line)") }
    }

    /// A URL for debug output, with every query value replaced by `***`: the query can hold
    /// the cart key, an order key, an email address or a verification key, which mustn't end
    /// up in logs.
    static func redactQuery(_ url: String) -> String {
        guard let mark = url.firstIndex(of: "?") else { return url }
        let pairs = url[url.index(after: mark)...].split(separator: "&", omittingEmptySubsequences: false)
        let query = pairs.map { pair -> String in
            guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
            return "\(pair[..<equals])=***"
        }
        return "\(url[..<mark])?\(query.joined(separator: "&"))"
    }

    /// Whether a response may be kept in the ETag cache: not when `Cache-Control` says
    /// `no-store` or `private`.
    static func mayStore(_ cacheControl: String?) -> Bool {
        guard let cacheControl else { return true }
        return cacheControl.range(of: #"(^|[\s,])(no-store|private)([\s,;=]|$)"#,
                                  options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Exponential backoff (`500ms * 2^attempt`) with ±20% jitter, so many
    /// clients retrying at once don't re-collide on the same schedule.
    private func retryDelayNanoseconds(attempt: Int) -> UInt64 {
        let base = 500_000_000.0 * pow(2.0, Double(attempt))
        let jitter = 0.8 + Double.random(in: 0...1) * 0.4
        return UInt64(base * jitter)
    }

    /// Removes the query string from any URL in a transport error message: it can carry the cart key.
    static func safeErrorMessage(_ message: String) -> String {
        message.replacingOccurrences(
            of: #"((?:https?://|/)[^\s?#"'<>()]*)[?#][^\s"'<>()]*"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func handleResponse(body: [String: Any], list: [Any]?, headers: [String: String],
                                statusCode: Int, raw: Data? = nil) throws -> CoCartResponse {
        if (200..<300).contains(statusCode) {
            return CoCartResponse(data: body, headers: headers, statusCode: statusCode, list: list, raw: raw)
        }
        let message = body["message"] as? String
        let code = body["code"] as? String
        switch statusCode {
        case 401:
            if code == "cocart_2fa_required" {
                let data = body["data"] as? [String: Any] ?? body
                let providers = data["available_providers"] as? [String] ?? []
                let defaultProvider = data["default_provider"] as? String
                let emailSent = data["email_sent"] as? Bool ?? false
                throw CoCartError.twoFactorRequired(
                    message ?? "Two-factor authentication required",
                    availableProviders: providers,
                    defaultProvider: defaultProvider,
                    emailSent: emailSent
                )
            }
            throw CoCartError.auth(message ?? "Unauthorized", code: code)
        case 403:
            throw CoCartError.forbidden(message ?? "Forbidden")
        case 404 where code == nil:
            throw CoCartError.notFound(message ?? "Not found")
        case 429:
            // CoCart Plus sends `RateLimit-Retry-After`; a proxy may send `Retry-After`.
            let retryAfter = (headers["ratelimit-retry-after"] ?? headers["retry-after"])
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            throw CoCartError.rateLimited(retryAfter: retryAfter)
        default:
            // A refused state (409) or the server's fault (5xx) is always `.api`, whatever its
            // code says (e.g. `cocart_order_invalid_status` is a 409).
            throw CoCartError.api(message ?? "Request failed", statusCode: statusCode, code: code, data: body)
        }
    }

    func on(_ event: CoCartEvent, handler: @escaping (CoCartEventPayload) -> Void) {
        eventHandlers[event, default: []].append(handler)
    }

    private func emit(_ event: CoCartEvent, payload: CoCartEventPayload) {
        eventHandlers[event]?.forEach { $0(payload) }
    }

    func clearETagCache() { etagCache.removeAll() }
}
