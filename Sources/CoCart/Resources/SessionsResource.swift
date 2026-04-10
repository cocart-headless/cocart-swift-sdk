import Foundation

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
        try await http.get("sessions/\(sessionKey)")
    }

    public func delete(_ sessionKey: String) async throws -> CoCartResponse {
        try await http.delete("sessions/\(sessionKey)")
    }

    public func deleteAll() async throws -> CoCartResponse {
        try await http.delete("sessions")
    }
}
