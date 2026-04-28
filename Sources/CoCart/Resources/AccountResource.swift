import Foundation

public final class AccountResource {
    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    // MARK: - Helpers

    private static let base = "cocart/v2/my-account"

    private func rawPath(_ sub: String = "") -> String {
        sub.isEmpty ? Self.base : "\(Self.base)/\(sub)"
    }

    private func handleNoRoute(_ error: Error) throws -> Never {
        if case CoCartError.api(_, _, let code) = error, code == "rest_no_route" {
            throw CoCartError.api(
                "This method is only available with another CoCart plugin. Please ask support for assistance!",
                statusCode: 404,
                code: "cocart_plugin_required"
            )
        }
        throw error
    }

    // MARK: - Profile

    /// Return the authenticated user's account profile.
    public func getProfile() async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath()) }
        catch { try handleNoRoute(error) }
    }

    /// Update the authenticated user's profile fields.
    public func updateProfile(_ data: [String: Any]) async throws -> CoCartResponse {
        do { return try await http.postRaw(rawPath(), body: data) }
        catch { try handleNoRoute(error) }
    }

    /// Change the authenticated user's password.
    ///
    /// Fields are remapped to the wire format: current → password_current,
    /// password → password_1, confirm → password_2.
    public func changePassword(current: String, password: String, confirm: String) async throws -> CoCartResponse {
        do {
            return try await http.postRaw(rawPath("change-password"), body: [
                "password_current": current,
                "password_1": password,
                "password_2": confirm,
            ])
        } catch { try handleNoRoute(error) }
    }

    // MARK: - Orders

    /// Return a paginated list of the user's orders.
    public func getOrders(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("orders"), queryParams: params) }
        catch { try handleNoRoute(error) }
    }

    /// Return a single order by ID.
    public func getOrder(_ id: Int) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("orders/\(id)")) }
        catch { try handleNoRoute(error) }
    }

    /// Return a single guest order by ID and billing email.
    public func getGuestOrder(_ id: Int, email: String) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("orders/\(id)"), queryParams: ["email": email]) }
        catch { try handleNoRoute(error) }
    }

    // MARK: - Downloads

    /// Return downloadable files for a specific order.
    public func getOrderDownloads(_ id: Int) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("orders/\(id)/downloads")) }
        catch { try handleNoRoute(error) }
    }

    /// Return downloadable files for a specific guest order.
    public func getGuestOrderDownloads(_ id: Int, email: String) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("orders/\(id)/downloads"), queryParams: ["email": email]) }
        catch { try handleNoRoute(error) }
    }

    /// Return all downloadable files available to the authenticated user.
    public func getDownloads() async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("downloads")) }
        catch { try handleNoRoute(error) }
    }

    // MARK: - Reviews

    /// Return the authenticated user's product reviews.
    public func getReviews() async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath("reviews")) }
        catch { try handleNoRoute(error) }
    }
}
