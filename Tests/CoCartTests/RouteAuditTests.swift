import XCTest
@testable import CoCart

/// Records every request and answers with the queued responses (then `{}`).
final class RecordingServer {
    struct Seen {
        let method: String
        let path: String
        let query: String?
        let headers: [String: String]
        let body: [String: Any]?

        var call: String { "\(method) \(path)" + (query.map { "?\($0)" } ?? "") }
    }

    private(set) var requests: [Seen] = []
    private var queue: [(status: Int, body: Any, headers: [String: String])] = []

    init() {
        MockURLProtocol.requestHandler = { [unowned self] req in
            let url = req.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let body = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            self.requests.append(Seen(
                method: req.httpMethod ?? "GET",
                path: components?.percentEncodedPath ?? url.path,
                query: components?.percentEncodedQuery,
                headers: req.allHTTPHeaderFields ?? [:],
                body: body
            ))
            let next = self.queue.isEmpty ? (status: 200, body: [String: Any]() as Any, headers: [String: String]()) : self.queue.removeFirst()
            let data = try JSONSerialization.data(withJSONObject: next.body)
            let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: "HTTP/1.1",
                                           headerFields: next.headers)!
            return (response, data)
        }
    }

    func enqueue(_ status: Int, _ body: Any, headers: [String: String] = [:]) {
        queue.append((status, body, headers))
    }

    var calls: [String] { requests.map(\.call) }
    var last: Seen { requests.last! }
}

/// Every method's route, checked against the CoCart Starter 5 and CoCart Plus 2.0 routes.
final class RouteAuditTests: XCTestCase {

    private func client(_ options: CoCartOptions = CoCartOptions()) -> CoCart {
        var options = options
        if options.storage == nil { options.storage = MemoryStorage() }
        return CoCart("https://store.example.com", options: options, session: makeMockSession())
    }

    // MARK: - Cart

    func testCartRoutes() async throws {
        let server = RecordingServer()
        let cart = client().cart()
        _ = try await cart.restoreItem("abc")
        _ = try await cart.getRemovedItems()
        _ = try await cart.getCustomer()
        _ = try await cart.getShippingMethods()
        _ = try await cart.getCrossSells()
        _ = try await cart.getCoupons()
        _ = try await cart.getFees()
        _ = try await cart.checkCoupons()
        _ = try await cart.checkCoupons(email: "jane+vip@example.com")
        _ = try await cart.removeCoupons()
        _ = try await cart.removeFees()
        _ = try await cart.getMini()
        _ = try await cart.removeAllItems()

        XCTAssertEqual(server.calls, [
            "PUT /wp-json/cocart/v2/cart/item/abc",
            "GET /wp-json/cocart/v2/cart?_fields=removed_items",
            "GET /wp-json/cocart/v2/cart?_fields=customer",
            "GET /wp-json/cocart/v2/cart?_fields=shipping",
            "GET /wp-json/cocart/v2/cart?_fields=cross_sells",
            "GET /wp-json/cocart/v2/cart?_fields=coupons",
            "GET /wp-json/cocart/v2/cart?_fields=fees",
            "GET /wp-json/cocart/v2/cart/coupons/validate",
            "GET /wp-json/cocart/v2/cart/coupons/validate?email=jane%2Bvip@example.com",
            "DELETE /wp-json/cocart/v2/cart/coupons",
            "POST /wp-json/cocart/v2/cart/remove-fees",
            "GET /wp-json/cocart/v2/cart/mini",
            "DELETE /wp-json/cocart/v2/cart/items",
        ])
    }

    func testApplyCouponSendsCodeToApplyCoupon() async throws {
        let server = RecordingServer()
        let cart = client().cart()
        _ = try await cart.applyCoupon("SAVE10")
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/cart/apply-coupon")
        XCTAssertEqual(server.last.body as NSDictionary?, ["code": "SAVE10"])

        _ = try await cart.applyCoupon("VIP", email: "jane@example.com")
        XCTAssertEqual(server.last.body as NSDictionary?, ["code": "VIP", "email": "jane@example.com"])
    }

    func testRemoveCouponEncodesTheCode() async throws {
        let server = RecordingServer()
        let cart = client().cart()
        for code in ["summer sale", "10%off", "a#b?c", "café"] {
            _ = try await cart.removeCoupon(code)
        }
        XCTAssertEqual(server.calls, [
            "DELETE /wp-json/cocart/v2/cart/coupons/summer%20sale",
            "DELETE /wp-json/cocart/v2/cart/coupons/10%25off",
            "DELETE /wp-json/cocart/v2/cart/coupons/a%23b%3Fc",
            "DELETE /wp-json/cocart/v2/cart/coupons/caf%C3%A9",
        ])
    }

    func testAddFeeSendsTheAmountAsAStringToAddFee() async throws {
        let server = RecordingServer()
        let cart = client().cart()
        _ = try await cart.addFee("Rush", amount: 5.99, taxable: true)
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/cart/add-fee")
        XCTAssertEqual(server.last.body as NSDictionary?, ["name": "Rush", "amount": "5.99", "taxable": true])

        _ = try await cart.addFee("Gift wrap", amount: 2.5, taxable: true, taxClass: "reduced-rate")
        XCTAssertEqual(server.last.body?["tax_class"] as? String, "reduced-rate")
    }

    func testChangePlanPostsUpdateItemSchema() async throws {
        let server = RecordingServer()
        _ = try await client().cart().changePlan("abc123", value: "0")
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/cart/update")
        XCTAssertEqual(server.last.body as NSDictionary?,
                       ["namespace": "update-item-schema", "item_key": "abc123", "convert_to_sub": "0"])

        do {
            _ = try await client().cart().changePlan("", value: "0")
            XCTFail("Expected a validation error")
        } catch CoCartError.validation {
        }
    }

    // MARK: - Products

    func testProductRoutes() async throws {
        let server = RecordingServer()
        let products = client().products()
        _ = try await products.getBySlug("blue-hoodie")
        _ = try await products.byCategory("hoodies")
        _ = try await products.byTag("sale")
        _ = try await products.variations(134)
        _ = try await products.variation(134, variationID: 157)
        _ = try await products.categories(["per_page": "50"])
        _ = try await products.category(20)
        _ = try await products.tags()
        _ = try await products.tag(8)
        _ = try await products.attributes()
        _ = try await products.attribute(1)
        _ = try await products.attributeTerms(1)
        _ = try await products.attributeTerm(1, termID: 5)
        _ = try await products.attributeBySlug("color")
        _ = try await products.attributeTermsBySlug("color")
        _ = try await products.attributeTermBySlug("color", termSlug: "blue")
        _ = try await products.brands()
        _ = try await products.brand(5)
        _ = try await products.byBrand("nike")
        _ = try await products.reviews()
        _ = try await products.productReviews(154)
        _ = try await products.myReviews()
        _ = try await products.createReview(["product_id": 42, "review": "Great", "rating": 5])
        _ = try await products.seo(154)
        _ = try await products.seoBySlug("beanie")

        let base = "/wp-json/cocart/v2/products"
        XCTAssertEqual(server.calls, [
            "GET \(base)/blue-hoodie",
            "GET \(base)?category=hoodies",
            "GET \(base)?tag=sale",
            "GET \(base)/134/variations",
            "GET \(base)/134/variations/157",
            "GET \(base)/categories?per_page=50",
            "GET \(base)/categories/20",
            "GET \(base)/tags",
            "GET \(base)/tags/8",
            "GET \(base)/attributes",
            "GET \(base)/attributes/1",
            "GET \(base)/attributes/1/terms",
            "GET \(base)/attributes/1/terms/5",
            "GET \(base)/attributes/color",
            "GET \(base)/attributes/color/terms",
            "GET \(base)/attributes/color/terms/blue",
            "GET \(base)/brands",
            "GET \(base)/brands/5",
            "GET \(base)?brand=nike",
            "GET \(base)/reviews",
            "GET \(base)/reviews?product=154",
            "GET \(base)/reviews/mine",
            "POST \(base)/reviews",
            "GET \(base)/154/seo",
            "GET \(base)/beanie/seo",
        ])
    }

    func testListingShortcutsAddTheirFilter() async throws {
        let server = RecordingServer()
        let products = client().products()
        _ = try await products.search("hoodie", params: ["per_page": "4"])
        _ = try await products.featured()
        _ = try await products.onSale()
        _ = try await products.byPriceRange(minPrice: "10", maxPrice: "50")
        _ = try await products.sortBy(.priceDesc, order: .desc)
        _ = try await products.byStockStatus(.inStock)
        _ = try await products.paginate(page: 2, perPage: 12)

        let base = "/wp-json/cocart/v2/products"
        XCTAssertEqual(server.calls, [
            "GET \(base)?per_page=4&search=hoodie",
            "GET \(base)?featured=true",
            "GET \(base)?on_sale=true",
            "GET \(base)?max_price=50&min_price=10",
            "GET \(base)?order=desc&orderby=price_desc",
            "GET \(base)?stock_status=instock",
            "GET \(base)?page=2&per_page=12",
        ])
    }

    func testStarterOnlyMethodsThrowInLegacyMode() async throws {
        let server = RecordingServer()
        let products = client(CoCartOptions(mainPlugin: .legacy)).products()
        let calls: [() async throws -> CoCartResponse] = [
            { try await products.getBySlug("x") },
            { try await products.variation(1, variationID: 2) },
            { try await products.category(1) },
            { try await products.tag(1) },
            { try await products.attributeBySlug("color") },
            { try await products.attributeTermsBySlug("color") },
            { try await products.attributeTermBySlug("color", termSlug: "blue") },
            { try await products.brands() },
            { try await products.brand(1) },
            { try await products.byBrand("nike") },
            { try await products.myReviews() },
        ]
        for (i, call) in calls.enumerated() {
            do {
                _ = try await call()
                XCTFail("Call \(i) should throw a version error")
            } catch CoCartError.version {
            }
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testShippingRatesIsSentWithoutTheCartKey() async throws {
        // The route prices a simulated cart and refuses a cart key (403).
        let server = RecordingServer()
        let c = client(CoCartOptions(cartKey: "t_guest_key"))
        _ = try await c.products().shippingRates(154, quantity: 2, variation: ["attribute_pa_color": "blue"])
        XCTAssertEqual(server.last.path, "/wp-json/cocart/v2/products/154/shipping-rates")
        XCTAssertEqual(server.last.query, "quantity=2&variation%5Battribute_pa_color%5D=blue")
        XCTAssertNil(server.last.headers["Cart-Key"])

        // Other requests keep the cart key.
        _ = try await c.products().get(154)
        XCTAssertEqual(server.last.query, "cart_key=t_guest_key")
        XCTAssertEqual(server.last.headers["Cart-Key"], "t_guest_key")

        _ = try await client(CoCartOptions(namespace: "mystore")).products().shippingRates("HOODIE/BLUE")
        XCTAssertEqual(server.last.path, "/wp-json/mystore/v2/products/HOODIE%2FBLUE/shipping-rates")
    }

    // MARK: - Sessions

    func testSessionRoutes() async throws {
        let server = RecordingServer()
        let sessions = client(CoCartOptions(consumerKey: "ck_x", consumerSecret: "cs_x")).sessions()
        _ = try await sessions.all()
        _ = try await sessions.get("t_abc")
        _ = try await sessions.getItems("t_abc")
        _ = try await sessions.delete("t_abc")
        XCTAssertEqual(server.calls, [
            "GET /wp-json/cocart/v2/sessions",
            "GET /wp-json/cocart/v2/session/t_abc",
            "GET /wp-json/cocart/v2/session/t_abc/items",
            "DELETE /wp-json/cocart/v2/session/t_abc",
        ])
    }

    // MARK: - Account

    func testAccountRoutes() async throws {
        let server = RecordingServer()
        let account = client(CoCartOptions(username: "user", password: "pass")).account()
        _ = try await account.updateAddress(["billing_address": ["city": "Paris"]])
        _ = try await account.cancelOrder(42)
        _ = try await account.verifyEmail(key: "k3y", userID: 7)
        _ = try await account.sendOrderEmailVerification()
        _ = try await account.verifyOrderEmail(key: "k3y", userID: 7)
        _ = try await account.getSubscriptions(["page": "2"])
        _ = try await account.getOrderDownloads(42)
        _ = try await account.getGuestOrderDownloads(42, email: "guest@example.com")
        _ = try await account.getSubscription(9)
        _ = try await account.getSubscription(9, email: "guest@example.com")
        _ = try await account.suspendSubscription(9)
        _ = try await account.reactivateSubscription(9)
        _ = try await account.cancelSubscription(9)
        _ = try await account.setSubscriptionAutoRenew(9, enabled: false)
        _ = try await account.updateSubscriptionPaymentMethod(9, ["payment_method": "stripe"])
        _ = try await account.resubscribe(9)
        _ = try await account.cancelResubscribe(9)

        let base = "/wp-json/cocart/v2/my-account"
        XCTAssertEqual(server.calls, [
            "POST \(base)/address",
            "POST \(base)/orders/42/cancel",
            "GET \(base)/verify-email?key=k3y&user_id=7",
            "POST \(base)/verify-order-email",
            "GET \(base)/verify-order-email?key=k3y&user_id=7",
            "GET \(base)/subscriptions?page=2",
            "GET \(base)/orders/42/downloads",
            "GET \(base)/orders/42/downloads?email=guest@example.com",
            "GET \(base)/subscriptions/9",
            "GET \(base)/subscriptions/9?email=guest@example.com",
            "POST \(base)/subscriptions/9/suspend",
            "POST \(base)/subscriptions/9/reactivate",
            "POST \(base)/subscriptions/9/cancel",
            "POST \(base)/subscriptions/9/auto-renew",
            "POST \(base)/subscriptions/9/payment-method",
            "POST \(base)/subscriptions/9/resubscribe",
            "DELETE \(base)/subscriptions/9/resubscribe",
        ])
        XCTAssertEqual(server.requests[13].body?["enabled"] as? Bool, false)
    }

    func testChangePasswordSendsOnlyThePasswordFields() async throws {
        let server = RecordingServer()
        _ = try await client(CoCartOptions(username: "user", password: "pass")).account()
            .changePassword(current: "old", password: "new", confirm: "new")

        XCTAssertEqual(server.calls, ["POST /wp-json/cocart/v2/my-account"])
        XCTAssertEqual(server.last.body as NSDictionary?, [
            "password_current": "old",
            "password_1": "new",
            "password_2": "new",
        ])
    }

    func testRegisterSendsRequestedUsernameAndPassword() async throws {
        // Not username/password: CoCart would treat those as a Basic Auth attempt.
        let server = RecordingServer()
        _ = try await client().account().register(email: "jane@example.com", username: "jane", password: "a-strong-password")
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/register")
        XCTAssertEqual(server.last.body as NSDictionary?,
                       ["email": "jane@example.com", "requested_username": "jane", "requested_password": "a-strong-password"])
        XCTAssertNil(server.last.headers["Authorization"])

        _ = try await client().account().requestOrderWithdrawal(["order_number": "1042"])
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/order-withdrawal")
    }

    // MARK: - JWT

    func testLoginPostsToLoginAndKeepsTheTokensFromExtras() async throws {
        let server = RecordingServer()
        server.enqueue(200, ["user_id": "1", "extras": ["jwt_token": "eyJ.a.b", "jwt_refresh": "refresh123"]])
        let c = client()
        _ = try await c.login("jane", password: "secret")

        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/login")
        XCTAssertEqual(server.last.body as NSDictionary?, ["username": "jane", "password": "secret"])
        XCTAssertTrue(c.isAuthenticated)

        _ = try await c.cart().get()
        XCTAssertEqual(server.last.headers["Authorization"], "Bearer eyJ.a.b")
    }

    func testLoginThrowsTwoFactorRequired() async throws {
        let server = RecordingServer()
        server.enqueue(401, ["code": "cocart_2fa_required", "message": "Enter your code.",
                             "data": ["status": 401, "available_providers": ["totp", "email"], "default_provider": "totp"]])
        do {
            _ = try await client().login("jane", password: "secret")
            XCTFail("Expected twoFactorRequired")
        } catch CoCartError.twoFactorRequired(_, let providers, let defaultProvider, _) {
            XCTAssertEqual(providers, ["totp", "email"])
            XCTAssertEqual(defaultProvider, "totp")
        }
        XCTAssertEqual(server.calls.count, 1)
    }

    func testVerifyTwoFactorRefreshValidateAndLogoutRoutes() async throws {
        let server = RecordingServer()
        server.enqueue(200, ["extras": ["jwt_token": "eyJ.a.b", "jwt_refresh": "refresh123"]])
        server.enqueue(200, ["token": "eyJ.new.token", "refresh_token": "refresh456"])
        let c = client()
        _ = try await c.jwt().verifyTwoFactor("jane", password: "secret", code: "123456", provider: "totp")
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/login")
        XCTAssertEqual(server.last.body?["2fa_code"] as? String, "123456")

        _ = try await c.jwt().refresh()
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/jwt/refresh-token")
        XCTAssertEqual(server.last.body as NSDictionary?, ["refresh_token": "refresh123"])

        let valid = try await c.jwt().validate()
        XCTAssertTrue(valid)
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/jwt/validate-token")
        XCTAssertEqual(server.last.headers["Authorization"], "Bearer eyJ.new.token")

        try await c.logout()
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/v2/logout")
    }

    // MARK: - Batch

    func testBatchSendsTheGuestCartKey() async throws {
        // Without it, a guest's batch would run against a new, empty cart.
        let server = RecordingServer()
        _ = try await client(CoCartOptions(cartKey: "t_guest_key")).batch([
            BatchRequestItem(method: "DELETE", path: "/cocart/v2/cart/item/abc"),
        ])
        XCTAssertEqual(server.last.call, "POST /wp-json/cocart/batch?cart_key=t_guest_key")
        XCTAssertEqual(server.last.headers["Cart-Key"], "t_guest_key")
    }
}
