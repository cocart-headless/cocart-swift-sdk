import XCTest
@testable import CoCart

final class ProductsResourceTests: XCTestCase {

    private func makeResource(options: CoCartOptions = CoCartOptions()) -> ProductsResource {
        let session = makeMockSession()
        let auth = AuthManager(options: options, storage: MemoryStorage())
        let http = HTTPClient(siteURL: "https://store.example.com", options: options,
                              auth: auth, session: session)
        return ProductsResource(http: http, options: options)
    }

    private func jsonResponse(_ req: URLRequest, body: Any, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: req.url!, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    // MARK: - get (by ID or SKU)

    func testGetSendsNumericProductID() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { req in
            capturedURL = req.url
            return try self.jsonResponse(req, body: ["id": 278])
        }

        _ = try await makeResource().get(278)

        XCTAssertTrue(capturedURL?.absoluteString.contains("products/278") == true)
    }

    func testGetAcceptsSku() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { req in
            capturedURL = req.url
            return try self.jsonResponse(req, body: ["sku": "PCT-2024"])
        }

        _ = try await makeResource().get("PCT-2024")

        XCTAssertTrue(capturedURL?.absoluteString.contains("products/PCT-2024") == true)
    }
}
