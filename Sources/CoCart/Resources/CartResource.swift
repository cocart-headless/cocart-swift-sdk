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

    /// Add an item to the cart by SKU. Both resolve a non-numeric `id` before falling back to a 404.
    public func addItem(_ sku: String, quantity: Double,
                        options: [String: Any]? = nil) async throws -> CoCartResponse {
        try validateProductID(sku)
        try validateQuantity(quantity)
        var body: [String: Any] = ["id": sku, "quantity": "\(quantity)"]
        options?.forEach { body[$0.key] = $0.value }
        return try await http.post("cart/add-item", body: body)
    }

    public func add(_ productID: Int, quantity: Double) async throws -> CoCartResponse {
        try await addItem(productID, quantity: quantity)
    }

    public func add(_ sku: String, quantity: Double) async throws -> CoCartResponse {
        try await addItem(sku, quantity: quantity)
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

    /// Add a variable product to the cart by SKU. See `addItem(_:quantity:options:)`
    /// for why a SKU is accepted here.
    public func addVariation(_ sku: String, quantity: Double,
                             attributes: [String: String]) async throws -> CoCartResponse {
        try validateProductID(sku)
        try validateQuantity(quantity)
        return try await http.post("cart/add-item", body: [
            "id": sku,
            "quantity": "\(quantity)",
            "variation": attributes
        ])
    }

    /// Add multiple children of a WooCommerce Grouped Product to the cart in a
    /// single request, via the dedicated `cart/add-items` endpoint.
    ///
    /// This is NOT a generic "add several unrelated products" call — the
    /// server requires a single grouped product ID plus a map of that
    /// group's child product IDs to quantities. For adding unrelated
    /// products in one request, use `HTTPClient.batch()` via a future batch
    /// helper instead.
    ///
    /// - Parameters:
    ///   - groupedProductID: The parent grouped product's ID.
    ///   - items: Map of child product ID (as a string) to quantity.
    public func addItems(_ groupedProductID: Int, items: [String: Int]) async throws -> CoCartResponse {
        try validateProductID(groupedProductID)
        guard !items.isEmpty else {
            throw CoCartError.validation("addItems() requires at least one item.")
        }
        let quantity = items.mapValues { "\($0)" }
        return try await http.post("cart/add-items", body: [
            "id": "\(groupedProductID)",
            "quantity": quantity
        ])
    }

    /// Add multiple children of a Grouped Product to the cart by the parent's
    /// SKU. See `addItem(_:quantity:options:)` for why a SKU is accepted for
    /// `groupedProductID` — note the child `items` map keys must still be
    /// numeric IDs, they are not resolved as SKUs server-side.
    public func addItems(_ groupedProductID: String, items: [String: Int]) async throws -> CoCartResponse {
        try validateProductID(groupedProductID)
        guard !items.isEmpty else {
            throw CoCartError.validation("addItems() requires at least one item.")
        }
        let quantity = items.mapValues { "\($0)" }
        return try await http.post("cart/add-items", body: [
            "id": groupedProductID,
            "quantity": quantity
        ])
    }

    /// Convenience overload accepting an ordered array of `(id, quantity)` entries.
    public func addItems(_ groupedProductID: Int,
                         items: [(id: String, quantity: Int)]) async throws -> CoCartResponse {
        var map: [String: Int] = [:]
        for item in items { map[item.id] = item.quantity }
        return try await addItems(groupedProductID, items: map)
    }

    /// Convenience overload accepting an ordered array of `(id, quantity)` entries, by the parent's SKU.
    public func addItems(_ groupedProductID: String,
                         items: [(id: String, quantity: Int)]) async throws -> CoCartResponse {
        var map: [String: Int] = [:]
        for item in items { map[item.id] = item.quantity }
        return try await addItems(groupedProductID, items: map)
    }

    public func updateItem(_ itemKey: String, quantity: Double,
                           options: [String: Any]? = nil) async throws -> CoCartResponse {
        try validateQuantity(quantity)
        var body: [String: Any] = ["quantity": "\(quantity)"]
        options?.forEach { body[$0.key] = $0.value }
        return try await http.post("cart/item/\(itemKey)", body: body)
    }

    /// Update multiple items' quantities, one request per item, sequentially.
    /// Returns the response from the last update (reflects the fully-updated cart).
    ///
    /// There is no real bulk-update endpoint on the server, so this loops
    /// one `updateItem()` request per entry. For a true single round trip,
    /// use `batchUpdateItems()` instead (requires CoCart Plus).
    public func updateItems(_ items: [String: Double]) async throws -> CoCartResponse {
        guard !items.isEmpty else {
            throw CoCartError.validation("updateItems() requires at least one item.")
        }
        var response: CoCartResponse!
        for (itemKey, quantity) in items {
            response = try await updateItem(itemKey, quantity: quantity)
        }
        return response
    }

    /// Update multiple items' quantities in a single request via the
    /// `{namespace}/batch` endpoint (requires CoCart Plus). Unlike
    /// `updateItems()`, this is a true single round trip instead of one
    /// sequential request per item.
    public func batchUpdateItems(_ items: [String: Double]) async throws -> CoCartResponse {
        guard !items.isEmpty else {
            throw CoCartError.validation("batchUpdateItems() requires at least one item.")
        }
        let requests = items.map { itemKey, quantity in
            BatchRequestItem(
                method: "POST",
                path: "/\(options.namespace)/v2/cart/item/\(itemKey)",
                body: ["quantity": "\(quantity)"]
            )
        }
        return try await http.batch(requests)
    }

    public func removeItem(_ itemKey: String) async throws -> CoCartResponse {
        try await http.delete("cart/item/\(itemKey)")
    }

    /// Remove multiple items from the cart, one request per item, sequentially.
    /// Returns the response from the last removal (reflects the fully-updated cart).
    ///
    /// There is no real bulk-remove endpoint on the server, so this loops
    /// one `removeItem()` request per entry. For a true single round trip,
    /// use `batchRemoveItems()` instead (requires CoCart Plus).
    public func removeItems(_ itemKeys: [String]) async throws -> CoCartResponse {
        guard !itemKeys.isEmpty else {
            throw CoCartError.validation("removeItems() requires at least one item key.")
        }
        var response: CoCartResponse!
        for itemKey in itemKeys {
            response = try await removeItem(itemKey)
        }
        return response
    }

    /// Remove multiple items in a single request via the `{namespace}/batch`
    /// endpoint (requires CoCart Plus). Unlike `removeItems()`, this is a true
    /// single round trip instead of one sequential request per item.
    public func batchRemoveItems(_ itemKeys: [String]) async throws -> CoCartResponse {
        guard !itemKeys.isEmpty else {
            throw CoCartError.validation("batchRemoveItems() requires at least one item key.")
        }
        let requests = itemKeys.map { itemKey in
            BatchRequestItem(method: "DELETE", path: "/\(options.namespace)/v2/cart/item/\(itemKey)")
        }
        return try await http.batch(requests)
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

    /// Update customer billing (and optionally shipping) address on the cart.
    ///
    /// Posts to the `update-customer` callback on `POST /cart/update` — billing
    /// fields are sent unprefixed (`first_name`, `address_1`, ...) and shipping
    /// fields are sent `s_`-prefixed (`s_first_name`, `s_address_1`, ...), which
    /// the server validates as required for any address field the destination
    /// country marks required, independent of whether `ship_to_different_address`
    /// is set. If `shipping` is omitted or empty, billing is mirrored into the
    /// `s_` fields so that check passes and the shipping address matches
    /// billing, same as leaving "ship to a different address" unchecked at a
    /// normal WooCommerce checkout.
    ///
    /// - Parameters:
    ///   - billing: Billing address fields (unprefixed, e.g. `first_name`, `address_1`, `city`, `postcode`, `country`, `email`, `phone`).
    ///   - shipping: Shipping address fields, if different from billing. Omit to mirror billing.
    public func updateCustomer(billing: [String: Any],
                               shipping: [String: Any]? = nil) async throws -> CoCartResponse {
        let hasDistinctShipping = shipping.map { !$0.isEmpty } ?? false
        let shipTo = hasDistinctShipping ? shipping! : billing

        var body: [String: Any] = ["namespace": "update-customer"]
        billing.forEach { body[$0.key] = $0.value }
        shipTo.forEach { body["s_\($0.key)"] = $0.value }
        if hasDistinctShipping {
            body["ship_to_different_address"] = true
        }

        return try await http.post("cart/update", body: body)
    }

    public func getCustomer() async throws -> CoCartResponse {
        try await http.get("cart/customer")
    }

    public func getShippingMethods() async throws -> CoCartResponse {
        try await http.get("cart/shipping-methods")
    }

    /// There is no address-taking shipping-calculation endpoint in the CoCart
    /// REST API — `POST /cart/shipping-methods` (what this method used to
    /// call) does not exist. To calculate shipping, call `updateCustomer()`
    /// with the destination address first (the server recalculates totals as
    /// part of that request); this method now just delegates to `calculate()`,
    /// ignoring `address`. Prefer `calculate()` directly.
    @available(*, deprecated, message: "This endpoint does not exist server-side. Use updateCustomer() to set the destination address, then calculate() (or call calculate() directly).")
    public func calculateShipping(_ address: [String: String]? = nil) async throws -> CoCartResponse {
        try await calculate()
    }

    /// Select a shipping rate for a package (CoCart Plus).
    ///
    /// Posts `rate_id` (and optional `package_id`) to `POST /cart/set-shipping-method`.
    /// Omit `packageID` to apply the rate to every package.
    ///
    /// - Parameters:
    ///   - rateID: The chosen rate's key, e.g. `flat_rate:2` (see a shipping package's `rates` map).
    ///   - packageID: Restrict the selection to one package. Omit to apply to all packages.
    public func setShippingMethod(_ rateID: String, packageID: String? = nil) async throws -> CoCartResponse {
        var body: [String: Any] = ["rate_id": rateID]
        if let packageID { body["package_id"] = packageID }
        return try await http.post("cart/set-shipping-method", body: body)
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
