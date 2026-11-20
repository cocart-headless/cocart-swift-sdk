import XCTest
@testable import CoCart
#if canImport(FoundationNetworking)
import FoundationNetworking // URLSession on Linux and Windows
#endif

/// `placeOrder` sends a `checkout_id`, and when no answer comes back it says so with that ID,
/// for `getStatus` to tell how the checkout ended.
final class CheckoutOutcomeTests: XCTestCase {

    private let order: [String: Any] = ["payment_method": "cod", "billing_address": ["email": "jane@example.com"]]

    private func makeCheckout() -> CheckoutResource {
        let options = CoCartOptions()
        let auth = AuthManager(options: options, storage: MemoryStorage())
        let http = HTTPClient(siteURL: "https://store.example.com", options: options,
                              auth: auth, session: makeMockSession())
        return CheckoutResource(http: http)
    }

    private func reply(_ req: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private static func checkoutId(_ req: URLRequest) -> String? {
        guard let data = req.httpBody,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["checkout_id"] as? String
    }

    private let paid = #"{"object":"order","result":{"code":"order_placed","message":"Thank you.","action":null,"redirect_url":null,"error":null},"id":217}"#

    func testEachOrderIsSentWithANewRandomCheckoutId() async throws {
        let sent = Sent()
        MockURLProtocol.requestHandler = { req in
            sent.append(Self.checkoutId(req))
            return self.reply(req, status: 200, body: self.paid)
        }

        _ = try await makeCheckout().placeOrder(order)
        _ = try await makeCheckout().placeOrder(order)

        let ids = sent.values.compactMap { $0 }
        XCTAssertEqual(ids.count, 2)
        for id in ids {
            XCTAssertNotNil(id.range(of: "^chk_[0-9a-f]{32}$", options: .regularExpression), id)
        }
        XCTAssertNotEqual(ids.first, ids.last)
    }

    func testTheCheckoutIdGivenIsSent() async throws {
        let sent = Sent()
        MockURLProtocol.requestHandler = { req in
            sent.append(Self.checkoutId(req))
            return self.reply(req, status: 200, body: self.paid)
        }

        var input = order
        input["checkout_id"] = "chk_mine_00000000001"
        _ = try await makeCheckout().placeOrder(input)

        XCTAssertEqual(sent.values.first ?? nil, "chk_mine_00000000001")
    }

    func testATimeoutSaysTheOutcomeIsUnknownWithTheCheckoutId() async throws {
        let sent = Sent()
        MockURLProtocol.requestHandler = { req in
            sent.append(Self.checkoutId(req))
            throw URLError(.timedOut)
        }

        do {
            _ = try await makeCheckout().placeOrder(order)
            XCTFail("Expected CheckoutOutcomeUnknownError")
        } catch let error as CheckoutOutcomeUnknownError {
            XCTAssertEqual(error.checkoutId, sent.values.first ?? nil)
            guard case .network = error.underlying else { return XCTFail("underlying: \(error.underlying)") }
        }
        XCTAssertEqual(sent.values.count, 1)
    }

    func testAProxyThatGaveUpSaysTheOutcomeIsUnknown() async throws {
        MockURLProtocol.requestHandler = { req in
            self.reply(req, status: 504, body: "<html>Gateway Time-out</html>")
        }

        do {
            _ = try await makeCheckout().placeOrder(order)
            XCTFail("Expected CheckoutOutcomeUnknownError")
        } catch let error as CheckoutOutcomeUnknownError {
            guard case .api(_, let status, _, _) = error.underlying else { return XCTFail("underlying: \(error.underlying)") }
            XCTAssertEqual(status, 504)
        }
    }

    func testAPaymentStillInProgressSaysTheOutcomeIsUnknown() async throws {
        let sent = Sent()
        MockURLProtocol.requestHandler = { req in
            sent.append(Self.checkoutId(req))
            return self.reply(req, status: 409, body: #"{"code":"cocart_payment_in_progress","message":"A payment is already being processed.","data":{"status":409}}"#)
        }

        do {
            _ = try await makeCheckout().placeOrder(order)
            XCTFail("Expected CheckoutOutcomeUnknownError")
        } catch let error as CheckoutOutcomeUnknownError {
            XCTAssertEqual(error.checkoutId, sent.values.first ?? nil)
            XCTAssertEqual(error.errorCode, "cocart_payment_in_progress")
        }
        XCTAssertEqual(sent.values.count, 1)
    }

    func testAMalformedCheckoutIdIsRefusedBeforeSending() async throws {
        let sent = Sent()
        MockURLProtocol.requestHandler = { req in
            sent.append(Self.checkoutId(req))
            return self.reply(req, status: 200, body: self.paid)
        }

        for bad: Any in ["too short", "chk_has spaces_000000", String(repeating: "a", count: 65), 1234567890123456] {
            var input = order
            input["checkout_id"] = bad
            do {
                _ = try await makeCheckout().placeOrder(input)
                XCTFail("Expected checkout_invalid_checkout_id for \(bad)")
            } catch let error as CoCartError {
                XCTAssertEqual(error.errorCode, "checkout_invalid_checkout_id")
            }
        }
        XCTAssertTrue(sent.values.isEmpty)
    }

    func testAnErrorTheStoreAnsweredWithIsKept() async throws {
        MockURLProtocol.requestHandler = { req in
            self.reply(req, status: 400, body: #"{"code":"cocart_cant_checkout_empty_cart","message":"Cannot checkout with empty cart.","data":{"status":400}}"#)
        }

        do {
            _ = try await makeCheckout().placeOrder(order)
            XCTFail("Expected the store's error")
        } catch let error as CoCartError {
            XCTAssertEqual(error.errorCode, "cocart_cant_checkout_empty_cart")
        }
    }
}

/// Thread-safe list of what a mock handler saw.
private final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String?] = []
    var values: [String?] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: String?) { lock.lock(); _values.append(value); lock.unlock() }
}
