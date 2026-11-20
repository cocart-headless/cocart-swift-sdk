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

    /// Add an item to the cart.
    ///
    /// `options` holds the request's other fields: `variation` (a variable product's
    /// attributes), `item_data` (custom data), `email`, `price` and `return_item`, and the
    /// choices for CoCart Plus's supported plugins: `convert_to_sub` (a subscription plan's
    /// `value`, `"0"` for one-time), `recipient_email` (a gift's recipient) and `item_data`
    /// `["warranty": key]` (a warranty option). Other plugins' fields pass through as given.
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

    /// Restore a removed item to the cart (`PUT cart/item/{item_key}`).
    public func restoreItem(_ itemKey: String) async throws -> CoCartResponse {
        try await http.put("cart/item/\(itemKey)")
    }

    /// Items removed from the cart that can be restored.
    public func getRemovedItems() async throws -> CoCartResponse {
        try await getFiltered(["removed_items"])
    }

    public func clear() async throws -> CoCartResponse { try await http.post("cart/clear") }
    public func empty() async throws -> CoCartResponse { try await clear() }

    public func calculate() async throws -> CoCartResponse {
        try await http.post("cart/calculate")
    }

    public func update(_ data: [String: Any]) async throws -> CoCartResponse {
        try await http.post("cart/update", body: data)
    }

    /// Switch a cart item to another subscription plan, or to one-time with `"0"`
    /// (CoCart Plus).
    ///
    /// The options are in the item's `extensions.subscription_schemes`; pass one's
    /// `value`. Posts the `update-item-schema` callback on `POST cart/update`.
    public func changePlan(_ itemKey: String, value: String) async throws -> CoCartResponse {
        guard !itemKey.isEmpty else {
            throw CoCartError.validation("changePlan() requires an item key.")
        }
        return try await update([
            "namespace": "update-item-schema",
            "item_key": itemKey,
            "convert_to_sub": value
        ])
    }

    /// A lighter cart response for a mini cart (CoCart Plus).
    public func getMini(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("cart/mini", queryParams: params)
    }

    /// Remove every item but keep the cart's coupons, fees and customer details
    /// (CoCart Plus, `DELETE cart/items`). `clear()` empties the whole cart.
    public func removeAllItems() async throws -> CoCartResponse {
        try await http.delete("cart/items")
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

    /// Apply a coupon (CoCart Plus). Pass the customer's `email` for coupons restricted
    /// to certain emails when the cart doesn't know it yet.
    public func applyCoupon(_ code: String, email: String? = nil) async throws -> CoCartResponse {
        var body: [String: Any] = ["code": code]
        if let email, !email.isEmpty { body["email"] = email }
        return try await http.post("cart/apply-coupon", body: body)
    }

    /// Remove a coupon (CoCart Plus).
    ///
    /// The code goes in the URL path, so it's encoded: codes can contain spaces, `%`,
    /// `#`, `?` and other characters. A code containing `/` can't be removed by code
    /// (CoCart Plus matches any path segment without `/`); `removeCoupons()` removes all
    /// of them instead.
    public func removeCoupon(_ code: String) async throws -> CoCartResponse {
        try await http.delete("cart/coupons/\(encodePathSegment(code))")
    }

    /// Remove every coupon from the cart (CoCart Plus).
    public func removeCoupons() async throws -> CoCartResponse {
        try await http.delete("cart/coupons")
    }

    /// The coupons applied to the cart.
    public func getCoupons() async throws -> CoCartResponse {
        try await getFiltered(["coupons"])
    }

    /// Check the applied coupons are still valid (CoCart Plus). Pass the customer's
    /// `email` to check coupons restricted to certain emails.
    public func checkCoupons(email: String? = nil) async throws -> CoCartResponse {
        let params = email.flatMap { $0.isEmpty ? nil : ["email": $0] }
        return try await http.get("cart/coupons/validate", queryParams: params)
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

    /// The customer's details on the cart.
    public func getCustomer() async throws -> CoCartResponse {
        try await getFiltered(["customer"])
    }

    /// The cart's shipping packages and their rates. Read them with
    /// `CoCartResponse.getShippingMethods()` (a list of packages) or
    /// `CoCartResponse.getShipping()` (the whole field).
    public func getShippingMethods() async throws -> CoCartResponse {
        try await getFiltered(["shipping"])
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

    /// The cart's fees. Read them as a list with `CoCartResponse.getFees()`.
    public func getFees() async throws -> CoCartResponse {
        try await getFiltered(["fees"])
    }

    /// Add a fee to the cart (CoCart Plus).
    ///
    /// - Parameter taxClass: The tax class to use when the fee is taxable.
    public func addFee(_ name: String, amount: Double, taxable: Bool = false,
                       taxClass: String? = nil) async throws -> CoCartResponse {
        // CoCart Plus takes the amount as a string (a number is rejected as rest_invalid_param).
        var body: [String: Any] = ["name": name, "amount": "\(amount)", "taxable": taxable]
        if let taxClass, !taxClass.isEmpty { body["tax_class"] = taxClass }
        return try await http.post("cart/add-fee", body: body)
    }

    /// Remove all fees from the cart (CoCart Plus).
    public func removeFees() async throws -> CoCartResponse {
        try await http.post("cart/remove-fees")
    }

    /// Cross-sell products for the items in the cart.
    public func getCrossSells() async throws -> CoCartResponse {
        try await getFiltered(["cross_sells"])
    }

    private func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
