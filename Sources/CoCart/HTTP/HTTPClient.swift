import Foundation

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
        let headers: [String: String]
    }

    init(siteURL: String, options: CoCartOptions, auth: AuthManager,
         session: URLSession = .shared) {
        self.siteURL = siteURL
        self.options = options
        self.auth = auth
        self.session = session
    }

    private var baseURL: String {
        "\(siteURL.trimmingCharacters(in: .init(charactersIn: "/")))/\(options.restPrefix)/\(options.namespace)/v2"
    }

    func get(_ path: String, queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        let request = try buildRequest(method: "GET", path: path, queryParams: mergedParams(queryParams))
        let key = request.url?.absoluteString ?? path
        return try await inFlightGets.run(key: key) { [self] in
            try await execute(request, path: path)
        }
    }

    func post(_ path: String, body: [String: Any]? = nil,
              queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        var request = try buildRequest(method: "POST", path: path, queryParams: mergedParams(queryParams))
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await execute(request, path: path)
    }

    func delete(_ path: String, queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        let request = try buildRequest(method: "DELETE", path: path, queryParams: mergedParams(queryParams))
        return try await execute(request, path: path)
    }

    func getRaw(_ path: String, queryParams: [String: String]? = nil) async throws -> CoCartResponse {
        let base = siteURL.trimmingCharacters(in: .init(charactersIn: "/"))
        var urlString = "\(base)/\(options.restPrefix)/\(path)"
        if let params = queryParams, !params.isEmpty {
            let query = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            urlString += "?" + query
        }
        guard let requestURL = URL(string: urlString) else {
            throw CoCartError.network("Invalid URL: \(urlString)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authValue = auth.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: options.authHeaderName)
        }
        let key = requestURL.absoluteString
        return try await inFlightGets.run(key: key) { [self] in
            try await execute(request, path: path)
        }
    }

    func postRaw(_ path: String, body: [String: Any]? = nil) async throws -> CoCartResponse {
        let url = "\(siteURL.trimmingCharacters(in: .init(charactersIn: "/")))/\(options.restPrefix)/\(path)"
        guard let requestURL = URL(string: url) else {
            throw CoCartError.network("Invalid URL: \(url)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authValue = auth.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: options.authHeaderName)
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await execute(request, path: path)
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
            if case CoCartError.api(_, let statusCode, let code) = error, code == "rest_no_route" {
                throw CoCartError.api(
                    "This method requires the CoCart Plus plugin. Please ask support for assistance!",
                    statusCode: statusCode,
                    code: "cocart_plugin_required"
                )
            }
            throw error
        }
    }

    private func mergedParams(_ params: [String: String]?) -> [String: String] {
        var merged = params ?? [:]
        if let cartKey = auth.guestCartKey {
            merged["cart_key"] = cartKey
        }
        return merged
    }

    private func buildRequest(method: String, path: String,
                              queryParams: [String: String]?) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)/\(path)") else {
            throw CoCartError.network("Invalid URL for path: \(path)")
        }
        if let params = queryParams, !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw CoCartError.network("Could not construct URL for path: \(path)")
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
        if let cartKey = auth.guestCartKey {
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

    private func execute(_ request: URLRequest, path: String,
                         attempt: Int = 0) async throws -> CoCartResponse {
        emit(.request, payload: ["method": request.httpMethod ?? "", "url": request.url?.absoluteString ?? ""])
        let start = Date()
        let isGet = request.httpMethod == "GET"
        let cacheKey = request.url?.absoluteString ?? path

        do {
            let (data, urlResponse) = try await session.data(for: request)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw CoCartError.network("Invalid response")
            }

            let duration = Date().timeIntervalSince(start) * 1000
            emit(.response, payload: ["status": http.statusCode, "duration": duration])

            let headers = Dictionary(
                uniqueKeysWithValues: http.allHeaderFields.compactMap { k, v -> (String, String)? in
                    guard let key = k as? String, let val = v as? String else { return nil }
                    return (key.lowercased(), val)
                }
            )

            // A 304 has no body — reuse the body/headers cached alongside the ETag
            // that produced the match, so callers still get the actual data instead
            // of an empty object. Falls back to the live (empty) response if we
            // somehow have no cache entry for this URL.
            if http.statusCode == 304 {
                if let cached = etagCache[cacheKey] {
                    return CoCartResponse(data: cached.body, headers: cached.headers, statusCode: 304)
                }
                return CoCartResponse(data: [:], headers: headers, statusCode: 304)
            }

            let body: [String: Any]
            if data.isEmpty {
                body = [:]
            } else {
                body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }

            // ETag: cache the ETag + body from a fresh (non-304) GET response.
            if options.etag, isGet, let etag = headers["etag"] {
                etagCache[cacheKey] = ETagCacheEntry(etag: etag, body: body, headers: headers)
            }

            auth.captureCartKey(from: body, headers: headers)

            return try handleResponse(body: body, headers: headers, statusCode: http.statusCode)

        } catch let error as CoCartError {
            emit(.error, payload: ["error": error.localizedDescription])
            throw error
        } catch {
            if attempt < options.maxRetries {
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(attempt: attempt))
                return try await execute(request, path: path, attempt: attempt + 1)
            }
            throw CoCartError.network(error.localizedDescription)
        }
    }

    /// Exponential backoff (`500ms * 2^attempt`) with ±20% jitter, so many
    /// clients retrying at once don't re-collide on the same schedule.
    private func retryDelayNanoseconds(attempt: Int) -> UInt64 {
        let base = 500_000_000.0 * pow(2.0, Double(attempt))
        let jitter = 0.8 + Double.random(in: 0...1) * 0.4
        return UInt64(base * jitter)
    }

    private func handleResponse(body: [String: Any], headers: [String: String],
                                statusCode: Int) throws -> CoCartResponse {
        switch statusCode {
        case 200, 201:
            return CoCartResponse(data: body, headers: headers, statusCode: statusCode)
        case 401:
            if body["code"] as? String == "cocart_2fa_required" {
                let data = body["data"] as? [String: Any] ?? body
                let providers = data["available_providers"] as? [String] ?? []
                let defaultProvider = data["default_provider"] as? String
                let emailSent = data["email_sent"] as? Bool ?? false
                throw CoCartError.twoFactorRequired(
                    body["message"] as? String ?? "Two-factor authentication required",
                    availableProviders: providers,
                    defaultProvider: defaultProvider,
                    emailSent: emailSent
                )
            }
            throw CoCartError.auth(body["message"] as? String ?? "Unauthorized",
                                   code: body["code"] as? String)
        case 403:
            throw CoCartError.forbidden(body["message"] as? String ?? "Forbidden")
        case 404:
            let code404 = body["code"] as? String
            if code404 != nil {
                throw CoCartError.api(body["message"] as? String ?? "Not found",
                                      statusCode: 404, code: code404)
            }
            throw CoCartError.notFound(body["message"] as? String ?? "Not found")
        case 429:
            let retryAfter = headers["retry-after"].flatMap(Int.init)
            throw CoCartError.rateLimited(retryAfter: retryAfter)
        default:
            throw CoCartError.api(body["message"] as? String ?? "Request failed",
                                  statusCode: statusCode,
                                  code: body["code"] as? String)
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
