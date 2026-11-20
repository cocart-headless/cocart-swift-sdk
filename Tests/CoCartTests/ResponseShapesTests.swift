import XCTest
@testable import CoCart

/// Reading responses in the shapes CoCart Starter 5 sends (recorded in Tests/Fixtures/cart.json).
final class ResponseShapesTests: XCTestCase {

    private func response(_ json: String, headers: [String: String] = [:]) -> CoCartResponse {
        let data = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
        return CoCartResponse(data: data, headers: headers, statusCode: 200)
    }

    private func recordedCart() throws -> CoCartResponse {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cart.json")
        return response(try String(contentsOf: url, encoding: .utf8))
    }

    func testGetShippingMethodsListsThePackages() throws {
        let packages = try recordedCart().getShippingMethods()
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?["package_name"] as? String, "Shipment")
        XCTAssertNotNil((packages.first?["rates"] as? [String: Any])?["flat_rate:1"])
    }

    func testGetShippingReturnsTheWholeField() throws {
        let shipping = try recordedCart().getShipping()
        XCTAssertEqual(shipping?["has_calculated_shipping"] as? Bool, true)
        XCTAssertNotNil((shipping?["packages"] as? [String: Any])?["default"])
    }

    func testGetShippingMethodsAcceptsAListAndIsEmptyWithoutShipping() {
        XCTAssertEqual(response(#"{"shipping":[{"package_name":"A"}]}"#).getShippingMethods().count, 1)
        XCTAssertTrue(response(#"{"items":[]}"#).getShippingMethods().isEmpty)
        XCTAssertNil(response(#"{"items":[]}"#).getShipping())
    }

    func testGetShippingMethodsOrdersPackagesByIndex() {
        let r = response(#"{"shipping":{"packages":{"b":{"package_name":"B","index":1},"a":{"package_name":"A","index":0}}}}"#)
        XCTAssertEqual(r.getShippingMethods().map { $0["package_name"] as? String }, ["A", "B"])
    }

    func testGetFeesListsFeesKeyedByFeeID() throws {
        let fees = response(#"{"fees":{"gift-wrap":{"name":"Gift wrap","fee":"500"}}}"#).getFees()
        XCTAssertEqual(fees.count, 1)
        XCTAssertEqual(fees.first?["fee"] as? String, "500")
        XCTAssertTrue(response(#"{"fees":[]}"#).getFees().isEmpty)
        XCTAssertTrue(try recordedCart().getFees().isEmpty)
    }

    func testGetNoticesReturnsNoticesKeyedByType() throws {
        let r = response(#"{"notices":{"success":["Item added"],"notice":["Quantity reduced"]}}"#)
        XCTAssertEqual(r.getNotices(), ["success": ["Item added"], "notice": ["Quantity reduced"]])
        // CoCart Starter 5 sends {}, CoCart 4.x [].
        XCTAssertTrue(try recordedCart().getNotices().isEmpty)
        XCTAssertTrue(response(#"{"notices":[]}"#).getNotices().isEmpty)
    }

    func testGetExtensions() throws {
        XCTAssertNotNil(response(#"{"extensions":{"recurring_totals":{"abc":{}}}}"#).getExtensions()["recurring_totals"])
        XCTAssertTrue(response(#"{"extensions":[]}"#).getExtensions().isEmpty)
        XCTAssertTrue(try recordedCart().getExtensions().isEmpty)
    }

    func testAListBodyIsKept() async throws {
        let server = RecordingServer()
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/categories.json")
        let categories = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        server.enqueue(200, categories)
        var options = CoCartOptions()
        options.storage = MemoryStorage()
        let response = try await CoCart("https://store.example.com", options: options, session: makeMockSession())
            .products().categories()
        XCTAssertFalse(response.toArray().isEmpty)
        XCTAssertEqual(response.getString("0.name"), "Accessories")
        XCTAssertTrue(response.toDictionary().isEmpty)
    }

    func testGetItemCountReadsItemCount() throws {
        XCTAssertEqual(try recordedCart().getItemCount(), 2)
    }

    func testGetRateLimitReadsTheHeadersIgnoringTheirCase() {
        let r = response("{}", headers: ["RateLimit-Limit": "25", "ratelimit-remaining": "24", "RATELIMIT-RESET": "1791108883"])
        XCTAssertEqual(r.getRateLimit(), RateLimitInfo(limit: 25, remaining: 24, reset: 1791108883, retryAfter: nil))
        XCTAssertEqual(response("{}").getRateLimit(), RateLimitInfo(limit: nil, remaining: nil, reset: nil, retryAfter: nil))
        XCTAssertEqual(response("{}", headers: ["RateLimit-Retry-After": "30"]).getRateLimit().retryAfter, 30)
        XCTAssertEqual(r.getHeader("RateLimit-Limit"), "25")
    }
}

final class InvalidCartAndErrorsTests: XCTestCase {
    private let invalidCart: [String: Any] = ["code": "cocart_invalid_cart", "message": "Cart is not valid.", "data": ["status": 404]]

    private func client(storage: MemoryStorage, options: CoCartOptions = CoCartOptions()) async throws -> CoCart {
        var options = options
        options.storage = storage
        let c = CoCart("https://store.example.com", options: options, session: makeMockSession())
        try await c.restoreSession()
        return c
    }

    private func storage(with key: String?) async throws -> MemoryStorage {
        let storage = MemoryStorage()
        if let key { try await storage.write("cocart_cart_key", value: key) }
        return storage
    }

    // CoCart Starter 5 refuses a cart key with no cart session (e.g. an expired cart).

    func testForgetsTheStoredKeyAndRetriesOnceAsANewGuest() async throws {
        let server = RecordingServer()
        server.enqueue(404, invalidCart)
        server.enqueue(200, ["cart_key": "t_fresh", "items": [Any]()], headers: ["Cart-Key": "t_fresh"])
        let store = try await storage(with: "t_expired")
        let c = try await client(storage: store)

        _ = try await c.cart().get()

        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests[0].query, "cart_key=t_expired")
        XCTAssertNil(server.requests[1].query)
        XCTAssertNil(server.requests[1].headers["Cart-Key"])
        XCTAssertEqual(c.cartKey, "t_fresh")
    }

    func testRetriesAWriteWithTheSameBody() async throws {
        let server = RecordingServer()
        server.enqueue(404, invalidCart)
        _ = try await client(storage: try await storage(with: "t_expired")).cart().addItem(42, quantity: 1)
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests[0].body as NSDictionary?, server.requests[1].body as NSDictionary?)
    }

    func testRetriesOnlyOnce() async throws {
        let server = RecordingServer()
        server.enqueue(404, invalidCart)
        server.enqueue(404, invalidCart)
        do {
            _ = try await client(storage: try await storage(with: "t_expired")).cart().get()
            XCTFail("Expected an error")
        } catch let error as CoCartError {
            XCTAssertEqual(error.errorCode, "cocart_invalid_cart")
        }
        XCTAssertEqual(server.requests.count, 2)
    }

    func testDoesNotRetryWithoutACartKeyOrWhenLoggedIn() async throws {
        let server = RecordingServer()
        server.enqueue(404, invalidCart)
        _ = try? await client(storage: MemoryStorage()).cart().get()
        XCTAssertEqual(server.requests.count, 1)

        server.enqueue(404, invalidCart)
        let store = try await storage(with: "t_expired")
        _ = try? await client(storage: store, options: CoCartOptions(username: "user", password: "pass")).cart().get()
        XCTAssertEqual(server.requests.count, 2)
        let kept = try await store.read("cocart_cart_key")
        XCTAssertEqual(kept, "t_expired")
    }

    func testLeavesOtherErrorsAlone() async throws {
        let server = RecordingServer()
        server.enqueue(404, ["code": "cocart_item_not_in_cart", "message": "Item not in cart."])
        let c = try await client(storage: try await storage(with: "t_expired"))
        _ = try? await c.cart().getItem("abc")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(c.cartKey, "t_expired")
    }

    // MARK: - Errors

    func testGetCartReturnsTheCartSentWithItemNotInCart() async throws {
        let server = RecordingServer()
        server.enqueue(404, ["code": "cocart_item_not_in_cart", "message": "Item specified does not exist in cart.",
                             "data": ["status": 404, "cart": ["items": [["item_key": "def"]], "item_count": 1]]])
        do {
            _ = try await client(storage: MemoryStorage()).cart().updateItem("abc", quantity: 2)
            XCTFail("Expected an error")
        } catch let error as CoCartError {
            XCTAssertEqual(error.errorCode, "cocart_item_not_in_cart")
            XCTAssertEqual(error.getCart()?["item_count"] as? Int, 1)
        }
        XCTAssertNil(CoCartError.api("Nope", statusCode: 404, code: "x", data: ["data": ["status": 404]]).getCart())
        XCTAssertNil(CoCartError.network("Nope").getCart())
        _ = server
    }

    func testSafeErrorMessageRemovesQueryStrings() {
        XCTAssertEqual(
            HTTPClient.safeErrorMessage("Could not load https://store.com/wp-json/cocart/v2/cart?cart_key=t_secret&x=1 now"),
            "Could not load https://store.com/wp-json/cocart/v2/cart now"
        )
        XCTAssertEqual(HTTPClient.safeErrorMessage("connection refused"), "connection refused")
    }
}
