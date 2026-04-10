import Foundation

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
        let mapped = items.map { ["item_key": $0.key, "quantity": $0.value] as [String: Any] }
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

    // MARK: - CoCart Plus

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
