import XCTest
@testable import CoCart

final class CartResourceTests: XCTestCase {

    private func makeResource(options: CoCartOptions = CoCartOptions()) -> CartResource {
        let session = makeMockSession()
        let auth = AuthManager(options: options, storage: MemoryStorage())
        let http = HTTPClient(siteURL: "https://store.example.com", options: options,
                              auth: auth, session: session)
        return CartResource(http: http, auth: auth, options: options)
    }

    private func jsonResponse(_ req: URLRequest, body: Any, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: req.url!, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    // MARK: - addItems (grouped-product semantics)

    func testAddItemsPostsGroupedProductShape() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().addItems(100, items: ["1": 2, "2": 3])

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("add-items") == true)
        XCTAssertEqual(capturedBody?["id"] as? String, "100")
        let quantity = capturedBody?["quantity"] as? [String: String]
        XCTAssertEqual(quantity?["1"], "2")
        XCTAssertEqual(quantity?["2"], "3")
    }

    func testAddItemsArrayOverloadBuildsSameShape() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().addItems(100, items: [(id: "1", quantity: 2)])

        XCTAssertEqual(capturedBody?["id"] as? String, "100")
        let quantity = capturedBody?["quantity"] as? [String: String]
        XCTAssertEqual(quantity?["1"], "2")
    }

    func testAddItemsThrowsOnEmptyItems() async throws {
        do {
            _ = try await makeResource().addItems(100, items: [String: Int]())
            XCTFail("Expected validation error")
        } catch CoCartError.validation(_) {
            // expected
        }
    }

    // MARK: - updateItems (per-item loop)

    func testUpdateItemsSendsOneRequestPerItem() async throws {
        var requestCount = 0
        MockURLProtocol.requestHandler = { req in
            requestCount += 1
            return try self.jsonResponse(req, body: ["items_count": requestCount])
        }

        let response = try await makeResource().updateItems(["abc": 2, "def": 3])

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(response.getItemCount(), 2)
    }

    func testUpdateItemsThrowsOnEmptyItems() async throws {
        do {
            _ = try await makeResource().updateItems([:])
            XCTFail("Expected validation error")
        } catch CoCartError.validation(_) {
            // expected
        }
    }

    // MARK: - removeItems (per-item loop)

    func testRemoveItemsSendsOneRequestPerItem() async throws {
        var capturedMethods: [String] = []
        MockURLProtocol.requestHandler = { req in
            capturedMethods.append(req.httpMethod ?? "")
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().removeItems(["abc", "def"])

        XCTAssertEqual(capturedMethods, ["DELETE", "DELETE"])
    }

    // MARK: - batchUpdateItems / batchRemoveItems

    func testBatchUpdateItemsPostsToBatchEndpoint() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().batchUpdateItems(["abc": 2])

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("cocart/batch") == true)
        let requests = capturedBody?["requests"] as? [[String: Any]]
        XCTAssertEqual(requests?.count, 1)
        XCTAssertEqual(requests?.first?["method"] as? String, "POST")
        XCTAssertTrue((requests?.first?["path"] as? String ?? "").contains("cart/item/abc"))
    }

    func testBatchRemoveItemsPostsToBatchEndpoint() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().batchRemoveItems(["abc", "def"])

        let requests = capturedBody?["requests"] as? [[String: Any]]
        XCTAssertEqual(requests?.count, 2)
        XCTAssertEqual(requests?.allSatisfy { ($0["method"] as? String) == "DELETE" }, true)
    }

    func testBatchThrowsPluginRequiredOnNoRoute() async throws {
        MockURLProtocol.requestHandler = { req in
            let body: [String: Any] = [
                "code": "rest_no_route",
                "message": "No route found.",
            ]
            return try self.jsonResponse(req, body: body, statusCode: 404)
        }

        do {
            _ = try await makeResource().batchUpdateItems(["abc": 1])
            XCTFail("Expected error to be thrown")
        } catch CoCartError.api(_, _, let code) {
            XCTAssertEqual(code, "cocart_plugin_required")
        }
    }

    // MARK: - updateCustomer

    func testUpdateCustomerMirrorsBillingWhenShippingOmitted() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().updateCustomer(billing: ["first_name": "John", "city": "NYC"])

        XCTAssertEqual(capturedBody?["namespace"] as? String, "update-customer")
        XCTAssertEqual(capturedBody?["first_name"] as? String, "John")
        XCTAssertEqual(capturedBody?["s_first_name"] as? String, "John")
        XCTAssertEqual(capturedBody?["s_city"] as? String, "NYC")
        XCTAssertNil(capturedBody?["ship_to_different_address"])
        XCTAssertNil(capturedBody?["billing_address"])
        XCTAssertNil(capturedBody?["shipping_address"])
    }

    func testUpdateCustomerWithDistinctShippingSetsFlag() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().updateCustomer(
            billing: ["first_name": "John"],
            shipping: ["first_name": "Jane", "city": "LA"]
        )

        XCTAssertEqual(capturedBody?["first_name"] as? String, "John")
        XCTAssertEqual(capturedBody?["s_first_name"] as? String, "Jane")
        XCTAssertEqual(capturedBody?["s_city"] as? String, "LA")
        XCTAssertEqual(capturedBody?["ship_to_different_address"] as? Bool, true)
    }

    func testUpdateCustomerWithEmptyShippingMirrorsBilling() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().updateCustomer(billing: ["first_name": "John"], shipping: [:])

        XCTAssertEqual(capturedBody?["s_first_name"] as? String, "John")
        XCTAssertNil(capturedBody?["ship_to_different_address"])
    }

    // MARK: - setShippingMethod

    func testSetShippingMethodPostsRateID() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().setShippingMethod("flat_rate:2")

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("set-shipping-method") == true)
        XCTAssertEqual(capturedBody?["rate_id"] as? String, "flat_rate:2")
        XCTAssertNil(capturedBody?["package_id"])
    }

    func testSetShippingMethodIncludesPackageIDWhenProvided() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { req in
            if let data = req.httpBody {
                capturedBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().setShippingMethod("flat_rate:2", packageID: "0")

        XCTAssertEqual(capturedBody?["rate_id"] as? String, "flat_rate:2")
        XCTAssertEqual(capturedBody?["package_id"] as? String, "0")
    }

    // MARK: - calculateShipping (deprecated, delegates to calculate())

    func testCalculateShippingDelegatesToCalculate() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().calculateShipping(["country": "US"])

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("cart/calculate") == true)
        XCTAssertFalse(capturedRequest?.url?.absoluteString.contains("shipping-methods") == true)
    }
}
