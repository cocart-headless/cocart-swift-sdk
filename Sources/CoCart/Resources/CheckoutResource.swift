import Foundation

/// Checkout (CoCart Plus 2.0): places orders and takes payment.
///
/// The card never passes through this SDK: the gateway's own iOS SDK (for Stripe,
/// stripe-ios with your publishable key) collects it and returns a payment method ID,
/// and the order is placed with that ID.
public final class CheckoutResource {
    private let http: HTTPClient

    private static let route = "cocart/v2/checkout"
    private static let api = "cocart/v2"

    init(http: HTTPClient) {
        self.http = http
    }

    /// The checkout as it stands, like a receipt: items, coupons, fees, `totals` and
    /// `total_lines`, the payment method, the addresses, each shipping package with its rates,
    /// and `actions`.
    ///
    /// Call it for the screen the customer reviews before paying: CoCart Plus remembers the
    /// total it showed, and refuses the order if the total has changed by then
    /// (`409 cocart_checkout_total_mismatch`). Don't call it just before placing the order.
    ///
    /// - Parameters:
    ///   - currency: Show prices in this currency (multi-currency stores).
    ///   - formatted: Amounts formatted for display (`"$18.00"`) instead of minor units (`"1800"`).
    ///   - thumb: `false` leaves each item's `featured_image` empty.
    public func get(currency: String? = nil, formatted: Bool? = nil, thumb: Bool? = nil) async throws -> CoCartResponse {
        try await http.getRaw(Self.route, queryParams: documentQuery([
            "currency": currency, "formatted": formatted, "thumb": thumb,
        ]))
    }

    /// Save addresses, the shipping method, the payment method, a coupon (`coupon_code` with
    /// `coupon_action` `apply` or `remove`) or the currency, without placing the order.
    ///
    /// Returns the checkout with what it did in `result`: `checkout_updated`, or
    /// `checkout_partly_updated` with what wasn't applied, and why, in `result.not_applied`
    /// (`[{field, code, message}]`). Every address field at fault is reported at once
    /// (`CoCartError.fields`).
    public func update(_ data: [String: Any]) async throws -> CoCartResponse {
        try await http.putRaw(Self.route, body: data)
    }

    /// Create the order and attempt payment, sending `payment_data` as given (the
    /// low-level call behind `placeOrder(_:)`).
    public func process(_ data: [String: Any]) async throws -> CoCartResponse {
        try await http.postRaw(Self.route, body: data)
    }

    /// Create the order and take payment.
    ///
    /// `payment_data` is a dictionary of the keys the WooCommerce gateway reads, e.g.
    /// `["wc-stripe-payment-method": paymentMethod.stripeId]`: gateway tokens only, never card
    /// details. A free order needs neither it nor `payment_method`. Calling again for the same
    /// cart lands on the same order. A declined card is a failed result; errors before payment
    /// (missing fields, an empty cart) are thrown as `CoCartError`.
    ///
    /// The order is sent with a random `checkout_id`, or the one in `input` (16 to 64 letters,
    /// digits, `-` or `_`; anything else is `checkout_invalid_checkout_id`, before sending).
    /// When no answer comes back, or another request is still taking payment for the cart
    /// (`409 cocart_payment_in_progress`), the order may have been placed: this throws
    /// `CheckoutOutcomeUnknownError`, and `getStatus(_:)` with its `checkoutId` tells how it ended.
    ///
    /// A total that changed since `get()` or `update(_:)` is `409 cocart_checkout_total_mismatch`:
    /// get the checkout again and show the new total.
    public func placeOrder(_ input: [String: Any]) async throws -> CheckoutResult {
        let checkoutId: String
        if let given = input["checkout_id"] {
            guard let id = given as? String,
                  id.range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil else {
                throw CoCartError.api(
                    "checkout_id must be 16 to 64 letters, digits, \"-\" or \"_\".",
                    statusCode: 0,
                    code: "checkout_invalid_checkout_id",
                    data: [:]
                )
            }
            checkoutId = id
        } else {
            checkoutId = Self.newCheckoutId()
        }
        var body = withPaymentDataPairs(input)
        body["checkout_id"] = checkoutId
        if let metaKeys = input["meta_keys"] as? [String] {
            body["meta_keys"] = metaKeys.joined(separator: ",")
        }
        do {
            return CheckoutResult.from(try await process(body))
        } catch let error as CoCartError where Self.isLostResponse(error) || Self.isPaymentInProgress(error) {
            throw CheckoutOutcomeUnknownError(checkoutId: checkoutId, underlying: error)
        }
    }

    /// How a checkout ended, when `placeOrder(_:)` couldn't tell (`CheckoutOutcomeUnknownError`).
    /// Ask from the same cart, or as the same customer. `code` is:
    ///
    /// - `order_placed`: show the order (`orderId`, `orderKey`).
    /// - `payment_required`: the order was placed but isn't paid; pay it with `payForOrder(_:_:_:)`.
    /// - `in_progress`: the checkout is still running; ask again in a few seconds.
    /// - `not_placed`: nothing went through; place the order again.
    public func getStatus(_ checkoutId: String) async throws -> CheckoutStatus {
        let data = try await http.getRaw("\(Self.route)/status", queryParams: ["checkout_id": checkoutId]).toDictionary()
        let result = data["result"] as? [String: Any] ?? [:]
        let order = data["order"] as? [String: Any]
        let status = order?["status"] as? [String: Any]
        return CheckoutStatus(
            checkoutId: data["checkout_id"] as? String ?? checkoutId,
            code: result["code"] as? String ?? "",
            message: result["message"] as? String ?? "",
            orderId: order?["id"] as? Int,
            orderKey: order?["key"] as? String,
            orderNumber: (order?["number"] as? String) ?? (order?["number"] as? Int).map(String.init),
            orderStatus: status?["code"] as? String
        )
    }

    /// A random ID for one checkout: `chk_` and 32 hex digits.
    private static func newCheckoutId() -> String {
        var generator = SystemRandomNumberGenerator()
        return "chk_" + (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    /// No answer came back: the connection dropped, it timed out, or a proxy gave up.
    private static func isLostResponse(_ error: CoCartError) -> Bool {
        switch error {
        case .network: return true
        case .api(_, let statusCode, _, _): return statusCode == 502 || statusCode == 504
        default: return false
        }
    }

    /// Another request is still taking payment for the same cart, so how this one ends isn't known yet.
    private static func isPaymentInProgress(_ error: CoCartError) -> Bool {
        guard case .api(_, let statusCode, let code, _) = error else { return false }
        return statusCode == 409 && code == "cocart_payment_in_progress"
    }

    /// The store's form settings (no cart needed): fields, countries, shipping, account and
    /// store settings, `order_received_url` for `confirmReturn(_:)`, whether address search is
    /// available (`address_autocomplete.enabled`, with its `providers`), and the terms
    /// (`store.terms_text`, `terms_links`, `terms_url`, `privacy_url`).
    public func getConfig() async throws -> CoCartResponse {
        try await http.getRaw("\(Self.route)/config")
    }

    /// The payment methods for this cart: `{"payment_methods": [...]}`, each with `id`,
    /// `title`, `supports` and, for a logged-in customer, `saved_tokens`.
    public func getPaymentMethods() async throws -> CoCartResponse {
        try await http.getRaw("\(Self.route)/payment-methods")
    }

    /// A logged-in customer's saved payment methods, for every gateway or one. Pay with one as
    /// `wc-{gatewayId}-payment-token` in `payment_data`, or change a subscription's card with
    /// its `id` as `token_id`. Empty for a guest.
    public func getSavedPaymentMethods(gateway: String? = nil) async throws -> [SavedPaymentMethod] {
        let methods = try await getPaymentMethods().get("payment_methods") as? [Any] ?? []
        var saved: [SavedPaymentMethod] = []
        for case let method as [String: Any] in methods {
            guard let id = method["id"] as? String, gateway == nil || id == gateway else { continue }
            let supports = method["supports"] as? [String: Any] ?? [:]
            for case let token as [String: Any] in method["saved_tokens"] as? [Any] ?? [] {
                let expires = token["expires"] as? String
                saved.append(SavedPaymentMethod(
                    id: token["id"] as? Int ?? Int(token["id"] as? String ?? "") ?? 0,
                    gatewayId: id,
                    label: token["label"] as? String ?? "",
                    type: token["type"] as? String ?? "",
                    expires: expires?.isEmpty == false ? expires : nil,
                    isDefault: token["is_default"] as? Bool == true,
                    supportsSubscriptions: supports["subscriptions"] as? Bool == true
                ))
            }
        }
        return saved
    }

    /// Address suggestions (no cart needed; at least 3 characters). Without an address
    /// provider on the store it's `404 cocart_address_search_no_provider`: check `getConfig()`'s
    /// `address_autocomplete.enabled` first.
    public func searchAddresses(_ query: String, country: String? = nil, type: String? = nil,
                                provider: String? = nil) async throws -> CoCartResponse {
        var params = ["query": query]
        if let country { params["country"] = country }
        if let type { params["type"] = type }
        if let provider { params["provider"] = provider }
        return try await http.getRaw("\(Self.api)/address/search", queryParams: params)
    }

    /// A suggestion's full address (no cart needed).
    public func getAddressDetails(_ addressId: String, provider: String) async throws -> CoCartResponse {
        try await http.getRaw("\(Self.api)/address/details",
                              queryParams: ["address_id": addressId, "provider": provider])
    }

    /// The order, for the thank-you screen. `orderKey` must match the order's key; a wrong
    /// key, or someone else's order, is `404 cocart_order_not_found`.
    ///
    /// - Parameters:
    ///   - formatted: Amounts formatted for display (`"$18.00"`) instead of minor units (`"1800"`).
    ///   - metaKeys: Only these keys in the order's `meta`.
    public func getOrderReceived(_ orderId: Int, _ orderKey: String, formatted: Bool? = nil,
                                 metaKeys: [String]? = nil) async throws -> CoCartResponse {
        var query = documentQuery(["formatted": formatted, "meta_keys": metaKeys]) ?? [:]
        query["order_key"] = orderKey
        return try await http.getRaw("\(Self.api)/order-received/\(orderId)", queryParams: query)
    }

    /// Take payment for an unpaid (`pending` or `failed`) order, e.g. to retry a failed
    /// payment. Read the result as for `placeOrder(_:)`: a card that needs 3D Secure gives
    /// `needsConfirmation`, then call again with the same input. A declined card is a failed
    /// result, not an error. The order key is sent in the body, not the URL. An order that needs
    /// no payment or can't be paid is a `409`, and so is another payment still running for it
    /// (`cocart_payment_in_progress`).
    public func payForOrder(_ orderId: Int, _ orderKey: String, _ input: [String: Any]) async throws -> CheckoutResult {
        var body = withPaymentDataPairs(input)
        body["order_key"] = orderKey
        return CheckoutResult.from(try await http.postRaw("\(Self.api)/order-received/\(orderId)/pay", body: body))
    }

    /// Finish a payment after an off-site step, from the parameters the customer came back
    /// with: pass every one unchanged. Returns the order with what the payment did in `result`
    /// (`confirmReturn(_:orderId:orderKey:)` reads it as a `CheckoutResult`). Safe to call
    /// more than once.
    public func confirmOrderPayment(_ orderId: Int, _ orderKey: String,
                                    returnParams: [String: String] = [:]) async throws -> CoCartResponse {
        try await http.postRaw("\(Self.api)/order-received/\(orderId)/confirm",
                               body: ["order_key": orderKey, "return_params": returnParams])
    }

    /// Finish a payment from the URL the app was opened with after an off-site step. Reads
    /// the order ID (`order_id`) and key (`key`) from the URL and forwards every query
    /// parameter. `isPending` means the gateway hasn't confirmed yet: call again shortly. Safe
    /// to call more than once.
    public func confirmReturn(_ url: String, orderId: Int? = nil, orderKey: String? = nil) async throws -> CheckoutResult {
        var params: [String: String] = [:]
        var components = URLComponents(string: url)
        // A "+" in a query string is a space; URLComponents leaves it as is.
        let query = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        components?.percentEncodedQuery = query
        for item in components?.queryItems ?? [] {
            params[item.name] = item.value ?? ""
        }
        let id = orderId ?? params["order_id"].flatMap(Int.init) ?? 0
        let key = orderKey ?? params["key"] ?? ""

        guard id > 0, !key.isEmpty else {
            throw CoCartError.api(
                "The return URL has no order ID or order key. Pass them if your link carries them elsewhere.",
                statusCode: 0,
                code: "checkout_return_missing_order",
                data: [:]
            )
        }

        return CheckoutResult.from(try await confirmOrderPayment(id, key, returnParams: params))
    }
}
