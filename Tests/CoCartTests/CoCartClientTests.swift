import XCTest
@testable import CoCart

final class CoCartClientTests: XCTestCase {

    func testDefaultInit() {
        let client = CoCart("https://example.com")
        XCTAssertEqual(client.siteURL, "https://example.com")
        XCTAssertTrue(client.isGuest)
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertNil(client.cartKey)
    }

    func testFactoryCreate() {
        let client = CoCart.create("https://example.com")
        XCTAssertEqual(client.siteURL, "https://example.com")
    }

    func testSetAuth() {
        let client = CoCart("https://example.com")
        let result = client.setAuth("admin", password: "pass")
        XCTAssertTrue(result === client)
        XCTAssertTrue(client.isAuthenticated)
        XCTAssertFalse(client.isGuest)
    }

    func testSetJWTToken() {
        let client = CoCart("https://example.com")
        let result = client.setJWTToken("token123")
        XCTAssertTrue(result === client)
        XCTAssertTrue(client.isAuthenticated)
    }

    func testFluentSetters() {
        let client = CoCart.create("https://example.com")
            .setTimeout(15)
            .setMaxRetries(3)
            .setRestPrefix("wp-json")
            .setNamespace("cocart")
            .addHeader("X-Custom", value: "test")
            .setAuthHeaderName("X-Auth")
            .setETag(false)
            .setMainPlugin(.legacy)
            .setDebug(true)

        XCTAssertNotNil(client)
    }

    func testResourceAccessors() {
        let client = CoCart("https://example.com")
        XCTAssertNotNil(client.cart())
        XCTAssertNotNil(client.products())
        XCTAssertNotNil(client.sessions())
        XCTAssertNotNil(client.jwt())
    }

    func testInitWithBasicAuth() {
        let client = CoCart("https://example.com",
                           options: CoCartOptions(username: "admin", password: "pass"))
        XCTAssertTrue(client.isAuthenticated)
        XCTAssertFalse(client.isGuest)
    }

    func testInitWithJWT() {
        let client = CoCart("https://example.com",
                           options: CoCartOptions(jwtToken: "abc.def.ghi"))
        XCTAssertTrue(client.isAuthenticated)
    }

    func testInitWithCartKey() {
        let client = CoCart("https://example.com",
                           options: CoCartOptions(cartKey: "guest_key"))
        XCTAssertEqual(client.cartKey, "guest_key")
        XCTAssertTrue(client.isGuest)
    }
}
