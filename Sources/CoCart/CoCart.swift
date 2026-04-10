import Foundation

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

    // MARK: - Auth

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

    // MARK: - Fluent Setters

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
