import Foundation

/// The customer's account: profile, address, orders, downloads, reviews,
/// subscriptions and email verification (CoCart Plus).
///
/// All methods require the customer to be authenticated (Basic Auth or JWT),
/// except `register(email:username:password:)`, the guest order lookups and
/// `requestOrderWithdrawal(_:)`.
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
        if case CoCartError.api(_, _, let code, _) = error, code == "rest_no_route" {
            throw CoCartError.api(
                "This method is only available with another CoCart plugin. Please ask support for assistance!",
                statusCode: 404,
                code: "cocart_plugin_required",
                data: [:]
            )
        }
        throw error
    }

    private func getRaw(_ sub: String, query: [String: String]? = nil) async throws -> CoCartResponse {
        do { return try await http.getRaw(rawPath(sub), queryParams: query) }
        catch { try handleNoRoute(error) }
    }

    private func postRaw(_ route: String, body: [String: Any]? = nil) async throws -> CoCartResponse {
        do { return try await http.postRaw(route, body: body) }
        catch { try handleNoRoute(error) }
    }

    // MARK: - Registration (CoCart Plus)

    /// Register a new customer. Doesn't need the customer logged in. Returns `201` with the
    /// customer and `account_created` in `result`; log in next. An email or username already
    /// used is a `409` (`cocart_account_exists`, `cocart_registration_username_exists`).
    ///
    /// The username and password are sent as `requested_username` and
    /// `requested_password`: CoCart treats non-empty `username` and `password` fields as
    /// a Basic Auth attempt.
    ///
    /// - Parameters:
    ///   - username: Optional if the store generates usernames from the email.
    ///   - password: Optional if the store generates passwords.
    public func register(email: String, username: String? = nil, password: String? = nil) async throws -> CoCartResponse {
        var body: [String: Any] = ["email": email]
        if let username { body["requested_username"] = username }
        if let password { body["requested_password"] = password }
        return try await postRaw("cocart/v2/register", body: body)
    }

    // MARK: - Profile

    /// The signed-in customer (`object` `customer`): name, email, addresses, order stats and
    /// `actions`.
    ///
    /// - Parameters:
    ///   - formatted: Amounts formatted for display instead of minor units.
    ///   - metaKeys: Only these keys in the customer's `meta`.
    public func getProfile(formatted: Bool? = nil, metaKeys: [String]? = nil) async throws -> CoCartResponse {
        try await getRaw("", query: documentQuery(["formatted": formatted, "meta_keys": metaKeys]))
    }

    /// Save the account details: send only what changes (`account_first_name`,
    /// `account_last_name`, `account_display_name`, `account_email`). Returns the customer with
    /// `account_updated` in `result`. Every field at fault is reported at once (`CoCartError.fields`).
    public func updateProfile(_ data: [String: Any]) async throws -> CoCartResponse {
        try await postRaw(rawPath(), body: data)
    }

    /// Change the customer's password (`POST my-account`). Returns the customer with
    /// `account_updated` in `result`. A wrong current password is
    /// `cocart_account_incorrect_current_password`.
    public func changePassword(current: String, password: String, confirm: String) async throws -> CoCartResponse {
        try await postRaw(rawPath(), body: [
            "password_current": current,
            "password_1": password,
            "password_2": confirm,
        ])
    }

    /// Save the customer's billing and/or shipping address (`billing_address`,
    /// `shipping_address`), each with unprefixed fields (`first_name`, `address_1`…).
    public func updateAddress(_ data: [String: Any]) async throws -> CoCartResponse {
        try await postRaw(rawPath("address"), body: data)
    }

    // MARK: - Orders

    /// The customer's orders, newest first, with `pagination` (also in the `X-WP-Total` and
    /// `X-WP-TotalPages` headers).
    ///
    /// `params` takes `page`, `per_page`, `order` (`ASC` or `DESC`), and the filters `status`
    /// (one, or a list such as `["processing", "on-hold"]`), `after` and `before` (ISO 8601
    /// dates), `subscription_order_type` (`parent`, `renewal`, `switch` or `resubscribe`),
    /// `formatted` (`Bool`) and `meta_keys` (a list). A list is sent comma-joined.
    public func getOrders(_ params: [String: Any]? = nil) async throws -> CoCartResponse {
        try await getRaw("orders", query: documentQuery((params ?? [:]).mapValues { $0 as Any? }))
    }

    /// One of the customer's orders. Someone else's order is `404 cocart_order_not_found`.
    public func getOrder(_ id: Int, formatted: Bool? = nil, metaKeys: [String]? = nil) async throws -> CoCartResponse {
        try await getRaw("orders/\(id)", query: documentQuery(["formatted": formatted, "meta_keys": metaKeys]))
    }

    /// A guest's order, looked up with its billing email. It comes without its `key`.
    /// Lookups are rate limited (`429 cocart_guest_lookup_rate_limited`).
    public func getGuestOrder(_ id: Int, email: String, formatted: Bool? = nil,
                              metaKeys: [String]? = nil) async throws -> CoCartResponse {
        try await getRaw("orders/\(id)", query: documentQuery([
            "email": email, "formatted": formatted, "meta_keys": metaKeys,
        ]))
    }

    /// Cancel one of the customer's orders where WooCommerce allows it (for example a
    /// pending or failed order).
    public func cancelOrder(_ id: Int) async throws -> CoCartResponse {
        try await postRaw(rawPath("orders/\(id)/cancel"))
    }

    // MARK: - Downloads

    /// The files one of the customer's orders can download: `{"downloads": [...]}`.
    public func getOrderDownloads(_ id: Int) async throws -> CoCartResponse {
        try await getRaw("orders/\(id)/downloads")
    }

    /// The files a guest's order can download, looked up with its billing email:
    /// `{"downloads": [...]}`.
    public func getGuestOrderDownloads(_ id: Int, email: String) async throws -> CoCartResponse {
        try await getRaw("orders/\(id)/downloads", query: ["email": email])
    }

    /// Every file the customer can download: `{"downloads": [...]}`.
    public func getDownloads() async throws -> CoCartResponse {
        try await getRaw("downloads")
    }

    // MARK: - Reviews

    /// The customer's product reviews (`GET products/reviews/mine`).
    public func getReviews(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/reviews/mine", queryParams: params)
    }

    // MARK: - Email verification (CoCart Plus)

    /// Confirm a pending email change, with the key and user ID from the emailed link.
    public func verifyEmail(key: String, userID: Int) async throws -> CoCartResponse {
        try await getRaw("verify-email", query: ["key": key, "user_id": "\(userID)"])
    }

    /// Email the customer a link proving they own the account email, so WooCommerce links
    /// their past guest orders to it (WooCommerce 11+). The response's `status` is `sent`,
    /// or `throttled` (once a minute).
    public func sendOrderEmailVerification() async throws -> CoCartResponse {
        try await postRaw(rawPath("verify-order-email"))
    }

    /// Verify the email with the key and user ID from `sendOrderEmailVerification()`'s link.
    public func verifyOrderEmail(key: String, userID: Int) async throws -> CoCartResponse {
        try await getRaw("verify-order-email", query: ["key": key, "user_id": "\(userID)"])
    }

    // MARK: - Subscriptions (CoCart Plus with WooCommerce Subscriptions)

    /// The customer's subscriptions, with `pagination`. `params` takes `page`, `per_page`,
    /// `order`, `status` (one, or a list), `formatted` (`Bool`) and `meta_keys` (a list). A
    /// list is sent comma-joined.
    public func getSubscriptions(_ params: [String: Any]? = nil) async throws -> CoCartResponse {
        try await getRaw("subscriptions", query: documentQuery((params ?? [:]).mapValues { $0 as Any? }))
    }

    /// One subscription. Pass the `email` to view it as a guest.
    public func getSubscription(_ id: Int, email: String? = nil, formatted: Bool? = nil,
                                metaKeys: [String]? = nil) async throws -> CoCartResponse {
        try await getRaw("subscriptions/\(id)", query: documentQuery([
            "email": email, "formatted": formatted, "meta_keys": metaKeys,
        ]))
    }

    /// Suspend (put on hold) a subscription.
    public func suspendSubscription(_ id: Int) async throws -> CoCartResponse {
        try await postRaw(rawPath("subscriptions/\(id)/suspend"))
    }

    /// Cancel a subscription.
    public func cancelSubscription(_ id: Int) async throws -> CoCartResponse {
        try await postRaw(rawPath("subscriptions/\(id)/cancel"))
    }

    /// Reactivate a suspended subscription.
    public func reactivateSubscription(_ id: Int) async throws -> CoCartResponse {
        try await postRaw(rawPath("subscriptions/\(id)/reactivate"))
    }

    /// Turn automatic renewal on or off.
    public func setSubscriptionAutoRenew(_ id: Int, enabled: Bool) async throws -> CoCartResponse {
        try await postRaw(rawPath("subscriptions/\(id)/auto-renew"), body: ["enabled": enabled])
    }

    /// Change the card a subscription renews with: `payment_method` (gateway ID, e.g.
    /// `stripe`) with a saved card's `token_id`, or a new card in `payment_data` (the keys the
    /// gateway reads, as for `CheckoutResource.placeOrder(_:)`).
    ///
    /// Returns a `CheckoutResult` read from the subscription the store sends back (`object`
    /// `subscription`): `isComplete` once changed (`payment_method_changed`, with
    /// `subscriptionId`). A new card may need 3D Secure: `needsConfirmation` gives the
    /// `clientSecret` to confirm, then call again with the same input; on `needsRedirect`, send
    /// the customer to `redirectUrl`. A declined card is a failed result, not an error. Another
    /// change still running is `409 cocart_payment_in_progress`.
    public func updateSubscriptionPaymentMethod(_ id: Int, _ data: [String: Any]) async throws -> CheckoutResult {
        CheckoutResult.from(
            try await postRaw(rawPath("subscriptions/\(id)/payment-method"), body: withPaymentDataPairs(data))
        )
    }

    /// Put an ended subscription's items in the cart to subscribe again (checkout follows as usual).
    public func resubscribe(_ id: Int) async throws -> CoCartResponse {
        try await postRaw(rawPath("subscriptions/\(id)/resubscribe"))
    }

    /// Undo `resubscribe(_:)`: restore the cart as it was before.
    public func cancelResubscribe(_ id: Int) async throws -> CoCartResponse {
        do { return try await http.deleteRaw(rawPath("subscriptions/\(id)/resubscribe")) }
        catch { try handleNoRoute(error) }
    }

    // MARK: - Order withdrawal (CoCart Plus)

    /// Submit an order withdrawal (right of withdrawal) request. Doesn't need the customer
    /// logged in. `data` takes `first_name`, `last_name`, `email`, `email_confirmation`,
    /// `order_number`, and optionally `withdrawal_type` (`full_order` or
    /// `specific_items_only`) and `additional_details` (required for `specific_items_only`).
    public func requestOrderWithdrawal(_ data: [String: Any]) async throws -> CoCartResponse {
        try await postRaw("cocart/v2/order-withdrawal", body: data)
    }
}
