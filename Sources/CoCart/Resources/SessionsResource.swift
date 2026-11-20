import Foundation

/// Cart sessions, for administrators (WooCommerce consumer keys). The list is
/// `sessions`; a single session is `session/{session_key}`.
public final class SessionsResource {
    private let http: HTTPClient
    private let auth: AuthManager

    init(http: HTTPClient, auth: AuthManager) {
        self.http = http
        self.auth = auth
    }

    public func all(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("sessions", queryParams: params)
    }

    public func get(_ sessionKey: String) async throws -> CoCartResponse {
        try await http.get("session/\(sessionKey)")
    }

    /// The items in a cart session.
    public func getItems(_ sessionKey: String) async throws -> CoCartResponse {
        try await http.get("session/\(sessionKey)/items")
    }

    public func delete(_ sessionKey: String) async throws -> CoCartResponse {
        try await http.delete("session/\(sessionKey)")
    }
}
