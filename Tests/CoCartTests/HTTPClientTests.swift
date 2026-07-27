import XCTest
@testable import CoCart

final class HTTPClientTests: XCTestCase {

    private func makeClient(options: CoCartOptions) -> HTTPClient {
        let auth = AuthManager(options: options, storage: MemoryStorage())
        return HTTPClient(siteURL: "https://store.example.com", options: options,
                          auth: auth, session: makeMockSession())
    }

    private func jsonResponse(_ req: URLRequest, body: Any, statusCode: Int = 200,
                              headers: [String: String] = [:]) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: req.url!, statusCode: statusCode,
                                       httpVersion: nil, headerFields: headers)!
        return (response, data)
    }

    // MARK: - Cart-key header gating

    func testCartKeyHeaderUsesCartKeyInBasicMode() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        let http = makeClient(options: CoCartOptions(cartKey: "guest_abc", mainPlugin: .basic))
        _ = try await http.get("cart")

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Cart-Key"), "guest_abc")
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "CoCart-API-Cart-Key"))
    }

    func testCartKeyHeaderUsesLegacyHeaderInLegacyMode() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { req in
            capturedRequest = req
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        let http = makeClient(options: CoCartOptions(cartKey: "guest_abc", mainPlugin: .legacy))
        _ = try await http.get("cart")

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "CoCart-API-Cart-Key"), "guest_abc")
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Cart-Key"))
    }

    // MARK: - ETag 304 cached body

    func testNotModifiedResponseReturnsCachedBody() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { req in
            callCount += 1
            if callCount == 1 {
                return try self.jsonResponse(req, body: ["items_count": 3], headers: ["ETag": "\"abc123\""])
            }
            XCTAssertEqual(req.value(forHTTPHeaderField: "If-None-Match"), "\"abc123\"")
            let response = HTTPURLResponse(url: req.url!, statusCode: 304, httpVersion: nil, headerFields: [:])!
            return (response, Data())
        }

        let http = makeClient(options: CoCartOptions())

        let first = try await http.get("cart")
        XCTAssertEqual(first.getItemCount(), 3)

        let second = try await http.get("cart")
        XCTAssertTrue(second.isNotModified())
        XCTAssertEqual(second.getItemCount(), 3, "304 responses should return the cached body, not an empty one")
        XCTAssertEqual(callCount, 2)
    }

    func testNotModifiedWithoutCacheEntryReturnsEmptyBody() async throws {
        MockURLProtocol.requestHandler = { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 304, httpVersion: nil, headerFields: [:])!
            return (response, Data())
        }

        let http = makeClient(options: CoCartOptions())
        let response = try await http.get("cart")

        XCTAssertTrue(response.isNotModified())
        XCTAssertEqual(response.toDictionary().count, 0)
    }

    // MARK: - In-flight GET de-duplication

    func testConcurrentIdenticalGETsShareOneRequest() async throws {
        let counter = Counter()
        MockURLProtocol.requestHandler = { req in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return try self.jsonResponse(req, body: ["items_count": 1])
        }

        let http = makeClient(options: CoCartOptions())

        async let r1 = http.get("cart")
        async let r2 = http.get("cart")
        async let r3 = http.get("cart")
        _ = try await (r1, r2, r3)

        XCTAssertEqual(counter.value, 1)
    }

    func testDifferentGETsAreNotCoalesced() async throws {
        let counter = Counter()
        MockURLProtocol.requestHandler = { req in
            counter.increment()
            return try self.jsonResponse(req, body: [:] as [String: Any])
        }

        let http = makeClient(options: CoCartOptions())

        _ = try await http.get("cart")
        _ = try await http.get("cart/totals")

        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - Retry backoff jitter

    func testRetriesOnTransientErrorBeforeThrowing() async throws {
        let counter = Counter()
        MockURLProtocol.requestHandler = { _ in
            counter.increment()
            throw NSError(domain: "test", code: -1)
        }

        let http = makeClient(options: CoCartOptions(maxRetries: 2))
        let start = Date()

        do {
            _ = try await http.get("cart")
            XCTFail("Expected network error")
        } catch CoCartError.network(_) {
            // expected
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(counter.value, 3, "initial attempt + 2 retries")
        // Backoff is ~500ms then ~1000ms with +-20% jitter, so total sleep
        // should land comfortably above 1s and well under a fixed 3s ceiling.
        XCTAssertGreaterThan(elapsed, 1.0)
        XCTAssertLessThan(elapsed, 3.0)
    }
}

/// Small thread-safe counter for mock request handlers (which may be invoked
/// from URLSession's background threads).
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); _value += 1; lock.unlock() }
}
