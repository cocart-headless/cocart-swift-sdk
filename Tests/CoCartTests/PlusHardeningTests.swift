import XCTest
@testable import CoCart

/// Client hardening for CoCart Plus 2.0: rate-limit headers, debug output, the ETag cache, the
/// raw (CoCart Plus) requests' events, error mapping and the error's field details.
final class PlusHardeningTests: XCTestCase {

    private func makeClient(_ options: CoCartOptions = CoCartOptions()) -> HTTPClient {
        let auth = AuthManager(options: options, storage: MemoryStorage())
        return HTTPClient(siteURL: "https://store.example.com", options: options, auth: auth,
                          session: makeMockSession())
    }

    private func reply(_ req: URLRequest, _ status: Int, _ body: Any = [String: Any](),
                       headers: [String: String] = [:]) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        return (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
    }

    // MARK: - Rate limits

    func testA429ReadsRateLimitRetryAfter() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 429, ["code": "cocart_rate_limited", "message": "Slow down"],
                           headers: ["RateLimit-Retry-After": "7", "Retry-After": "99"])
        }

        do {
            _ = try await makeClient().get("cart")
            XCTFail("Expected rateLimited")
        } catch CoCartError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 7)
        }
    }

    func testA429StillReadsRetryAfterWhenThatIsAllAProxySends() async throws {
        MockURLProtocol.requestHandler = { req in try self.reply(req, 429, headers: ["Retry-After": "3"]) }

        do {
            _ = try await makeClient().get("cart")
            XCTFail("Expected rateLimited")
        } catch CoCartError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 3)
        }
    }

    // MARK: - Debug output

    func testDebugOutputHidesEveryQueryValue() {
        let url = "https://store.example.com/wp-json/cocart/v2/order-received/12?email=jane@example.com&order_key=wc_order_secret&flag"
        let redacted = HTTPClient.redactQuery(url)

        XCTAssertEqual(redacted, "https://store.example.com/wp-json/cocart/v2/order-received/12?email=***&order_key=***&flag")
        XCTAssertFalse(redacted.contains("wc_order_secret"))
        XCTAssertFalse(redacted.contains("jane@example.com"))
        XCTAssertEqual(HTTPClient.redactQuery("https://store.example.com/wp-json/cocart/v2/cart"),
                       "https://store.example.com/wp-json/cocart/v2/cart")
    }

    // MARK: - ETag cache

    func testDoesNotKeepANoStoreResponseInTheETagCache() async throws {
        var ifNoneMatch: [String?] = []
        MockURLProtocol.requestHandler = { req in
            ifNoneMatch.append(req.value(forHTTPHeaderField: "If-None-Match"))
            return try self.reply(req, 200, ["object": "order"], headers: [
                "ETag": "\"abc\"",
                "Cache-Control": "no-cache, no-store, must-revalidate, max-age=0, private",
            ])
        }

        let http = makeClient()
        _ = try await http.get("cart")
        _ = try await http.get("cart")

        XCTAssertEqual(ifNoneMatch.count, 2)
        XCTAssertNil(ifNoneMatch[1])
    }

    func testStillUsesTheETagCacheForAResponseThatMayBeStored() async throws {
        var ifNoneMatch: [String?] = []
        MockURLProtocol.requestHandler = { req in
            ifNoneMatch.append(req.value(forHTTPHeaderField: "If-None-Match"))
            return try self.reply(req, 200, ["items": [] as [Any]], headers: ["ETag": "\"abc\""])
        }

        let http = makeClient()
        _ = try await http.get("products")
        _ = try await http.get("products")

        XCTAssertEqual(ifNoneMatch.last ?? nil, "\"abc\"")
    }

    func testMayStoreReadsCacheControl() {
        XCTAssertTrue(HTTPClient.mayStore(nil))
        XCTAssertTrue(HTTPClient.mayStore("max-age=60, public"))
        XCTAssertFalse(HTTPClient.mayStore("no-store"))
        XCTAssertFalse(HTTPClient.mayStore("Private, max-age=0"))
        XCTAssertTrue(HTTPClient.mayStore("x-private-thing=1"))
    }

    // MARK: - Raw (CoCart Plus) requests

    func testARawRequestEmitsRequestAndResponseEventsWithTheResponse() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 200, ["object": "order", "result": ["code": "order_placed"]])
        }
        let http = makeClient()
        var seen: [String] = []
        var code: String?
        http.on(.request) { payload in seen.append("request \(payload["method"] as? String ?? "")") }
        http.on(.response) { payload in
            seen.append("response \(payload["status"] as? Int ?? 0)")
            code = (payload["response"] as? CoCartResponse)?.get("result.code") as? String
        }

        _ = try await http.postRaw("cocart/v2/checkout", body: ["payment_method": "cod"])

        XCTAssertEqual(seen, ["request POST", "response 200"])
        XCTAssertEqual(code, "order_placed")
    }

    func testARawErrorEmitsAnErrorEventNamingItsRoute() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 404, ["code": "cocart_order_not_found", "message": "Not found.", "data": ["status": 404]])
        }
        let http = makeClient()
        var errors: [String] = []
        http.on(.error) { payload in
            errors.append("\(payload["method"] as? String ?? "") \(payload["url"] as? String ?? "")")
        }

        do {
            _ = try await http.getRaw("cocart/v2/order-received/12", queryParams: ["order_key": "wc_order_secret"])
            XCTFail("Expected cocart_order_not_found")
        } catch let error as CoCartError {
            XCTAssertEqual(error.errorCode, "cocart_order_not_found")
        }
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("GET https://store.example.com/wp-json/cocart/v2/order-received/12"))
    }

    func testARawGetIsNeverSentAgain() async throws {
        var count = 0
        MockURLProtocol.requestHandler = { _ in
            count += 1
            throw URLError(.timedOut)
        }

        do {
            _ = try await makeClient(CoCartOptions(maxRetries: 2)).getRaw("cocart/v2/checkout/status",
                                                                            queryParams: ["checkout_id": "chk_0000000000000001"])
            XCTFail("Expected network error")
        } catch CoCartError.network(_) {
            // expected
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Error mapping

    func testA409IsAnAPIErrorEvenWhenItsCodeSaysInvalid() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 409, ["code": "cocart_order_invalid_status", "message": "Paid already.", "data": ["status": 409]])
        }

        do {
            _ = try await makeClient().postRaw("cocart/v2/order-received/12/pay")
            XCTFail("Expected an error")
        } catch CoCartError.api(_, let status, let code, _) {
            XCTAssertEqual(status, 409)
            XCTAssertEqual(code, "cocart_order_invalid_status")
        }
    }

    func testAServerErrorIsAnAPIError() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 500, ["code": "cocart_missing_thing", "message": "Oops.", "data": ["status": 500]])
        }

        do {
            _ = try await makeClient().getRaw("cocart/v2/checkout")
            XCTFail("Expected an error")
        } catch CoCartError.api(_, let status, _, _) {
            XCTAssertEqual(status, 500)
        }
    }

    func testReadsEveryFieldAtFaultTheFirstOneAndTheReason() async throws {
        MockURLProtocol.requestHandler = { req in
            try self.reply(req, 400, [
                "code": "cocart_invalid_address_fields",
                "message": "Check the address.",
                "data": [
                    "status": 400,
                    "field": "billing.postcode",
                    "fields": ["billing.postcode": "Enter a valid postcode.", "billing.phone": "Enter a phone number."],
                    "reason": "postcode_format",
                ] as [String: Any],
            ])
        }

        do {
            _ = try await makeClient().putRaw("cocart/v2/checkout")
            XCTFail("Expected an error")
        } catch let error as CoCartError {
            XCTAssertEqual(error.fields, ["billing.postcode": "Enter a valid postcode.", "billing.phone": "Enter a phone number."])
            XCTAssertEqual(error.field, "billing.postcode")
            XCTAssertEqual(error.reason, "postcode_format")
        }
    }

    func testAnErrorWithoutFieldDetailsGivesAnEmptyMapAndNils() {
        let error = CoCartError.api("Nope", statusCode: 404, code: "cocart_order_not_found",
                                    data: ["code": "cocart_order_not_found", "data": ["status": 404]])
        XCTAssertEqual(error.fields, [:])
        XCTAssertNil(error.field)
        XCTAssertNil(error.reason)
        XCTAssertEqual(CoCartError.network("down").fields, [:])
    }
}

/// `CheckoutResult` reads `result`, and printing it never shows the payment's secret or the order key.
final class CheckoutResultTests: XCTestCase {

    private func result(_ json: String) -> CheckoutResult {
        let data = Data(json.utf8)
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return CheckoutResult.from(CoCartResponse(data: body, headers: [:], statusCode: 200, raw: data))
    }

    private let needsConfirmation = #"""
    {"object":"order","result":{"code":"action_required","message":"Confirm the payment.",
     "action":{"type":"stripe_confirm_payment","data":{"client_secret":"pi_123_secret_456","intent_type":"payment_intent"}},
     "redirect_url":"https://shop.example.com/checkout/order-received/217/?key=wc_order_abc","error":null},
     "id":217,"number":"217","key":"wc_order_abc","status":{"code":"pending","label":"Pending payment"}}
    """#

    func testPrintingNeverShowsTheClientSecretOrTheOrderKey() {
        let result = result(needsConfirmation)
        XCTAssertEqual(result.clientSecret, "pi_123_secret_456")
        XCTAssertEqual(result.orderKey, "wc_order_abc")

        var dumped = ""
        dump(result, to: &dumped)
        var debugPrinted = ""
        debugPrint(result, to: &debugPrinted)
        var printed = ""
        print(result, to: &printed)

        for output in [printed, debugPrinted, dumped, "\(result)", String(describing: result), String(reflecting: result)] {
            XCTAssertFalse(output.contains("pi_123_secret_456"), output)
            XCTAssertFalse(output.contains("wc_order_abc"), output)
            XCTAssertTrue(output.contains("action_required"), output)
        }
        XCTAssertTrue(printed.contains("orderId: 217"), printed)
    }

    func testAMissingCodeReadsAsAFailure() {
        let result = result(#"{"object":"order","id":217}"#)
        XCTAssertEqual(result.code, .paymentFailed)
        XCTAssertTrue(result.isFailed)
        XCTAssertFalse(result.isComplete)
    }

    func testAnOrderPlacedWithAnActionIsAwaitingPaymentNotComplete() {
        let result = result(#"""
        {"object":"order","result":{"code":"order_placed","message":"Approve in your banking app.",
         "action":{"type":"stripe_blik_confirmation_pending","data":{}},"redirect_url":null,"error":null},"id":217}
        """#)
        XCTAssertTrue(result.isAwaitingPayment)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.actionType, "stripe_blik_confirmation_pending")
    }

    func testTheOffSiteStepComesFirstOnlyWhenActionIsRequired() {
        let redirect = result(#"""
        {"object":"order","result":{"code":"action_required","message":"…",
         "action":{"type":"redirect","data":{"redirect":"https://pay.example.com/step"}},
         "redirect_url":"https://shop.example.com/thanks","error":null},"id":217}
        """#)
        XCTAssertTrue(redirect.needsRedirect)
        XCTAssertEqual(redirect.redirectUrl, "https://pay.example.com/step")

        let placed = result(#"""
        {"object":"order","result":{"code":"order_placed","message":"…",
         "action":{"type":"voucher","data":{"redirect":"https://pay.example.com/voucher"}},
         "redirect_url":"https://shop.example.com/thanks","error":null},"id":217}
        """#)
        XCTAssertEqual(placed.redirectUrl, "https://shop.example.com/thanks")
    }

    func testASubscriptionResultHasNoOrderFields() {
        let result = result(#"""
        {"object":"subscription","result":{"code":"payment_method_changed","message":"Changed.","action":null,
         "redirect_url":null,"error":null},"id":512,"number":"512","key":"wc_order_sub","status":{"code":"active"}}
        """#)
        XCTAssertEqual(result.object, "subscription")
        XCTAssertEqual(result.subscriptionId, 512)
        XCTAssertNil(result.orderId)
        XCTAssertNil(result.orderKey)
        XCTAssertNil(result.orderStatus)
        XCTAssertTrue(result.isComplete)
    }
}
