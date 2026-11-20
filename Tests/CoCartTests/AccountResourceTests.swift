import XCTest
@testable import CoCart

final class AccountResourceTests: XCTestCase {

    private func makeResource() -> AccountResource {
        let session = makeMockSession()
        let options = CoCartOptions()
        let auth = AuthManager(options: options, storage: MemoryStorage())
        let http = HTTPClient(siteURL: "https://store.example.com", options: options,
                              auth: auth, session: session)
        return AccountResource(http: http)
    }

    private func jsonResponse(_ req: URLRequest, body: Any, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: req.url!, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    // MARK: - getProfile

    func testGetProfileCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["user": ["id": 1]])
        }

        _ = try await makeResource().getProfile()

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("cocart/v2/my-account") == true)
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
    }

    // MARK: - updateProfile

    func testUpdateProfileSendsPostRequest() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["user": [:] as [String: Any]])
        }

        _ = try await makeResource().updateProfile(["account_email": "new@example.com"])

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("cocart/v2/my-account") == true)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    // MARK: - changePassword

    func testChangePasswordRemapsFieldNames() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let body = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().changePassword(current: "old", password: "new", confirm: "new")

        XCTAssertEqual(capturedBody?["password_current"] as? String, "old")
        XCTAssertEqual(capturedBody?["password_1"] as? String, "new")
        XCTAssertEqual(capturedBody?["password_2"] as? String, "new")
    }

    func testChangePasswordPostsOnlyThePasswordFieldsInOneRequest() async throws {
        var requests: [URLRequest] = []
        MockURLProtocol.requestHandler = { req in
            requests.append(req)
            return try self.jsonResponse(req, body: ["object": "customer"])
        }

        _ = try await makeResource().changePassword(current: "old-password", password: "new-password",
                                                    confirm: "new-password")

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/wp-json/cocart/v2/my-account")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        let body = requests.first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
        XCTAssertEqual(body, [
            "password_current": "old-password",
            "password_1": "new-password",
            "password_2": "new-password",
        ])
    }

    // MARK: - getOrder

    func testGetOrderCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["order_id": 42])
        }

        _ = try await makeResource().getOrder(42)

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("orders/42") == true)
    }

    // MARK: - getGuestOrder

    func testGetGuestOrderIncludesEmailQueryParam() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["order_id": 7])
        }

        _ = try await makeResource().getGuestOrder(7, email: "guest@example.com")

        let url = capturedRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("orders/7"))
        XCTAssertTrue(url.contains("email="))
    }

    // MARK: - getOrders

    func testGetOrdersSendsNoQueryWithoutParams() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["orders": [] as [Any]])
        }

        _ = try await makeResource().getOrders()

        XCTAssertEqual(capturedRequest?.url?.path, "/wp-json/cocart/v2/my-account/orders")
        XCTAssertNil(capturedRequest?.url?.query)
    }

    func testGetOrdersSendsTheFiltersJoiningListsWithCommas() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["orders": [] as [Any]])
        }

        _ = try await makeResource().getOrders([
            "page": 2,
            "per_page": 20,
            "order": "ASC",
            "status": ["processing", "on-hold"],
            "after": "2026-01-01T00:00:00",
            "before": "2026-12-31T23:59:59",
            "subscription_order_type": "renewal",
            "formatted": true,
            "meta_keys": ["gift_message", "_configuration"],
        ])

        XCTAssertEqual(query(capturedRequest), [
            "page": "2",
            "per_page": "20",
            "order": "ASC",
            "status": "processing,on-hold",
            "after": "2026-01-01T00:00:00",
            "before": "2026-12-31T23:59:59",
            "subscription_order_type": "renewal",
            "formatted": "true",
            "meta_keys": "gift_message,_configuration",
        ])
    }

    func testDocumentsTakeFormattedAndMetaKeys() async throws {
        var requests: [URLRequest] = []
        MockURLProtocol.requestHandler = { req in
            requests.append(req)
            return try self.jsonResponse(req, body: ["object": "order"])
        }

        let account = makeResource()
        _ = try await account.getProfile(formatted: true)
        _ = try await account.getOrder(42, metaKeys: ["gift_message", "_configuration"])
        _ = try await account.getGuestOrder(7, email: "guest@example.com", formatted: false)
        _ = try await account.getSubscription(9, formatted: true, metaKeys: ["note"])
        _ = try await account.getSubscriptions(["status": ["active", "on-hold"], "page": 2])

        XCTAssertEqual(requests.map { $0.url?.path ?? "" }, [
            "/wp-json/cocart/v2/my-account",
            "/wp-json/cocart/v2/my-account/orders/42",
            "/wp-json/cocart/v2/my-account/orders/7",
            "/wp-json/cocart/v2/my-account/subscriptions/9",
            "/wp-json/cocart/v2/my-account/subscriptions",
        ])
        XCTAssertEqual(requests.map(query), [
            ["formatted": "true"],
            ["meta_keys": "gift_message,_configuration"],
            ["email": "guest@example.com", "formatted": "false"],
            ["formatted": "true", "meta_keys": "note"],
            ["status": "active,on-hold", "page": "2"],
        ])
    }

    // MARK: - getOrderDownloads

    func testGetOrderDownloadsCallsTheDownloadsRoute() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["downloads": [["download_id": "abc"]]])
        }

        let response = try await makeResource().getOrderDownloads(3)

        // The response as sent: `{"downloads": [...]}`.
        XCTAssertEqual(capturedRequest?.url?.path, "/wp-json/cocart/v2/my-account/orders/3/downloads")
        XCTAssertNil(capturedRequest?.url?.query)
        XCTAssertEqual((response.get("downloads") as? [[String: Any]])?.first?["download_id"] as? String, "abc")
    }

    func testGetGuestOrderDownloadsSendsTheBillingEmailToTheSameRoute() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: ["downloads": [] as [Any]])
        }

        _ = try await makeResource().getGuestOrderDownloads(3, email: "jane@example.com")

        XCTAssertEqual(capturedRequest?.url?.path, "/wp-json/cocart/v2/my-account/orders/3/downloads")
        XCTAssertEqual(query(capturedRequest), ["email": "jane@example.com"])
    }

    // MARK: - updateSubscriptionPaymentMethod

    func testUpdateSubscriptionPaymentMethodReadsTheResultFromTheSubscription() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [
                "object": "subscription",
                "result": ["code": "payment_method_changed", "message": "Changed.", "action": NSNull(),
                           "redirect_url": NSNull(), "error": NSNull()],
                "id": 9,
            ])
        }

        let result = try await makeResource().updateSubscriptionPaymentMethod(9, ["payment_method": "stripe", "token_id": 3])

        XCTAssertEqual(capturedRequest?.url?.path, "/wp-json/cocart/v2/my-account/subscriptions/9/payment-method")
        XCTAssertEqual(result.code, .paymentMethodChanged)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.subscriptionId, 9)
        XCTAssertNil(result.orderId)
    }

    // MARK: - getDownloads

    func testGetDownloadsCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [] as [Any])
        }

        _ = try await makeResource().getDownloads()

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("my-account/downloads") == true)
    }

    // MARK: - getReviews

    func testGetReviewsCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [] as [Any])
        }

        _ = try await makeResource().getReviews()

        XCTAssertEqual(capturedRequest?.url?.path, "/wp-json/cocart/v2/products/reviews/mine")
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        var query: [String: String] = [:]
        for item in request.flatMap({ URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) })?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }

    // MARK: - rest_no_route

    func testRestNoRouteBecomesPluginRequired() async throws {
        MockURLProtocol.requestHandler = { req in
            let body: [String: Any] = [
                "code": "rest_no_route",
                "message": "No route found.",
                "data": ["status": 404],
            ]
            return try self.jsonResponse(req, body: body, statusCode: 404)
        }

        do {
            _ = try await makeResource().getProfile()
            XCTFail("Expected error to be thrown")
        } catch CoCartError.api(_, _, let code, _) {
            XCTAssertEqual(code, "cocart_plugin_required")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
