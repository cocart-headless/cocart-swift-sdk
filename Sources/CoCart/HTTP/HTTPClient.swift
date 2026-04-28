import Foundation

public enum CoCartEvent: Hashable { case request, response, error }
public typealias CoCartEventPayload = [String: Any]

final class HTTPClient {
    private let siteURL: String
    private var options: CoCartOptions
    private let auth: AuthManager
    private let session: URLSession
    private var etagCache: [String: String] = [:]
    private var eventHandlers: [CoCartEvent: [(CoCartEventPayload) -> Void]] = [:]

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
        return try await execute(request, path: path)
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
        return try await execute(request, path: path)
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

        // Cart key headers for guest sessions
        if let cartKey = auth.guestCartKey {
            request.setValue(cartKey, forHTTPHeaderField: "Cart-Key")
            request.setValue(cartKey, forHTTPHeaderField: "CoCart-API-Cart-Key")
        }

        if options.etag, let etag = etagCache[path] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
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

            if options.etag, let etag = headers["etag"] {
                etagCache[path] = etag
            }

            if http.statusCode == 304 {
                return CoCartResponse(data: [:], headers: headers, statusCode: 304)
            }

            let body: [String: Any]
            if data.isEmpty {
                body = [:]
            } else {
                body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }

            auth.captureCartKey(from: body, headers: headers)

            return try handleResponse(body: body, headers: headers, statusCode: http.statusCode)

        } catch let error as CoCartError {
            emit(.error, payload: ["error": error.localizedDescription])
            throw error
        } catch {
            if attempt < options.maxRetries {
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * pow(2.0, Double(attempt))))
                return try await execute(request, path: path, attempt: attempt + 1)
            }
            throw CoCartError.network(error.localizedDescription)
        }
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
