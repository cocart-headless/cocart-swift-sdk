import Foundation

public final class ProductsResource {
    private let http: HTTPClient
    private let options: CoCartOptions

    init(http: HTTPClient, options: CoCartOptions) {
        self.http = http
        self.options = options
    }

    public func all(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products", queryParams: params)
    }

    public func get(_ productID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)", queryParams: params)
    }

    public func variations(_ productID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)/variations", queryParams: params)
    }

    public func variation(_ productID: Int, variationID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)/variations/\(variationID)", queryParams: params)
    }

    public func categories(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/categories", queryParams: params)
    }

    public func tags(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/tags", queryParams: params)
    }

    public func attributes(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/attributes", queryParams: params)
    }

    public func reviews(_ productID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)/reviews", queryParams: params)
    }
}
