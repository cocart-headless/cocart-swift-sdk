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

    func testChangePasswordCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        _ = try await makeResource().changePassword(current: "old", password: "new", confirm: "new")

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("change-password") == true)
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

    // MARK: - getOrderDownloads

    func testGetOrderDownloadsCallsCorrectPath() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [] as [Any])
        }

        _ = try await makeResource().getOrderDownloads(3)

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("orders/3/downloads") == true)
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

        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("my-account/reviews") == true)
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
        } catch CoCartError.api(_, _, let code) {
            XCTAssertEqual(code, "cocart_plugin_required")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
