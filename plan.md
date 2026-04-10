# CoCart Swift SDK — Developer Plan

> Based on the `@cocartheadless/sdk` TypeScript SDK, adapted faithfully to Swift/Apple platform conventions.

---

## 1. Overview

| Item | Detail |
|---|---|
| Package name | `CoCart` |
| Language | Swift 5.9+ |
| Platforms | iOS 17+, macOS 14+, watchOS 11+ |
| Distribution | Swift Package Manager |
| HTTP | `URLSession` (zero dependencies) |
| Storage | Keychain via `Security` framework |
| Auth | Guest (cart key), Basic Auth, JWT with auto-refresh, Consumer Keys |
| Serialisation | `Codable` |
| Async model | `async/await` + Swift Concurrency |

---

## 2. Package Structure

```
CoCart/
├── Package.swift
├── README.md
├── CHANGELOG.md
├── LICENSE
├── Sources/
│   └── CoCart/
│       ├── CoCart.swift                    # Main client class
│       ├── CoCartOptions.swift             # Configuration
│       ├── Auth/
│       │   ├── AuthManager.swift           # Priority logic, header building
│       │   ├── GuestSession.swift          # Cart key capture + Keychain
│       │   └── JWTManager.swift            # JWT login, refresh, validate, auto-refresh
│       ├── HTTP/
│       │   ├── HTTPClient.swift            # URLSession wrapper, retries, ETag, events
│       │   └── CoCartResponse.swift        # Response wrapper + dot-notation .get()
│       ├── Models/
│       │   ├── Cart.swift
│       │   ├── CartItem.swift
│       │   ├── CartTotals.swift
│       │   ├── Currency.swift
│       │   ├── Product.swift
│       │   ├── ProductVariation.swift
│       │   └── JWTToken.swift
│       ├── Resources/
│       │   ├── CartResource.swift          # client.cart()
│       │   ├── ProductsResource.swift      # client.products()
│       │   ├── SessionsResource.swift      # client.sessions()
│       │   └── JWTResource.swift           # client.jwt()
│       ├── Storage/
│       │   ├── CoCartStorage.swift         # Protocol
│       │   ├── KeychainStorage.swift       # Default (Keychain)
│       │   └── MemoryStorage.swift         # Tests / previews
│       ├── Validation/
│       │   └── Validators.swift            # validateProductId, validateQuantity, validateEmail
│       ├── Utilities/
│       │   └── CurrencyFormatter.swift
│       └── Errors/
│           ├── CoCartError.swift           # Base error enum
│           ├── AuthError.swift
│           ├── ValidationError.swift
│           ├── VersionError.swift
│           └── NetworkError.swift
└── Tests/
    └── CoCartTests/
        ├── AuthManagerTests.swift
        ├── GuestSessionTests.swift
        ├── JWTManagerTests.swift
        ├── CartResourceTests.swift
        ├── ProductsResourceTests.swift
        ├── ResponseTests.swift
        ├── ValidatorsTests.swift
        └── Mocks/
            └── MockURLSession.swift
```

---

## 3. Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoCart",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "CoCart", targets: ["CoCart"]),
    ],
    targets: [
        .target(
            name: "CoCart",
            path: "Sources/CoCart"
        ),
        .testTarget(
            name: "CoCartTests",
            dependencies: ["CoCart"],
            path: "Tests/CoCartTests"
        ),
    ]
)
```

Zero dependencies — `URLSession` and `Security` framework are both part of the Apple SDK.

---

## 4. Configuration (`CoCartOptions.swift`)

Maps directly to the JS SDK's second constructor argument.

```swift
public struct CoCartOptions {
    // Guest session
    public var cartKey: String?
    public var storageKey: String

    // Basic Auth
    public var username: String?
    public var password: String?

    // JWT
    public var jwtToken: String?
    public var jwtRefreshToken: String?

    // Consumer Keys (Sessions API / admin)
    public var consumerKey: String?
    public var consumerSecret: String?

    // HTTP
    public var timeout: TimeInterval
    public var maxRetries: Int

    // REST prefix / namespace
    public var restPrefix: String   // default: "wp-json"
    public var namespace: String    // default: "cocart"

    // Plugin version target
    public var mainPlugin: MainPlugin  // .basic (default) or .legacy

    // Auth header name override (for proxies that strip Authorization)
    public var authHeaderName: String  // default: "Authorization"

    // Storage
    public var storage: CoCartStorage?

    // Misc
    public var extraHeaders: [String: String]
    public var etag: Bool
    public var debug: Bool

    public enum MainPlugin {
        case basic, legacy
    }

    public init(
        cartKey: String? = nil,
        storageKey: String = "cocart_cart_key",
        username: String? = nil,
        password: String? = nil,
        jwtToken: String? = nil,
        jwtRefreshToken: String? = nil,
        consumerKey: String? = nil,
        consumerSecret: String? = nil,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        restPrefix: String = "wp-json",
        namespace: String = "cocart",
        mainPlugin: MainPlugin = .basic,
        authHeaderName: String = "Authorization",
        storage: CoCartStorage? = nil,
        extraHeaders: [String: String] = [:],
        etag: Bool = true,
        debug: Bool = false
    ) {
        self.cartKey = cartKey
        self.storageKey = storageKey
        self.username = username
        self.password = password
        self.jwtToken = jwtToken
        self.jwtRefreshToken = jwtRefreshToken
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.restPrefix = restPrefix
        self.namespace = namespace
        self.mainPlugin = mainPlugin
        self.authHeaderName = authHeaderName
        self.storage = storage
        self.extraHeaders = extraHeaders
        self.etag = etag
        self.debug = debug
    }
}
```

---

## 5. Main Client (`CoCart.swift`)

```swift
public final class CoCart {
    public let siteURL: String
    private var options: CoCartOptions
    private let auth: AuthManager
    private let http: HTTPClient

    // MARK: - Init

    public init(_ siteURL: String, options: CoCartOptions = CoCartOptions()) {
        self.siteURL = siteURL
        self.options = options
        let storage = options.storage ?? KeychainStorage()
        self.auth = AuthManager(options: options, storage: storage)
        self.http = HTTPClient(siteURL: siteURL, options: options, auth: auth)
    }

    // Factory — mirrors CoCart.create() in TS
    public static func create(_ siteURL: String, options: CoCartOptions = CoCartOptions()) -> CoCart {
        CoCart(siteURL, options: options)
    }

    // MARK: - Resources

    public func cart() -> CartResource {
        CartResource(http: http, auth: auth, options: options)
    }

    public func products() -> ProductsResource {
        ProductsResource(http: http, options: options)
    }

    public func sessions() -> SessionsResource {
        SessionsResource(http: http, auth: auth)
    }

    public func jwt() -> JWTResource {
        JWTResource(http: http, auth: auth)
    }

    // MARK: - Guest Session

    public var cartKey: String? { auth.cartKey }

    public func restoreSession() async throws {
        try await auth.restoreSession()
    }

    public func clearSession() async throws {
        try await auth.clearSession()
    }

    // MARK: - Auth (runtime switching, mirrors TS)

    @discardableResult
    public func setAuth(_ identifier: String, password: String) -> CoCart {
        auth.setBasicAuth(identifier, password: password)
        return self
    }

    @discardableResult
    public func setJWTToken(_ token: String) -> CoCart {
        auth.setJWTToken(token)
        return self
    }

    @discardableResult
    public func setRefreshToken(_ token: String) -> CoCart {
        auth.setRefreshToken(token)
        return self
    }

    public var isAuthenticated: Bool { auth.isAuthenticated }
    public var isGuest: Bool { auth.isGuest }

    // MARK: - Fluent Setters (mirrors TS method chaining)

    @discardableResult public func setTimeout(_ seconds: TimeInterval) -> CoCart {
        options.timeout = seconds; return self
    }

    @discardableResult public func setMaxRetries(_ n: Int) -> CoCart {
        options.maxRetries = n; return self
    }

    @discardableResult public func setRestPrefix(_ prefix: String) -> CoCart {
        options.restPrefix = prefix; return self
    }

    @discardableResult public func setNamespace(_ namespace: String) -> CoCart {
        options.namespace = namespace; return self
    }

    @discardableResult public func addHeader(_ key: String, value: String) -> CoCart {
        options.extraHeaders[key] = value; return self
    }

    @discardableResult public func setAuthHeaderName(_ name: String) -> CoCart {
        options.authHeaderName = name; return self
    }

    @discardableResult public func setETag(_ enabled: Bool) -> CoCart {
        options.etag = enabled; return self
    }

    @discardableResult public func setMainPlugin(_ plugin: CoCartOptions.MainPlugin) -> CoCart {
        options.mainPlugin = plugin; return self
    }

    @discardableResult public func setDebug(_ enabled: Bool) -> CoCart {
        options.debug = enabled; return self
    }

    // MARK: - Events

    public func on(_ event: CoCartEvent, handler: @escaping (CoCartEventPayload) -> Void) {
        http.on(event, handler: handler)
    }

    // MARK: - Shorthand login/logout

    public func login(_ identifier: String, password: String) async throws -> CoCartResponse {
        try await jwt().login(identifier, password: password)
    }

    public func logout() async throws {
        try await jwt().logout()
    }
}
```

---

## 6. Auth Manager (`Auth/AuthManager.swift`)

```swift
public enum AuthMode {
    case guest, basicAuth, jwt, consumerKeys
}

final class AuthManager {
    private(set) var mode: AuthMode = .guest
    private(set) var cartKey: String?

    private var username: String?
    private var password: String?
    private var jwtToken: String?
    private var refreshToken: String?
    private var consumerKey: String?
    private var consumerSecret: String?

    private let options: CoCartOptions
    private let storage: CoCartStorage

    init(options: CoCartOptions, storage: CoCartStorage) {
        self.options = options
        self.storage = storage
        self.cartKey = options.cartKey
        self.consumerKey = options.consumerKey
        self.consumerSecret = options.consumerSecret

        if let token = options.jwtToken {
            jwtToken = token
            refreshToken = options.jwtRefreshToken
            mode = .jwt
        } else if let user = options.username {
            username = user
            password = options.password
            mode = .basicAuth
        } else if options.consumerKey != nil {
            mode = .consumerKeys
        }
    }

    var isAuthenticated: Bool { mode != .guest }
    var isGuest: Bool { mode == .guest }
    var activeJWTToken: String? { jwtToken }
    var activeRefreshToken: String? { refreshToken }

    // Auth header value — used by HTTPClient
    func authorizationHeaderValue() -> String? {
        switch mode {
        case .jwt:
            guard let token = jwtToken else { return nil }
            return "Bearer \(token)"
        case .basicAuth:
            guard let u = username, let p = password else { return nil }
            let encoded = Data("\(u):\(p)".utf8).base64EncodedString()
            return "Basic \(encoded)"
        case .consumerKeys:
            guard let ck = consumerKey, let cs = consumerSecret else { return nil }
            let encoded = Data("\(ck):\(cs)".utf8).base64EncodedString()
            return "Basic \(encoded)"
        case .guest:
            return nil
        }
    }

    // Guest cart key for query param
    var guestCartKey: String? {
        mode == .guest ? cartKey : nil
    }

    // Called by HTTPClient after every cart response
    func captureCartKey(from body: [String: Any], headers: [String: String]) {
        guard mode == .guest else { return }
        let key = body["cart_key"] as? String
            ?? headers["cart-key"]
            ?? headers["x-cocart-api"]
        guard let key, key != cartKey else { return }
        cartKey = key
        Task { try? await storage.write(options.storageKey, value: key) }
    }

    func setBasicAuth(_ identifier: String, password: String) {
        username = identifier
        self.password = password
        jwtToken = nil
        refreshToken = nil
        mode = .basicAuth
    }

    func setJWTToken(_ token: String) {
        jwtToken = token
        username = nil
        password = nil
        mode = .jwt
    }

    func setRefreshToken(_ token: String) {
        refreshToken = token
    }

    func restoreSession() async throws {
        if cartKey == nil {
            cartKey = try await storage.read(options.storageKey)
        }
    }

    func clearSession() async throws {
        cartKey = nil
        jwtToken = nil
        refreshToken = nil
        username = nil
        password = nil
        mode = .guest
        try await storage.delete(options.storageKey)
    }
}
```

---

## 7. HTTP Client (`HTTP/HTTPClient.swift`)

```swift
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

    // For JWT endpoints that use a different base path
    func postRaw(_ path: String, body: [String: Any]? = nil) async throws -> CoCartResponse {
        let url = "\(siteURL.trimmingCharacters(in: .init(charactersIn: "/")))/\(options.restPrefix)/\(path)"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        var components = URLComponents(string: "\(baseURL)/\(path)")!
        if let params = queryParams, !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!, timeoutInterval: options.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CoCart-Swift-SDK/1.0.0", forHTTPHeaderField: "User-Agent")

        // Auth header
        if let authValue = auth.authorizationHeaderValue() {
            request.setValue(authValue, forHTTPHeaderField: options.authHeaderName)
        }

        // ETag
        if options.etag, let etag = etagCache[path] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        // Extra headers
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

            // Cache ETag
            if options.etag, let etag = headers["etag"] {
                etagCache[path] = etag
            }

            // 304 Not Modified
            if http.statusCode == 304 {
                return CoCartResponse(data: [:], headers: headers, statusCode: 304)
            }

            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            // Capture guest cart key
            auth.captureCartKey(from: body, headers: headers)

            return try handleResponse(body: body, headers: headers, statusCode: http.statusCode)

        } catch let error as CoCartError {
            emit(.error, payload: ["error": error.localizedDescription])
            throw error
        } catch {
            // Retry on transient errors
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
            throw CoCartError.auth(body["message"] as? String ?? "Unauthorized",
                                   code: body["code"] as? String)
        case 403:
            throw CoCartError.forbidden(body["message"] as? String ?? "Forbidden")
        case 404:
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

public enum CoCartEvent: Hashable { case request, response, error }
public typealias CoCartEventPayload = [String: Any]
```

---

## 8. Response Object (`HTTP/CoCartResponse.swift`)

```swift
public struct CoCartResponse {
    private let data: [String: Any]
    private let headers: [String: String]
    public let statusCode: Int

    init(data: [String: Any], headers: [String: String], statusCode: Int) {
        self.data = data
        self.headers = headers
        self.statusCode = statusCode
    }

    // MARK: - Dot-notation access (mirrors TS response.get('totals.total'))

    public func get(_ path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any? = data
        for part in parts {
            if let dict = current as? [String: Any] {
                current = dict[part]
            } else if let array = current as? [Any], let idx = Int(part), idx < array.count {
                current = array[idx]
            } else {
                return nil
            }
        }
        return current
    }

    public func has(_ path: String) -> Bool { get(path) != nil }

    // MARK: - Typed convenience getters

    public func getString(_ path: String) -> String? { get(path) as? String }
    public func getInt(_ path: String) -> Int? { get(path) as? Int }
    public func getDouble(_ path: String) -> Double? { get(path) as? Double }
    public func getBool(_ path: String) -> Bool? { get(path) as? Bool }

    public func getItems() -> [[String: Any]] { get("items") as? [[String: Any]] ?? [] }
    public func getTotals() -> [String: Any] { get("totals") as? [String: Any] ?? [:] }
    public func getItemCount() -> Int { get("items_count") as? Int ?? 0 }
    public func getCartKey() -> String? { headers["cart-key"] ?? getString("cart_key") }
    public func getCartHash() -> String? { getString("cart_hash") }
    public func getNotices() -> [[String: Any]] { get("notices") as? [[String: Any]] ?? [] }
    public func getCurrency() -> [String: Any]? { get("currency") as? [String: Any] }
    public func getCacheStatus() -> String? { headers["cocart-cache"] }
    public func isNotModified() -> Bool { statusCode == 304 }

    public func toJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
    }

    public func toDictionary() -> [String: Any] { data }

    // MARK: - Codable decoding

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: self.data)
        return try JSONDecoder().decode(type, from: data)
    }
}
```

---

## 9. Cart Resource (`Resources/CartResource.swift`)

```swift
public final class CartResource {
    private let http: HTTPClient
    private let auth: AuthManager
    private let options: CoCartOptions

    init(http: HTTPClient, auth: AuthManager, options: CoCartOptions) {
        self.http = http
        self.auth = auth
        self.options = options
    }

    public func create() async throws -> CoCartResponse {
        try await http.post("cart")
    }

    public func get(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("cart", queryParams: params)
    }

    public func getFiltered(_ fields: [String]) async throws -> CoCartResponse {
        let param = options.mainPlugin == .legacy ? "fields" : "_fields"
        return try await http.get("cart", queryParams: [param: fields.joined(separator: ",")])
    }

    public func addItem(_ productID: Int, quantity: Double,
                        options: [String: Any]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        try validateQuantity(quantity)
        var body: [String: Any] = ["id": "\(productID)", "quantity": "\(quantity)"]
        options?.forEach { body[$0.key] = $0.value }
        return try await http.post("cart/add-item", body: body)
    }

    // Alias
    public func add(_ productID: Int, quantity: Double) async throws -> CoCartResponse {
        try await addItem(productID, quantity: quantity)
    }

    public func addVariation(_ productID: Int, quantity: Double,
                             attributes: [String: String]) async throws -> CoCartResponse {
        try validateProductID(productID)
        try validateQuantity(quantity)
        return try await http.post("cart/add-item", body: [
            "id": "\(productID)",
            "quantity": "\(quantity)",
            "variation": attributes
        ])
    }

    public func addItems(_ items: [[String: Any]]) async throws -> CoCartResponse {
        try await http.post("cart/add-items", body: ["items": items])
    }

    public func updateItem(_ itemKey: String, quantity: Double,
                           options: [String: Any]? = nil) async throws -> CoCartResponse {
        try validateQuantity(quantity)
        var body: [String: Any] = ["quantity": "\(quantity)"]
        options?.forEach { body[$0.key] = $0.value }
        return try await http.post("cart/item/\(itemKey)", body: body)
    }

    public func updateItems(_ items: [String: Double]) async throws -> CoCartResponse {
        let mapped = items.map { ["item_key": $0.key, "quantity": $0.value] }
        return try await http.post("cart/update-items", body: ["items": mapped])
    }

    public func removeItem(_ itemKey: String) async throws -> CoCartResponse {
        try await http.delete("cart/item/\(itemKey)")
    }

    public func removeItems(_ itemKeys: [String]) async throws -> CoCartResponse {
        try await http.post("cart/remove-items", body: ["items": itemKeys])
    }

    public func restoreItem(_ itemKey: String) async throws -> CoCartResponse {
        try await http.post("cart/item/\(itemKey)/restore")
    }

    public func getRemovedItems() async throws -> CoCartResponse {
        try await http.get("cart/items/removed")
    }

    public func clear() async throws -> CoCartResponse { try await http.post("cart/clear") }
    public func empty() async throws -> CoCartResponse { try await clear() }

    public func calculate() async throws -> CoCartResponse {
        try await http.post("cart/calculate")
    }

    public func update(_ data: [String: Any]) async throws -> CoCartResponse {
        try await http.post("cart/update", body: data)
    }

    public func getTotals(formatted: Bool = false) async throws -> CoCartResponse {
        try await http.get("cart/totals", queryParams: formatted ? ["html": "true"] : nil)
    }

    public func getItemCount() async throws -> CoCartResponse {
        try await http.get("cart/items/count")
    }

    public func getItems() async throws -> CoCartResponse {
        try await http.get("cart/items")
    }

    public func getItem(_ itemKey: String) async throws -> CoCartResponse {
        try await http.get("cart/item/\(itemKey)")
    }

    // CoCart Plus
    public func applyCoupon(_ code: String) async throws -> CoCartResponse {
        try await http.post("cart/coupon", body: ["coupon": code])
    }

    public func removeCoupon(_ code: String) async throws -> CoCartResponse {
        try await http.delete("cart/coupon/\(code)")
    }

    public func getCoupons() async throws -> CoCartResponse {
        try await http.get("cart/coupons")
    }

    public func checkCoupons() async throws -> CoCartResponse {
        try await http.get("cart/check-coupons")
    }

    public func updateCustomer(billing: [String: Any],
                               shipping: [String: Any]? = nil) async throws -> CoCartResponse {
        var body: [String: Any] = ["billing_address": billing]
        if let shipping { body["shipping_address"] = shipping }
        return try await http.post("cart/customer", body: body)
    }

    public func getCustomer() async throws -> CoCartResponse {
        try await http.get("cart/customer")
    }

    public func getShippingMethods() async throws -> CoCartResponse {
        try await http.get("cart/shipping-methods")
    }

    public func calculateShipping(_ address: [String: String]) async throws -> CoCartResponse {
        try await http.post("cart/shipping-methods", body: address)
    }

    public func setShippingMethod(_ method: String) async throws -> CoCartResponse {
        try await http.post("cart/shipping-method", body: ["key": method])
    }

    public func getFees() async throws -> CoCartResponse {
        try await http.get("cart/fees")
    }

    public func addFee(_ name: String, amount: Double,
                       taxable: Bool = false) async throws -> CoCartResponse {
        try await http.post("cart/fees", body: [
            "name": name,
            "amount": "\(amount)",
            "taxable": "\(taxable)"
        ])
    }

    public func removeFees() async throws -> CoCartResponse {
        try await http.delete("cart/fees")
    }

    public func getCrossSells() async throws -> CoCartResponse {
        try await http.get("cart/cross-sells")
    }
}
```

---

## 10. JWT Resource (`Resources/JWTResource.swift`)

```swift
public final class JWTResource {
    private let http: HTTPClient
    private let auth: AuthManager
    private var autoRefreshEnabled = false

    init(http: HTTPClient, auth: AuthManager) {
        self.http = http
        self.auth = auth
    }

    public func login(_ identifier: String, password: String) async throws -> CoCartResponse {
        let response = try await http.postRaw("cocart/jwt/token", body: [
            "username": identifier,
            "password": password
        ])
        guard let token = response.getString("token") else {
            throw CoCartError.auth("JWT login failed — no token returned", code: nil)
        }
        auth.setJWTToken(token)
        if let refresh = response.getString("refresh_token") {
            auth.setRefreshToken(refresh)
        }
        return response
    }

    public func logout() async throws {
        _ = try? await http.postRaw("cocart/jwt/logout")
        try await auth.clearSession()
    }

    public func refresh() async throws -> CoCartResponse {
        guard let refreshToken = auth.activeRefreshToken else {
            throw CoCartError.auth("No refresh token available", code: nil)
        }
        let response = try await http.postRaw("cocart/jwt/refresh-token",
                                              body: ["refresh_token": refreshToken])
        if let token = response.getString("token") {
            auth.setJWTToken(token)
        }
        return response
    }

    public func validate() async throws -> Bool {
        do {
            let response = try await http.postRaw("cocart/jwt/validate-token")
            return response.getInt("data.status") == 200
        } catch {
            return false
        }
    }

    public func isTokenExpired(leeway: TimeInterval = 30) -> Bool {
        guard let expiry = getTokenExpiry() else { return true }
        return Date().timeIntervalSince1970 > expiry - leeway
    }

    public func getTokenExpiry() -> TimeInterval? {
        guard let token = auth.activeJWTToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64Encoded: String(parts[1]).base64Padded),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else { return nil }
        return exp
    }

    public func hasTokens() -> Bool { auth.activeJWTToken != nil }

    public func setAutoRefresh(_ enabled: Bool) { autoRefreshEnabled = enabled }
    public func isAutoRefreshEnabled() -> Bool { autoRefreshEnabled }

    public func withAutoRefresh<T>(_ operation: () async throws -> T) async throws -> T {
        if isTokenExpired() { _ = try await refresh() }
        return try await operation()
    }
}

private extension String {
    var base64Padded: String {
        let remainder = count % 4
        guard remainder != 0 else { return self }
        return self + String(repeating: "=", count: 4 - remainder)
    }
}
```

---

## 11. Keychain Storage (`Storage/KeychainStorage.swift`)

```swift
import Security

public final class KeychainStorage: CoCartStorage {
    private let service: String

    public init(service: String = "com.cocart.sdk") {
        self.service = service
    }

    public func read(_ key: String) async throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    public func write(_ key: String, value: String) async throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public func delete(_ key: String) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

---

## 12. Validation (`Validation/Validators.swift`)

```swift
public struct ValidationError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public func validateProductID(_ id: Int) throws {
    guard id > 0 else {
        throw ValidationError("Product ID must be a positive integer")
    }
}

public func validateQuantity(_ quantity: Double) throws {
    guard quantity > 0 else {
        throw ValidationError("Quantity must be a positive number")
    }
}

public func validateEmail(_ email: String) throws {
    let regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    guard email.contains(regex) else {
        throw ValidationError("Invalid email address")
    }
}
```

---

## 13. Currency Formatter (`Utilities/CurrencyFormatter.swift`)

```swift
public struct CurrencyFormatter {
    public init() {}

    /// Formats a raw integer (e.g. 4599) into "$45.99"
    public func format(_ amount: Int, currency: [String: Any]) -> String {
        let decimals = currency["currency_minor_unit"] as? Int ?? 2
        let symbol = currency["currency_symbol"] as? String ?? ""
        let position = currency["currency_symbol_position"] as? String ?? "left"
        let decSep = currency["currency_decimal_separator"] as? String ?? "."
        let thouSep = currency["currency_thousand_separator"] as? String ?? ","

        let value = Double(amount) / pow(10.0, Double(decimals))
        let formatted = formatNumber(value, decimals: decimals, decSep: decSep, thouSep: thouSep)
        return position == "left" ? "\(symbol)\(formatted)" : "\(formatted)\(symbol)"
    }

    public func formatDecimal(_ amount: Int, currency: [String: Any]) -> String {
        let decimals = currency["currency_minor_unit"] as? Int ?? 2
        let value = Double(amount) / pow(10.0, Double(decimals))
        return String(format: "%.\(decimals)f", value)
    }

    private func formatNumber(_ value: Double, decimals: Int,
                              decSep: String, thouSep: String) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.groupingSeparator = thouSep
        formatter.decimalSeparator = decSep
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
```

---

## 14. Error Types (`Errors/CoCartError.swift`)

```swift
public enum CoCartError: Error, LocalizedError {
    case auth(String, code: String?)
    case forbidden(String)
    case notFound(String)
    case rateLimited(retryAfter: Int?)
    case api(String, statusCode: Int, code: String?)
    case network(String)
    case validation(String)
    case version(String)

    public var errorDescription: String? {
        switch self {
        case .auth(let msg, _): return "Authentication error: \(msg)"
        case .forbidden(let msg): return "Forbidden: \(msg)"
        case .notFound(let msg): return "Not found: \(msg)"
        case .rateLimited(let after): return "Rate limited\(after.map { ". Retry after \($0)s" } ?? "")"
        case .api(let msg, let code, _): return "API error \(code): \(msg)"
        case .network(let msg): return "Network error: \(msg)"
        case .validation(let msg): return "Validation error: \(msg)"
        case .version(let msg): return "Version error: \(msg)"
        }
    }
}
```

---

## 15. Quick Start

```swift
import CoCart

// Guest — simplest setup
let client = CoCart("https://your-store.com")

// Restore previous session on app launch
try await client.restoreSession()

// Browse products
let products = try await client.products().all(["per_page": "12"])

// Add to cart — cart key captured automatically
try await client.cart().addItem(123, quantity: 2)
print(client.cartKey) // Optional("guest_abc123...")

// Dot-notation response access
let cart = try await client.cart().get()
print(cart.get("totals.total"))       // Any?
print(cart.getString("items.0.name")) // String?

// Decode into a Codable model
let decoded = try cart.decode(CartResponse.self)

// Authenticated customer
let authClient = CoCart("https://your-store.com",
    options: CoCartOptions(username: "email@example.com", password: "pass"))

// JWT auth
let jwtClient = CoCart("https://your-store.com")
try await jwtClient.login("email@example.com", password: "password")
let authCart = try await jwtClient.cart().get()

// Fluent config
let client2 = CoCart.create("https://your-store.com")
    .setTimeout(15)
    .setMaxRetries(2)
    .setAuthHeaderName("X-Auth-Token")
    .addHeader("X-Custom", value: "value")

// Currency formatting
let fmt = CurrencyFormatter()
let currency = cart.getCurrency()!
print(fmt.format(4599, currency: currency)) // "$45.99"

// Events
client.on(.request) { payload in
    print("\(payload["method"]!) \(payload["url"]!)")
}
client.on(.response) { payload in
    print("\(payload["status"]!) in \(payload["duration"]!)ms")
}
client.on(.error) { payload in
    print(payload["error"]!)
}
```

---

## 16. SwiftUI Integration Example

```swift
@MainActor
class CartViewModel: ObservableObject {
    @Published var items: [[String: Any]] = []
    @Published var total: String = ""
    @Published var isLoading = false
    @Published var error: String?

    private let client = CoCart("https://your-store.com")

    func loadCart() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.restoreSession()
            let response = try await client.cart().get()
            items = response.getItems()
            total = response.getString("totals.total") ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addItem(_ productID: Int) async {
        do {
            _ = try await client.cart().addItem(productID, quantity: 1)
            await loadCart()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

---

## 17. Build Phases

| Phase | Scope | Output |
|---|---|---|
| **1 — Core** | `CoCart`, `CoCartOptions`, `AuthManager`, `HTTPClient`, `CoCartResponse` | Client makes authenticated/guest requests |
| **2 — Guest Session** | `KeychainStorage`, `MemoryStorage`, `restoreSession()`, cart key capture | Cart key persists across app launches |
| **3 — Cart Resource** | All `cart()` methods, validation | Full cart workflow |
| **4 — JWT** | `JWTManager`, `JWTResource`, auto-refresh, token expiry | JWT login/refresh/logout |
| **5 — Products** | `ProductsResource`, `VersionError` for legacy mode | Product browsing |
| **6 — Utilities** | `CurrencyFormatter`, event system, ETag | Feature parity with TS SDK |
| **7 — Tests** | Unit tests with `MockURLSession` | 90%+ coverage |
| **8 — SPM Publish** | README, CHANGELOG, DocC comments, example app | Published to SPM |

---

## 18. Key TS → Swift Mapping

| TypeScript | Swift |
|---|---|
| `new CoCart(url, opts)` | `CoCart(url, options: opts)` |
| `CoCart.create(url)` | `CoCart.create(url)` |
| `client.cart()` | `client.cart()` → `CartResource` |
| `Promise<T>` / `async/await` | `async throws -> T` |
| `localStorage` / `EncryptedStorage` | `KeychainStorage` |
| `MemoryStorage` | `MemoryStorage` |
| `new CurrencyFormatter()` | `CurrencyFormatter()` |
| `response.get('a.b.c')` | `response.get("a.b.c")` |
| `response.getString(...)` | `response.getString(...)` (added typed variants) |
| `ValidationError` | `ValidationError` |
| `VersionError` | `CoCartError.version(...)` |
| `client.on('request', fn)` | `client.on(.request) { ... }` |
| Method chaining returns `this` | `@discardableResult` setters return `CoCart` |
| `Codable` via JSON.parse | `response.decode(MyType.self)` via `JSONDecoder` |