import XCTest
@testable import CoCart

final class AuthManagerTests: XCTestCase {

    func testDefaultModeIsGuest() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        XCTAssertEqual(auth.mode, .guest)
        XCTAssertTrue(auth.isGuest)
        XCTAssertFalse(auth.isAuthenticated)
    }

    func testBasicAuthFromOptions() {
        let opts = CoCartOptions(username: "admin", password: "pass")
        let auth = AuthManager(options: opts, storage: MemoryStorage())
        XCTAssertEqual(auth.mode, .basicAuth)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertNotNil(auth.authorizationHeaderValue())
        XCTAssertTrue(auth.authorizationHeaderValue()!.hasPrefix("Basic "))
    }

    func testJWTFromOptions() {
        let opts = CoCartOptions(jwtToken: "abc.def.ghi", jwtRefreshToken: "refresh123")
        let auth = AuthManager(options: opts, storage: MemoryStorage())
        XCTAssertEqual(auth.mode, .jwt)
        XCTAssertEqual(auth.authorizationHeaderValue(), "Bearer abc.def.ghi")
        XCTAssertEqual(auth.activeRefreshToken, "refresh123")
    }

    func testConsumerKeysFromOptions() {
        let opts = CoCartOptions(consumerKey: "ck_test", consumerSecret: "cs_test")
        let auth = AuthManager(options: opts, storage: MemoryStorage())
        XCTAssertEqual(auth.mode, .consumerKeys)
        XCTAssertTrue(auth.authorizationHeaderValue()!.hasPrefix("Basic "))
    }

    func testSetBasicAuth() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        auth.setBasicAuth("user", password: "pass")
        XCTAssertEqual(auth.mode, .basicAuth)
        XCTAssertTrue(auth.isAuthenticated)
    }

    func testSetJWTToken() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        auth.setJWTToken("token123")
        XCTAssertEqual(auth.mode, .jwt)
        XCTAssertEqual(auth.activeJWTToken, "token123")
    }

    func testGuestCartKeyReturnsNilWhenAuthenticated() {
        let auth = AuthManager(options: CoCartOptions(cartKey: "key123"), storage: MemoryStorage())
        auth.setBasicAuth("user", password: "pass")
        XCTAssertNil(auth.guestCartKey)
    }

    func testGuestCartKeyReturnsValueWhenGuest() {
        let auth = AuthManager(options: CoCartOptions(cartKey: "key123"), storage: MemoryStorage())
        XCTAssertEqual(auth.guestCartKey, "key123")
    }

    func testCaptureCartKeyFromBody() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        auth.captureCartKey(from: ["cart_key": "captured_key"], headers: [:])
        XCTAssertEqual(auth.cartKey, "captured_key")
    }

    func testCaptureCartKeyFromHeaders() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        auth.captureCartKey(from: [:], headers: ["cart-key": "header_key"])
        XCTAssertEqual(auth.cartKey, "header_key")
    }

    func testCaptureCartKeyFromFallbackHeader() {
        let auth = AuthManager(options: CoCartOptions(), storage: MemoryStorage())
        auth.captureCartKey(from: [:], headers: ["cocart-api-cart-key": "fallback_key"])
        XCTAssertEqual(auth.cartKey, "fallback_key")
    }

    func testCaptureCartKeyIgnoredWhenAuthenticated() {
        let opts = CoCartOptions(username: "admin", password: "pass")
        let auth = AuthManager(options: opts, storage: MemoryStorage())
        auth.captureCartKey(from: ["cart_key": "should_ignore"], headers: [:])
        XCTAssertNil(auth.cartKey)
    }

    func testClearSession() async throws {
        let auth = AuthManager(options: CoCartOptions(cartKey: "key"), storage: MemoryStorage())
        auth.setJWTToken("token")
        try await auth.clearSession()
        XCTAssertEqual(auth.mode, .guest)
        XCTAssertNil(auth.cartKey)
        XCTAssertNil(auth.activeJWTToken)
    }

    func testRestoreSession() async throws {
        let storage = MemoryStorage()
        try await storage.write("cocart_cart_key", value: "stored_key")
        let auth = AuthManager(options: CoCartOptions(), storage: storage)
        try await auth.restoreSession()
        XCTAssertEqual(auth.cartKey, "stored_key")
    }
}
