import Foundation

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
