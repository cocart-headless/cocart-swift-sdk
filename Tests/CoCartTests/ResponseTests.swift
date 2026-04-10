import XCTest
@testable import CoCart

final class ResponseTests: XCTestCase {

    func testGetDotNotation() {
        let response = CoCartResponse(
            data: [
                "totals": ["total": "4599", "subtotal": "3999"],
                "items": [["name": "T-Shirt", "quantity": 2]]
            ],
            headers: [:],
            statusCode: 200
        )
        XCTAssertEqual(response.getString("totals.total"), "4599")
        XCTAssertEqual(response.getString("totals.subtotal"), "3999")
        XCTAssertEqual(response.getString("items.0.name"), "T-Shirt")
    }

    func testGetReturnsNilForMissingPath() {
        let response = CoCartResponse(data: [:], headers: [:], statusCode: 200)
        XCTAssertNil(response.get("nonexistent.path"))
    }

    func testHas() {
        let response = CoCartResponse(data: ["key": "value"], headers: [:], statusCode: 200)
        XCTAssertTrue(response.has("key"))
        XCTAssertFalse(response.has("missing"))
    }

    func testTypedGetters() {
        let response = CoCartResponse(
            data: [
                "name": "Test",
                "count": 5,
                "price": 19.99,
                "active": true
            ],
            headers: [:],
            statusCode: 200
        )
        XCTAssertEqual(response.getString("name"), "Test")
        XCTAssertEqual(response.getInt("count"), 5)
        XCTAssertEqual(response.getDouble("price"), 19.99)
        XCTAssertEqual(response.getBool("active"), true)
    }

    func testGetItems() {
        let response = CoCartResponse(
            data: ["items": [["name": "A"], ["name": "B"]]],
            headers: [:],
            statusCode: 200
        )
        XCTAssertEqual(response.getItems().count, 2)
    }

    func testGetItemCount() {
        let response = CoCartResponse(data: ["items_count": 3], headers: [:], statusCode: 200)
        XCTAssertEqual(response.getItemCount(), 3)
    }

    func testGetCartKeyFromHeaders() {
        let response = CoCartResponse(data: [:], headers: ["cart-key": "abc123"], statusCode: 200)
        XCTAssertEqual(response.getCartKey(), "abc123")
    }

    func testGetCartKeyFromBody() {
        let response = CoCartResponse(data: ["cart_key": "body_key"], headers: [:], statusCode: 200)
        XCTAssertEqual(response.getCartKey(), "body_key")
    }

    func testIsNotModified() {
        let response304 = CoCartResponse(data: [:], headers: [:], statusCode: 304)
        let response200 = CoCartResponse(data: [:], headers: [:], statusCode: 200)
        XCTAssertTrue(response304.isNotModified())
        XCTAssertFalse(response200.isNotModified())
    }

    func testToDictionary() {
        let response = CoCartResponse(data: ["key": "val"], headers: [:], statusCode: 200)
        XCTAssertEqual(response.toDictionary()["key"] as? String, "val")
    }

    func testDecode() throws {
        struct TestModel: Decodable {
            let name: String
            let count: Int
        }
        let response = CoCartResponse(
            data: ["name": "Test", "count": 42],
            headers: [:],
            statusCode: 200
        )
        let decoded = try response.decode(TestModel.self)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.count, 42)
    }
}
