import Foundation

public final class JWTResource {
    private let http: HTTPClient
    private let auth: AuthManager
    private var autoRefreshEnabled = false

    init(http: HTTPClient, auth: AuthManager) {
        self.http = http
        self.auth = auth
    }

    /// Log in with username and password to acquire JWT tokens (`POST login`, with the
    /// CoCart JWT Authentication plugin).
    ///
    /// If the user has 2FA enabled, throws `CoCartError.twoFactorRequired`.
    /// Catch that error, prompt for the verification code, then call `verifyTwoFactor()`.
    public func login(_ identifier: String, password: String) async throws -> CoCartResponse {
        let response = try await http.post("login", body: [
            "username": identifier,
            "password": password
        ])
        return try storeTokens(response)
    }

    /// Keep the tokens a login sends under `extras` (`jwt_token`, `jwt_refresh`).
    private func storeTokens(_ response: CoCartResponse) throws -> CoCartResponse {
        guard let token = response.getString("extras.jwt_token") else {
            throw CoCartError.auth(
                "The login response has no JWT token. Is the CoCart JWT Authentication plugin active?",
                code: "cocart_jwt_missing"
            )
        }
        auth.setJWTToken(token)
        if let refresh = response.getString("extras.jwt_refresh") {
            auth.setRefreshToken(refresh)
        }
        return response
    }

    /// Complete a Two Factor Authentication login challenge.
    ///
    /// Call this after catching `CoCartError.twoFactorRequired` from `login()`.
    /// Submits the verification code (and optional provider) to acquire JWT tokens.
    ///
    /// - Parameters:
    ///   - identifier: Username or email address.
    ///   - password: Account password.
    ///   - code: Verification code from the user's 2FA provider.
    ///   - provider: Provider to use (e.g. `"totp"`, `"email"`, `"backup"`). Uses server default if nil.
    public func verifyTwoFactor(_ identifier: String, password: String, code: String, provider: String? = nil) async throws -> CoCartResponse {
        var body: [String: Any] = [
            "username": identifier,
            "password": password,
            "2fa_code": code
        ]
        if let provider { body["2fa_provider"] = provider }

        let response = try await http.post("login", body: body)
        return try storeTokens(response)
    }

    /// Log out on the server (`POST logout`), then clear the tokens and cart key.
    public func logout() async throws {
        _ = try? await http.post("logout")
        try await auth.clearSession()
    }

    /// Get a new access token with the refresh token (`POST {namespace}/jwt/refresh-token`).
    public func refresh() async throws -> CoCartResponse {
        guard let refreshToken = auth.activeRefreshToken else {
            throw CoCartError.auth("No refresh token available", code: nil)
        }
        let response = try await http.postRaw("\(http.namespace)/jwt/refresh-token",
                                              body: ["refresh_token": refreshToken])
        if let token = response.getString("token") {
            auth.setJWTToken(token)
        }
        if let refresh = response.getString("refresh_token") {
            auth.setRefreshToken(refresh)
        }
        return response
    }

    /// Check the JWT token with the server (`POST {namespace}/jwt/validate-token`).
    /// `false` when the server refuses it.
    public func validate() async throws -> Bool {
        do {
            _ = try await http.postRaw("\(http.namespace)/jwt/validate-token")
            return true
        } catch CoCartError.auth, CoCartError.forbidden {
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
